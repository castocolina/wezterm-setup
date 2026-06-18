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
#      release tag is RESOLVED from a channel (see WEZ_CHANNEL below) and the
#      download is verified against a published per-asset `<asset>.sha256`
#      checksum BEFORE chmod +x; a checksum mismatch aborts non-zero. We never
#      run an unverified download. The base points at the real
#      `github.com/castocolina/wezterm-setup/releases/download`; the path stays
#      dormant until a matching release asset exists.
#
# Release channel selector (D-02/D-08 — the minimal D-01 trigger-plumbing
# exception; no install/version policy grows in bash):
#
#   WEZ_CHANNEL selects WHICH `wez` release the download path pulls:
#     * nightly  (DEFAULT) — the newest `nightly-*` prerelease (the rolling
#                build Plan 02 publishes). A non-interactive `curl|bash` pipe
#                resolves nightly deterministically and NEVER hangs (D-02).
#     * stable             — GitHub `/releases/latest`, which EXCLUDES
#                prereleases, so the nightlies are auto-filtered out (D-03).
#     * <vX.Y.Z>           — that exact tag, used literally (an explicit pin).
#   An interactive TTY with no channel set shows a numbered picker (nightly /
#   newest stable / recent tags) mirroring bootstrap-wezterm.sh select_release().
#
#   WEZ_RELEASE_TAG is now the EXPLICIT-PIN escape hatch only (D-01): when set it
#   forces WEZ_CHANNEL to that literal tag, so an existing `WEZ_RELEASE_TAG=v0.1.0`
#   caller keeps working. It is NO LONGER the channel default (the v0.1.0 pin is
#   gone). A degraded/empty channel resolution FAILS LOUDLY (non-zero) — it never
#   silently installs an unverified or wrong asset.
#
# Usage:
#   ./tools/build.sh                          # local build: luastatic -> dev launcher
#   WEZ_REMOTE_BOOTSTRAP=1 ./tools/build.sh   # remote installer: luastatic -> verified nightly download
#   WEZ_CHANNEL=stable  WEZ_REMOTE_BOOTSTRAP=1 ./tools/build.sh  # newest stable release
#   WEZ_CHANNEL=v0.1.0  WEZ_REMOTE_BOOTSTRAP=1 ./tools/build.sh  # an explicit pin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck source=tools/lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"

DIST_DIR="${REPO_ROOT}/dist"
OUT="${DIST_DIR}/wez"
ENTRY="cli/wez.lua"

# Release channel for the download fallback (D-02/D-08). Default `nightly` (the
# rolling build); `stable` -> /releases/latest; `<vX.Y.Z>` -> that literal tag.
# WEZ_RELEASE_TAG is demoted to the explicit-pin escape hatch (D-01): when set it
# forces the channel to that literal tag (so `WEZ_RELEASE_TAG=v0.1.0` still works),
# but it is NO LONGER the channel default — the hardcoded v0.1.0 pin is gone.
WEZ_CHANNEL="${WEZ_CHANNEL:-nightly}"
if [ -n "${WEZ_RELEASE_TAG:-}" ]; then
  WEZ_CHANNEL="${WEZ_RELEASE_TAG}"
fi
WEZ_RELEASE_BASE="${WEZ_RELEASE_BASE:-https://github.com/castocolina/wezterm-setup/releases/download}"
# The releases-host repo slug + GitHub API host for channel resolution. Derived
# from WEZ_RELEASE_BASE's `.../<owner>/<repo>/releases/download` shape so the API
# stays in lockstep with the download base (override-friendly for tests/forks).
WEZ_RELEASE_REPO="${WEZ_RELEASE_REPO:-castocolina/wezterm-setup}"
WEZ_RELEASE_API="${WEZ_RELEASE_API:-https://api.github.com}"

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
# Shared curl-or-wget fetch-to-stdout helper for the GitHub release API queries
# (channel resolution). Mirrors the curl/wget shape used by download_release and
# bootstrap-wezterm.sh's _wezterm_fetch — DO NOT add a third fetcher.
# ---------------------------------------------------------------------------
_api_fetch() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "${url}"
  else
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Channel -> release tag resolver (D-03/D-08). Echoes the resolved tag on stdout;
# all prompts/logs go to stderr (stdout stays the tag, exactly like
# bootstrap-wezterm.sh select_release). FAIL-LOUD (T-06.3-03-03 / P6-D01/D07): a
# failed/empty/unparseable resolution returns NON-ZERO so download_release aborts
# rather than fetching an empty/`latest`/unverified asset.
#
#   stable    -> GET /repos/<repo>/releases/latest .tag_name (prereleases excluded)
#   nightly   -> newest `nightly-*` tag from /repos/<repo>/releases (prereleases)
#   <literal> -> echoed verbatim (an explicit vX.Y.Z pin)
#
# On a TTY with no channel forced, present a numbered picker (nightly / newest
# stable / a few recent tags); a no-TTY pipe resolves deterministically from
# WEZ_CHANNEL (default nightly) and NEVER blocks on a read.
# ---------------------------------------------------------------------------
resolve_stable_tag() {
  local json tag
  json="$(_api_fetch "${WEZ_RELEASE_API}/repos/${WEZ_RELEASE_REPO}/releases/latest" 2>/dev/null)" || return 1
  [ -n "${json}" ] || return 1
  # Robust field extraction (no jq): split on commas, grab the tag_name token.
  tag="$(printf '%s' "${json}" \
    | tr ',' '\n' \
    | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | head -n1 \
    | grep -oE '"[^"]+"$' \
    | tr -d '"')"
  [ -n "${tag}" ] || return 1
  printf '%s\n' "${tag}"
}

# Echo all `nightly-*` tags (newest first as returned by the API), one per line.
list_nightly_tags() {
  local json
  json="$(_api_fetch "${WEZ_RELEASE_API}/repos/${WEZ_RELEASE_REPO}/releases?per_page=30" 2>/dev/null)" || return 1
  [ -n "${json}" ] || return 1
  printf '%s' "${json}" \
    | tr ',' '\n' \
    | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"nightly-[^"]+"' \
    | grep -oE 'nightly-[^"]+'
}

resolve_nightly_tag() {
  local tag
  tag="$(list_nightly_tags 2>/dev/null | head -n1)" || return 1
  [ -n "${tag}" ] || return 1
  printf '%s\n' "${tag}"
}

resolve_channel_tag() {
  # No-TTY pipe (the curl|bash path): resolve deterministically from WEZ_CHANNEL
  # (default nightly), NEVER prompting. Mirrors select_release()'s `[ ! -t 0 ]`.
  if [ ! -t 0 ]; then
    case "${WEZ_CHANNEL}" in
      nightly)
        log "no TTY on stdin -> resolving the rolling 'nightly' channel (D-02 default)" >&2
        resolve_nightly_tag || { log "ERROR: could not resolve a nightly release tag — refusing to install an unverified asset" >&2; return 1; }
        ;;
      stable)
        log "no TTY on stdin -> resolving the 'stable' channel (/releases/latest)" >&2
        resolve_stable_tag || { log "ERROR: could not resolve the stable /releases/latest tag — refusing to install an unverified asset" >&2; return 1; }
        ;;
      *)
        # An explicit literal tag (vX.Y.Z / the WEZ_RELEASE_TAG escape hatch).
        log "no TTY on stdin -> WEZ_CHANNEL is an explicit tag: ${WEZ_CHANNEL}" >&2
        printf '%s\n' "${WEZ_CHANNEL}"
        ;;
    esac
    return 0
  fi

  # An explicit literal tag short-circuits the TTY picker (a forced pin always
  # wins, with or without a TTY).
  case "${WEZ_CHANNEL}" in
    nightly|stable) : ;;
    *) printf '%s\n' "${WEZ_CHANNEL}"; return 0 ;;
  esac

  # Interactive TTY, channel is the symbolic default: present a numbered picker
  # (1=nightly / 2=newest stable / 3+=recent nightly tags). All menu output to
  # stderr; stdout stays the resolved tag.
  local nightly_tag stable_tag
  nightly_tag="$(resolve_nightly_tag 2>/dev/null || true)"
  stable_tag="$(resolve_stable_tag 2>/dev/null || true)"

  local -a choices=() labels=()
  if [ -n "${nightly_tag}" ]; then
    choices+=("${nightly_tag}"); labels+=("nightly (${nightly_tag})")
  fi
  if [ -n "${stable_tag}" ]; then
    choices+=("${stable_tag}"); labels+=("newest stable (${stable_tag})")
  fi
  local t
  while IFS= read -r t; do
    [ -n "${t}" ] || continue
    [ "${t}" = "${nightly_tag}" ] && continue
    choices+=("${t}"); labels+=("${t}")
  done < <(list_nightly_tags 2>/dev/null | head -n5)

  if [ "${#choices[@]}" -eq 0 ]; then
    log "ERROR: release list empty — could not resolve any channel tag (refusing unverified install)" >&2
    return 1
  fi

  printf 'Select a wez release channel to install:\n' >&2
  local i=1
  for t in "${labels[@]}"; do
    printf '  %d) %s\n' "${i}" "${t}" >&2
    i=$((i + 1))
  done
  local pick
  printf 'Choice [1-%d, default 1]: ' "${#choices[@]}" >&2
  read -r pick || pick=""
  case "${pick}" in
    ''|*[!0-9]*) pick=1 ;;
  esac
  if [ "${pick}" -lt 1 ] || [ "${pick}" -gt "${#choices[@]}" ]; then
    pick=1
  fi
  printf '%s\n' "${choices[$((pick - 1))]}"
}

# ---------------------------------------------------------------------------
# Remote bootstrap path: release-download (channel-resolved + checksum-verified).
# OPT-IN ONLY via WEZ_REMOTE_BOOTSTRAP=1 — never reached on a local source build.
# ---------------------------------------------------------------------------
download_release() {
  local os arch asset url sums_url tag
  os="$(platform_os)"
  arch="$(platform_arch)"
  asset="wez-${os}-${arch}"

  # Resolve the channel to a concrete release tag. A degraded/empty resolution
  # returns non-zero here, so we abort BEFORE constructing any URL — never fall
  # through to an empty/`latest` segment that would fetch an unverified asset.
  if ! tag="$(resolve_channel_tag)" || [ -z "${tag}" ]; then
    log "ERROR: could not resolve WEZ_CHANNEL='${WEZ_CHANNEL}' to a release tag — aborting (no unverified install)"
    return 1
  fi

  url="${WEZ_RELEASE_BASE}/${tag}/${asset}"
  # Per-asset checksum (Plan 01 Open Q2 verdict): one line, '<64-hex>  <name>'.
  sums_url="${WEZ_RELEASE_BASE}/${tag}/${asset}.sha256"

  log "Lua toolchain absent -> release-download fallback (channel=${WEZ_CHANNEL}, tag=${tag}, ${asset})"

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
      log "  Likely cause: no published release for channel '${WEZ_CHANNEL}', or"
      log "  no asset exists for ${os}-${arch}. Check the releases page:"
      log "    ${WEZ_RELEASE_BASE%/download}"
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

# Run main only when EXECUTED, not when SOURCED. The sourcing guard lets the unit
# test (tests/cli/build_channel_test.lua) source this script and exercise
# resolve_channel_tag() without triggering a build. Mirrors bootstrap-wezterm.sh.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
