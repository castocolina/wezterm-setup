#!/usr/bin/env bash
# tools/run-tests.sh
#
# Thin test harness (bootstrap/glue only, no decision logic per D-01).
#
# Discovers every *_test.lua file co-located with source — under tests/, cli/,
# and config/ (tests live next to the code they cover, e.g. cli/lib/scene_test.lua
# beside cli/lib/scene.lua) — runs each under lua5.4, collects exit codes, prints
# per-file pass/fail, and exits non-zero if ANY test fails.
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

# Source roots that hold co-located tests. tests/ is canonical; cli/ and config/
# carry the unit tests that live next to the modules they cover.
TEST_ROOTS=()
for d in tests cli config; do
  [ -d "$d" ] && TEST_ROOTS+=("$d")
done

if [ "${#TEST_ROOTS[@]}" -eq 0 ]; then
  echo "run-tests: no test roots (tests/ cli/ config/); nothing to run"
  exit 0
fi

INTEGRATION="${WEZTERM_INTEGRATION:-0}"

# Collect unit test files: *_test.lua, EXCLUDING *_integration_test.lua unless
# integration mode is on. (Integration files live only under tests/integration/.)
# Stock macOS ships bash 3.2.57, which lacks the bash-4+ array-read builtin. Use
# the repo's bash-3.2-safe array-fill idiom (same shape as the SHELL_SCRIPTS loop
# below) so the harness runs on stock macOS with zero extra installs (D-08).
ALL_TESTS=()
while IFS= read -r f; do ALL_TESTS+=("$f"); done < <(find "${TEST_ROOTS[@]}" -type f -name '*_test.lua' | sort)

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

FAILED=0

# --- Shell-syntax gate (bash -n) over tracked tools/*.sh -----------------------
# Catch a syntactically broken installer/build/publish script in `make test`
# BEFORE the Lua suite (the install.sh one-liner can't be safely EXECUTED in CI —
# `curl|bash` is live RCE — so the gate is syntax-only; the live one-liner is
# verified by the Plan 04 human checkpoint). If shellcheck is present we also run
# `shellcheck -x` and report it, but a missing shellcheck never fails the suite.
SHELL_SCRIPTS=()
while IFS= read -r s; do
  [ -f "$s" ] && SHELL_SCRIPTS+=("$s")
done < <(find tools -maxdepth 1 -type f -name '*.sh' | sort)

if [ "${#SHELL_SCRIPTS[@]}" -gt 0 ]; then
  echo "run-tests: bash -n syntax gate over ${#SHELL_SCRIPTS[@]} tools/*.sh script(s)"
  HAVE_SHELLCHECK=0
  if command -v shellcheck >/dev/null 2>&1; then HAVE_SHELLCHECK=1; fi
  for s in "${SHELL_SCRIPTS[@]}"; do
    if bash -n "$s" 2>/dev/null; then
      printf 'PASS  bash -n %s\n' "$s"
    else
      printf 'FAIL  bash -n %s\n' "$s"
      bash -n "$s" || true
      FAILED=$((FAILED + 1))
    fi
    if [ "$HAVE_SHELLCHECK" = "1" ]; then
      if shellcheck -x "$s" >/dev/null 2>&1; then
        printf 'PASS  shellcheck -x %s\n' "$s"
      else
        printf 'warn  shellcheck -x %s (advisory — not failing the suite)\n' "$s"
      fi
    fi
  done
  echo
fi

echo "run-tests: ${#FILES[@]} file(s) (integration=${INTEGRATION})"
echo

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
