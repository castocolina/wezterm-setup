#!/usr/bin/env bash
# tools/run-tests.sh
#
# Thin test harness (bootstrap/glue only, no decision logic per D-01).
#
# Discovers every tests/**/*_test.lua file and runs each under lua5.4, collects
# exit codes, prints per-file pass/fail, and exits non-zero if ANY test fails.
#
# When WEZTERM_INTEGRATION=1, additionally runs live/integration tests:
#   - any tests/**/*_integration_test.lua
#   - everything under tests/integration/ (when that directory exists)
# Integration tests are skipped by default (they need a real WezTerm session).
#
# Usage:
#   ./tools/run-tests.sh
#   WEZTERM_INTEGRATION=1 ./tools/run-tests.sh

set -u

# Resolve the repo root from this script's location so the runner works from any
# CWD (and so each test's relative requires resolve against the same root).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

LUA_BIN="${LUA_BIN:-lua5.4}"
if ! command -v "${LUA_BIN}" >/dev/null 2>&1; then
  echo "run-tests: '${LUA_BIN}' not found on PATH" >&2
  exit 127
fi

if [ ! -d tests ]; then
  echo "run-tests: no tests/ directory; nothing to run"
  exit 0
fi

INTEGRATION="${WEZTERM_INTEGRATION:-0}"

# Collect unit test files: *_test.lua, EXCLUDING *_integration_test.lua unless
# integration mode is on.
mapfile -t ALL_TESTS < <(find tests -type f -name '*_test.lua' | sort)

FILES=()
for f in "${ALL_TESTS[@]}"; do
  case "$f" in
    *_integration_test.lua)
      if [ "$INTEGRATION" = "1" ]; then FILES+=("$f"); fi
      ;;
    tests/integration/*)
      if [ "$INTEGRATION" = "1" ]; then FILES+=("$f"); fi
      ;;
    *)
      FILES+=("$f")
      ;;
  esac
done

# In integration mode, also pick up any test files under tests/integration/ that
# don't match the *_test.lua glob discovery above.
if [ "$INTEGRATION" = "1" ] && [ -d tests/integration ]; then
  while IFS= read -r f; do
    # avoid duplicates
    case " ${FILES[*]} " in
      *" $f "*) : ;;
      *) FILES+=("$f") ;;
    esac
  done < <(find tests/integration -type f -name '*.lua' | sort)
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "run-tests: no test files discovered under tests/"
  exit 0
fi

echo "run-tests: ${#FILES[@]} file(s) (integration=${INTEGRATION})"
echo

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
  echo "run-tests: ${FAILED} file(s) failed"
  exit 1
fi

echo "run-tests: all ${#FILES[@]} file(s) passed"
exit 0
