#!/usr/bin/env bash
# tools/ci-classify-e2e-output.sh
#
# Single source of truth for the D-02 skip-gate decision (06.8). Classifies an
# e2e battery log and exits 0 iff:
#   1. The ONE expected macOS-only self-skip (the Tier 1 keys-siblings
#      bundle-symlink contract, which self-skips loudly and correctly on Linux)
#      appears EXACTLY ONCE — cycle-2 MEDIUM-3: this is now REQUIRED, not merely
#      tolerated. Zero or more-than-one occurrences is a hard failure, evidencing
#      that the self-skip gate itself was genuinely exercised.
#   2. NO other `SKIPPED (reason=` line appears ANYWHERE in the log — cycle-1
#      HIGH-2, sharpened by cycle-2 MEDIUM-1: this check is INDEPENDENT of the
#      live-label check below, so it still fires even when a gate-bound label's
#      `LIVE-ASSERTED` line is ALSO present elsewhere in the log (the real
#      dual-emit shape `tests/e2e/tier2/scene_motd_race_e2e_test.lua` can
#      produce when bash is unexpectedly absent).
#   3. Every gate-bound Tier 2/3 label shows `LIVE-ASSERTED` at least once (D-02).
#
# Every check runs and reports regardless of the others' outcome (never exiting
# early), so a multi-cause failure shows all causes at once. A real exit code is
# returned (never echo-only diagnostics) — this is what makes the script directly
# reusable as a hard CI gate, by ci.yml's e2e step, Task 2's local dry-run,
# tests/ci_classify_test.lua's durable regression coverage, and Task 3's
# remote-log verification, never a divergent copy of this same grep logic.
#
# Usage:  tools/ci-classify-e2e-output.sh <log-file>
set -euo pipefail

LOG="${1:?usage: tools/ci-classify-e2e-output.sh <log-file>}"

if [ ! -f "${LOG}" ]; then
  echo "::error::log file not found: ${LOG}" >&2
  exit 1
fi

# The ONE tolerated self-skip (Tier 1's macOS-only keys-siblings check,
# tests/e2e/tier1/keys_siblings_e2e_test.lua — always self-skips on Linux).
EXPECTED_SKIP_LABEL="keys-siblings macOS bundle-symlink contract"

# The four gate-bound Tier 2/3 labels that MUST print LIVE-ASSERTED on a runner
# with a genuinely resolvable WezTerm + wezterm-mux-server (D-02).
REQUIRED_LIVE_LABELS=(
  "tier2 scene-launch-motd-race regression"
  "tier2 new-tab-mode scene live-mux"
  "tier2 reuse-mode scene live-mux"
  "tier3 show-keys registration"
)

status=0

# --- Check 1: exactly-once required self-skip (cycle-2 MEDIUM-3) ------------
# The `|| true` is REQUIRED: a zero-match `grep -c` exits 1, which under
# `set -e` inside a `var="$(...)"` assignment would otherwise abort the whole
# script. Guarding every such substitution this way is non-negotiable
# throughout this script.
expected_count="$(grep -cF "${EXPECTED_SKIP_LABEL}: SKIPPED" "${LOG}" || true)"
if [ "${expected_count}" -ne 1 ]; then
  echo "::error::expected self-skip '${EXPECTED_SKIP_LABEL}' appeared ${expected_count} time(s) (must be exactly 1)" >&2
  status=1
fi

# --- Check 2: no unexpected skip anywhere (cycle-1 HIGH-2, cycle-2 MEDIUM-1) -
# Scans the WHOLE log for any disallowed SKIPPED line, independent of whether a
# gate-bound label's LIVE-ASSERTED line is also present elsewhere in the log.
unexpected="$(grep -F 'SKIPPED (reason=' "${LOG}" | grep -vF "${EXPECTED_SKIP_LABEL}: SKIPPED" || true)"
if [ -n "${unexpected}" ]; then
  echo "::error::unexpected SKIPPED line(s) found:" >&2
  printf '%s\n' "${unexpected}" >&2
  status=1
fi

# --- Check 3: every gate-bound label shows LIVE-ASSERTED at least once (D-02) -
for label in "${REQUIRED_LIVE_LABELS[@]}"; do
  if ! grep -qF "${label}: LIVE-ASSERTED" "${LOG}"; then
    echo "::error::required gate-bound label missing LIVE-ASSERTED: '${label}'" >&2
    status=1
  fi
done

if [ "${status}" -eq 0 ]; then
  echo "ci-classify-e2e-output: OK — expected self-skip exactly once, no unexpected skip, all ${#REQUIRED_LIVE_LABELS[@]} gate-bound labels LIVE-ASSERTED"
else
  echo "ci-classify-e2e-output: FAILED — see ::error:: lines above" >&2
fi

exit "${status}"
