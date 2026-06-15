#!/usr/bin/env bash
# tools/build.sh
#
# Produce a runnable `dist/wez` from the Lua sources. Bootstrap/build GLUE only
# (D-01): the only decision this script makes is which build PATH to take based
# on toolchain presence; all behavior logic lives in the Lua `wez` binary.
#
# A LOCAL SOURCE BUILD NEVER TOUCHES THE NETWORK. The default path resolves
# entirely from in-repo sources:
#
#   1. luastatic  — when a Lua 5.4 toolchain + `luastatic` + a C compiler are
#      present, bundle cli/wez.lua + every cli/ source + the vendored deps + the
#      Lua interpreter into ONE static binary at dist/wez (the shipping artifact;
#      see .planning/decisions/cli-language.md, D-02).
#
#   2. dev source-launcher (local dev only) — when luastatic is ABSENT, emit a
#      tiny launcher at dist/wez that execs lua5.4 against the in-repo cli/wez.lua.
#      This keeps `dist/wez version` runnable for local verification without any
#      network access. NOT a release artifact.
#
# Remote bootstrap (OPT-IN ONLY, never the local default):
#
#   release-download — when the explicit env flag WEZ_REMOTE_BOOTSTRAP=1 is set
#      (the future `curl|bash` remote installer's path) AND luastatic is absent,
#      download the matching prebuilt `wez` release binary (asset via
#      tools/lib/platform.sh) and place it at dist/wez. SECURITY (T-01-01): the
#      release tag is PINNED and the download is verified against a published
#      per-asset `<asset>.sha256` checksum BEFORE chmod +x; a checksum mismatch
#      aborts non-zero. We never run an unverified download. The base points at
#      the real `github.com/castocolina/wezterm-setup/releases/download`; the
#      path stays dormant until the first `v*` release asset exists.
#
# Usage:
#   ./tools/build.sh                         # local build: luastatic -> dev launcher
#   WEZ_REMOTE_BOOTSTRAP=1 ./tools/build.sh  # remote installer: luastatic -> verified release download
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck source=tools/lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"

DIST_DIR="${REPO_ROOT}/dist"
OUT="${DIST_DIR}/wez"
ENTRY="cli/wez.lua"

# Pinned release for the download fallback (T-01-01: never "latest").
WEZ_RELEASE_TAG="${WEZ_RELEASE_TAG:-v0.1.0}"
WEZ_RELEASE_BASE="${WEZ_RELEASE_BASE:-https://github.com/castocolina/wezterm-setup/releases/download}"

mkdir -p "${DIST_DIR}"

log() { printf '[build] %s\n' "$*"; }

# --- toolchain detection (the only decision this glue makes) -----------------
have_luastatic() {
  command -v luastatic >/dev/null 2>&1 \
    && command -v lua5.4 >/dev/null 2>&1 \
    && { command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; }
}

# ---------------------------------------------------------------------------
# Path 1: luastatic single-binary build
# ---------------------------------------------------------------------------
build_with_luastatic() {
  log "luastatic toolchain present -> static single-binary build"

  # Resolve the Lua 5.4 compile flags for luastatic. Use `pkg-config --cflags`,
  # NOT `--variable=includedir`: on Debian/Ubuntu the .pc includedir is /usr/include
  # while the actual headers (lauxlib.h, lua.h) live in /usr/include/lua5.4, so
  # `--cflags` is the only query that yields the correct `-I/usr/include/lua5.4`.
  # Try the common .pc names across distros, then fall back to the Debian path.
  local lua_cflags
  lua_cflags="$(pkg-config --cflags lua5.4 2>/dev/null \
    || pkg-config --cflags lua-5.4 2>/dev/null \
    || pkg-config --cflags lua 2>/dev/null \
    || echo '-I/usr/include/lua5.4')"

  # luastatic must also LINK the Lua interpreter — locate the static archive.
  # Debian ships it as liblua5.4.a; other distros as liblua.a. Passing it
  # explicitly (per luastatic's documented form) avoids relying on a `-llua`
  # auto-guess that fails under Debian's versioned library naming.
  local lua_libdir liblua=""
  lua_libdir="$(pkg-config --variable=libdir lua5.4 2>/dev/null \
    || pkg-config --variable=libdir lua 2>/dev/null || true)"
  local cand
  for cand in \
    "${lua_libdir}/liblua5.4.a" "${lua_libdir}/liblua.a" \
    /usr/lib/*/liblua5.4.a /usr/lib/liblua5.4.a /usr/local/lib/liblua5.4.a \
    /usr/lib/*/liblua.a /usr/local/lib/liblua.a; do
    [ -f "${cand}" ] && { liblua="${cand}"; break; }
  done

  # Collect every Lua source under cli/ (entry + spec + commands + vendored deps).
  # CRITICAL: luastatic derives each bundled module's name from the PATH STRING it
  # is given, so we must invoke it from REPO_ROOT with RELATIVE paths (cli/spec.lua
  # -> module `cli.spec`). Absolute paths would bake in names like
  # `home.user.repo.cli.spec`, and every `require("cli.spec")` in the binary would
  # fail at runtime. So paths here stay relative and luastatic runs with cwd=REPO_ROOT.
  local sources=()
  while IFS= read -r f; do sources+=("$f"); done \
    < <(find cli -type f -name '*.lua' ! -name 'wez.lua' | sort)

  (
    cd "${REPO_ROOT}"
    # luastatic <main.lua> <module.lua...> [liblua.a] <cflags>
    # shellcheck disable=SC2086
    luastatic "${ENTRY}" \
      "${sources[@]}" \
      ${liblua:+"${liblua}"} \
      ${lua_cflags}
  )

  # luastatic writes ./<name> (and ./<name>.c) into the cwd (REPO_ROOT). Normalize
  # the binary to dist/wez and clean up the generated C translation unit.
  rm -f "${REPO_ROOT}/wez.luastatic.c"
  if [ -f "${REPO_ROOT}/wez" ]; then
    mv "${REPO_ROOT}/wez" "${OUT}"
  fi
  chmod +x "${OUT}"
  log "built static binary: ${OUT}"
}

# ---------------------------------------------------------------------------
# Remote bootstrap path: release-download (pinned + checksum-verified).
# OPT-IN ONLY via WEZ_REMOTE_BOOTSTRAP=1 — never reached on a local source build.
# ---------------------------------------------------------------------------
download_release() {
  local os arch asset url sums_url
  os="$(platform_os)"
  arch="$(platform_arch)"
  asset="wez-${os}-${arch}"
  url="${WEZ_RELEASE_BASE}/${WEZ_RELEASE_TAG}/${asset}"
  # Per-asset checksum (Plan 01 Open Q2 verdict): one line, '<64-hex>  <name>'.
  sums_url="${WEZ_RELEASE_BASE}/${WEZ_RELEASE_TAG}/${asset}.sha256"

  log "Lua toolchain absent -> release-download fallback (${WEZ_RELEASE_TAG}, ${asset})"

  if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL -o "$2" "$1"; }
  elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -qO "$2" "$1"; }
  else
    log "ERROR: neither curl nor wget available for download fallback"
    return 1
  fi

  local tmp sums
  tmp="$(mktemp)"
  sums="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '${tmp}' '${sums}'" RETURN

  if ! fetch "${url}" "${tmp}"; then
    log "ERROR: failed to download ${url}"
    return 1
  fi
  if ! fetch "${sums_url}" "${sums}"; then
    log "ERROR: failed to download checksum file ${sums_url}"
    return 1
  fi

  # T-01-01: verify SHA-256 BEFORE making it executable. Abort on mismatch.
  # The per-asset `.sha256` is a single line, so take field 1 of that one line.
  local want got
  want="$(awk '{print $1}' "${sums}")"
  if [ -z "${want}" ]; then
    log "ERROR: no checksum for ${asset} in ${asset}.sha256 — refusing unverified download"
    return 1
  fi
  # Portable digest (Pitfall 4): macOS has no `sha256sum`, only `shasum -a 256`.
  if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "${tmp}" | awk '{print $1}')"
  else
    got="$(shasum -a 256 "${tmp}" | awk '{print $1}')"
  fi
  if [ "${want}" != "${got}" ]; then
    log "ERROR: checksum mismatch for ${asset} (want ${want}, got ${got}) — aborting"
    return 1
  fi
  log "checksum verified for ${asset}"

  mv "${tmp}" "${OUT}"
  trap - RETURN
  rm -f "${sums}"
  chmod +x "${OUT}"
  log "installed verified release binary: ${OUT}"
}

# ---------------------------------------------------------------------------
# Path 3: dev source-launcher (local verification only)
# ---------------------------------------------------------------------------
build_dev_launcher() {
  log "luastatic absent (local build) -> dev source-launcher (NOT a release artifact)"
  cat >"${OUT}" <<EOF
#!/usr/bin/env bash
# wez — DEV source launcher (generated by tools/build.sh path 3).
# Not a release artifact: it execs lua5.4 against the in-repo Lua sources.
# A shipped build uses the luastatic single binary instead.
REPO_ROOT="${REPO_ROOT}"
exec lua5.4 "\${REPO_ROOT}/${ENTRY}" "\$@"
EOF
  chmod +x "${OUT}"
  log "built dev launcher: ${OUT}"
}

# ---------------------------------------------------------------------------
main() {
  if have_luastatic; then
    build_with_luastatic
  elif [ "${WEZ_REMOTE_BOOTSTRAP:-0}" = "1" ]; then
    # REMOTE bootstrap path ONLY (the curl|bash installer opts in with
    # WEZ_REMOTE_BOOTSTRAP=1). The ONLY acceptable artifact here is the verified
    # prebuilt static binary. We must NEVER fall back to the dev source-launcher:
    # it bakes in REPO_ROOT pointing at install.sh's ephemeral temp checkout, which
    # is deleted on exit — leaving a `wez` that dies with "cannot open
    # /tmp/.../cli/wez.lua". Detect the missing artifact and STOP LOUDLY with
    # actionable instructions rather than installing something broken.
    if ! download_release; then
      local os arch
      os="$(platform_os)"; arch="$(platform_arch)"
      log "ERROR: no prebuilt wez binary available for this platform (wez-${os}-${arch})."
      log "  The remote installer requires a published release asset and will NOT"
      log "  build from source on your machine (sudo-free invariant: no toolchain"
      log "  is installed for you)."
      log "  Likely cause: no release published yet for tag '${WEZ_RELEASE_TAG}', or"
      log "  no asset exists for ${os}-${arch}. Check the releases page:"
      log "    ${WEZ_RELEASE_BASE%/download}/tag/${WEZ_RELEASE_TAG}"
      log "  Then re-run the installer once the asset is available."
      exit 1
    fi
  else
    # LOCAL source build: NEVER touch the network. luastatic absent -> the dev
    # source-launcher directly. The release download is remote-installer-only and
    # is gated behind WEZ_REMOTE_BOOTSTRAP=1 above.
    build_dev_launcher
  fi

  # Smoke-verify the produced artifact. Assert NON-EMPTY output, not just exit 0:
  # the previous luastatic binary exited 0 while running nothing (broken is_main),
  # so an exit-code-only check would have shipped an inert binary. Requiring real
  # `version` output catches that failure mode at build time.
  local smoke
  if smoke="$("${OUT}" version 2>/dev/null)" && [ -n "${smoke}" ]; then
    log "verify: '${OUT} version' OK (${smoke})"
  else
    log "ERROR: '${OUT} version' produced no output or non-zero exit — refusing to"
    log "       ship an inert binary."
    exit 1
  fi
}

main "$@"
