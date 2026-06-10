#!/usr/bin/env bash
# tools/uninstall.sh
#
# The wezterm-setup UNINSTALLER — decision-free GLUE ONLY (D-01). It makes NO
# removal decisions itself: every "what to remove vs. preserve" decision and all
# sentinel-block excision live in the Lua `wez` binary
# (cli/commands/uninstall_state.lua). This script ONLY:
#   1. reads the KEEP_CONFIG / KEEP_CLI / KEEP_BACKUP env vars that the Makefile
#      `uninstall` target passes in,
#   2. translates each truthy value into the corresponding
#      `--keep-config` / `--keep-cli` / `--keep-backup` flag,
#   3. delegates to `wez uninstall-state`, surfacing its exit code as ours.
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
err() { printf '[uninstall] ERROR: %s\n' "$*" >&2; }

# Locate the wez binary: prefer one on PATH, else the default install location.
BIN_DIR="${WEZ_BIN_DIR:-${HOME}/.local/bin}"
if command -v wez >/dev/null 2>&1; then
  WEZ="$(command -v wez)"
elif [ -x "${BIN_DIR}/wez" ]; then
  WEZ="${BIN_DIR}/wez"
else
  err "wez binary not found (looked on PATH and at ${BIN_DIR}/wez)"
  err "if you only need to remove the binary, it is already gone"
  exit 1
fi

# Translate the Makefile KEEP_* env into uninstall-state flags. A value is "keep"
# when it is set to anything non-empty other than 0/false/no (case-insensitive).
keep_flag() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    ''|0|false|no) return 1 ;;
    *) return 0 ;;
  esac
}

FLAGS=()
keep_flag "${KEEP_CONFIG:-}" && FLAGS+=(--keep-config)
keep_flag "${KEEP_CLI:-}"    && FLAGS+=(--keep-cli)
keep_flag "${KEEP_BACKUP:-}" && FLAGS+=(--keep-backup)

log "delegating removal decisions to wez uninstall-state ${FLAGS[*]:-(remove all)}"
"${WEZ}" uninstall-state "${FLAGS[@]}"
exit $?
