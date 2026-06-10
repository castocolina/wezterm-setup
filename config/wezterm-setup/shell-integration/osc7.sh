#!/usr/bin/env bash
# wezterm-setup :: OSC 7 cwd reporter (bash)
#
# Emits OSC 7 (`ESC ] 7 ; file://HOST/path ST`) on every prompt so WezTerm
# always knows the active pane's cwd. This is the FOUND-01 portability
# guarantee: we ship our OWN emission rather than relying on a distro's
# vte-2.91.sh, which is not universal (decisions/cwd-mechanism.md).
#
# Sourced from the user's ~/.bashrc by the installer (Plan 04). This file only
# ships a correct, idempotent emitter; it does not edit rc files itself.
#
# Portability (D-18): POSIX-friendly, no /proc reads, no GNU-only flags, so it
# also works on macOS. macOS verification deferred to the Mac pass.
#
# Threat mitigations:
#   T-03-02: emit only when stdout is a TTY, so the escape never contaminates
#            piped/redirected output.
#   T-03-03: the hook is a single fast printf with no subshell fork in the hot
#            path; guard against double-registration so re-sourcing does not
#            stack duplicate hooks.

# Guard against double-registration if this file is sourced twice.
if [ -n "${__WEZTERM_OSC7_REGISTERED:-}" ]; then
  return 0 2>/dev/null || true
fi
__WEZTERM_OSC7_REGISTERED=1

# URL-encode a path: percent-encode every byte that is not an RFC 3986
# unreserved char or '/'. Pure-builtin loop -- no external command, no subshell
# in the caller's hot path beyond this function call.
__wezterm_osc7_encode() {
  local string="$1"
  local out="" c i
  local len=${#string}
  for (( i = 0; i < len; i++ )); do
    c="${string:i:1}"
    case "$c" in
      [a-zA-Z0-9/._~-]) out+="$c" ;;
      *) printf -v out '%s%%%02X' "$out" "'$c" ;;
    esac
  done
  printf '%s' "$out"
}

# Emit the OSC 7 sequence for the current directory.
__wezterm_osc7() {
  # T-03-02: only report when stdout is a terminal.
  [ -t 1 ] || return 0
  local host="${HOSTNAME:-}"
  if [ -z "$host" ]; then
    host="$(hostname 2>/dev/null)"
  fi
  printf '\033]7;file://%s%s\033\\' "$host" "$(__wezterm_osc7_encode "$PWD")"
}

# Register on PROMPT_COMMAND without clobbering any existing value, and without
# adding ourselves twice.
case "${PROMPT_COMMAND:-}" in
  *__wezterm_osc7*) : ;; # already present
  "") PROMPT_COMMAND="__wezterm_osc7" ;;
  *)  PROMPT_COMMAND="__wezterm_osc7;${PROMPT_COMMAND}" ;;
esac
