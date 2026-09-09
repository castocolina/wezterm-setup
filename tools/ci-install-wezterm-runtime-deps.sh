#!/usr/bin/env bash
# tools/ci-install-wezterm-runtime-deps.sh
#
# Linux-only CI provisioning glue (D-01): installs the shared libraries the
# PREBUILT wezterm-gui binary (fetched by tools/bootstrap-wezterm.sh) needs at
# RUNTIME. `wezterm show-keys` re-execs into wezterm-gui (see
# tests/e2e/platform.lua's bundle_siblings row), and GitHub's `ubuntu-latest`
# image does not ship the XCB/xkbcommon runtime libs wezterm-gui dynamically
# links against — confirmed live via a real CI failure (06.8-01 Task 3):
#
#   wezterm-gui: error while loading shared libraries: libxcb-image.so.0:
#   cannot open shared object file: No such file or directory
#
# This installs ONLY the runtime (non `-dev`) packages — no compiler/headers,
# no decision logic beyond "which package manager" (this project ships Linux
# CI on apt-based ubuntu-latest only; a non-apt runner is a hard error, not a
# silent skip, so a config-drift regression is loud).
#
# SUDO SCOPE NOTE (same as tools/ci-setup-toolchain.sh): this runs on a GitHub
# Actions RUNNER, where `sudo apt-get` is the sanctioned provisioning path —
# distinct from the sudo-free end-user install invariant (P6-D03), which
# governs tools/setup.sh and is never touched by this script.
#
# Usage (CI step, Linux job only):
#   ./tools/ci-install-wezterm-runtime-deps.sh
set -euo pipefail

log() { printf '[ci-wezterm-deps] %s\n' "$*"; }
err() { printf '[ci-wezterm-deps] ERROR: %s\n' "$*" >&2; }

if ! command -v apt-get >/dev/null 2>&1; then
  err "no apt-get on this runner — this script is apt-only (ubuntu-latest CI job)"
  exit 1
fi

# The exact set wezterm-gui's dynamic linker needs beyond what ubuntu-latest
# already ships: XCB image/ewmh/icccm/keysyms/randr/render/xkb extensions plus
# xkbcommon (+ its X11 binding). Runtime (non-dev) package names.
PKGS=(
  libxcb-image0
  libxcb-ewmh2
  libxcb-icccm4
  libxcb-keysyms1
  libxcb-randr0
  libxcb-render0
  libxcb-xkb1
  libxkbcommon0
  libxkbcommon-x11-0
)

log "apt-get install -y ${PKGS[*]}"
sudo apt-get update
sudo apt-get install -y "${PKGS[@]}"
log "wezterm-gui runtime deps installed"
