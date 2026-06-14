#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` report idiom; pass/fail always return 0, so the SC2015 hazard cannot occur (file-wide).
# tools/verify-macos.sh
#
# Complementary auto-verifier for the macOS batched parity pass (D-18).
# Runs every NON-INTERACTIVE, NON-LIVE-MUX check that confirms the shipped
# wezterm-setup CLI behaves on this machine, and prints PASS / FAIL / SKIP per
# check. Pairs with the step-by-step human/agent runbook docs/macos-verification.md
# (which covers the visual, live-WezTerm, and install-mutating steps this script
# deliberately does NOT perform).
#
# Design:
#   * NON-DESTRUCTIVE — never installs, never touches ~/.config/wezterm. All
#     stateful checks use a scratch WEZTERM_SETUP_DIR under $TMPDIR.
#   * Live-mux / interactive / install-mutating checks are SKIPPED with a reason
#     (drive those from the runbook on a real WezTerm session).
#   * Runs on macOS (the target) AND Linux (so you can smoke-test the script
#     itself before going to the Mac); OS-specific probes self-detect.
#   * Exit non-zero if any HARD check FAILs. SKIP and KNOWN-BUG never fail.
#
# Usage:  bash tools/verify-macos.sh
#         WEZ=/path/to/wez bash tools/verify-macos.sh   # test an installed wez

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

PASS=0; FAIL=0; SKIP=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33mSKIP\033[0m  %s — %s\n' "$1" "${2:-}"; SKIP=$((SKIP+1)); }
note() { printf '  \033[36mNOTE\033[0m  %s\n' "$1"; }
hdr()  { printf '\n=== %s ===\n' "$1"; }

OS="$(uname -s)"
IS_MAC=false; [ "$OS" = "Darwin" ] && IS_MAC=true

# ---------------------------------------------------------------------------
hdr "0. Environment"
if $IS_MAC; then
  note "macOS $(sw_vers -productVersion 2>/dev/null || echo '?')  arch=$(uname -m)"
else
  note "non-macOS ($OS) — running in self-test mode; macOS-only probes will SKIP"
fi

# Toolchain
command -v lua5.4 >/dev/null 2>&1 && pass "lua5.4 present" \
  || { command -v lua >/dev/null 2>&1 && { note "lua5.4 not found; using 'lua' (set LUA_BIN=lua)"; export LUA_BIN="${LUA_BIN:-lua}"; } || fail "no lua5.4 / lua on PATH"; }
command -v luastatic >/dev/null 2>&1 && pass "luastatic present (ships a real binary)" \
  || skip "luastatic" "absent — build falls back to dev launcher (not the shipping artifact)"
if $IS_MAC; then
  { command -v cc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1; } \
    && pass "C compiler present (luastatic link step)" || fail "no cc/clang — install Xcode CLT (xcode-select --install)"
  command -v shasum >/dev/null 2>&1 && pass "shasum present" || fail "no shasum"
  command -v sha256sum >/dev/null 2>&1 \
    && note "sha256sum present (unusual on macOS)" \
    || note "sha256sum ABSENT — build.sh remote path (WEZ_REMOTE_BOOTSTRAP=1) needs shasum -a 256 (§C-1 / A)"
fi
command -v wezterm >/dev/null 2>&1 && pass "wezterm on PATH ($(wezterm --version 2>/dev/null))" \
  || skip "wezterm" "not on PATH — install before the live-session runbook steps"

# ---------------------------------------------------------------------------
hdr "1. Build & test"
if bash tools/build.sh >/tmp/verify-macos-build.log 2>&1; then
  pass "tools/build.sh"
else
  fail "tools/build.sh (see /tmp/verify-macos-build.log)"; tail -5 /tmp/verify-macos-build.log
fi
WEZ="${WEZ:-${REPO_ROOT}/dist/wez}"
if [ -x "$WEZ" ] || [ -f "$WEZ" ]; then pass "wez artifact at $WEZ"; else fail "no wez artifact at $WEZ"; fi

# Apple Silicon codesign probe (informational)
if $IS_MAC && [ "$(uname -m)" = "arm64" ] && [ -f "$WEZ" ]; then
  if "$WEZ" version >/dev/null 2>&1; then pass "dist/wez runs (no codesign needed)";
  else note "dist/wez did not run — try: codesign -s - '$WEZ' (Apple Silicon ad-hoc sign, §C-1)"; fi
fi

if [ -n "${WEZ_SKIP_TESTS:-}" ]; then skip "unit suite" "WEZ_SKIP_TESTS set";
elif bash tools/run-tests.sh >/tmp/verify-macos-tests.log 2>&1; then
  pass "unit suite ($(grep -oE 'all [0-9]+ file' /tmp/verify-macos-tests.log | head -1))"
else
  fail "unit suite (see /tmp/verify-macos-tests.log)"; tail -8 /tmp/verify-macos-tests.log
fi

run_wez() { "$WEZ" "$@" 2>&1; }

# ---------------------------------------------------------------------------
hdr "2. __complete contexts (no install needed)"
chk_ctx() { # name  expect-nonempty
  local out; out="$(WEZTERM_SETUP_DIR="$SCRATCH" run_wez __complete "$1")"
  if [ -n "$out" ]; then pass "__complete $1 → $(echo "$out" | tr '\n' ' ')"; else fail "__complete $1 empty"; fi
}
SCRATCH="$(mktemp -d)"; mkdir -p "$SCRATCH/scenes"
# seed three recipes so list-backed contexts have data
WEZTERM_SETUP_DIR="$SCRATCH" WEZ_SEED_SRC_DIR="$REPO_ROOT/scenes" run_wez seed-scenes >/dev/null 2>&1 || true
chk_ctx subcommands
chk_ctx pane-colors
chk_ctx pane-icons
chk_ctx tab-colors
chk_ctx tab-icons
chk_ctx scene-layouts
chk_ctx scene-names

# ---------------------------------------------------------------------------
hdr "3. Completion scripts"
for sh in zsh bash; do
  if run_wez completions "$sh" >/tmp/verify-comp.$sh 2>/dev/null; then
    if [ "$sh" = bash ] && command -v bash >/dev/null 2>&1; then
      bash -n /tmp/verify-comp.bash 2>/dev/null && pass "completions bash + bash -n" || fail "bash -n on generated bash script"
    elif [ "$sh" = zsh ] && command -v zsh >/dev/null 2>&1; then
      zsh -n /tmp/verify-comp.zsh 2>/dev/null && pass "completions zsh + zsh -n" || fail "zsh -n on generated zsh script"
    else
      skip "completions $sh syntax" "$sh not installed to run -n"
    fi
  else
    fail "wez completions $sh"
  fi
done
# Known bug A-1: --layout value is NOT wired in the generated scripts.
if grep -q "scene-layouts" /tmp/verify-comp.zsh 2>/dev/null; then
  pass "KNOWN-BUG A-1 appears FIXED: --layout value wired (scene-layouts in generated zsh)"
else
  note "KNOWN-BUG A-1 confirmed: 'wez scene new --layout <Tab>' does NOT complete values (scene-layouts not wired). Deferred per user 2026-06-14 (§A-1)."
fi

# ---------------------------------------------------------------------------
hdr "4. scene launch error/exit-code contract (scratch dir, non-destructive)"
chk_exit() { # label  expected-code  -- cmd...
  local label="$1" want="$2"; shift 2
  WEZTERM_SETUP_DIR="$SCRATCH" "$WEZ" "$@" >/tmp/verify-sl.out 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then pass "$label (exit $got)"; else fail "$label (got $got, want $want): $(head -1 /tmp/verify-sl.out)"; fi
}
chk_exit "no-name, recipes present → 2" 2 scene launch
chk_exit "unknown name → 1" 1 scene launch nope
chk_exit "path traversal blocked → 1" 1 scene launch ../../etc/passwd
# single error: token on the no-name+empty case (UX fix I-1)
EMPTY="$(mktemp -d)"; mkdir -p "$EMPTY/scenes"
n_err="$(WEZTERM_SETUP_DIR="$EMPTY" "$WEZ" scene launch 2>&1 | grep -c '^error:')"
[ "$n_err" -eq 1 ] && pass "no-name+empty → exactly ONE error: line (I-1)" || fail "no-name+empty → $n_err error: lines (want 1)"
# malformed recipe → exit 1, no Lua traceback
printf 'layout = "boguslayout"\n[[panes]]\ncommand = "shell"\n' > "$SCRATCH/scenes/bad.toml"
out="$(WEZTERM_SETUP_DIR="$SCRATCH" "$WEZ" scene launch bad 2>&1)"; code=$?
if [ "$code" -eq 1 ] && ! printf '%s' "$out" | grep -q "stack traceback"; then
  printf '%s' "$out" | grep -q "invalid: error:" && fail "malformed → double 'error:' prefix" || pass "malformed → exit 1, single prefix, no traceback"
else fail "malformed recipe (code=$code or traceback present)"; fi
rm -f "$SCRATCH/scenes/bad.toml"; rm -rf "$EMPTY"

# ---------------------------------------------------------------------------
hdr "5. seed-scenes copy-if-absent (SCEN-06 / D-06, scratch dir)"
S2="$(mktemp -d)"
run1="$(WEZTERM_SETUP_DIR="$S2" WEZ_SEED_SRC_DIR="$REPO_ROOT/scenes" "$WEZ" seed-scenes 2>&1)"
seeded=$(printf '%s\n' "$run1" | grep -c '^seeded scene recipe:')
[ "$seeded" -eq 3 ] && pass "fresh seed → 3 'seeded' lines" || fail "fresh seed → $seeded (want 3)"
ls "$S2/scenes"/*.toml >/dev/null 2>&1 && pass "3 recipe files written" || fail "no recipe files written"
# edit dev, reseed, assert byte-identical + 'kept existing'
echo "# user edit $(date +%s 2>/dev/null || echo x)" >> "$S2/scenes/dev.toml"
before="$(cat "$S2/scenes/dev.toml")"
run2="$(WEZTERM_SETUP_DIR="$S2" WEZ_SEED_SRC_DIR="$REPO_ROOT/scenes" "$WEZ" seed-scenes 2>&1)"
kept=$(printf '%s\n' "$run2" | grep -c '^kept existing scene recipe:')
[ "$kept" -ge 1 ] && pass "reseed → 'kept existing' (no overwrite)" || fail "reseed → $kept kept lines"
[ "$before" = "$(cat "$S2/scenes/dev.toml")" ] && pass "user edit survives reseed byte-identical (D-06)" || fail "user edit was clobbered (D-06 VIOLATION)"
rm -rf "$S2"

# ---------------------------------------------------------------------------
hdr "6. Install-dependent & live-session checks (NOT auto-run)"
skip "make install / uninstall (INST-01..06)"   "mutates ~/.config/wezterm — drive from runbook §2"
skip "wez doctor green/fails (DIAG-01)"          "needs an install — runbook §3"
skip "CWD inheritance / Cmd+K / keys (FOUND-*)"  "needs a live WezTerm session — runbook §3-4"
skip "pane/tab identity (PANE-*/TAB-*)"          "needs a live WezTerm session — runbook §5"
skip "scene new / launch materialization"        "needs a live WezTerm mux — runbook §6-7"
if $IS_MAC; then
  skip "WezTerm.app quarantine (Gatekeeper)"     "check xattr com.apple.quarantine before first launch — runbook prereq / §C-1"
  skip "INST-06 macOS .app bootstrap"            "install_macos() is design-only — pre-install WezTerm — §C-2"
fi

rm -rf "$SCRATCH"
# ---------------------------------------------------------------------------
printf '\n=== Summary ===\n  PASS=%d  FAIL=%d  SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] && { echo "verify-macos: auto-checks OK — now drive docs/macos-verification.md for the live/visual steps."; exit 0; } \
                   || { echo "verify-macos: $FAIL hard check(s) failed — see above."; exit 1; }
