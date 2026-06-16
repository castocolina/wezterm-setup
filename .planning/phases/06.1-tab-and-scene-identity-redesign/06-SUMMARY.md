---
phase: 06.1-tab-and-scene-identity-redesign
plan: 06
subsystem: testing
tags: [lua, doctor, diagnostics, tdd, shadow-detection, format-tab-title, migration]

# Dependency graph
requires:
  - phase: 06-doctor (Plan 06, original)
    provides: "wez doctor gate()/aggregate() core-vs-advisory pattern + four core integrity gates"
  - phase: 04-ad-hoc-scenes
    provides: "install_state.parse() LOCKED sentinel markers (OPEN/CLOSE_MARKER) reused to bound the managed block"
provides:
  - "Fifth wez doctor CORE gate (gate_no_shadowing) that fails non-zero on an inline format-tab-title handler outside the managed block (D-11)"
  - "docs/migration-tab-color-decouple.md: best-effort detect+instruct migration guide for the tab-color decouple (D-10)"
affects: [07-prototype-migration, doctor, format-tab-title, tab-color-decouple]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure text-grep core gate: reads the user's wezterm.lua as TEXT and greps OUTSIDE the managed sentinel block — never loadfile/dofile/executes it (T-06-02)"
    - "Single source of guidance: the doctor gate's failure detail and the migration doc say the same 'what to remove'"

key-files:
  created:
    - docs/migration-tab-color-decouple.md
  modified:
    - cli/commands/doctor.lua
    - tests/cli/doctor_test.lua

key-decisions:
  - "Conservative shadow heuristic: only a format-tab-title registration OUTSIDE the managed block fails; a managed-block-internal match is the expected managed renderer (T-06.1-15)"
  - "Reused install_state OPEN/CLOSE_MARKER (the SAME LOCKED markers GATE 2 uses) for the block boundary — one shared parser, no second sentinel scanner (D-01)"
  - "SUMMARY filename is 06-SUMMARY.md (matches the phase's existing NN-SUMMARY.md convention and the orchestrator's expected path), not the plan's 06.1-06-SUMMARY.md literal"

patterns-established:
  - "Shadow-detection gate: grep the user's config text for shadowing registrations bounded by the managed sentinel block, fail loudly as a core (exit-gating) gate"

requirements-completed: [D-10, D-11]

# Metrics
duration: ~12min
completed: 2026-06-15
---

# Phase 06.1 Plan 06: Doctor Shadow-Detection + Migration Guide Summary

**`wez doctor` gains a fifth CORE gate that fails non-zero on an inline `format-tab-title` handler shadowing the managed block (the `cyan:`/no-color root cause), plus a migration doc that says exactly what to remove — all decided by a pure text grep that never executes the user's wezterm.lua.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-06-15T22:28Z
- **Completed:** 2026-06-15T22:40Z
- **Tasks:** 2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- Added `M.gate_no_shadowing(text)` — a fifth `wez doctor` CORE gate (gates the exit code, D-11) that detects a user-defined `wezterm.on("format-tab-title", ...)` registration (single- or double-quoted) OUTSIDE the managed sentinel block and FAILS with an actionable detail.
- The gate reuses `install_state.OPEN_MARKER`/`CLOSE_MARKER` to bound the managed block, so a managed-block-internal handler is correctly treated as the expected managed renderer (no false positive, T-06.1-15).
- Verified the gate is a PURE text decision — no `loadfile`/`dofile`/execution of the user's wezterm.lua (T-06-02 preserved); the four prior gates are unchanged and a healthy install still exits 0.
- Wrote `docs/migration-tab-color-decouple.md` (78 lines): explains the prefix→`WEZTERM_TAB_COLOR` user-var move, the `cyan:`/no-color/no-cwd symptom, the shadowing-handler root cause, the exact fix (matching the doctor gate detail), the installer backup, the clean-reinstall reset (D-10), and the live-tab reset behavior.

## Task Commits

Each task was committed atomically (TDD for Task 1: RED → GREEN):

1. **Task 1 (RED): doctor shadow-detection tests** - `506124d` (test)
2. **Task 1 (GREEN): doctor shadow-detection core gate (D-11)** - `21432dd` (feat)
3. **Task 2: tab-color decouple migration guide (D-10)** - `e1cfa48` (docs)

**Plan metadata:** see final `docs(06.1-06)` commit.

_TDD: the RED commit proved the gate absent (test failed: `attempt to call a nil value (field 'gate_no_shadowing')`); GREEN added the gate (25/25 assertions pass)._

## Files Created/Modified
- `cli/commands/doctor.lua` - Added `M.gate_no_shadowing(text)` (GATE 5) + wired it into the `core` array in `run()`; updated the header docstring from four to five core gates.
- `tests/cli/doctor_test.lua` - Added the shadow-detection cases: clean PASS, inline handler outside the managed block FAIL (single + double quote), managed-block-internal PASS, actionable detail mentions `format-tab-title`, and aggregate non-zero on a failing shadow gate.
- `docs/migration-tab-color-decouple.md` - The best-effort detect+instruct migration guide (D-10).

## Decisions Made
- **Conservative heuristic (T-06.1-15):** only a `format-tab-title` registration found OUTSIDE the managed block fails; a match INSIDE the managed block is the expected managed renderer and passes. This avoids false failures on a healthy install.
- **Reused the LOCKED markers (D-01):** the block boundary comes from `install_state.OPEN_MARKER`/`CLOSE_MARKER` (the same markers GATE 2 uses) rather than a second sentinel scanner.
- **Duplicate-keybinding heuristic kept to detect+instruct in prose:** the gate's automatable proxy is the `format-tab-title` grep (the precise, low-false-positive signal); the migration doc tells the user to also remove duplicate keybindings. A broader keybinding grep was intentionally NOT added to the gate to keep it conservative (T-06.1-15) — the doc carries that guidance.
- **SUMMARY filename:** used `06-SUMMARY.md` (the phase's existing `NN-SUMMARY.md` convention and the orchestrator/prompt success-criteria path), not the plan `<output>` literal `06.1-06-SUMMARY.md`.

## Deviations from Plan

None - plan executed exactly as written.

The plan permitted an optional `--fix` (D-10, Claude's discretion); it was NOT added — the bar is detect + instruct + the installer's existing backup, which is met by the gate + the migration doc. The plan's verify grep `grep -c 'loadfile.*wezterm%.lua\|dofile' | grep -qx 0` reports 4 (not 0) because the substring `dofile` matches the pre-existing `gate_config_dofiles` function/label name ("config **dofiles** cleanly"); the true security invariant — doctor never `loadfile`/`dofile`s the *user's* wezterm.lua — was verified directly and holds (the only `loadfile` is of the *managed* `init.lua` in GATE 3, which T-06-02 explicitly permits).

## Issues Encountered
- An initial test scaffold block tried to exercise `run()` against a planted config via `WEZTERM_CONFIG_FILE`, but pure Lua cannot portably `setenv`; the dead block was removed before the RED commit. Core-membership is instead covered by the aggregate-non-zero case plus the plan's `grep -q 'format-tab-title' cli/commands/doctor.lua` check; live `wez doctor` against a planted shadowing handler is deferred to Plan 07 per the plan's verification note.

## Verification
- `lua5.4 tests/cli/doctor_test.lua` — 25 passed, 0 failed (exit 0).
- `./tools/run-tests.sh` — all 23 files passed.
- `grep -q 'format-tab-title' cli/commands/doctor.lua` — gate present.
- `grep -nE 'loadfile|dofile'` on non-`dofiles`/non-`init.lua` lines — no `loadfile`/`dofile` of the user's wezterm.lua (T-06-02 holds).
- `docs/migration-tab-color-decouple.md` present, English, mentions `WEZTERM_TAB_COLOR` + `format-tab-title`, 78 lines (>20 min).

## Next Phase Readiness
- The shadow-detection gate is the automatable proxy for the render-bug class; **a live `wez doctor` repro against a planted shadowing handler is deferred to Plan 07** (the prototype-migration / integration-guard plan), per this plan's `<verification>`.
- The migration doc and the gate detail are a single source of guidance — Plan 07's prototype cleanup can point users directly at `docs/migration-tab-color-decouple.md`.

## Self-Check: PASSED

- FOUND: cli/commands/doctor.lua
- FOUND: tests/cli/doctor_test.lua
- FOUND: docs/migration-tab-color-decouple.md
- FOUND commit: 506124d (test RED)
- FOUND commit: 21432dd (feat GREEN)
- FOUND commit: e1cfa48 (docs migration)

## TDD Gate Compliance
- RED gate: `506124d` (`test(06.1-06)`) — committed with a proven failing test.
- GREEN gate: `21432dd` (`feat(06.1-06)`) — committed after the test passed.
- REFACTOR: none needed (the gate was clean on first GREEN).

---
*Phase: 06.1-tab-and-scene-identity-redesign*
*Completed: 2026-06-15*
