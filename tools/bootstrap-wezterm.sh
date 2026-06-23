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
#      resolved WANT target (the latest-nightly datestamp by default, or the
#      pinned date when WEZTERM_TARGET=pinned), REUSE it untouched and exit 0
#      (D-07 detection-first / non-destructive). If a PROJECT user-path install
#      (under ${BIN_DIR}) is BEHIND the want, UPDATE IT IN PLACE by reusing the
#      STEP-3 fetch (P6-D09 / SC#8). A SYSTEM install (e.g. /usr/bin/wezterm) is
#      NEVER fetched-over or sudo'd — it is left intact and a user-path copy that
#      wins on PATH is offered instead (gated on wezterm_install_is_user_path).
#   2. SELECT  — only when missing/below-want: with a TTY, offer the rolling
#      `nightly` + the last 5 dated releases (via tools/lib/wezterm-release.sh)
#      and read the user's pick; without a TTY, install the WEZTERM_TARGET
#      (default `nightly`; `pinned`/explicit-tag is the reproducibility opt-in).
#
# Version policy (P6-D09): the install TARGET defaults to the rolling `nightly`
# (WEZTERM_TARGET=nightly), INCLUDING the non-interactive pipe path. The pinned
# dated release (WEZTERM_PINNED_RELEASE) stays an explicit opt-in via
# WEZTERM_TARGET=pinned. WEZTERM_MIN_RELEASE remains the distinct reuse FLOOR.
#   3. FETCH/EXTRACT/SYMLINK (Linux, verified now) — download the matching
#      generic `.Ubuntu<base>.tar.xz` (NOT AppImage, no FUSE, no sudo — D-05),
#      integrity-check it BEFORE extraction (T-02-01), extract into a fresh
#      per-release dir under ~/.local/opt/wezterm (T-02-02), and symlink the
#      in-archive binary into ~/.local/bin (T-02-03 user-path only).
#   4. macOS (REAL, D-04/D-05) — fetch the official nightly macOS `.zip`,
#      integrity-gate it BEFORE extract (PK magic + size + member-safety), extract
#      with `ditto -x -k`, and place WezTerm.app under ~/Applications (user-path,
#      sudo-free, no DMG/hdiutil). Does NOT pre-strip com.apple.quarantine (D-07 —
#      verify-then-decide is Plan 04's job).
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

# Reuse FLOOR: the absolute minimum a found install must meet before it is
# considered usable at all (D-07/D-08). Distinct from the install TARGET below.
# WezTerm versions are date-stamped (YYYYMMDD-HHMMSS-shortsha); the leading
# 8-digit date is the monotonic comparator we gate on. An install BELOW this
# floor always triggers a fresh fetch regardless of target.
WEZTERM_MIN_RELEASE="${WEZTERM_MIN_RELEASE:-${WEZTERM_PINNED_RELEASE}}"

# Install TARGET (P6-D09): the version the bootstrap aims to PLACE/UPDATE TO.
# Defaults to the rolling `nightly` — including the non-interactive pipe path —
# so the installer tracks the latest nightly by default. Set WEZTERM_TARGET=pinned
# (or an explicit dated tag) to opt into the reproducible pinned release. This is
# the install TARGET, distinct from the WEZTERM_MIN_RELEASE reuse FLOOR above.
WEZTERM_TARGET="${WEZTERM_TARGET:-nightly}"

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

# Resolve the latest-nightly want-datestamp (06-01-SUMMARY Open-Q1 verdict).
#
# Query: GET ${WEZTERM_RELEASE_API}/repos/${WEZTERM_RELEASE_REPO}/releases/tags/nightly
# (official wez/wezterm HTTPS only, via the same curl-or-wget shape as
# _wezterm_fetch in wezterm-release.sh — DO NOT add a new fetcher). From that
# rolling-tag release, take the OS-base-matched asset's PER-ASSET `updated_at`
# (NEVER the release-level published_at/created_at, which are frozen at the tag's
# 2017/2019 creation and would falsely report "never newer") and reduce it to the
# leading 8-digit YYYYMMDD, comparable by wezterm_datestamp_ge.
#
# GRACEFUL DEGRADATION (T-06-06-01): a failed/garbage/unparseable fetch prints
# NOTHING (empty want). The caller treats an empty want as a NO-OP (reuse
# untouched) so a tampered/missing "newer?" signal can NEVER force a swap. We
# never fabricate a datestamp.
latest_nightly_datestamp() {
  local api_url base asset_name json updated
  api_url="${WEZTERM_RELEASE_API}/repos/${WEZTERM_RELEASE_REPO}/releases/tags/nightly"

  # Match the asset to THIS host's OS base so we compare like-for-like (Ubuntu20
  # lags 24 by months — Open-Q1 caveat). macOS stays design-only (D-06/D-18).
  case "$(platform_os)" in
    linux)
      base="$(platform_ubuntu_base 2>/dev/null)" || base=""
      [ -n "${base}" ] && asset_name="wezterm-nightly.Ubuntu${base}.tar.xz"
      ;;
    macos) asset_name="WezTerm-macos-nightly.zip" ;;
  esac
  [ -n "${asset_name:-}" ] || return 0

  json="$(_wezterm_fetch "${api_url}" 2>/dev/null)" || return 0
  [ -n "${json}" ] || return 0

  # Pull the `updated_at` that belongs to the matched asset's object. We scope to
  # the window AFTER the asset's "name" and grab the NEXT updated_at — robust to
  # the assets[] ordering without a strict full-document jq parse (the releases
  # payload can carry C0 control chars in bodies; see wezterm-release.sh).
  updated="$(printf '%s' "${json}" \
    | tr ',' '\n' \
    | grep -A40 -F "\"${asset_name}\"" 2>/dev/null \
    | grep -oE '"updated_at"[[:space:]]*:[[:space:]]*"[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    | head -n1 \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
    | head -n1 \
    | tr -d '-')"

  # Only emit a real 8-digit stamp; anything else degrades to empty (no-op).
  case "${updated}" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) printf '%s\n' "${updated}" ;;
    *) return 0 ;;
  esac
}

# Resolve the WANT datestamp the active install is compared against:
#   - WEZTERM_TARGET=nightly (default) -> the latest-nightly datestamp (may be
#     empty on fetch failure -> caller treats as no-op / never a forced swap).
#   - otherwise (pinned / explicit dated tag) -> the datestamp of that target,
#     defaulting to WEZTERM_PINNED_RELEASE when WEZTERM_TARGET=pinned.
resolve_want_datestamp() {
  if [ "${WEZTERM_TARGET}" = "nightly" ]; then
    latest_nightly_datestamp
    return 0
  fi
  local target="${WEZTERM_TARGET}"
  [ "${target}" = "pinned" ] && target="${WEZTERM_PINNED_RELEASE}"
  wezterm_version_datestamp "${target}"
}

# Install-kind predicate (P6-D09 safety gate / Blocker 3). Returns 0 (true) iff
# the active `wezterm` binary resolves UNDER ${BIN_DIR} (the project user-path
# install), non-zero (false) for any other path (e.g. /usr/bin/wezterm — the
# verified apt `wezterm-nightly` SYSTEM install). The update-in-place branch and
# any symlink swap are GATED on this = user-path so a system install is NEVER
# fetched-over or sudo'd. Reusable by cli/commands/update.lua (Plan 05).
#
# Arg: $1 = a wezterm path to classify; when omitted, resolves the active one via
# `command -v wezterm`. Pure path compare — unit-testable by sourcing the script.
wezterm_install_is_user_path() {
  local path="${1:-}"
  if [ -z "${path}" ]; then
    path="$(command -v wezterm 2>/dev/null || true)"
  fi
  [ -n "${path}" ] || return 1
  case "${path}" in
    "${BIN_DIR}/"*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- STEP 1: DETECT / REUSE --------------------------------------------------

# If an adequate WezTerm is already present, reuse it untouched and exit 0.
# When a PROJECT user-path install is BEHIND the resolved WANT (the latest-nightly
# datestamp by default), UPDATE IT IN PLACE by reusing the STEP-3 fetch (SC#8 /
# P6-D09). A SYSTEM install is NEVER fetched-over or sudo'd — it is left intact and
# routed to a user-path placement that wins on PATH.
#
# Returns 0 if it handled the bootstrap (reused or updated in place), 1 if main()
# must proceed to select_release + install_linux (fresh / user-path placement).
detect_and_reuse() {
  command -v wezterm >/dev/null 2>&1 || return 1

  local ver wez_path have floor want
  ver="$(wezterm --version 2>/dev/null || true)"
  wez_path="$(command -v wezterm 2>/dev/null || true)"
  have="$(wezterm_version_datestamp "${ver}")"
  # Reuse FLOOR (the absolute minimum) and install WANT (the target: latest
  # nightly by default, else the pinned/explicit-tag date). These are distinct.
  floor="$(wezterm_version_datestamp "${WEZTERM_MIN_RELEASE}")"
  want="$(resolve_want_datestamp)"

  if [ -z "${have}" ]; then
    log "found a wezterm on PATH but could not parse its version ('${ver}') — treating as below minimum"
    return 1
  fi

  # Below the absolute floor -> always a fresh fetch, regardless of target.
  if ! wezterm_datestamp_ge "${have}" "${floor}"; then
    log "existing WezTerm '${ver}' is below minimum ${WEZTERM_MIN_RELEASE} — will fetch a newer release"
    return 1
  fi

  # At/above the floor. Decide against the WANT target.
  #   - empty want (degraded/failed latest-nightly fetch) -> treat as no-op
  #     (reuse untouched); a garbage "newer?" signal NEVER forces a swap (T-06-06-01).
  #   - have >= want                                      -> reuse untouched (no-op).
  if [ -z "${want}" ] || wezterm_datestamp_ge "${have}" "${want}"; then
    if [ -z "${want}" ]; then
      log "could not resolve a latest-nightly want — reusing existing WezTerm '${ver}' untouched (no forced swap)"
    else
      log "existing WezTerm '${ver}' meets target ${want} (>= floor ${WEZTERM_MIN_RELEASE}) — reusing it untouched (D-07)"
    fi
    # Install-kind detection lives in the reusable wezterm_install_is_user_path()
    # predicate (Blocker 3); here it is informational only.
    if ! wezterm_install_is_user_path "${wez_path}"; then
      log "note: reused install is outside ${BIN_DIR} (likely a system/managed install); leaving it intact"
    fi
    return 0
  fi

  # have < want: a newer nightly exists. The update-in-place + any swap are GATED
  # on the user-path predicate (P6-D09 Blocker 3).
  if wezterm_install_is_user_path "${wez_path}"; then
    # Project user-path install behind the want -> UPDATE IN PLACE by REUSING the
    # existing STEP-3 fetch/extract/symlink (install_linux). Never re-implement
    # fetch; never touch a system path (SC#8).
    log "project user-path WezTerm '${ver}' (${have}) is behind target ${want} — updating in place"
    if install_linux "$(select_release)"; then
      return 0
    fi
    err "in-place update failed; leaving the existing user-path install in place"
    return 0
  fi

  # System install (e.g. /usr/bin/wezterm, the apt wezterm-nightly case) behind
  # the want -> NEVER fetch-over/sudo it. Leave it intact and route main() to a
  # user-path placement under ${BIN_DIR} that wins on PATH (install_linux writes
  # ONLY under ${PREFIX}/${BIN_DIR} — sudo-free, system path untouched).
  log "a newer nightly (${want}) is available, but the active WezTerm '${wez_path}' is a SYSTEM install — leaving it intact (no sudo)"
  log "will place a user-path copy under ${BIN_DIR} that wins on PATH (P6-D09)"
  return 1
}

# --- STEP 2: SELECT ----------------------------------------------------------

# Echo the release tag to install. With a TTY, present nightly + last 5 dated and
# read a pick; without a TTY, install WEZTERM_TARGET — the rolling `nightly` by
# default (P6-D09), or the pinned/explicit dated tag when WEZTERM_TARGET=pinned
# (or set to a literal tag) for reproducibility (D-08).
select_release() {
  if [ ! -t 0 ]; then
    case "${WEZTERM_TARGET}" in
      nightly)
        log "no TTY on stdin — targeting the rolling 'nightly' (P6-D09 default)" >&2
        printf '%s\n' "nightly"
        ;;
      pinned)
        log "no TTY on stdin — WEZTERM_TARGET=pinned: selecting pinned release ${WEZTERM_PINNED_RELEASE} (D-08)" >&2
        printf '%s\n' "${WEZTERM_PINNED_RELEASE}"
        ;;
      *)
        log "no TTY on stdin — WEZTERM_TARGET is an explicit tag: selecting ${WEZTERM_TARGET}" >&2
        printf '%s\n' "${WEZTERM_TARGET}"
        ;;
    esac
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

# Place the shipped XDG desktop entry + icon(s) into the user-space XDG data dirs
# so the WezTerm app shows up in the desktop launcher and can be pinned. Pure
# bash glue (D-01): no install/version decisions, sudo-free, idempotent (cp -f),
# Linux-only (called from install_linux). NON-FATAL by design — a missing desktop
# file or absent cache tool is logged and skipped, never failing the install.
#
# Arg: $1 = the per-release dir (${PREFIX}/${tag}). Shipped assets live under
# <release_dir>/wezterm/usr/share/{applications,icons}. The .desktop's Exec/Icon
# are left AS-IS (Exec resolves wezterm via ~/.local/bin on PATH; Icon resolves
# from the placed hicolor theme).
install_desktop_entry() {
  local release_dir="$1"
  local xdg share_apps share_icons desktop_src desktop_name
  xdg="${XDG_DATA_HOME:-$HOME/.local/share}"
  share_apps="${release_dir}/wezterm/usr/share/applications"
  share_icons="${release_dir}/wezterm/usr/share/icons"
  desktop_name="org.wezfurlong.wezterm.desktop"
  desktop_src="${share_apps}/${desktop_name}"

  if [ ! -f "${desktop_src}" ]; then
    log "no shipped desktop entry at ${desktop_src} — skipping launcher integration (non-fatal)"
    return 0
  fi

  # Place the .desktop into ${XDG_DATA_HOME}/applications (idempotent overwrite).
  mkdir -p "${xdg}/applications"
  cp -f "${desktop_src}" "${xdg}/applications/${desktop_name}"
  log "placed ${xdg}/applications/${desktop_name}"

  # Mirror ALL shipped icons, preserving the hicolor/<size>/apps structure, so
  # every available size lands in the user icon theme (not just 128x128).
  if [ -d "${share_icons}" ]; then
    local icon_count=0 icon_file rel dest_dir
    while IFS= read -r icon_file; do
      [ -n "${icon_file}" ] || continue
      rel="${icon_file#"${share_icons}"/}"
      dest_dir="${xdg}/icons/$(dirname "${rel}")"
      mkdir -p "${dest_dir}"
      cp -f "${icon_file}" "${dest_dir}/"
      icon_count=$((icon_count + 1))
    done < <(find "${share_icons}" -type f 2>/dev/null)
    log "placed ${icon_count} icon file(s) under ${xdg}/icons"
  else
    log "no shipped icons at ${share_icons} — skipping icon placement (non-fatal)"
  fi

  # Best-effort, non-fatal cache refresh so the entry/icon surface immediately on
  # DEs that read the caches. Both tools may be absent; never let them fail install.
  update-desktop-database "${xdg}/applications" 2>/dev/null || true
  gtk-update-icon-cache -f -t "${xdg}/icons/hicolor" 2>/dev/null || true
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
  # Extract into the fresh per-release dir. Path-traversal safety is already
  # enforced by assert_safe_members() above (rejects absolute / '..' members),
  # and both GNU tar and macOS/BSD tar strip a leading '/' by default — so no
  # extra flag is needed here. (A previous BSD-only absolute-names guard flag was
  # removed: GNU tar rejected it as an unrecognized option and broke every Linux
  # install; it went uncaught because the e2e curl|bash path was never run.)
  tar -xJf "${archive}" -C "${release_dir}"

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

  # Place the shipped XDG launcher entry + icon(s) so WezTerm appears in the
  # desktop bar / app menu and can be pinned (non-fatal, sudo-free, idempotent).
  install_desktop_entry "${release_dir}"

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

# --- macOS (REAL, sudo-free `.app` placement — D-04/D-05/D-07) ---------------
#
# The structural mirror of install_linux with the OS/asset specifics swapped:
# fetch the official WezTerm nightly macOS `.zip` (via the SHARED fetch_to — never
# a new downloader), integrity-gate it BEFORE extraction (T-07-04 PK magic + size
# floor; T-07-05 reject absolute/`..` members — NEVER extract-then-check), extract
# with Apple-native `ditto -x -k` (fall back to `unzip` only if ditto is absent)
# into a scratch dir, then rm -rf + cp -R the WezTerm.app bundle into
# ${HOME}/Applications (user-path only — never the system /Applications, never
# sudo, never hdiutil/DMG — D-05). Version selection (the `tag` arg) is fed by the
# SAME resolve_want_datestamp + select_release path the Linux branch uses, so both
# OSes track the same nightly contract (D-05).
#
# D-07: this does NOT pre-strip com.apple.quarantine. Whether curl downloads carry
# quarantine and trip Gatekeeper is verified empirically on hardware in Plan 04
# (verify-then-decide); a non-launching binary here is LOGGED, not a hard fail.
install_macos() {
  local tag="$1"
  local app_dir="${HOME}/Applications"
  local url tmpdir zip size magic

  url="$(wezterm_macos_asset_url "${tag}")"
  log "fetching ${url}"

  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmpdir}'" RETURN
  zip="${tmpdir}/WezTerm.zip"

  if ! fetch_to "${url}" "${zip}"; then
    err "download failed for ${url}"
    return 1
  fi

  # T-07-04: integrity gate BEFORE extraction. Reject empty / implausibly small
  # downloads and anything lacking the PK zip local-file-header magic 504b0304.
  if [ ! -s "${zip}" ]; then
    err "downloaded archive is empty — refusing to extract"
    return 1
  fi
  size="$(wc -c < "${zip}")"
  if [ "${size}" -lt 1000000 ]; then
    err "downloaded archive is implausibly small (${size} bytes) — refusing to extract"
    return 1
  fi
  magic="$(od -An -tx1 -N4 "${zip}" | tr -d ' \n')"
  if [ "${magic}" != "504b0304" ]; then
    err "downloaded archive is not a valid zip stream (magic=${magic}) — refusing to extract"
    return 1
  fi

  # T-07-05: reject absolute / '..' members BEFORE copying any bundle out (zip
  # path-traversal). `unzip -Z1` (zipinfo "names only" mode) emits ONE bare member
  # name per line with NO header/footer — unlike `unzip -l`, whose "Archive: <abs
  # path>" header would itself be a false-positive absolute match. BSD unzip ships
  # stock on macOS and on Linux CI.
  if unzip -Z1 "${zip}" 2>/dev/null | grep -Eq '^/|(^|/)\.\.(/|$)'; then
    err "archive contains absolute or '..' members — refusing to extract (path traversal)"
    return 1
  fi

  # Extract into a scratch dir with Apple-native ditto (preserves the bundle's
  # extended attributes / symlinks); fall back to unzip only if ditto is absent.
  local unzipped="${tmpdir}/unzipped"
  mkdir -p "${unzipped}"
  if command -v ditto >/dev/null 2>&1; then
    ditto -x -k "${zip}" "${unzipped}"
  else
    unzip -q "${zip}" -d "${unzipped}"
  fi

  # The nightly macOS `.zip` wraps the bundle inside a top-level dated dir
  # (WezTerm-macos-<tag>/WezTerm.app/...), so locate WezTerm.app anywhere in the
  # extracted tree rather than assuming it sits at the scratch root.
  local app_src
  app_src="$(find "${unzipped}" -maxdepth 3 -type d -name 'WezTerm.app' 2>/dev/null | head -n1)"
  if [ -z "${app_src}" ] || [ ! -d "${app_src}" ]; then
    err "expected WezTerm.app not found in the extracted archive — layout drift?"
    return 1
  fi

  # Place under ${HOME}/Applications (user-path only — never /Applications, never
  # sudo). Fresh placement: rm -rf the prior bundle then cp -R the new one.
  mkdir -p "${app_dir}"
  rm -rf "${app_dir}/WezTerm.app"
  cp -R "${app_src}" "${app_dir}/WezTerm.app"
  log "placed ${app_dir}/WezTerm.app"

  # Run-the-binary evidence (exit code is the proof). D-07: a non-launch here is a
  # NOTE, not a hard fail — Gatekeeper/quarantine is Plan 04's verify-then-decide.
  if "${app_dir}/WezTerm.app/Contents/MacOS/wezterm" --version >/dev/null 2>&1; then
    log "installed: $("${app_dir}/WezTerm.app/Contents/MacOS/wezterm" --version)"
  else
    log "note: ${app_dir}/WezTerm.app/Contents/MacOS/wezterm did not run cleanly — if Gatekeeper blocks it, see Plan 04 (quarantine is verify-then-decide, D-07)"
  fi

  # Symlink the bundled CLI onto the user PATH, mirroring install_linux:449-451.
  # `wez scene new` / `wez scene launch` shell out to `wezterm` BY NAME; the macOS
  # `.app` keeps the CLI at Contents/MacOS/wezterm and never exports it, so a clean
  # install fails `mux returned a non-numeric pane id`. Sudo-free, user-path only,
  # no shell-rc edits; `ln -sfn` is idempotent on re-install/update (D-01 / A-4,
  # closes macOS deviation #6 — restores Linux↔macOS install symmetry).
  local wez_bin="${app_dir}/WezTerm.app/Contents/MacOS/wezterm"
  mkdir -p "${BIN_DIR}"
  ln -sfn "${wez_bin}" "${BIN_DIR}/wezterm"
  log "symlinked ${BIN_DIR}/wezterm -> ${wez_bin}"

  case ":${PATH}:" in
    *":${BIN_DIR}:"*) : ;;
    *) log "note: ${BIN_DIR} is not on PATH — add it so 'wezterm' resolves" ;;
  esac
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
