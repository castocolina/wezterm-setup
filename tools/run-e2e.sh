#!/usr/bin/env bash
# tools/run-e2e.sh
#
# E2E battery orchestrator (bootstrap/glue only, no decision logic per D-01).
#
# Discovers every tests/e2e/**/*_e2e_test.lua file, runs each under lua5.4,
# prints per-file PASS/FAIL, and exits non-zero if ANY file fails. Empty
# discovery (e.g. THIS scaffolding phase, before Tier 1 lands) is a CLEAN exit 0.
#
# The e2e battery is OWNED by `make e2e` (this script), never `make test`:
# run-tests.sh explicitly EXCLUDES *_e2e_test.lua so the unit suite never runs the
# battery against the stale PATH `wez`. This script defaults WEZ_BIN to the in-repo
# dev launcher ./dist/wez so local runs exercise the live cli/ sources; CI
# OVERRIDES WEZ_BIN to point at the freshly built luastatic binary (do NOT hardcode
# CI here — it just exports WEZ_BIN before invoking this script).
#
# BASH-3.2 SAFE (macOS ships bash 3.2): no bash-4-only array-read builtins, no
# associative arrays, no in-place uppercase expansion. Discovery uses the
# while-read + array-append idiom; case-folding (if ever needed) uses `tr`. Clean
# under `bash -n` and `shellcheck -x`.
#
# Usage:
#   ./tools/run-e2e.sh           # run the battery
#   ./tools/run-e2e.sh --setup   # print test-tool/permission setup notes (06.9)
#   WEZ_BIN=./dist/wez ./tools/run-e2e.sh

set -u

# Resolve the repo root from this script's location so the runner works from any
# CWD (and so each test's relative requires resolve against the same root).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

LUA_BIN="${LUA_BIN:-lua5.4}"
if ! command -v "${LUA_BIN}" >/dev/null 2>&1; then
  echo "run-e2e: '${LUA_BIN}' not found on PATH" >&2
  exit 127
fi

# --- --setup: print the test-tool / permission setup notes -------------------
# THIS phase (06.6) installs NOTHING — Tier 1 is deterministic and headless and
# needs no input/screenshot tools or OS permissions. The actual tool install +
# macOS Accessibility/Screen-Recording grant flow lands in 06.9; this arm exists
# so `make e2e-setup` resolves today and so the macOS permission steps have a home.
if [ "${1:-}" = "--setup" ]; then
  SETUP_SH="${SCRIPT_DIR}/e2e-setup.sh"
  if [ ! -e "${SETUP_SH}" ]; then
    echo "run-e2e: '${SETUP_SH}' not found" >&2
    exit 127
  fi
  if [ ! -x "${SETUP_SH}" ]; then
    echo "run-e2e: '${SETUP_SH}' is not executable" >&2
    exit 126
  fi
  exec "${SETUP_SH}"
fi

# --- Discover the e2e battery (bash-3.2-safe while-read + array-append) -------
# No bash-4-only array-read builtin (those break on macOS bash 3.2). The
# `while...done < <(find | sort)` process-substitution idiom IS bash-3.2-safe.
FILES=()
while IFS= read -r f; do
  [ -f "$f" ] && FILES+=("$f")
done < <(find tests/e2e -type f -name '*_e2e_test.lua' | sort)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "run-e2e: no *_e2e_test.lua files under tests/e2e (clean no-op)"
  exit 0
fi

# Default WEZ_BIN to the in-repo dev launcher when present and unset, so local
# `make e2e` exercises the live cli/ sources. CI exports WEZ_BIN to the built
# luastatic binary BEFORE calling this script (no CI logic hardcoded here).
if [ -z "${WEZ_BIN:-}" ] && [ -x ./dist/wez ]; then
  WEZ_BIN="./dist/wez"
  export WEZ_BIN
fi

echo "run-e2e: ${#FILES[@]} file(s)  (WEZ_BIN=${WEZ_BIN:-wez})"
echo

# --- Dispatch -> per-file PASS/FAIL -> aggregate (no set -e over the loop, so
# one bad file cannot abort the batch — T-06.6-02). -----------------------------
FAILED=0
for f in "${FILES[@]}"; do
  if "${LUA_BIN}" "$f"; then
    printf 'PASS  %s\n' "$f"
  else
    printf 'FAIL  %s\n' "$f"
    FAILED=$((FAILED + 1))
  fi
  echo
done

if [ "$FAILED" -ne 0 ]; then
  echo "run-e2e: ${FAILED} file(s) failed"
  exit 1
fi

echo "run-e2e: all ${#FILES[@]} file(s) passed"
exit 0
