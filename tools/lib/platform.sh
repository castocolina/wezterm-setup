#!/usr/bin/env bash
# tools/lib/platform.sh
#
# Shared, sourceable platform-detection helpers reused by the build pipeline
# (tools/build.sh), the WezTerm bootstrap (Plan 02), and the installer (Plan 04).
#
# Pure glue per D-01: detection only, zero decision logic (that lives in the Lua
# `wez` binary). Cross-platform per D-18: detects via `uname` and /etc/os-release;
# makes NO /proc-specific assumptions, so macOS reuse is mechanical. Never
# hard-fails on a non-Ubuntu Linux distro — warns and falls back to a sane base.
#
# Source it:  . tools/lib/platform.sh
# Then call:  platform_os ; platform_arch ; platform_ubuntu_base
#
# This file is meant to be SOURCED, not executed; it defines functions and sets
# no `set -e` so it never disturbs the sourcing shell's options.

# platform_os -> "linux" | "macos" | "<lowercased uname>" (unknown passthrough)
platform_os() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || echo unknown)"
  case "$uname_s" in
    Linux) echo "linux" ;;
    Darwin) echo "macos" ;;
    *) echo "$uname_s" | tr '[:upper:]' '[:lower:]' ;;
  esac
}

# platform_arch -> "x86_64" | "aarch64" (normalized; arm64 -> aarch64)
platform_arch() {
  local uname_m
  uname_m="$(uname -m 2>/dev/null || echo unknown)"
  case "$uname_m" in
    x86_64 | amd64) echo "x86_64" ;;
    aarch64 | arm64) echo "aarch64" ;;
    *) echo "$uname_m" ;;
  esac
}

# platform_ubuntu_base -> the Ubuntu base version string used to match the
# WezTerm `.Ubuntu<base>.tar.xz` asset (e.g. "24.04", "22.04", "20.04").
#
# Reads /etc/os-release. Honors ubuntu and ubuntu-derived distros (Pop!_OS, Mint,
# elementary, ...) via UBUNTU_CODENAME / ID_LIKE. On a non-Ubuntu distro or when
# detection fails, emits a warning to stderr and falls back to a known-good base
# so the caller never hard-fails (D-18). On macOS this is not meaningful and
# returns the fallback with a warning.
platform_ubuntu_base() {
  local fallback="24.04"
  local os
  os="$(platform_os)"

  if [ "$os" != "linux" ]; then
    echo "platform_ubuntu_base: not Linux ($os); using fallback ${fallback}" >&2
    echo "$fallback"
    return 0
  fi

  if [ ! -r /etc/os-release ]; then
    echo "platform_ubuntu_base: /etc/os-release not readable; using fallback ${fallback}" >&2
    echo "$fallback"
    return 0
  fi

  # Read os-release into local vars without leaking them to the sourcing shell.
  local ID="" ID_LIKE="" VERSION_ID="" UBUNTU_CODENAME=""
  # shellcheck disable=SC1091
  . /etc/os-release 2>/dev/null || true

  # Map known Ubuntu codenames to their base version, since derived distros may
  # carry their own VERSION_ID (e.g. Pop!_OS uses Ubuntu's, Mint does not).
  case "${UBUNTU_CODENAME:-}" in
    noble) echo "24.04" ; return 0 ;;
    jammy) echo "22.04" ; return 0 ;;
    focal) echo "20.04" ; return 0 ;;
  esac

  # Native Ubuntu (or a derivative that mirrors Ubuntu's VERSION_ID).
  case "${ID:-} ${ID_LIKE:-}" in
    *ubuntu*)
      if [ -n "${VERSION_ID:-}" ]; then
        echo "$VERSION_ID"
        return 0
      fi
      ;;
  esac

  echo "platform_ubuntu_base: non-Ubuntu distro (ID=${ID:-?}); using fallback ${fallback}" >&2
  echo "$fallback"
  return 0
}

# If executed directly (not sourced), print a one-line detection summary. This
# makes the file convenient to eyeball but keeps decision logic out (D-01).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'os=%s arch=%s ubuntu_base=%s\n' \
    "$(platform_os)" "$(platform_arch)" "$(platform_ubuntu_base)"
fi
