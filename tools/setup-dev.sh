#!/usr/bin/env bash
# tools/setup-dev.sh
#
# Sudo-free DEV compile-toolchain provisioner for an end-developer's OWN machine
# (autonomy item #1). It installs the build toolchain that the SUBSEQUENT
# `tools/build.sh` step needs to take path 1 (the luastatic single-binary build)
# instead of the dev source-launcher: `lua@5.4` (keg-only), `luarocks`, and
# `luastatic`, then exposes `lua5.4` on PATH via the keg-only prefix.
#
# This is DISTINCT from tools/ci-setup-toolchain.sh, which provisions a GitHub
# Actions RUNNER (apt-sudo on the Linux leg is sanctioned there). This script
# targets a developer's personal Mac and therefore honors the project's sudo-free
# invariant (P6-D03 / D-08): it NEVER runs sudo and NEVER auto-installs Xcode —
# it detects the Xcode Command Line Tools and, when absent, instructs the user to
# run the one-time interactive `xcode-select --install` themselves.
#
# Usage:
#   ./tools/setup-dev.sh   (or: make setup)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=tools/lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"

log() { printf '[setup-dev] %s\n' "$*"; }
err() { printf '[setup-dev] ERROR: %s\n' "$*" >&2; }

# --- Xcode Command Line Tools: detect-then-instruct (never sudo, never auto) ---
# The CLT ship Apple clang, which luastatic needs to LINK the Mach-O `wez`. We
# only DETECT it here; installing it is the user's one-time interactive action
# (a system GUI prompt). We never auto-install or sudo it (D-08 sudo-free).
require_xcode_clt() {
  if xcode-select -p >/dev/null 2>&1; then
    log "Xcode Command Line Tools present: $(xcode-select -p)"
    return 0
  fi
  err "Xcode Command Line Tools are not installed (Apple clang is required to"
  err "link the luastatic binary). Run this ONE-TIME interactive command and"
  err "accept the system dialog, then re-run 'make setup':"
  err "    xcode-select --install"
  return 1
}

# --- macOS: sudo-free keg-only lua@5.4 + luarocks + luastatic -----------------
install_macos() {
  # NEVER `brew install lua` — the bare `lua` formula is now Lua 5.5, which would
  # silently link the build against the wrong interpreter (Pitfall 1). Always pin
  # the keg-only `lua@5.4` formula.
  log "macos dev host -> brew install lua@5.4 + luarocks (sudo-free), then luastatic"
  if ! command -v brew >/dev/null 2>&1; then
    err "Homebrew (brew) not found on PATH — install it from https://brew.sh first."
    return 1
  fi

  require_xcode_clt

  brew list lua@5.4 >/dev/null 2>&1 || brew install lua@5.4
  brew list luarocks >/dev/null 2>&1 || brew install luarocks

  # lua@5.4 is keg-only: Homebrew does NOT symlink it onto PATH, so resolve its
  # prefix and prepend the keg bin (Pitfall 2). This is what provides `lua5.4`
  # for build.sh's have_luastatic() predicate. Note: installing `luarocks` pulls
  # in the bare `lua` (5.5) formula as its own runtime dependency and unlinks the
  # keg-only lua@5.4 symlinks — harmless, since lua@5.4 stays in the Cellar and we
  # add its keg bin to PATH explicitly here.
  local prefix
  prefix="$(brew --prefix lua@5.4)"
  export PATH="${prefix}/bin:${PATH}"
  # Persist onto the job PATH when running under GitHub Actions.
  if [ -n "${GITHUB_PATH:-}" ]; then
    printf '%s\n' "${prefix}/bin" >>"${GITHUB_PATH}"
  fi

  # Install luastatic sudo-free with `--local`: the bare `luarocks install`
  # targets the system tree (/usr/local) and FAILS without write access, which
  # would violate the sudo-free invariant (D-08). `--local` installs into
  # ~/.luarocks (mirrors ci-setup-toolchain.sh's Linux leg). Then prepend
  # ~/.luarocks/bin so `luastatic` is findable for build.sh and the assert below.
  command -v luastatic >/dev/null 2>&1 || luarocks install --local luastatic
  if [ -d "${HOME}/.luarocks/bin" ]; then
    export PATH="${HOME}/.luarocks/bin:${PATH}"
    if [ -n "${GITHUB_PATH:-}" ]; then
      printf '%s\n' "${HOME}/.luarocks/bin" >>"${GITHUB_PATH}"
    fi
  fi
}

# --- Linux: delegate to the CI toolchain provisioner (apt-based dev path) ------
install_linux() {
  # The verified macOS path is this script; the Linux developer path is apt-based
  # and already implemented in ci-setup-toolchain.sh. Delegate rather than
  # duplicating the apt logic so there is a single source of truth.
  log "linux dev host -> delegating to tools/ci-setup-toolchain.sh (apt-based)"
  "${SCRIPT_DIR}/ci-setup-toolchain.sh"
}

# --- toolchain assertion (fail loud if lua5.4 / luastatic are absent) ----------
# Reuses the spirit of ci-setup-toolchain.sh's assert_and_capture(): a missing
# toolchain must fail LOUDLY here rather than silently degrade build.sh to the
# non-shippable dev launcher.
assert_and_capture() {
  if ! command -v lua5.4 >/dev/null 2>&1; then
    err "lua5.4 not on PATH after install — luastatic cannot bundle the interpreter."
    return 1
  fi
  if ! command -v luastatic >/dev/null 2>&1; then
    err "luastatic not on PATH after install — build.sh would fall back to the dev"
    err "launcher and produce a non-shippable artifact."
    return 1
  fi
  log "lua5.4 version: $(lua5.4 -v 2>&1 || echo 'lua5.4 -v failed')"
  log "luastatic version (via luarocks show): $(luarocks show luastatic 2>&1 | head -1 || echo 'luarocks show luastatic failed')"
  log "toolchain ready: lua5.4 + luastatic present"
}

# ---------------------------------------------------------------------------
main() {
  local os
  os="$(platform_os)"
  case "${os}" in
    macos) install_macos ;;
    linux) install_linux ;;
    *)
      err "unsupported dev OS '${os}' — no toolchain install path"
      return 1
      ;;
  esac
  assert_and_capture
}

# Run only when executed, not when sourced (testability). The unit test sources
# this script to exercise its functions without running main.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
