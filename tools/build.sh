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
#     * stable             — GitHub's latest-release API, which EXCLUDES
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
# rolling build); `stable` -> the latest-release API; `<vX.Y.Z>` -> that literal tag.
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
# ---------------------------------------------------------------------------
# D-11 branch-aware version stamp. Resolve the version string the shipped binary
# reports via `wez version`, and stamp it into cli/spec.lua's M.VERSION constant
# at build time (the file comment already designates this the build/installer
# stamp point). The string is:
#
#   <channel-tag>                on the `main` branch (or when no branch context)
#   <channel-tag>+<branchname>   on ANY non-main branch (D-11)
#
# so the published asset is identifiable as branch-built and the autonomous E2E
# loop installs+verifies THIS branch's artifact (the GitHub release TAG itself
# stays `nightly-YYYYMMDD`; the `+<branchname>` lives only in the embedded
# version string, since `+` is not tag-name-safe). SemVer build-metadata only
# allows [0-9A-Za-z-] (and `.`), so `/` in a branch name maps to `-`.
#
# Inputs (all optional; this is glue, not policy):
#   * WEZ_BUILD_VERSION — an explicit full version string (CI's Resolve step can
#     pass the resolved $TAG here). When set it is the channel-tag base.
#   * WEZ_BUILD_BRANCH  — the branch name (CI passes $GITHUB_REF_NAME; locally we
#     fall back to `git branch --show-current`).
# When no base is resolvable we leave M.VERSION untouched (the in-repo default).
resolve_build_version() {
  local base branch sanitized
  base="${WEZ_BUILD_VERSION:-}"
  if [ -z "${base}" ]; then
    # No explicit base (local dev build): derive a datestamped nightly base so a
    # local build is still identifiable, mirroring release.yml's nightly tag shape.
    base="nightly-$(date -u +%Y%m%d)"
  fi
  branch="${WEZ_BUILD_BRANCH:-}"
  if [ -z "${branch}" ]; then
    branch="$(git -C "${REPO_ROOT}" branch --show-current 2>/dev/null || true)"
  fi
  if [ -n "${branch}" ] && [ "${branch}" != "main" ]; then
    sanitized="$(printf '%s' "${branch}" | tr '/' '-' | tr -cd '0-9A-Za-z.-')"
    printf '%s+%s\n' "${base}" "${sanitized}"
  else
    printf '%s\n' "${base}"
  fi
}

build_with_luastatic() {
  log "luastatic toolchain present -> static single-binary build"

  # D-11: stamp the branch-aware version into cli/spec.lua BEFORE luastatic bundles
  # it, then restore the original immediately AFTER the bundle so a local `make
  # build` never leaves the tree dirty (in CI the checkout is ephemeral, but the
  # restore keeps the dev tree clean too). We deliberately do NOT use a RETURN trap:
  # the luastatic step below runs in a `( )` subshell, and a RETURN trap can fire on
  # that subshell's return (consuming the backup early), so we save + restore
  # explicitly around the bundle instead. SPEC_BAK is function-scoped and the
  # restore is unconditional via the `[ -n "${SPEC_BAK}" ]` guard at the call site.
  local version spec_file SPEC_BAK=""
  version="$(resolve_build_version)"
  spec_file="${REPO_ROOT}/cli/spec.lua"
  if [ -n "${version}" ] && [ -f "${spec_file}" ]; then
    SPEC_BAK="$(mktemp)"
    cp "${spec_file}" "${SPEC_BAK}"
    # Replace the M.VERSION literal. The version contains only tag/date/branch
    # chars (digits, letters, '.', '-', '+') — no '/' or sed-delimiter conflict —
    # so a '#'-delimited s### is safe. `sed -i.sedtmp` is portable across GNU/BSD
    # (both honor the suffix arg); remove the suffixed backup it leaves behind.
    sed -i.sedtmp "s#^M\.VERSION = \".*\"#M.VERSION = \"${version}\"#" "${spec_file}"
    rm -f "${spec_file}.sedtmp"
    log "D-11: stamped version -> ${version}"
  fi

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

  # macOS keg-only fallback (D-08): Homebrew's lua@5.4 is keg-only, so its .pc is
  # NOT on the default pkg-config path (and pkg-config may be absent entirely),
  # which makes the Debian-oriented probes above resolve to the wrong header path
  # (/usr/include/lua5.4 does not exist on macOS) and the wrong static archive
  # (/usr/local/lib/liblua.a points at the bare `lua` 5.5 formula). When running
  # on macOS with the lua@5.4 keg present, resolve cflags + liblua directly from
  # the keg prefix (setup-dev.sh installs it there). Branch on availability, not
  # OS hard-coding: only override when the keg's header + static lib actually exist.
  if [ "$(platform_os)" = "macos" ] && command -v brew >/dev/null 2>&1; then
    local keg
    keg="$(brew --prefix lua@5.4 2>/dev/null || true)"
    if [ -n "${keg}" ] && [ -f "${keg}/include/lua5.4/lauxlib.h" ] && [ -f "${keg}/lib/liblua.a" ]; then
      lua_cflags="-I${keg}/include/lua5.4"
      liblua="${keg}/lib/liblua.a"
    fi
  fi

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

  # D-11: the bundle is baked — restore the original cli/spec.lua now so the dev
  # tree is left byte-clean (the stamped version is already inside the binary).
  if [ -n "${SPEC_BAK}" ]; then
    mv -f "${SPEC_BAK}" "${spec_file}"
  fi

  # luastatic writes ./<name> (and ./<name>.c) into the cwd (REPO_ROOT). Normalize
  # the binary to dist/wez and clean up the generated C translation unit.
  rm -f "${REPO_ROOT}/wez.luastatic.c"
  if [ -f "${REPO_ROOT}/wez" ]; then
    mv "${REPO_ROOT}/wez" "${OUT}"
  fi
  chmod +x "${OUT}"

  # Build-time ad-hoc codesign (D-06) — macOS ONLY. The codesign calls MUST stay
  # inside this platform_os=macos guard: Linux has no `codesign` binary, so an
  # unguarded call would break the Linux leg. We sign BOTH macOS arches uniformly
  # (the arm64 Mach-O is the one the kernel SIGKILLs when unsigned; signing the
  # x86_64 binary too is harmless and keeps CI and `make publish` producing the
  # same signed asset — the publish.sh same-contract rule, widened from arm64-only
  # to both arches). `codesign --verify --verbose` is the EVIDENCE line proving a
  # valid signature. We intentionally do NOT gate the build on Gatekeeper
  # assessment: it ALWAYS rejects ad-hoc signatures (Pitfall 4), so its rejection
  # is meaningless here — `codesign --verify` success is the real evidence.
  if [ "$(platform_os)" = "macos" ]; then
    log "macOS -> ad-hoc codesign + verify ${OUT}"
    codesign --force --sign - "${OUT}"
    codesign --verify --verbose "${OUT}"
  fi

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
# all prompts/logs go to stderr (stdout stays the tag, like bootstrap-wezterm.sh
# select_release). FAIL-LOUD (T-06.3-03-03 / P6-D01/D07): an empty/unparseable
# resolution returns NON-ZERO so download_release aborts rather than fetching an
# unverified asset. stable -> the latest-release API .tag_name (prereleases
# excluded); nightly -> newest `nightly-*`; <literal> -> verbatim. A no-TTY pipe
# resolves deterministically from WEZ_CHANNEL (default nightly) and never blocks.
# ---------------------------------------------------------------------------

# Generic JSON string extractor (no external JSON tool) — the SINGLE shared
# idiom. Reads JSON on STDIN, takes a field name as $1, echoes the FIRST top-level
# string value of that field. Callers pass ONLY literal field names (tag_name /
# published_at — never user input), so the field interpolates into the grep ERE
# with no escaping. DO NOT re-inline this per field.
_json_str() {
  local field="$1"
  tr ',' '\n' \
    | grep -oE "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" \
    | head -n1 | grep -oE '"[^"]+"$' | tr -d '"'
}

# Single-fetch stable resolver: ONE _api_fetch of the latest-release API yields
# BOTH the tag (line 1, REQUIRED) and the YYYY-MM-DD date (line 2, best-effort,
# possibly empty) from that ONE payload — reuses _api_fetch + _json_str (no third
# fetcher, no duplicate idiom). Empty fetch / missing tag -> NON-ZERO; a
# missing/unparseable published_at only leaves the date empty (never aborts).
resolve_stable_latest() {
  local json tag date
  json="$(_api_fetch "${WEZ_RELEASE_API}/repos/${WEZ_RELEASE_REPO}/releases/latest" 2>/dev/null)" || return 1
  [ -n "${json}" ] || return 1
  tag="$(printf '%s' "${json}" | _json_str tag_name)"
  [ -n "${tag}" ] || return 1
  # Date is best-effort: reduce the raw ISO8601 published_at to its leading
  # YYYY-MM-DD via pure grep -oE (no `date`/`cut -dT`/GNU-only flags — portable).
  # `|| true` so a missing/unparseable date (no grep match under set -e/pipefail)
  # leaves the date empty WITHOUT aborting — the date line is allowed to be empty.
  date="$(printf '%s' "${json}" | _json_str published_at \
    | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"
  printf '%s\n%s\n' "${tag}" "${date}"
}

# THIN delegate over resolve_stable_latest. FROZEN OUTPUT CONTRACT: echoes ONLY
# the bare tag (feeds download_release's URL), non-zero on failure. The only
# change vs. before is internal delegation — NO date logic (no published_at).
resolve_stable_tag() {
  local tag
  tag="$(resolve_stable_latest | head -n1)" || return 1
  [ -n "${tag}" ] || return 1
  printf '%s\n' "${tag}"
}

# Echo all `nightly-*` tags (newest first as returned by the API), one per line.
# NOTE: this does NOT reuse `_json_str` — it needs ALL nightly-* values (a list,
# filtered to the `nightly-` prefix), not the first single top-level string, so
# the single-value first-match shape of `_json_str` does not fit. Left as-is.
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
        log "no TTY on stdin -> resolving the 'stable' channel (latest-release API)" >&2
        resolve_stable_tag || { log "ERROR: could not resolve the stable latest-release tag — refusing to install an unverified asset" >&2; return 1; }
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
  local nightly_tag stable_out stable_tag stable_date
  nightly_tag="$(resolve_nightly_tag 2>/dev/null || true)"
  # ONE fetch for the stable arm: resolve_stable_latest yields tag (line 1) +
  # YYYY-MM-DD date (line 2, possibly empty) from a single latest-release call.
  # Tolerate empty (|| true); split into tag/date with POSIX `sed -n`.
  stable_out="$(resolve_stable_latest 2>/dev/null || true)"
  stable_tag="$(printf '%s\n' "${stable_out}" | sed -n 1p)"
  stable_date="$(printf '%s\n' "${stable_out}" | sed -n 2p)"

  local -a choices=() labels=()
  if [ -n "${nightly_tag}" ]; then
    choices+=("${nightly_tag}"); labels+=("nightly (${nightly_tag})")
  fi
  if [ -n "${stable_tag}" ]; then
    # Date-augment the stable label for parity with the nightly tag (which bakes
    # its date into the tag itself). The date is best-effort: when present emit
    # the date-bearing label, else fall back to the tag-only label (NEVER abort).
    # No extra fetch — the date rides the single resolve_stable_latest call above.
    choices+=("${stable_tag}")
    if [ -n "${stable_date}" ]; then
      labels+=("newest stable (${stable_tag} · ${stable_date})")
    else
      labels+=("newest stable (${stable_tag})")
    fi
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

# Resolve a Lua 5.4 interpreter for the dev source-launcher, echoing its path on
# stdout (all diagnostics to stderr). Mirrors the keg-only macOS idiom the
# luastatic static path already uses (lines ~202-209): on macOS, Homebrew's
# `lua@5.4` is keg-only so `lua5.4` is NOT on the default PATH — a bare
# `exec lua5.4` in the generated launcher would die `exec: lua5.4: not found`
# (exit 127). Resolution order, FAIL-LOUD when none is found:
#   1. `lua5.4` on PATH                              -> its `command -v` path.
#   2. `$(brew --prefix lua@5.4)/bin/lua5.4` (keg)   -> when brew + the keg exist.
#   3. a `lua` on PATH that REPORTS 5.4              -> guards against the bare
#      Homebrew `lua` 5.5 formula (only accept when `lua -v` says `Lua 5.4`).
#   4. none -> stderr ERROR + `return 1` so build_dev_launcher aborts before
#      generating an inert launcher.
# bash-3.2-safe (no ${var,,}, no associative arrays), sudo-free, no new deps.
resolve_dev_lua() {
  local p keg

  # 1. lua5.4 on PATH (the Linux/keg-on-PATH happy path).
  if p="$(command -v lua5.4 2>/dev/null)" && [ -n "${p}" ]; then
    printf '%s\n' "${p}"
    return 0
  fi

  # 2. macOS keg-only lua@5.4 (same idiom as build_with_luastatic, ~lines 202-209).
  if command -v brew >/dev/null 2>&1; then
    keg="$(brew --prefix lua@5.4 2>/dev/null || true)"
    if [ -n "${keg}" ] && [ -x "${keg}/bin/lua5.4" ]; then
      printf '%s\n' "${keg}/bin/lua5.4"
      return 0
    fi
  fi

  # 3. a bare `lua` that actually reports 5.4 (NOT the Homebrew `lua` 5.5 formula).
  if p="$(command -v lua 2>/dev/null)" && [ -n "${p}" ]; then
    if "${p}" -v 2>&1 | grep -q 'Lua 5\.4'; then
      printf '%s\n' "${p}"
      return 0
    fi
  fi

  # 4. fail loud — never generate a launcher that will 127 at runtime.
  log "ERROR: no Lua 5.4 interpreter found (need 'lua5.4' on PATH, a Homebrew" >&2
  log "       'lua@5.4' keg, or a 'lua' reporting 5.4) — run tools/setup-dev.sh" >&2
  return 1
}

build_dev_launcher() {
  log "luastatic absent (local build) -> dev source-launcher (NOT a release artifact)"

  # Resolve the Lua 5.4 interpreter ONCE at build time and BAKE its path into the
  # generated launcher's exec line (consistent with how REPO_ROOT is baked). A
  # failed resolution aborts here rather than emitting an inert launcher.
  local DEV_LUA
  DEV_LUA="$(resolve_dev_lua)" || exit 1

  cat >"${OUT}" <<EOF
#!/usr/bin/env bash
# wez — DEV source launcher (generated by tools/build.sh path 3).
# Not a release artifact: it execs the resolved Lua 5.4 interpreter against the
# in-repo Lua sources. A shipped build uses the luastatic single binary instead.
REPO_ROOT="${REPO_ROOT}"
exec "${DEV_LUA}" "\${REPO_ROOT}/${ENTRY}" "\$@"
EOF
  chmod +x "${OUT}"
  log "built dev launcher: ${OUT} (interpreter: ${DEV_LUA})"
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
