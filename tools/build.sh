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

  # Locate the Lua 5.4 headers for luastatic linking.
  local lua_incdir
  lua_incdir="$(pkg-config --variable=includedir lua5.4 2>/dev/null || true)"
  [ -z "${lua_incdir}" ] && lua_incdir="/usr/include/lua5.4"

  # Collect every Lua source under cli/ (entry + spec + commands + vendored deps)
  # so luastatic bakes them in by their module names.
  local sources=()
  while IFS= read -r f; do sources+=("$f"); done \
    < <(find cli -type f -name '*.lua' ! -name 'wez.lua' | sort)

  (
    cd "${DIST_DIR}"
    # luastatic <main.lua> <module.lua...> liblua.a -I<headers>
    luastatic "${REPO_ROOT}/${ENTRY}" \
      "${sources[@]/#/${REPO_ROOT}/}" \
      -I"${lua_incdir}"
  )

  # luastatic writes <name> (and a <name>.c). Normalize the artifact to dist/wez.
  if [ -f "${DIST_DIR}/wez" ]; then
    :
  elif [ -f "${DIST_DIR}/wez.lua" ]; then
    mv "${DIST_DIR}/wez.lua" "${OUT}"
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
    # REMOTE bootstrap path ONLY (the future curl|bash installer opts in with
    # WEZ_REMOTE_BOOTSTRAP=1). Try the pinned+verified release download; if that
    # is not reachable (e.g. no releases published yet) fall back to the dev
    # launcher so the installer still yields a runnable dist/wez.
    if download_release; then
      :
    else
      build_dev_launcher
    fi
  else
    # LOCAL source build: NEVER touch the network. luastatic absent -> the dev
    # source-launcher directly. The release download is remote-installer-only and
    # is gated behind WEZ_REMOTE_BOOTSTRAP=1 above.
    build_dev_launcher
  fi

  # Smoke-verify the produced artifact.
  if "${OUT}" version >/dev/null 2>&1; then
    log "verify: '${OUT} version' OK"
  else
    log "ERROR: '${OUT} version' did not exit 0"
    exit 1
  fi
}

main "$@"
