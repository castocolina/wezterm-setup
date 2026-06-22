#!/usr/bin/env bash
# tools/lib/wezterm-release.sh
#
# Sourceable helper for the WezTerm emulator bootstrap (tools/bootstrap-wezterm.sh,
# Plan 02). Two responsibilities, both PURE glue per D-01 (no install/decision
# logic — that stays in the bootstrap flow and, ultimately, the Lua `wez` CLI):
#
#   1. wezterm_release_list  -> the SELECTABLE set: the rolling `nightly` tag plus
#      the last 5 DATED releases, from the GitHub releases API for wez/wezterm.
#      Per D-08 the version model is ONE rolling `nightly` + the listable DATED
#      releases. Degrades gracefully to the pinned known-good default when the API
#      is unreachable / rate-limited / unparseable (T-02-04 accept).
#
#   2. wezterm_release_asset_url <tag> <ubuntu_base>  -> the HTTPS download URL of
#      the generic Linux `.tar.xz` asset for that release + Ubuntu base, using the
#      asset-name pattern probe 02 confirmed.
#
# Source it:  . tools/lib/wezterm-release.sh
# Then call:  wezterm_release_list ; wezterm_release_asset_url <tag> <base>
#
# Meant to be SOURCED, not executed. Defines functions; sets no `set -e` so it
# never disturbs the sourcing shell's options.

# Pinned known-good default release (D-08). This is the audited WezTerm version
# (see .planning/decisions/wezterm-cli-surface.md). The non-interactive bootstrap
# default AND the graceful-degradation fallback when the releases API is
# unavailable. Probe 02: the public wez/wezterm API may sit BEHIND this pinned
# build (the audited local build is ahead of the public dated releases), so we
# always keep the pinned value reachable rather than depending on the API for it.
: "${WEZTERM_PINNED_RELEASE:=20260604-145453}"

# Official upstream release host (T-02-05: fetch ONLY from here, over HTTPS; the
# asset URL is built from a pinned/selected tag, never from arbitrary input).
: "${WEZTERM_RELEASE_REPO:=wez/wezterm}"
: "${WEZTERM_RELEASE_HOST:=https://github.com}"
: "${WEZTERM_RELEASE_API:=https://api.github.com}"

# Internal: fetch a URL to stdout via curl or wget. Returns non-zero on failure.
_wezterm_fetch() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO - "$url"
  else
    return 1
  fi
}

# Internal: extract dated tag names from the releases API JSON on stdin.
# Why (probe 02): a release BODY can contain raw C0 control chars (emoji-reaction
# artifacts) that make the payload invalid JSON, so strict `jq` over the whole
# body FAILS. Prefer a tolerant python parse; fall back to a `tag_name`-only
# regex (which never touches the offending body field). Never depend on strict
# jq across the full document.
#
# Implementation note: the JSON arrives on THIS function's stdin. We must NOT
# also feed the python SCRIPT via stdin (a `python3 - <<HEREDOC` while stdin is
# the piped JSON makes python try to execute the JSON as source). Instead read
# the JSON into a variable and hand it to python via argv, keeping the script in
# `-c`. (Bug found in Task 1 verification: heredoc-on-stdin collided with the
# piped JSON and produced a SyntaxError, silently falling back to the pinned
# default and hiding the real dated list.)
_wezterm_parse_dated_tags() {
  local json
  json="$(cat)"
  [ -n "$json" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    # Hand the JSON to python via a TEMP FILE, not argv/env. The releases payload
    # is ~1 MB; passing it through an env var or argument overflows ARG_MAX
    # (E2BIG, exit 127). (Bug found in Task 1 verification — the env-var attempt
    # failed silently behind 2>/dev/null and degraded to the pinned default.)
    local tmp
    tmp="$(mktemp)" || return 1
    printf '%s' "$json" > "$tmp"
    python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except Exception:
    sys.exit(1)
for r in data:
    tag = r.get("tag_name", "")
    if tag and tag != "nightly":
        print(tag)
' "$tmp" 2>/dev/null
    local rc=$?
    rm -f "$tmp"
    return $rc
  else
    # Fallback: scrape "tag_name": "<value>" pairs. This ignores release bodies
    # entirely, so the control-char gotcha above cannot break it.
    printf '%s' "$json" \
      | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' \
      | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' \
      | grep -v '^nightly$'
  fi
}

# wezterm_release_list -> prints, one per line, the selectable releases:
#   nightly
#   <last 5 dated tags, newest first>
#
# On any API failure (unreachable, rate-limited, unparseable), degrades to:
#   nightly
#   <WEZTERM_PINNED_RELEASE>
# so the caller always has a usable, reproducible choice (D-08, T-02-04).
wezterm_release_list() {
  local api_url="${WEZTERM_RELEASE_API}/repos/${WEZTERM_RELEASE_REPO}/releases?per_page=10"
  local json dated
  json="$(_wezterm_fetch "$api_url" 2>/dev/null)" || json=""

  if [ -n "$json" ]; then
    dated="$(printf '%s' "$json" | _wezterm_parse_dated_tags | head -n 5)"
  fi

  # The rolling nightly tag is always offered first (D-08).
  echo "nightly"
  if [ -n "${dated:-}" ]; then
    printf '%s\n' "$dated"
  else
    # Graceful degradation: keep the pinned known-good default reachable even
    # when the API path failed (T-02-04 accept; D-08 reproducible default).
    echo "${WEZTERM_PINNED_RELEASE}"
  fi
}

# wezterm_release_asset_url <tag> <ubuntu_base>
#   -> https://github.com/wez/wezterm/releases/download/<tag>/wezterm-<tag>.Ubuntu<base>.tar.xz
#
# Why (probe 01/02): the generic Linux asset is named
# `wezterm-<FULL-TAG>.Ubuntu<base>.tar.xz` (full dated tag incl. its -<shortsha>
# suffix), and inside it the binary lives at `wezterm/usr/bin/wezterm`. This
# builds ONLY the official-host HTTPS URL (T-02-05); the bootstrap verifies the
# downloaded bytes before extraction (T-02-01).
wezterm_release_asset_url() {
  local tag="${1:?wezterm_release_asset_url: missing release tag}"
  local base="${2:?wezterm_release_asset_url: missing Ubuntu base (e.g. 24.04)}"
  printf '%s/%s/releases/download/%s/wezterm-%s.Ubuntu%s.tar.xz\n' \
    "${WEZTERM_RELEASE_HOST}" "${WEZTERM_RELEASE_REPO}" "$tag" "$tag" "$base"
}

# wezterm_macos_asset_url <tag>
#   -> https://github.com/wez/wezterm/releases/download/<tag>/WezTerm-macos-<tag>.zip
#
# The macOS counterpart of wezterm_release_asset_url (Phase 7 / D-04/D-05). Builds
# ONLY the official-host HTTPS URL for the macOS `.zip` bundle asset (T-07-06: the
# tag is a pinned/selected value, never arbitrary host input). The install_macos
# flow integrity-gates + ditto-extracts the downloaded bytes before placement.
#
# API-confirmed asset name (gh api repos/wez/wezterm/releases, checked 2026-06-22):
# both the rolling `nightly` tag and dated tags name the macOS asset uniformly
# `WezTerm-macos-<TAG>.zip` (e.g. `WezTerm-macos-nightly.zip`,
# `WezTerm-macos-20240203-110809-5046fc22.zip`) — closes Open Q2/A3. No fixed
# per-arch suffix: the single universal `.zip` carries WezTerm.app.
wezterm_macos_asset_url() {
  local tag="${1:?wezterm_macos_asset_url: missing release tag}"
  printf '%s/%s/releases/download/%s/WezTerm-macos-%s.zip\n' \
    "${WEZTERM_RELEASE_HOST}" "${WEZTERM_RELEASE_REPO}" "$tag" "$tag"
}

# wezterm_release_archive_binary_path -> the relative path to the `wezterm`
# executable INSIDE the extracted archive (probe 01: holds). The bootstrap
# symlinks ~/.local/bin/wezterm to <release-dir>/<this path>.
wezterm_release_archive_binary_path() {
  echo "wezterm/usr/bin/wezterm"
}

# If executed directly (not sourced), print the selectable list as a convenience
# for eyeballing — keeps decision logic out (D-01).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "# selectable releases (nightly + last 5 dated, or pinned fallback):"
  wezterm_release_list
  echo "# pinned default: ${WEZTERM_PINNED_RELEASE}"
fi
