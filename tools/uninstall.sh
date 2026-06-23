#!/usr/bin/env bash
# tools/uninstall.sh
#
# The wezterm-setup UNINSTALLER — decision-free GLUE ONLY (D-01). It makes NO
# removal decisions itself: every "what to remove vs. preserve" decision and all
# sentinel-block excision live in the Lua `wez` binary (cli/commands/uninstall.lua,
# the front door, over cli/commands/uninstall_state.lua, the engine). This script
# ONLY:
#   1. reads the KEEP_CONFIG / KEEP_CLI / KEEP_BACKUP env vars that the Makefile
#      `uninstall` target passes in,
#   2. translates each truthy value into the corresponding
#      `--keep-config` / `--keep-cli` / `--keep-backup` flag,
#   3. delegates to `wez uninstall --yes` (the documented front door, D-09),
#      surfacing its exit code as ours. The `--yes` is required because this
#      `make uninstall` path is non-interactive (no TTY) per D-11.
#
# There is deliberately NO `rm` here and NO branching over which components to
# remove — that logic is owned by the binary (INST-04/05). Sudo-free +
# cross-platform: every removal targets user paths (T-06-04, D-18).
#
# Usage (normally via `make uninstall [KEEP_*=1]`):
#   ./tools/uninstall.sh                       # remove block + config + cli + backups
#   KEEP_CONFIG=1 ./tools/uninstall.sh         # preserve ~/.config/wezterm/wezterm-setup/
#   KEEP_CLI=1    ./tools/uninstall.sh         # preserve the wez binary
#   KEEP_BACKUP=1 ./tools/uninstall.sh         # preserve wezterm.lua.bak.*
set -euo pipefail

log() { printf '[uninstall] %s\n' "$*"; }

# Locate the wez binary: prefer one on PATH, else the default install location,
# else a repo-local DEV build (so `make build && make uninstall` can clean up even
# when nothing is installed on PATH). Resolve the repo-local fallback relative to
# THIS script's own directory so it works from any CWD: <script_dir>/../dist/wez.
# Derive the script dir with pure bash parameter expansion (no external `dirname`)
# so resolution still works under a stripped PATH — the only externals this script
# may invoke are the delegated `wez` itself (bash-3.2-safe, sudo-free).
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
case "${SCRIPT_SOURCE}" in
  */*) SCRIPT_DIR="${SCRIPT_SOURCE%/*}" ;;
  *)   SCRIPT_DIR="." ;;
esac
DIST_WEZ="${SCRIPT_DIR}/../dist/wez"
BIN_DIR="${WEZ_BIN_DIR:-${HOME}/.local/bin}"
if command -v wez >/dev/null 2>&1; then
  WEZ="$(command -v wez)"
elif [ -x "${BIN_DIR}/wez" ]; then
  WEZ="${BIN_DIR}/wez"
elif [ -x "${DIST_WEZ}" ]; then
  # Repo-local dev build (e.g. fresh from `make build`). Using it keeps removal
  # owned by the binary (D-01) — this glue still adds NO rm / NO path-branching;
  # it only points the delegation at a reachable binary so `make uninstall`
  # actually cleans up the managed block when nothing is installed on PATH yet.
  WEZ="${DIST_WEZ}"
  log "using repo-local dev build ${DIST_WEZ} (nothing installed on PATH)"
else
  # No wez is reachable ANYWHERE (PATH, ${BIN_DIR}/wez, or the repo-local
  # ${DIST_WEZ}). The binary self-deletes as the LAST step of its own uninstall
  # (D-01), so a re-run / clean-state run has nothing to delegate to -- treat it
  # as a no-op SUCCESS rather than aborting (keeps `make uninstall` idempotent and
  # `make uninstall install` from a clean state working). NO rm / NO path-branching
  # here -- removal stays owned by the binary; if the binary is absent, any leftover
  # config artifacts need it present again (e.g. `make build`) to be cleaned.
  log "wez binary not found (looked on PATH, at ${BIN_DIR}/wez, and at ${DIST_WEZ}); already uninstalled, nothing to remove"
  log "if config artifacts remain, build/reinstall the wez binary to clean them (removal is owned by the binary, D-01)"
  exit 0
fi

# Translate the Makefile KEEP_* env into uninstall-state flags. A value is "keep"
# when it is set to anything non-empty other than 0/false/no (case-insensitive).
keep_flag() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    ''|0|false|no) return 1 ;;
    *) return 0 ;;
  esac
}

# Seed with --yes: the `make uninstall` path is non-interactive, and the front
# door requires --yes on a non-TTY pipe (D-11).
FLAGS=(--yes)
keep_flag "${KEEP_CONFIG:-}" && FLAGS+=(--keep-config)
keep_flag "${KEEP_CLI:-}"    && FLAGS+=(--keep-cli)
keep_flag "${KEEP_BACKUP:-}" && FLAGS+=(--keep-backup)

log "delegating removal decisions to wez uninstall ${FLAGS[*]}"
"${WEZ}" uninstall "${FLAGS[@]}"
exit $?
