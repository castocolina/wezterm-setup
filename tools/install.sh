#!/usr/bin/env bash
# tools/install.sh
#
# The wezterm-setup REMOTE ONE-LINER — pipe-safe bootstrap GLUE ONLY (D-01).
# This is the user-facing front door:
#
#   curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash
#   wget -qO- https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash
#   bash <(curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh)
#
# It makes ZERO install decisions. It only: (1) wraps its whole body in main()
# invoked on the LITERAL last line so a truncated `curl` stream can never execute
# a half-command (P6-D05 / RESEARCH Pattern 1); (2) creates a `mktemp -d` guarded
# by `trap … EXIT` so nothing is left behind (P6-D02 SC#3 / Pattern 3); (3) fetches
# the repo via the GitHub codeload tar.gz endpoint piped into `tar --strip-components=1`
# (no `git` dependency — Pattern 5); (4) hands off to the EXISTING tools/setup.sh
# with WEZ_REMOTE_BOOTSTRAP=1, reviving /dev/tty so the re-install decision (D-03)
# and the WezTerm version selector (D-08) stay interactive under the pipe (P6-D04).
#
# ALL install decisions live in setup.sh + build.sh + the Lua `wez` binary. The
# WezTerm refresh half of the hand-off is owned by 06-06's nightly-default +
# update-in-place path (setup.sh STEP 2 -> bootstrap-wezterm.sh): the default
# target is the rolling `nightly`, a behind-the-latest user-path install is updated
# in place, and a system install is left intact. install.sh adds NO version,
# update, target, or asset-selection logic of its own — it is pure glue.
#
# Pin a specific tag/commit instead of `main` (trust model, P6-D05):
#   WEZ_REF=v1.0.0 bash <(curl -fsSL …/tools/install.sh)   # tag  -> tar.gz/refs/tags/<tag>
#   WEZ_REF=<sha>  bash <(curl -fsSL …/tools/install.sh)    # commit
# The README documents the matching `tar.gz/refs/tags/<tag>` / `tar.gz/<sha>` URL forms.
#
# NOTE: install.sh is fetched STANDALONE over `curl|bash`, so there is no repo (and
# no tools/lib/platform.sh) at the entry point. It therefore does NOT source
# platform.sh at the top — the one documented deviation from setup.sh's header
# skeleton. setup.sh sources platform.sh itself AFTER the tarball is unpacked.
set -euo pipefail

log() { printf '[install] %s\n' "$*"; }
err() { printf '[install] ERROR: %s\n' "$*" >&2; }

main() {
  # (1) Per-run temp checkout + guaranteed cleanup on success / error / signal.
  # `tmp` is intentionally NOT `local`: the EXIT trap fires at shell exit, AFTER
  # main() has returned, where a function-local would be out of scope — under
  # `set -u` that aborts the trap with "tmp: unbound variable", leaking the temp
  # dir AND forcing a non-zero exit even on success. A script-scope var keeps it
  # visible to the trap; `${tmp:-}` guards the window before mktemp assigns it.
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/wezterm-setup.XXXXXX")"
  # shellcheck disable=SC2064
  trap 'rm -rf "${tmp:-}"' EXIT

  # (2) Curl-or-wget fetch-to-stdout helper (mirrors build.sh:114-121). Prefer
  #     curl, fall back to wget, hard-fail if neither is present.
  local fetcher
  if command -v curl >/dev/null 2>&1; then
    fetcher="curl"
  elif command -v wget >/dev/null 2>&1; then
    fetcher="wget"
  else
    err "neither curl nor wget available — cannot fetch the repository"
    exit 1
  fi

  # (3) Fetch the repo snapshot via the codeload tar.gz endpoint (no git), then
  #     extract with --strip-components=1 to drop GitHub's wrapper dir so setup.sh
  #     lands at "$tmp/tools/setup.sh" (Pattern 5 / Pitfall 6). The ref is
  #     overridable via WEZ_REF (default `main`) for pin-to-tag/commit (P6-D05).
  #
  #     codeload serves the three ref kinds at DIFFERENT paths: a branch at
  #     /tar.gz/refs/heads/<branch>, a tag at /tar.gz/refs/tags/<tag>, a commit at
  #     /tar.gz/<sha> (no refs/ prefix). A tag fetched under refs/heads/ 404s (and
  #     vice-versa), so WEZ_REF must be resolved by kind — a 7-40 char hex string
  #     is treated as a commit SHA, anything else is tried as a branch then a tag.
  #     This is a fetch mechanic, not an install decision, so D-01 still holds.
  local ref base candidates url tarball got
  ref="${WEZ_REF:-main}"
  base="https://codeload.github.com/castocolina/wezterm-setup/tar.gz"
  if printf '%s' "$ref" | grep -Eq '^[0-9a-fA-F]{7,40}$'; then
    candidates="${base}/${ref}"
  else
    candidates="${base}/refs/heads/${ref} ${base}/refs/tags/${ref}"
  fi
  tarball="${tmp}/wezterm-setup.tar.gz"
  log "fetching wezterm-setup@${ref} -> ${tmp}"
  # Download to a file (not a pipe) so an unmatched ref kind can fall through to
  # the next candidate; `-fsSL`/`-q` fail non-2xx so a 404 just tries the next.
  got=""
  for url in $candidates; do
    if [ "$fetcher" = "curl" ]; then
      if curl -fsSL "$url" -o "$tarball" 2>/dev/null; then got="$url"; break; fi
    else
      if wget -qO "$tarball" "$url" 2>/dev/null; then got="$url"; break; fi
    fi
  done
  if [ -z "$got" ]; then
    err "could not fetch wezterm-setup@${ref} (tried branch, tag, and commit forms)"
    exit 1
  fi
  tar -xzf "$tarball" -C "$tmp" --strip-components=1

  local setup="$tmp/tools/setup.sh"
  if [ ! -f "$setup" ]; then
    err "unpacked checkout is missing tools/setup.sh (ref '${ref}' may not exist)"
    exit 1
  fi

  # (4) Hand off to the EXISTING setup.sh with WEZ_REMOTE_BOOTSTRAP=1. Flags
  #     (--force/--restore/--skip) flow through "$@" to setup.sh STEP 6's
  #     `wez install-state`. The hand-off command is overridable via the
  #     WEZ_BOOTSTRAP_CMD test seam (default: the unpacked setup.sh) so the
  #     deterministic headless-abort gate can drive the hand-off without a full
  #     network fetch + WezTerm bootstrap; in normal use it is the unpacked setup.sh.
  local bootstrap_cmd="${WEZ_BOOTSTRAP_CMD:-$setup}"

  # Revive interactivity under the pipe by redirecting the child's stdin from
  # /dev/tty (P6-D04): under `curl|bash` stdin is the script, so setup.sh STEP 6's
  # `test -t 0` would otherwise see no TTY and abort an interactive re-install.
  # The WEZ_ASSUME_HEADLESS=1 seam exists ONLY to make the headless abort
  # deterministically testable in CI: it forces the headless hand-off branch (no
  # `< /dev/tty`) regardless of whether /dev/tty exists. The REAL headless
  # detection remains the absence of a readable /dev/tty (e.g. genuine CI),
  # which keeps setup.sh's surfaced D-03 non-zero abort.
  # Detect a USABLE controlling terminal by actually opening /dev/tty, not just
  # `[ -e ] && [ -r ]`: some containers expose a /dev/tty node that passes those
  # tests yet fails to open (ENXIO, "No such device or address"). The open-probe
  # `{ : < /dev/tty; }` is the canonical usable-tty check and degrades to the
  # headless branch when there is no controlling terminal.
  if [ "${WEZ_ASSUME_HEADLESS:-0}" != "1" ] && { : < /dev/tty; } 2>/dev/null; then
    log "handing off to setup.sh (interactive: stdin <- /dev/tty)"
    WEZ_REMOTE_BOOTSTRAP=1 "$bootstrap_cmd" "$@" < /dev/tty
  else
    log "handing off to setup.sh (headless: flags via \"\$@\")"
    WEZ_REMOTE_BOOTSTRAP=1 "$bootstrap_cmd" "$@"
  fi
  # `set -e` propagates setup.sh's non-zero exit (e.g. the D-03 abort) as ours.
}

main "$@"
