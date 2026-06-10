#!/usr/bin/env bash
# tools/bootstrap-wezterm.sh
#
# Sudo-free WezTerm EMULATOR bootstrap (INST-06). Resolves the chicken-and-egg of
# Phase 1: WezTerm must exist before any config or `wez` CLI behavior can run.
# Bootstrap/installer GLUE only per D-01 — detection + fetch + place; zero policy
# decisions beyond which install PATH to take.
#
# Flow:
#   1. DETECT  — `wezterm --version`; if it parses to a version meeting the
#      declared MINIMUM, REUSE it untouched and exit 0 (D-07 detection-first /
#      non-destructive). Never modify a system install.
#   2. SELECT  — only when missing/below-minimum: with a TTY, offer the rolling
#      `nightly` + the last 5 dated releases (via tools/lib/wezterm-release.sh)
#      and read the user's pick; without a TTY, use the pinned known-good dated
#      release for reproducibility (D-08).
#   3. FETCH/EXTRACT/SYMLINK (Linux, verified now) — download the matching
#      generic `.Ubuntu<base>.tar.xz` (NOT AppImage, no FUSE, no sudo — D-05),
#      integrity-check it BEFORE extraction (T-02-01), extract into a fresh
#      per-release dir under ~/.local/opt/wezterm (T-02-02), and symlink the
#      in-archive binary into ~/.local/bin (T-02-03 user-path only).
#   4. macOS — a `.app` -> ~/Applications branch is present but DESIGN-ONLY /
#      deferred to the Mac pass (D-06, D-18); not exercised on Linux.
#
# Usage:  ./tools/bootstrap-wezterm.sh        # interactive when a TTY is present
#         ./tools/bootstrap-wezterm.sh < /dev/null   # non-interactive: pinned
#
# Env overrides (testing): WEZTERM_BOOTSTRAP_PREFIX, WEZTERM_BIN_DIR.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=tools/lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"
# shellcheck source=tools/lib/wezterm-release.sh
. "${SCRIPT_DIR}/lib/wezterm-release.sh"

# Minimum acceptable WezTerm: the pinned known-good baseline (D-07/D-08). An
# install at or above this date-stamp is REUSED untouched. WezTerm versions are
# date-stamped (YYYYMMDD-HHMMSS-shortsha); the leading 8-digit date is the
# monotonic comparator we gate on.
WEZTERM_MIN_RELEASE="${WEZTERM_MIN_RELEASE:-${WEZTERM_PINNED_RELEASE}}"

# User-path install locations (D-04/D-05; T-02-03 — never a system path, never sudo).
PREFIX="${WEZTERM_BOOTSTRAP_PREFIX:-${HOME}/.local/opt/wezterm}"
BIN_DIR="${WEZTERM_BIN_DIR:-${HOME}/.local/bin}"

log() { printf '[bootstrap] %s\n' "$*"; }
err() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; }

# --- version helpers ---------------------------------------------------------

# Extract the leading 8-digit YYYYMMDD date stamp from a wezterm version string
# (e.g. "wezterm 20260604-145453-eeb80972" -> "20260604"). Empty if none found.
wezterm_version_datestamp() {
  printf '%s\n' "$1" | grep -oE '[0-9]{8}' | head -n1
}

# Compare two date stamps. Returns 0 (true) if $1 >= $2.
wezterm_datestamp_ge() {
  [ -n "$1" ] && [ -n "$2" ] && [ "$1" -ge "$2" ]
}

# --- STEP 1: DETECT / REUSE --------------------------------------------------

# If an adequate WezTerm is already present, reuse it untouched and exit 0.
# Returns 0 if it handled the bootstrap (reused), 1 if a fetch is required.
detect_and_reuse() {
  command -v wezterm >/dev/null 2>&1 || return 1

  local ver have want
  ver="$(wezterm --version 2>/dev/null || true)"
  have="$(wezterm_version_datestamp "${ver}")"
  want="$(wezterm_version_datestamp "${WEZTERM_MIN_RELEASE}")"

  if [ -z "${have}" ]; then
    log "found a wezterm on PATH but could not parse its version ('${ver}') — treating as below minimum"
    return 1
  fi

  if wezterm_datestamp_ge "${have}" "${want}"; then
    log "existing WezTerm '${ver}' meets minimum ${WEZTERM_MIN_RELEASE} — reusing it untouched (D-07)"
    if [ "$(command -v wezterm)" != "${BIN_DIR}/wezterm" ]; then
      log "note: reused install is outside ${BIN_DIR} (likely a system/managed install); leaving it intact"
    fi
    return 0
  fi

  log "existing WezTerm '${ver}' is below minimum ${WEZTERM_MIN_RELEASE} — will fetch a newer release"
  return 1
}

# --- STEP 2: SELECT ----------------------------------------------------------

# Echo the release tag to install. With a TTY, present nightly + last 5 dated and
# read a pick; without a TTY, use the pinned known-good default (D-08).
select_release() {
  if [ ! -t 0 ]; then
    log "no TTY on stdin — selecting pinned known-good release ${WEZTERM_PINNED_RELEASE} (D-08)" >&2
    printf '%s\n' "${WEZTERM_PINNED_RELEASE}"
    return 0
  fi

  local -a choices=()
  while IFS= read -r tag; do
    [ -n "${tag}" ] && choices+=("${tag}")
  done < <(wezterm_release_list)

  if [ "${#choices[@]}" -eq 0 ]; then
    log "release list empty — falling back to pinned ${WEZTERM_PINNED_RELEASE}" >&2
    printf '%s\n' "${WEZTERM_PINNED_RELEASE}"
    return 0
  fi

  printf 'Select a WezTerm release to install:\n' >&2
  local i=1
  for tag in "${choices[@]}"; do
    printf '  %d) %s\n' "${i}" "${tag}" >&2
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

# --- STEP 3: FETCH / EXTRACT / SYMLINK (Linux) -------------------------------

# Integrity-check a downloaded .tar.xz BEFORE extraction (T-02-01). With no
# published checksum in hand, verify: non-empty, plausible size, and a valid xz
# magic header (probe 01: "\xFD7zXZ\x00"). Returns non-zero on any failure.
verify_tarxz() {
  local file="$1"
  [ -s "${file}" ] || { err "downloaded archive is empty"; return 1; }

  # Plausible minimum size: a real wezterm tarball is tens of MB; anything under
  # ~1 MB is almost certainly an error page or truncated download.
  local size
  size="$(wc -c < "${file}")"
  if [ "${size}" -lt 1000000 ]; then
    err "downloaded archive is implausibly small (${size} bytes) — refusing to extract"
    return 1
  fi

  # xz magic header check (cheap pre-extract sanity, T-02-01).
  local magic
  magic="$(od -An -tx1 -N6 "${file}" | tr -d ' \n')"
  if [ "${magic}" != "fd377a585a00" ]; then
    err "downloaded archive is not a valid xz stream (magic=${magic}) — refusing to extract"
    return 1
  fi
  return 0
}

# Refuse any archive member that is absolute or contains a '..' component
# (T-02-02 path-traversal). Returns non-zero if a dangerous member is present.
assert_safe_members() {
  local file="$1"
  if tar -tJf "${file}" | grep -Eq '^/|(^|/)\.\.(/|$)'; then
    err "archive contains absolute or '..' members — refusing to extract (path traversal)"
    return 1
  fi
  return 0
}

# Download fetch helper (curl or wget).
fetch_to() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${dest}" "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${dest}" "${url}"
  else
    err "neither curl nor wget available to download ${url}"
    return 1
  fi
}

install_linux() {
  local tag="$1"
  local base url tmpdir archive release_dir target

  base="$(platform_ubuntu_base)"
  url="$(wezterm_release_asset_url "${tag}" "${base}")"
  log "fetching ${url}"

  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmpdir}'" RETURN
  archive="${tmpdir}/wezterm-${tag}.Ubuntu${base}.tar.xz"

  if ! fetch_to "${url}" "${archive}"; then
    err "download failed for ${url}"
    return 1
  fi

  # T-02-01 / T-02-02: integrity + path-traversal gates BEFORE extraction.
  verify_tarxz "${archive}" || return 1
  assert_safe_members "${archive}" || return 1

  # Fresh per-release dir (T-02-02): never extract over $HOME root.
  release_dir="${PREFIX}/${tag}"
  rm -rf "${release_dir}"
  mkdir -p "${release_dir}"
  # --no-absolute-names belt-and-suspenders alongside assert_safe_members.
  tar -xJf "${archive}" --no-absolute-names -C "${release_dir}"

  # Probe 01: the binary lives at <release_dir>/wezterm/usr/bin/wezterm.
  local rel_bin
  rel_bin="$(wezterm_release_archive_binary_path)"
  target="${release_dir}/${rel_bin}"
  if [ ! -x "${target}" ]; then
    err "expected binary not found at ${target} (probe-01 layout drift?)"
    return 1
  fi

  mkdir -p "${BIN_DIR}"
  ln -sfn "${target}" "${BIN_DIR}/wezterm"
  log "symlinked ${BIN_DIR}/wezterm -> ${target}"

  # Verify the freshly placed binary runs (R2 — exit code is the evidence).
  if "${BIN_DIR}/wezterm" --version >/dev/null 2>&1; then
    log "installed: $("${BIN_DIR}/wezterm" --version)"
  else
    err "placed binary did not run cleanly: ${BIN_DIR}/wezterm --version"
    return 1
  fi

  case ":${PATH}:" in
    *":${BIN_DIR}:"*) : ;;
    *) log "note: ${BIN_DIR} is not on PATH — add it so 'wezterm' resolves" ;;
  esac
}

# --- macOS (DESIGN-ONLY / deferred to the Mac pass — D-06, D-18) -------------
#
# Present for cross-platform shape; NOT exercised on Linux. The macOS asset is a
# zip containing WezTerm.app, placed under ~/Applications (sudo-free, user-path).
# Verified in the deferred Mac pass — see D-06/D-18. Kept as a branch so the
# control flow is complete and the Mac pass fills in the fetch/unzip specifics.
install_macos() {
  local tag="$1"
  local app_dir="${HOME}/Applications"
  log "macOS path is DESIGN-ONLY / deferred to the Mac pass (D-06, D-18): would place WezTerm.app for ${tag} under ${app_dir}"
  log "skipping macOS install on this run (not verified outside the Mac pass)"
  return 0
}

# --- main --------------------------------------------------------------------

main() {
  if detect_and_reuse; then
    exit 0
  fi

  local os tag
  os="$(platform_os)"
  tag="$(select_release)"
  log "selected release: ${tag}"

  case "${os}" in
    linux) install_linux "${tag}" ;;
    macos) install_macos "${tag}" ;;
    *)
      err "unsupported OS '${os}' — only linux is verified now (macOS deferred, D-18)"
      exit 1
      ;;
  esac
}

# Run main only when EXECUTED, not when SOURCED. Sourcing exposes the individual
# steps (detect_and_reuse / select_release / install_linux / verify_tarxz / ...)
# for end-to-end verification of the fetch path without triggering the reuse
# short-circuit on a host that already has an adequate WezTerm.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
