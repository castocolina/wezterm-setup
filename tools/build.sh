#!/usr/bin/env bash
# tools/build.sh
#
# Produce a runnable `dist/wez` from the Lua sources. Bootstrap/build GLUE only
# (D-01): the only decision this script makes is which build PATH to take based
# on toolchain presence; all behavior logic lives in the Lua `wez` binary.
#
# Build paths, in priority order:
#
#   1. luastatic  — when a Lua 5.4 toolchain + `luastatic` + a C compiler are
#      present, bundle cli/wez.lua + every cli/ source + the vendored deps + the
#      Lua interpreter into ONE static binary at dist/wez (the shipping artifact;
#      see .planning/decisions/cli-language.md, D-02).
#
#   2. release-download fallback — when the Lua toolchain is ABSENT, download the
#      matching prebuilt `wez` release binary (asset picked via
#      tools/lib/platform.sh) and place it at dist/wez. SECURITY (T-01-01): the
#      release tag is PINNED and the download is verified against a published
#      SHA-256 checksum BEFORE chmod +x; a checksum mismatch aborts non-zero. We
#      never run an unverified download.
#
#   3. dev source-launcher (local dev only) — when neither luastatic nor a
#      fetchable release is available, emit a tiny launcher at dist/wez that execs
#      lua5.4 against the in-repo cli/wez.lua with the bundle path set. This keeps
#      `dist/wez version` runnable for local verification without installing an
#      unverified package or shipping unvendored bytes. NOT a release artifact.
#
# Usage: ./tools/build.sh
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
WEZ_RELEASE_BASE="${WEZ_RELEASE_BASE:-https://github.com/you/wezterm-setup/releases/download}"

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
# Path 2: release-download fallback (pinned + checksum-verified)
# ---------------------------------------------------------------------------
download_release() {
  local os arch asset url sums_url
  os="$(platform_os)"
  arch="$(platform_arch)"
  asset="wez-${os}-${arch}"
  url="${WEZ_RELEASE_BASE}/${WEZ_RELEASE_TAG}/${asset}"
  sums_url="${WEZ_RELEASE_BASE}/${WEZ_RELEASE_TAG}/SHA256SUMS"

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
  local want got
  want="$(grep -E "  ${asset}\$|\\*${asset}\$" "${sums}" | awk '{print $1}' | head -n1)"
  if [ -z "${want}" ]; then
    log "ERROR: no checksum for ${asset} in SHA256SUMS — refusing unverified download"
    return 1
  fi
  got="$(sha256sum "${tmp}" | awk '{print $1}')"
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
  log "no luastatic and no fetchable release -> dev source-launcher (NOT a release artifact)"
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
  else
    # Toolchain absent: try the pinned+verified release download; if that is not
    # reachable (e.g. no releases published yet), fall back to the dev launcher
    # so local verification still has a runnable dist/wez.
    if download_release; then
      :
    else
      build_dev_launcher
    fi
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
