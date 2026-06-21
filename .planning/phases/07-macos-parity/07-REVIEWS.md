# Phase 07 — Plan Review Feedback

**Source:** `/review-spec` (reviewing-specs, GSD · plan archetype), iteration 1, 2026-06-21
**Plans reviewed:** 07-01..05-PLAN.md
**Grounding (read, not reviewed):** 07-CONTEXT.md, 07-RESEARCH.md, 07-PATTERNS.md
**Codebase root:** /Users/ramon/git/personal/wezterm-setup (branch gsd/phase-07-macos-parity)

> **Disposition:** the `gsd-plan-checker` already passed these plans with 0 blockers. The findings
> below are polish/precision items — none architectural, none blocking. Apply the ACTIONABLE items
> as targeted edits; preserve all existing structure, waves, frontmatter, requirements coverage, and
> the locked CONTEXT decisions (D-01..D-08, D-01b, the Phase 7/7.1 split). Do NOT widen scope.

---

## ACTIONABLE — apply these fixes

### F1 (07-01 Task 1) — `set -u` is not part of the shebang
The action says "Keep `run-tests.sh`'s `set -u` shebang `#!/usr/bin/env bash` untouched." These are
two distinct constructs: the shebang is line 1; `set -u` is a separate `set` builtin around line 20.
**Fix:** rephrase so the executor treats them separately — e.g. "leave the shebang (line 1) and the
`set -u` line untouched; only replace the `mapfile` on line 50."

### F2 (07-01 Task 1) — disambiguate the read-loop analog from the line being replaced
`tools/run-tests.sh` has TWO `while IFS= read -r` loops: line 70 (inside the FILES filter) and lines
93-95 (the SHELL_SCRIPTS fill). The `mapfile` to replace is line 50 (`mapfile -t ALL_TESTS`). The
`<read_first>`/action should cite the analog precisely (the SHELL_SCRIPTS `while IFS= read -r s` loop
at L93-95) AND the exact target (the `mapfile -t ALL_TESTS` on L50), so an executor cannot confuse
the analog, the FILES read-loop at L70, or the downstream `ALL_TESTS` filter at L52-65.
**Fix:** add explicit line/label references distinguishing analog (L93-95) vs. target (L50) vs.
leave-untouched filter (L52-65).

### F3 (07-02 Task 2) — mark the PATTERNS.md install_macos() snippet as a skeleton; integrity gate is additive
PATTERNS.md Pattern 4 shows `fetch_to` → `ditto` with NO integrity gate between them, but Task 2
(correctly) mandates a PK-magic / size-floor / member-safety check BEFORE any extraction (threats
T-07-04/T-07-05). Since the action cites PATTERNS.md as the primary guide, add one sentence noting
the PATTERNS.md example is a structural skeleton only and the integrity-gate-before-extract is an
additive requirement that the snippet omits.
**Fix:** add the clarifying note to 07-02 Task 2 `<action>`.

### F4 (07-03 Task 1) — strengthen the codesign acceptance grep to assert the macos guard
`grep -c 'codesign --force --sign -' tools/build.sh` passes whether or not the codesign call sits
inside the `[ "$(platform_os)" = "macos" ]` guard (an unguarded/Linux-path call would still pass).
**Fix:** add a scope assertion to the SOURCE acceptance criteria — e.g. confirm the codesign block is
within a `platform_os`=macos guard (an `awk` scope check or a `grep` proving the guard precedes the
codesign call), so an unguarded call cannot satisfy the gate.

### F5 (07-05 Task 2) — make the status-flip gate ID-level, not a raw line count
`grep -c 'macOS verified D-18' .planning/REQUIREMENTS.md >= 13` is unreliable: each ID can appear in
multiple rows (the checkbox list AND the Traceability table), so a raw line count does not prove all
13 distinct IDs flipped. **Fix:** assert at the ID level — verify each of the 13 IDs (INST-01,
INST-06, INST-07, FOUND-01, DIAG-05, PANE-01..04, SCEN-03..06) no longer carries a "macOS deferred
D-18" qualifier, rather than counting occurrences of a flip string.

## ACTIONABLE — MEDIUM

- **F6 (07-01 Task 2):** `<read_first>` cites `tools/setup.sh` (A-3) but the action never references it
  — remove the stray read directive, or add one line explaining its role.
- **F7 (07-02 Task 1):** the "RED expected" acceptance criterion should enumerate WHICH assertions are
  expected to fail RED (the not-yet-real `install_macos` ones) vs. PASS (the `wezterm_macos_asset_url`
  ones), so a correct RED is distinguishable from a test-infra failure.
- **F8 (07-05 Task 1):** specify the `agent-ui-ux-designer` invocation protocol — what input it
  receives (which runbook visual sections / transcript) and how its notes are appended — referencing
  CONTEXT D-02 as the source.
- **F9 (07-03 Task 2 → 07-04 Task 1):** minor cross-plan note — record that `actionlint` already ran
  on `release.yml` in 07-03 so 07-04 Task 1 neither double-runs nor silently skips it.

---

## NOT ACTIONABLE — verified non-issues (do NOT "fix"; leaving for audit trail)

- **N1 (07-04 Task 1, was flagged HIGH "unverified"):** the `docs/macos-verification.md` "§Prerequisites
  & environment, lines 47-103" citation is **accurate** — confirmed: that section spans ~L46–L103 and
  Section 1 begins ~L105 (file is 508 lines). No change needed.
- **N2 (07-05 Task 2, was flagged MEDIUM "12 vs 13"):** the distinct D-18 ID set is **13**
  (INST-01/06/07, FOUND-01, DIAG-05, PANE-01..04, SCEN-03..06) — the plan's count is correct. Only the
  grep-reliability sub-point is real and is captured as F5 above.
- **N3 (upstream grounding nit):** RESEARCH Pattern 3's `spctl --assess ... || true` example line could
  mislead, but the plans correctly exclude any `spctl` gate from `build.sh`. This is an upstream-doc
  observation, not a plan defect — no plan change required.
