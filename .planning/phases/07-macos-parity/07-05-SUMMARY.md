---
phase: 07-macos-parity
plan: 05
subsystem: testing
tags: [macos, parity, verification, runbook, agent-ui-ux-designer, screencapture, wezterm, scenes, completions]

# Dependency graph
requires:
  - phase: 07-04
    provides: "Live macOS install (install_macos .app placement + wez binary) + v1.0.0 tag + INST-06/07 E2E evidence"
  - phase: 07-01
    provides: "Sudo-free macOS compile toolchain (lua@5.4 keg + luastatic) + bash-3.2-safe run-tests.sh"
  - phase: 07-03
    provides: "CI/CD release matrix + build-time ad-hoc codesign (arm64 evidence cited via the shared build, D-01)"
provides:
  - "Fully agent-driven macOS verification runbook (docs/macos-verification.md): Results + deviations + §5/§6 agent-ui-ux-designer PASS notes from screencapture"
  - "verify-macos.sh auto gate confirmed green on this Intel Mac (PASS=26 FAIL=0, exit 0)"
  - "The 13 platform-sensitive D-18 requirement IDs flipped from deferred to 'macOS verified D-18 (§...)' in REQUIREMENTS + ROADMAP (byte-for-byte per ID)"
  - "macOS deviation #6 recorded: wez scene new needs the wezterm CLI on PATH (the .app bundle does not export it) + A-4 installer follow-up"
affects: [milestone-close, phase-7.1-arm64-enduser, macos-followups]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Agent-driven runbook verification: tmux + wezterm cli + screencapture harness feeds the agent-ui-ux-designer subagent (D-12); no human visual sign-off"
    - "D-03 evidence bar for status flips: each Done flip cites a specific runbook section"
    - "Per-ID flip gate (not a raw line count): each ID must report zero remaining deferred rows across both files"

key-files:
  created:
    - .planning/phases/07-macos-parity/07-05-SUMMARY.md
  modified:
    - docs/macos-verification.md
    - .planning/MACOS-PARITY-AND-FOLLOWUPS.md
    - .planning/REQUIREMENTS.md
    - .planning/ROADMAP.md

key-decisions:
  - "§5/§6 agent-ui-ux-designer verdict = PASS for both visual sections (no rendering defects); the orchestrator-run review notes inserted verbatim inline"
  - "wez scene new PATH deviation (#6) is honest-but-non-blocking: scene launch error/exit-code contract + verify-macos §4 passed, and scene new works once PATH is wired (proven in §6)"
  - "Flipped exactly the 13 plan IDs; SCEN-01/02 + INST-08 left deferred (out of the 07-05 flip scope); arm64 cited via the shared CI/CD build + codesign + Intel-proven parity (D-01), no Silicon hardware claim"

patterns-established:
  - "Pattern 1: Visual parity sign-off lives inline with the section it reviewed, fed by screencapture (never relocated to a separate file)"
  - "Pattern 2: Footer reconciliation notes must avoid the literal 'macOS deferred D-18' phrase next to ID lists so the per-ID flip gate does not false-positive on prose"

requirements-completed: [INST-01, INST-06, INST-07, FOUND-01, DIAG-05, PANE-01, PANE-02, PANE-03, PANE-04, SCEN-03, SCEN-04, SCEN-05, SCEN-06]

# Metrics
duration: 20min
completed: 2026-06-22
---

# Phase 7 Plan 05: macOS Parity Verification & D-18 Close Summary

**Closed the Phase 7 v1 gate: the agent-driven macOS runbook is complete with §5/§6 agent-ui-ux-designer PASS notes, the auto gate is green (PASS=26 FAIL=0), and all 13 platform-sensitive D-18 requirement IDs are flipped to "macOS verified" with per-section citations.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-06-22
- **Completed:** 2026-06-22
- **Tasks:** 2 completed (Task 1 harness portion was pre-done by a prior agent; this session inserted the orchestrator-run ui-ux notes + recorded one deviation, then did Task 2)
- **Files modified:** 4 (+1 created)

## Accomplishments

- Replaced the §5 and §6 `<PENDING orchestrator ui-ux review …>` placeholders in `docs/macos-verification.md` with the verbatim `agent-ui-ux-designer` notes — both verdicts **PASS, no rendering defects** (emoji cell-width, box-drawing glyphs, distinct pane backgrounds, fancy tab bar active/inactive distinction; even non-overlapping 2×2 grid scene in the same window, faithful colors/glyphs).
- Flipped the §5/§6 Results-table rows from `PENDING (ui-ux)` / `PARTIAL` to **PASS** (PANE-01..04, TAB-01..05, SCEN-01..02, SCEN-03/04) and updated the visual-section harness note from "limitation" to "resolved".
- Recorded **macOS deviation #6**: `wez scene new` fails `error: mux returned a non-numeric pane id` unless the `wezterm` CLI is on PATH (the macOS `WezTerm.app` bundle keeps it at `Contents/MacOS/wezterm` and does not export it). Workaround proven live; logged an A-4 installer follow-up. Non-blocking for the SCEN flips.
- Ticked the remaining `MACOS-PARITY-AND-FOLLOWUPS.md` §C visual boxes (C-5, C-6, C-7, C-8) and resolved the "Scene windowing" candidate (no per-scene Aqua window).
- Re-confirmed the auto gate: `bash tools/verify-macos.sh` → **PASS=26 FAIL=0 SKIP=8, exit 0**.
- Flipped the **13 D-18 IDs** (INST-01, INST-06, INST-07, FOUND-01, DIAG-05, PANE-01..04, SCEN-03..06) from the deferred qualifier to `macOS verified D-18 (§...)` in BOTH `.planning/REQUIREMENTS.md` (checkbox + Traceability) and `.planning/ROADMAP.md` (Coverage), byte-for-byte agreeing per ID; aligned the ROADMAP INST-07 row to REQUIREMENTS.
- Marked Phase 7 complete: ROADMAP Progress row 5/5, top-line Phase 7 + 07-05 checkboxes ticked. Phase 7.1 (arm64 end-user) scope untouched.

## Task Commits

1. **Task 1: insert §5/§6 ui-ux PASS notes + record wez-scene PATH deviation** - `39aff7e` (docs)
2. **Task 2: flip the 13 macOS D-18 IDs to verified (D-09)** - `92fa306` (docs)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP tracking) — see the final tracking commit.

## Files Created/Modified

- `docs/macos-verification.md` - §5/§6 placeholders replaced with verbatim agent-ui-ux-designer PASS notes; Results rows flipped to PASS; deviation #6 added; "Scene windowing" candidate resolved.
- `.planning/MACOS-PARITY-AND-FOLLOWUPS.md` - C-5..C-8 visual boxes ticked; A-4 follow-up added (install_macos could symlink `wezterm` into `~/.local/bin`).
- `.planning/REQUIREMENTS.md` - 13 D-18 IDs flipped to "macOS verified D-18 (§...)" in the checkbox list (FOUND-01) + Traceability table; footer note reworded.
- `.planning/ROADMAP.md` - Coverage table flipped per ID (incl. INST-07 alignment); Phase 7 Progress row 5/5 Complete; Phase 7 + 07-05 checkboxes ticked; footer note reworded.

## Verification

- `bash tools/verify-macos.sh` → `PASS=26 FAIL=0 SKIP=8`, `gate_exit=0` (re-confirmed this session under the lua@5.4 keg PATH).
- Per-ID flip gate over BOTH files: all 13 IDs report `deferred=0` in REQUIREMENTS.md and ROADMAP.md.
- Per-ID consistency diff (`grep -oE '(INST|FOUND|DIAG|PANE|SCEN)-[0-9]+ \| Phase … \| …'` sorted) between the two tables: **no divergence** (`TABLES_AGREE_PER_ID`).
- SCEN-01/02 + INST-08 confirmed still deferred (legitimately out of the 13-ID scope). Phase 7.1 split note untouched; no Apple-Silicon hardware claim introduced.

## Decisions Made

- **§5/§6 visual PASS:** the orchestrator-run agent-ui-ux-designer review returned PASS for both sections; inserted verbatim. Two honest low-confidence caveats kept in the notes (fine accent-color hue not pixel-confirmable at capture resolution; bash 3.2 printf `\u` scrollback escapes are a harness artifact, not a defect).
- **Deviation #6 is non-blocking for the SCEN flips:** the `scene launch` error/exit-code contract + `verify-macos.sh` §4 passed, and `scene new` builds correctly once PATH is wired (proven in the §6 grid capture). Filed as a post-v1 installer follow-up rather than hidden.
- **Footer reconciliation notes reworded** to avoid the literal `macOS deferred D-18` phrase adjacent to the ID list, which was false-positive-tripping the per-ID flip gate on prose (the actual table rows were correctly flipped).

## Deviations from Plan

**1. [Rule 1 - Bug] Per-ID flip gate false-positived on the reconciliation footer prose**
- **Found during:** Task 2 (D-18 flips)
- **Issue:** The first-draft "Last updated" footer notes literally contained `"macOS deferred D-18"` alongside the ID list (INST-01, PANE-01..04, …), so `grep -F "$id" | grep -c 'macOS deferred D-18'` reported `deferred=1` for several IDs even though every Traceability/Coverage row was correctly flipped.
- **Fix:** Reworded both footer notes to describe the flip without the literal phrase next to the IDs; re-ran the gate → all 13 IDs `deferred=0` in both files.
- **Files modified:** `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`
- **Verification:** per-ID loop + consistency diff both clean.
- **Committed in:** `92fa306`

**2. [Plan-recorded] macOS deviation #6 — `wez scene new` needs `wezterm` on PATH**
- **Found during:** Task 1 (live harness, orchestrator)
- **Issue:** `wez scene new` errors `mux returned a non-numeric pane id` unless `wezterm` is on PATH; the macOS `.app` bundle keeps it at `Contents/MacOS/wezterm`.
- **Fix:** Recorded as deviation #6 in the runbook + A-4 follow-up in the tracker (installer could symlink `wezterm` into `~/.local/bin`). Workaround proven live; does not block the flip.
- **Files modified:** `docs/macos-verification.md`, `.planning/MACOS-PARITY-AND-FOLLOWUPS.md`
- **Committed in:** `39aff7e`

---

**Total deviations:** 1 auto-fixed (Rule 1) + 1 plan-recorded macOS deviation.
**Impact on plan:** No scope creep. The Rule 1 fix is a doc-prose correction so the verification gate reflects reality; deviation #6 is honestly recorded and non-blocking.

## Issues Encountered

- The `gsd-tools`/`node …gsd-tools.cjs` SDK binary was not relied upon in this sequential subagent env; STATE/ROADMAP/REQUIREMENTS were updated via direct Edit per the orchestrator's instruction (prior executor confirmed the binary path may not resolve here). Format/prose preserved.

## User Setup Required

None - verification + documentation flips only; this plan installs nothing.

## Next Phase Readiness

- **Phase 7 is the v1 close gate and is now complete** on the available Intel Mac with recorded agent-driven evidence (D-09/D-12) and D-03-compliant citations.
- **Open (non-gating):** Phase 7.1 (Apple-Silicon end-user first-launch on real hardware) remains separate; arm64 status rests on the shared CI/CD build + codesign + Intel-proven parity (D-01).
- **Follow-ups filed (post-v1):** A-4 (install_macos `wezterm` PATH symlink), the cross-platform `wez keys --json` dkjson require-path bug (deviation #5, deferred-items.md), and the standing UX backlog (A-2).
- Ready for `/gsd-complete-milestone` consideration once Phases 6.4/6.5 are addressed per the roadmap order.

## Self-Check: PASSED

- Files verified present: 07-05-SUMMARY.md, docs/macos-verification.md, .planning/REQUIREMENTS.md, .planning/ROADMAP.md, .planning/MACOS-PARITY-AND-FOLLOWUPS.md.
- Commits verified in git log: `39aff7e` (Task 1), `92fa306` (Task 2).
- Auto gate re-confirmed: `verify-macos.sh` PASS=26 FAIL=0 exit 0.
- Per-ID flip gate: all 13 IDs deferred=0 in both files; tables agree per ID.

---
*Phase: 07-macos-parity*
*Completed: 2026-06-22*
