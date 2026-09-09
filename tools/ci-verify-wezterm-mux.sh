#!/usr/bin/env bash
# tools/ci-verify-wezterm-mux.sh
#
# D-02 precondition check (06.8): confirms `wezterm` and `wezterm-mux-server`
# are genuinely resolvable on this runner BEFORE the e2e battery runs, so the
# gate is meaningful rather than a permanent self-skip. Mirrors
# tests/e2e/lib/mux.lua's `resolve_mux_server` lookup order EXACTLY (PATH first,
# then a SIBLING of the resolved `wezterm` binary — the nightly bundle ships
# `wezterm-mux-server` beside `wezterm` but off PATH) as a standalone,
# reusable precondition check.
#
# This is the ONLY place this discovery logic lives — never mirrored inline in
# .github/workflows/ci.yml again (cycle-2 MEDIUM-5, the project's existing
# thin-glue boundary).
#
# Usage:  tools/ci-verify-wezterm-mux.sh
set -euo pipefail

command -v wezterm >/dev/null 2>&1 || {
  echo "::error::wezterm not resolvable on PATH after provisioning" >&2
  exit 1
}
wezterm --version

# 1. Directly on PATH.
if command -v wezterm-mux-server >/dev/null 2>&1; then
  wezterm-mux-server --version
  exit 0
fi

# 2. Sibling of the resolved `wezterm` binary (readlink -f follows the symlink
#    into the bundle, then look in the same dir) — the mux.lua order.
dir="$(dirname "$(readlink -f "$(command -v wezterm)")")"
if [ -x "${dir}/wezterm-mux-server" ]; then
  "${dir}/wezterm-mux-server" --version
  exit 0
fi

echo "::error::wezterm-mux-server not resolvable on PATH nor as a sibling of wezterm at ${dir}" >&2
exit 1
