#!/usr/bin/env bash
# tools/run-e2e-prove.sh
#
# The PERMANENT, per-bug "break harness" (D-09). A green E2E battery is only
# trustworthy if it actually FAILS on the two real regression classes that
# motivated it. This script PROVES that, ONE BUG AT A TIME:
#
#   for each known regression:
#     1. INJECT the regression into its single source file (deterministic edit)
#     2. RUN the battery (tools/run-e2e.sh) — EXPECTED to fail
#     3. ASSERT the battery FAILED *in the catching tier* (teeth) — or loud-SKIP
#        when that tier's live dependency is unavailable (never a false pass)
#     4. REVERT that file before the next regression
#
# Two regressions, run SEPARATELY (per-bug, not combined):
#   A. scene escape-leak  -> cli/commands/scene.lua              (Tier 2 no-leak, D-05)
#   B. dead new-tab chord -> config/wezterm-setup/keybindings.lua (Tier 3 reg, D-06)
#
# Regression B drops the SpawnTab CTRL-FAMILY chord (the live Ctrl+Shift+T new-tab
# default) — the exact family Tier 3 (Plan 03) asserts on Linux. The managed
# SUPER+T row is WM-shadowed/absent on Linux, so dropping IT would leave the
# battery green; the CTRL-family disable is what flips the test.
#
# LIVE-CONFIG MECHANISM: Tier 3's live layer reads the EFFECTIVE key map via
# `wezterm show-keys --lua`, which parses the user's INSTALLED config
# (~/.config/wezterm) — a COPY of the in-repo config. So Regression B injects the
# canonical repo source AND cp-syncs it to the installed copy so the live wezterm
# sees the regression. We deliberately do NOT export WEZTERM_CONFIG_FILE: pointing
# wezterm at a scratch config makes `wez doctor` (Tier 1) report a non-standard
# install and fail spuriously, polluting the proof. Instead we back up the
# installed copy, sync the injected source over it, then restore it byte-for-byte
# (T-06.7-20). The user's live WezTerm GUI session is never touched. Regression A
# rides WEZ_BIN=./dist/wez (the dev launcher execs the in-repo cli/ sources), so
# the scene.lua edit is exercised directly with no config dance.
#
# SAFETY (T-06.7-20): the harness MUTATES then RESTORES two tracked source files
# (and one installed copy). It refuses to start if either repo target is already
# dirty (never clobber a real in-progress edit), reverts everything inside a
# `trap ... EXIT` so an abort / error / Ctrl-C still restores the tree, and asserts
# `git diff --quiet` on both repo targets before exiting.
#
# BASH-3.2 SAFE (macOS ships bash 3.2): only POSIX builtins; no bash-4-only
# array-read builtins (mapfile/readarray), no associative arrays (declare -A), no
# in-place case-expansion (${var^^}). Case-folding uses `grep -i`. In-place edits
# use awk -> temp -> mv (BSD/GNU `sed -i` differ). Clean under `bash -n` and
# `shellcheck -x`.
#
# Usage:
#   ./tools/run-e2e-prove.sh        # prove both regressions, leave the tree clean
#   make e2e-prove                  # the same, via the Makefile

set -u

# Resolve the repo root from this script's location so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

# The two injection targets (one per regression).
SCENE_FILE="cli/commands/scene.lua"
KEYS_FILE="config/wezterm-setup/keybindings.lua"

# The INSTALLED keybindings copy that `wezterm show-keys --lua` actually parses.
INSTALLED_KEYS="${XDG_CONFIG_HOME:-${HOME}/.config}/wezterm/wezterm-setup/keybindings.lua"

# --- Reverting EXIT trap (T-06.7-20): restore BOTH repo files and the installed
# copy unconditionally, and wipe scratch, so an abort/error/Ctrl-C leaves a clean
# tree. PROVE_TMP + INSTALLED_BACKUP are set later; revert_all guards on them. ---
PROVE_TMP=""
INSTALLED_BACKUP=""
# shellcheck disable=SC2317  # revert_all is invoked indirectly via the EXIT trap
revert_all() {
  git checkout HEAD -- "${SCENE_FILE}" "${KEYS_FILE}" >/dev/null 2>&1 || true
  if [ -n "${INSTALLED_BACKUP}" ] && [ -f "${INSTALLED_BACKUP}" ]; then
    cp "${INSTALLED_BACKUP}" "${INSTALLED_KEYS}" >/dev/null 2>&1 || true
  fi
  if [ -n "${PROVE_TMP}" ] && [ -d "${PROVE_TMP}" ]; then
    rm -rf "${PROVE_TMP}" >/dev/null 2>&1 || true
  fi
}

# --- SAFETY PRE-FLIGHT (T-06.7-20): refuse to run if a repo target is already
# dirty (staged OR unstaged). Done BEFORE the trap is armed so a user's
# in-progress edit is never `git checkout`-clobbered. -----------------------------
preflight_clean() {
  local f rc=0
  for f in "${SCENE_FILE}" "${KEYS_FILE}"; do
    if ! git diff --quiet -- "${f}" || ! git diff --quiet --cached -- "${f}"; then
      echo "run-e2e-prove: REFUSING to run — target already dirty: ${f}" >&2
      echo "  commit or stash it first; the harness must own a clean baseline." >&2
      rc=1
    fi
  done
  return "${rc}"
}

if ! preflight_clean; then
  exit 1
fi

# Repo targets are clean: arm the reverting trap for the rest of the run.
trap revert_all EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

PROVE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/wez-e2e-prove.XXXXXX")"

# Default WEZ_BIN to the in-repo dev launcher so the battery exercises the live
# cli/ sources (incl. the injected scene.lua). CI may override before calling.
if [ -z "${WEZ_BIN:-}" ] && [ -x ./dist/wez ]; then
  WEZ_BIN="./dist/wez"
fi
export WEZ_BIN

# --- Deterministic injectors (awk -> temp -> mv; bash-3.2/macOS-safe). ----------
inject_scene() {
  # Regression A: neutralize the self-erasing scrollback+viewport wipe so the
  # typed `printf '...'` setup line's ECHO survives in the pane viewport and Tier
  # 2's no-leak check (get-text finds `printf '`) flips to FAIL.
  awk '
    /local CLEAR_SCROLLBACK_AND_VIEWPORT = / {
      print "        local CLEAR_SCROLLBACK_AND_VIEWPORT = \"\" -- INJECTED-BREAK(run-e2e-prove): self-erase removed so the printf echo leaks"
      next
    }
    { print }
  ' "${SCENE_FILE}" > "${SCENE_FILE}.prove.tmp" && mv "${SCENE_FILE}.prove.tmp" "${SCENE_FILE}"
}

inject_keys() {
  # Regression B: disable the default Ctrl+Shift+T new-tab so the EFFECTIVE key
  # map carries NO SpawnTab chord in the CTRL family (the Linux dead-new-tab loss
  # Tier 3 asserts). Inserted right after the SUPER+T disabled-default line.
  awk '
    { print }
    /-- default SpawnTab variant/ {
      print "  { key = \"t\", mods = \"CTRL|SHIFT\" }, -- INJECTED-BREAK(run-e2e-prove): disable default Ctrl+Shift+T new-tab"
    }
  ' "${KEYS_FILE}" > "${KEYS_FILE}.prove.tmp" && mv "${KEYS_FILE}.prove.tmp" "${KEYS_FILE}"
}

# spawntab_ctrl_present: success (0) when SpawnTab STILL registers a CTRL-family
# chord in the effective table (injection ineffective); non-zero when it is gone.
spawntab_ctrl_present() {
  wezterm show-keys --lua 2>/dev/null | grep -i "SpawnTab" | grep -iq "CTRL"
}

# run_battery <logfile>: run the full battery, capturing all output. The battery
# is EXPECTED to be non-zero under injection; `set -u` (no `set -e`) lets it
# return without aborting this script.
run_battery() {
  ./tools/run-e2e.sh > "$1" 2>&1
}

# classify_regression <label> <log> <fail_regex> <skip_regex>
#   -> prints PROVE ok / PROVE SKIP / PROVE FAIL; returns 0 / 2 / 1 respectively.
# A run-e2e `FAIL  <path>` line matching <fail_regex> = caught (teeth proven).
# Else a `<skip_regex> ... SKIPPED` line = the catching tier self-skipped (honest
# loud SKIP, not a pass). Else the regression had NO TEETH (a real problem).
classify_regression() {
  local label="$1" log="$2" fail_re="$3" skip_re="$4"
  if grep -Eq "^FAIL[[:space:]]+.*${fail_re}" "${log}"; then
    echo "PROVE ok   - ${label}: the battery FAILED in its catching tier (teeth proven)"
    return 0
  fi
  if grep -Eq "${skip_re}.*SKIPPED" "${log}"; then
    echo "PROVE SKIP - ${label}: NOT proven — catching tier self-skipped (live dependency unavailable)"
    return 2
  fi
  echo "PROVE FAIL - ${label}: the injected regression did NOT fail the battery (NO TEETH)"
  return 1
}

OVERALL=0

echo "run-e2e-prove: break harness (D-09) — WEZ_BIN=${WEZ_BIN:-wez}"
echo

# ============================================================================
# Regression B — dead new-tab (drop the SpawnTab CTRL-family Ctrl+Shift+T).
# ============================================================================
echo "== Regression B: dead new-tab — disable the CTRL-family Ctrl+Shift+T (Tier 3) =="
if ! command -v wezterm >/dev/null 2>&1; then
  echo "PROVE SKIP - Regression B (dead new-tab): NOT proven — no runnable wezterm for show-keys"
elif [ ! -f "${INSTALLED_KEYS}" ]; then
  echo "PROVE SKIP - Regression B (dead new-tab): NOT proven — installed config absent (${INSTALLED_KEYS}); show-keys cannot see the repo injection"
else
  # Back up the installed copy so we restore it byte-for-byte regardless of git.
  INSTALLED_BACKUP="${PROVE_TMP}/installed-keybindings.bak"
  cp "${INSTALLED_KEYS}" "${INSTALLED_BACKUP}"
  # Inject the canonical repo source, then sync it to the installed copy so the
  # live `wezterm show-keys --lua` (default config) sees the regression.
  inject_keys
  cp "${KEYS_FILE}" "${INSTALLED_KEYS}"
  if spawntab_ctrl_present; then
    echo "PROVE FAIL - Regression B: injection ineffective — SpawnTab STILL registers a CTRL chord post-inject" >&2
    OVERALL=1
  else
    echo "  verified: post-injection \`wezterm show-keys --lua\` shows NO SpawnTab chord under any CTRL-family mods"
    run_battery "${PROVE_TMP}/battery-B.log"
    classify_regression "Regression B (dead new-tab)" "${PROVE_TMP}/battery-B.log" \
      "tier3/registration_e2e_test\.lua" "tier3 show-keys registration"
    rc=$?
    [ "${rc}" -eq 1 ] && OVERALL=1
  fi
  # Revert: restore both the repo source and the installed copy.
  git checkout HEAD -- "${KEYS_FILE}" >/dev/null 2>&1 || true
  cp "${INSTALLED_BACKUP}" "${INSTALLED_KEYS}"
  rm -f "${INSTALLED_BACKUP}"
  INSTALLED_BACKUP=""
fi
echo

# ============================================================================
# Regression A — scene escape-leak (drop the self-erasing printf wipe).
# ============================================================================
echo "== Regression A: scene escape-leak — drop the self-erasing wipe (Tier 2) =="
inject_scene
run_battery "${PROVE_TMP}/battery-A.log"
classify_regression "Regression A (scene escape-leak)" "${PROVE_TMP}/battery-A.log" \
  "tier2/scene_(reuse|newtab)_e2e_test\.lua" "tier2 .*scene live-mux"
rc=$?
[ "${rc}" -eq 1 ] && OVERALL=1
git checkout HEAD -- "${SCENE_FILE}" >/dev/null 2>&1 || true
echo

# ============================================================================
# FINAL tree-clean assertion (belt-and-braces, T-06.7-20). The per-regression
# reverts already restored both files; the EXIT trap restores again. Fail loudly
# if anything is somehow still dirty.
# ============================================================================
if git diff --quiet -- "${SCENE_FILE}" "${KEYS_FILE}" \
  && git diff --quiet --cached -- "${SCENE_FILE}" "${KEYS_FILE}"; then
  echo "tree-clean: ${SCENE_FILE} + ${KEYS_FILE} restored to HEAD"
else
  echo "run-e2e-prove: FATAL — tree still dirty after reverts (T-06.7-20)" >&2
  OVERALL=1
fi

echo
if [ "${OVERALL}" -eq 0 ]; then
  echo "run-e2e-prove: PASS — every provable regression was proven (or loud-SKIPPED); tree clean."
else
  echo "run-e2e-prove: FAIL — a regression had no teeth, or the tree was left dirty." >&2
fi
exit "${OVERALL}"
