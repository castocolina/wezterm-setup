#!/usr/bin/env zsh
# wezterm-setup :: OSC 7 cwd reporter (zsh)
#
# Emits OSC 7 (`ESC ] 7 ; file://HOST/path ST`) on every prompt and on every
# directory change so WezTerm always knows the active pane's cwd. This is the
# FOUND-01 portability guarantee: we ship our OWN emission rather than relying
# on a distro's vte-2.91.sh (decisions/cwd-mechanism.md).
#
# Sourced from the user's ~/.zshrc by the installer (Plan 04). This file only
# ships a correct, idempotent emitter; it does not edit rc files itself.
#
# Portability (D-18): no /proc reads, no GNU-only flags, so it also works on
# macOS. macOS verification deferred to the Mac pass.
#
# Threat mitigations:
#   T-03-02: emit only when stdout is a TTY, so the escape never contaminates
#            piped/redirected output.
#   T-03-03: the hook is a single fast print with no subshell fork in the hot
#            path; guard against double-registration so re-sourcing does not
#            stack duplicate hooks.

# Guard against double-registration if this file is sourced twice.
if [[ -n "${__WEZTERM_OSC7_REGISTERED:-}" ]]; then
  return 0
fi
typeset -g __WEZTERM_OSC7_REGISTERED=1

# Emit the OSC 7 sequence for the current directory.
__wezterm_osc7() {
  # T-03-02: only report when stdout is a terminal.
  [[ -t 1 ]] || return 0
  local host="${HOST:-$HOSTNAME}"
  # zsh's ${(j::)${(s::)PWD}//(#b)([^A-Za-z0-9\/._~-])/%${(l:2::0:)$(([##16]#match[1]))}}
  # is dense; use a clear builtin loop instead for auditability and portability.
  local path_encoded="" i c
  for (( i = 1; i <= ${#PWD}; i++ )); do
    c="${PWD[i]}"
    case "$c" in
      [a-zA-Z0-9/._~-]) path_encoded+="$c" ;;
      *) path_encoded+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  print -n -- $'\033]7;file://'"${host}${path_encoded}"$'\033\\'
}

# Register via zsh hook arrays. precmd fires before each prompt; chpwd fires on
# every directory change. add-zsh-hook is idempotent (it will not add a function
# that is already present in the hook array), which also satisfies T-03-03's
# no-duplicate-stacking requirement.
autoload -Uz add-zsh-hook
add-zsh-hook precmd __wezterm_osc7
add-zsh-hook chpwd __wezterm_osc7
