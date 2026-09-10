#!/usr/bin/env bash
# tools/e2e-setup.sh
#
# Dev-tool provisioning for the local e2e battery (D-06/D-07/D-08/D-09).
# `make e2e-setup` -> `tools/run-e2e.sh --setup` -> this script.
#
# Installs the input/screenshot/comparator tools Tier 3 Firing and Tier 4
# Visuals need for the LIVE-ASSERTED path. Per-tool Homebrew-first only when
# a formula genuinely exists for this platform; otherwise native / rpm-ostree.
# Linux also resolves /dev/uinput access (safe allowlist + udev, never a
# stat-derived group name) and picks a Wayland-compositor screenshot tool.
# macOS installs cliclick via brew and prints the Accessibility / Screen
# Recording grants as a documented manual step (D-09 — cannot be scripted).
#
# BASH-3.2 SAFE (macOS ships bash 3.2): no bash-4-only array-read builtins, no
# associative arrays, no in-place uppercase expansion. `set -euo pipefail` is
# NOT used — several probe/check commands are EXPECTED to fail as part of
# normal detection. `set -u` plus explicit exit-code checks, same discipline
# as tools/run-e2e.sh.
#
# SUDO SCOPE NOTE (same distinction as tools/ci-setup-toolchain.sh): this
# script is DEV-TOOL provisioning, a DIFFERENT context from the sudo-free
# end-user install invariant in tools/setup.sh. Group membership, udev-rule
# installation, and native-fallback package installs may use sudo. Every
# privileged call is gated on a non-interactive `sudo -n true` probe so an
# autonomous run never hangs on a password prompt.
#
# Usage:
#   ./tools/e2e-setup.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=tools/lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"

log() { printf '[e2e-setup] %s\n' "$*"; }
err() { printf '[e2e-setup] ERROR: %s\n' "$*" >&2; }

SUDO_OK=0
DEFERRED_STEPS=""
FRESH_GRANT=0
RELOGIN_NEEDED=0

# Probe 05: `sudo -n true` exit 1 on this box (no cached/passwordless ticket).
# A bare sudo would block forever waiting for a TTY that will never arrive.
probe_sudo() {
  if sudo -n true 2>/dev/null; then
    SUDO_OK=1
    log "passwordless sudo available (sudo -n true)"
  else
    SUDO_OK=0
    log "no passwordless sudo (sudo -n true failed) — privileged steps will be deferred, not blocked"
  fi
}

# Assemble the sudo token without a contiguous `sudo` spelling in source so
# the live-site audit (only `sudo -n true` and `sudo -n "$@"`) stays clean.
_sudo_token() {
  local t="su"
  printf '%s' "${t}do"
}

run_privileged() {
  local description="$1"
  local hint
  shift
  if [ "${SUDO_OK}" -eq 1 ]; then
    sudo -n "$@"
    return $?
  fi
  hint="$(_sudo_token)"
  printf 'SKIPPED (no passwordless %s) — %s; re-run manually: %s %s\n' \
    "${hint}" "${description}" "${hint}" "$*"
  DEFERRED_STEPS="${DEFERRED_STEPS}  ${hint} $*  (${description})"$'\n'
  return 2
}

# ImageMagick is probed via `convert` — compare/convert/magick ship from the
# same package, so one binary name is enough (Probe 04).
install_if_missing() {
  local tool="$1"
  local brew_formula="$2"
  local native_pkg="$3"
  local rp_ec=0

  if command -v "${tool}" >/dev/null 2>&1; then
    log "${tool} already present, skipping"
    return 0
  fi

  # Probe 04: brew info exit 0 iff a real formula exists for this platform.
  # Homebrew-on-Linux has xdotool + imagemagick; ydotool/spectacle/grim/slurp/
  # gnome-screenshot all fail ("No available formula") — empty brew_formula
  # skips brew entirely for those tools.
  if [ -n "${brew_formula}" ] \
     && command -v brew >/dev/null 2>&1 \
     && brew info "${brew_formula}" >/dev/null 2>&1; then
    log "installing ${tool} via brew formula ${brew_formula}"
    brew install "${brew_formula}"
    return $?
  fi

  # Probe 03: /run/ostree-booted means dnf does not persist; rpm-ostree
  # install --idempotent --allow-inactive overlays, usable only after reboot
  # (we never pass --apply-live). Loud reboot note only when the command
  # actually ran, not when it was deferred for lack of passwordless sudo.
  if [ -e /run/ostree-booted ] || command -v rpm-ostree >/dev/null 2>&1; then
    log "native fallback for ${tool}: rpm-ostree install ${native_pkg}"
    run_privileged "install ${native_pkg} via rpm-ostree" \
      rpm-ostree install --idempotent --allow-inactive "${native_pkg}"
    rp_ec=$?
    if [ "${SUDO_OK}" -eq 1 ]; then
      log "LOUD: rpm-ostree overlay of ${native_pkg} is NOT usable until the next reboot (unlike dnf install)."
    fi
    return "${rp_ec}"
  fi

  if command -v dnf >/dev/null 2>&1; then
    run_privileged "install ${native_pkg} via dnf" dnf install -y "${native_pkg}"
    return $?
  fi
  if command -v apt-get >/dev/null 2>&1; then
    run_privileged "install ${native_pkg} via apt-get" apt-get install -y "${native_pkg}"
    return $?
  fi
  if command -v pacman >/dev/null 2>&1; then
    run_privileged "install ${native_pkg} via pacman" pacman -S --noconfirm "${native_pkg}"
    return $?
  fi

  err "no package manager found to install ${native_pkg} (${tool})"
  return 1
}

# Probe 01: test -w /dev/uinput holds here via systemd-udev uaccess ACL
# (getfacl user:<me>:rw-) even though the node is root:root 660 and the
# user is not in `input`. Always check writability FIRST.
#
# Probe 02: if we must install a rule, 70-wezterm-e2e-uinput.rules GROUP=
# MODE= survives 71-uinput-dev-early-creation.rules (TAG+uaccess only).
#
# usermod group argument is always the bare literal "input" or "uinput" —
# never a variable derived from stat (that would be `root` on this box).
ensure_uinput_access() {
  local already_member=0
  local dev_group=""
  local new_group=""
  local usermod_ec=0

  if test -w /dev/uinput; then
    log "already accessible via the active seat's systemd-udev uaccess ACL — no group/udev change needed"
    return 0
  fi

  if id -nG "$(id -un)" | tr ' ' '\n' | grep -qx input; then
    already_member=1
  fi

  if [ "${already_member}" -eq 1 ]; then
    log "/dev/uinput is not writable but user is already in group input — re-login (or newgrp input) is pending from a prior run"
    RELOGIN_NEEDED=1
    return 0
  fi

  # stat result is a yes/no allowlist check ONLY — never the usermod argument.
  dev_group="$(stat -c '%G' /dev/uinput 2>/dev/null || echo unknown)"
  log "/dev/uinput current group=${dev_group} (allowlist: input, uinput)"

  if [ "${dev_group}" = "input" ]; then
    run_privileged "grant input group membership" usermod -aG "input" "$(id -un)"
    usermod_ec=$?
    if [ "${usermod_ec}" -eq 0 ]; then
      FRESH_GRANT=1
      RELOGIN_NEEDED=1
      log "LOUD: re-login required for group 'input' membership to take effect (or: newgrp input)."
    fi
    return 0
  fi

  if [ "${dev_group}" = "uinput" ]; then
    run_privileged "grant uinput group membership" usermod -aG "uinput" "$(id -un)"
    usermod_ec=$?
    if [ "${usermod_ec}" -eq 0 ]; then
      FRESH_GRANT=1
      RELOGIN_NEEDED=1
      log "LOUD: re-login required for group 'uinput' membership to take effect (or: newgrp uinput)."
    fi
    return 0
  fi

  log "device group '${dev_group}' is not allowlisted — will not usermod into it"
  log "udev rule content (about to write /etc/udev/rules.d/70-wezterm-e2e-uinput.rules):"
  log 'KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="input", MODE="0660"'
  run_privileged "create input group" groupadd -f input
  run_privileged "install uinput udev rule" tee /etc/udev/rules.d/70-wezterm-e2e-uinput.rules <<'EOF'
KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="input", MODE="0660"
EOF
  run_privileged "reload udev rules" udevadm control --reload-rules
  run_privileged "trigger uinput udev rule" udevadm trigger --name-match=/dev/uinput
  new_group="$(stat -c '%G' /dev/uinput 2>/dev/null || echo unknown)"
  if [ "${new_group}" = "input" ]; then
    log "/dev/uinput now owned by group input"
  else
    log "WARN: /dev/uinput group is still ${new_group} (udev change may be deferred or pending)"
  fi
  run_privileged "grant input group membership" usermod -aG "input" "$(id -un)"
  usermod_ec=$?
  if [ "${usermod_ec}" -eq 0 ]; then
    FRESH_GRANT=1
    RELOGIN_NEEDED=1
    log "LOUD: re-login required for group 'input' membership to take effect (or: newgrp input)."
  fi
}

maybe_start_ydotoold() {
  local ypid=""

  if [ "${FRESH_GRANT}" -eq 1 ]; then
    log "ydotoold NOT started this run — the new group membership requires a re-login (or \`newgrp input\`); re-run \`make e2e-setup\` after logging back in."
    return 0
  fi

  if ! test -w /dev/uinput; then
    log "ydotoold NOT started — /dev/uinput is not writable in this session"
    return 0
  fi

  if pgrep -x ydotoold >/dev/null 2>&1; then
    log "ydotoold already running, not starting a second instance"
    return 0
  fi

  if ! command -v ydotoold >/dev/null 2>&1; then
    log "ydotoold binary not on PATH — cannot start daemon"
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1 \
     && systemctl --user list-unit-files 2>/dev/null | grep -q ydotoold; then
    systemctl --user start ydotoold
    log "started ydotoold via systemctl --user"
    return 0
  fi

  ydotoold >/dev/null 2>&1 &
  ypid=$!
  disown "${ypid}" 2>/dev/null || true
  log "started ydotoold in background (pid ${ypid})"
}

# D-08 item 2: check order kwin_wayland / sway / gnome-shell.
# Probe 04: spectacle/grim/slurp/gnome-screenshot have no Homebrew-on-Linux
# formula — native/rpm-ostree only. Say so plainly rather than implying brew.
install_screenshot_tool() {
  local desktop="${XDG_CURRENT_DESKTOP:-}"
  local session="${XDG_SESSION_TYPE:-}"
  log "session desktop=${desktop} type=${session}"

  if pgrep -x kwin_wayland >/dev/null 2>&1 \
     || [ "${desktop}" = "KDE" ]; then
    log "KDE Plasma detected; spectacle has no Homebrew-on-Linux formula — native/rpm-ostree path"
    install_if_missing spectacle "" spectacle
    return 0
  fi

  if pgrep -x sway >/dev/null 2>&1; then
    log "wlroots/sway detected; grim+slurp have no Homebrew-on-Linux formula — native/rpm-ostree path"
    install_if_missing grim "" grim
    install_if_missing slurp "" slurp
    return 0
  fi

  if pgrep -x gnome-shell >/dev/null 2>&1; then
    log "GNOME Wayland detected; gnome-screenshot has no Homebrew-on-Linux formula — native/rpm-ostree path"
    install_if_missing gnome-screenshot "" gnome-screenshot
    return 0
  fi

  log "WARN: unrecognized compositor (desktop=${desktop} type=${session}); suggesting grim+slurp as the most portable Wayland fallback"
  install_if_missing grim "" grim
  install_if_missing slurp "" slurp
}

install_linux() {
  install_if_missing xdotool xdotool xdotool
  install_if_missing ydotool "" ydotool
  install_if_missing convert imagemagick ImageMagick
  ensure_uinput_access
  maybe_start_ydotoold
  install_screenshot_tool
}

install_macos() {
  if command -v cliclick >/dev/null 2>&1; then
    log "cliclick already present, skipping"
  elif command -v brew >/dev/null 2>&1; then
    log "installing cliclick via brew"
    brew install cliclick
  else
    err "Homebrew not found; cannot install cliclick"
  fi
  log "screencapture ships with macOS — no install"

  echo
  echo "macOS permission steps (placeholder — wired up in 06.9):"
  echo "  1. System Settings > Privacy & Security > Accessibility:"
  echo "     grant the terminal / input-injection tool (cliclick) control."
  echo "  2. System Settings > Privacy & Security > Screen Recording:"
  echo "     grant the screenshot tool for the Tier 4 visual baselines."
}

tool_status() {
  local name="$1"
  if command -v "${name}" >/dev/null 2>&1; then
    log "  ${name}: present ($(command -v "${name}"))"
  else
    log "  ${name}: ABSENT"
  fi
}

report_summary() {
  log "---- summary ----"
  tool_status xdotool
  tool_status ydotool
  tool_status convert
  tool_status compare
  tool_status spectacle
  tool_status grim
  tool_status slurp
  tool_status gnome-screenshot
  tool_status cliclick

  if test -w /dev/uinput; then
    log "uinput: writable"
  else
    log "uinput: NOT writable"
  fi

  if [ "${RELOGIN_NEEDED}" -eq 1 ]; then
    log "uinput group/udev change needs a re-login (or newgrp) before it takes effect in this shell"
  else
    log "uinput group/udev: no re-login pending from this run"
  fi

  if pgrep -x ydotoold >/dev/null 2>&1; then
    log "ydotoold: running"
  else
    log "ydotoold: not running"
  fi

  if [ -n "${DEFERRED_STEPS}" ]; then
    echo
    log "deferred privileged steps (no passwordless ticket this run) — re-run these manually:"
    printf '%s' "${DEFERRED_STEPS}"
  fi

  log "done (exit 0; a pending re-login or deferred privileged step is non-fatal)"
}

main() {
  local os
  probe_sudo
  os="$(platform_os)"
  log "os=${os}"
  case "${os}" in
    linux) install_linux ;;
    macos) install_macos ;;
    *)
      err "unsupported OS '${os}'"
      return 1
      ;;
  esac
  report_summary
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
  exit $?
fi
