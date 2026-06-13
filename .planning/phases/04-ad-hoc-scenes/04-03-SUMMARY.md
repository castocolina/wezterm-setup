---
phase: 04-ad-hoc-scenes
plan: 03
subsystem: cli
tags: [lua, wezterm, scene, spec, completion, tdd, single-source-of-truth, D-16]

# Dependency graph
requires:
  - phase: 04 (plan 01)
    provides: cli/lib/scene.lua pure core (validate_layout to refactor; M.LAYOUTS new home)
  - phase: 04 (plan 02)
    provides: cli/spec.lua scene argspec (already registered) + cli/commands/scene.lua live orchestration
provides:
  - cli/lib/scene.lua M.LAYOUTS ordered array (single source of truth for the 4 layout names)
  - cli/commands/complete.lua scene-layouts completion context (wez __complete scene-layouts)
affects: [05 (named scenes — scene-names completion context will follow this pattern)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Closed-set completion context: provider iterates an exported lib array (scene.LAYOUTS), mirrors tab_colors/pane_colors minus the 'reset' append"
    - "Single source of truth (D-16): the layout name set is written ONCE (M.LAYOUTS); validate_layout + the completion provider both derive from it, so validation and completion cannot drift"

key-files:
  created: []
  modified:
    - cli/lib/scene.lua
    - cli/lib/scene_test.lua
    - cli/commands/complete.lua
    - cli/commands/complete_test.lua

key-decisions:
  - "spec.lua scene argspec was ALREADY fully registered in 04-02 (--layout, repeated --pane via count('*'), --color, --title) — 04-03's spec.lua work was already satisfied, so this plan reduced to the M.LAYOUTS export + scene-layouts completion context. No spec.lua edit needed."
  - "validate_layout reimplemented to check a LAYOUT_SET derived once from M.LAYOUTS at module load — the inline {tall=true,...} literal set is gone, so the 4 names exist in exactly one production location"
  - "Error message rebuilt via table.concat(M.LAYOUTS, ', ') so the 'expected one of' list also derives from the single source (byte-identical to the prior hardcoded string — test 3e2 unchanged and green)"
  - "scene_layouts provider does NOT table.sort: M.LAYOUTS is already in intended display order (tall first); alphabetizing would wrongly reorder to grid/horizontal/tall/tall:mirrored"

patterns-established:
  - "scene-layouts joins subcommands/pane-colors/pane-icons/tab-colors/tab-icons in the closed CONTEXTS dispatch — future phases (scene-names) add an entry here with zero edits to the generated completion scripts (completions.lua)"

requirements-completed: [SCEN-01, SCEN-02]

# Metrics
duration: 4min
completed: 2026-06-13
---

# Phase 04 Plan 03: Scene Argspec + Completion Wiring Summary

**Closed the `wez scene new` command surface for D-16: exported `M.LAYOUTS` as the single source of truth for the 4 layout names (validate_layout now derives from it) and added the `wez __complete scene-layouts` context — flag-name and layout-value completion now flow entirely from the spec + the closed-set hook, with no edits to the generated completion scripts or the dispatcher.**

## Performance

- **Duration:** ~4 min
- **Completed:** 2026-06-13
- **Tasks:** 3 (RED / GREEN / REFACTOR) — executed inline
- **Files modified:** 4

## Accomplishments
- `cli/lib/scene.lua`: added `M.LAYOUTS = {"tall", "tall:mirrored", "grid", "horizontal"}` (ordered) and rewrote `validate_layout` to check a `LAYOUT_SET` derived from it — the inline literal set is gone (single source of truth, D-16)
- `cli/commands/complete.lua`: added `require("cli.lib.scene")` + a `scene_layouts()` provider + registered `CONTEXTS["scene-layouts"]` — `wez __complete scene-layouts` now emits exactly the 4 names, in display order
- `cli/spec.lua`: **no change needed** — 04-02 already registered the full scene argspec (`--layout`, repeated `--pane`, `--color`, `--title`); verified by the smoke-parse
- Tests: +3 assertions in `scene_test.lua` (M.LAYOUTS contents/order + validate_layout derives from it) and +4 in `complete_test.lua` (scene-layouts exits 0, count, exact-order-derived-from-module, not-alphabetized)

## Task Commits

Executed inline (interactive-style), folded into a single cohesive commit per the project's commit-discipline rule. The TDD sequence was still honored and verified at each gate:

1. **RED** — tests added first; ran both files and confirmed failures attributable to missing `M.LAYOUTS` (nil) / missing `scene-layouts` context, NOT syntax/require errors
2. **GREEN** — implemented M.LAYOUTS + scene-layouts; both suites green (53 / 18)
3. **REFACTOR** — no-op: single-source-of-truth already held in the GREEN form (one M.LAYOUTS, validate_layout + provider both derive); `completions.lua`/`wez.lua` confirmed untouched

**Commit:** `b5217cb feat(04-03): export scene M.LAYOUTS + scene-layouts completion context`

## Files Created/Modified
- `cli/lib/scene.lua` — M.LAYOUTS ordered array + LAYOUT_SET-derived validate_layout
- `cli/lib/scene_test.lua` — +section 8 (M.LAYOUTS + validate_layout-derives-from-it)
- `cli/commands/complete.lua` — scene require + scene_layouts provider + CONTEXTS["scene-layouts"]
- `cli/commands/complete_test.lua` — scene-layouts context assertions (derived from the module, not a literal)

## Decisions Made
- **spec.lua already done:** the scene argspec was registered in 04-02 (the comment there said "minimal routing" but in fact carried all four options). 04-03 therefore added no spec.lua block; the smoke-parse `scene new --layout tall --pane a --pane b --color blue --title x` → `command=scene, scene_cmd=new, layout=tall, panes=2` confirms it.
- **Single source of truth:** `M.LAYOUTS` is the only place the 4 names are written in production code; `validate_layout` derives `LAYOUT_SET` from it and rebuilds its error list via `table.concat(M.LAYOUTS, ", ")`; the completion provider iterates `scene.LAYOUTS`. The complete_test builds its expected value from `require("cli.lib.scene").LAYOUTS`, so drift is structurally caught.
- **No table.sort in the provider:** M.LAYOUTS is already in display order; sorting would break it.

## Deviations from Plan
- Plan assumed spec.lua had NO scene block to add ("net-new addition"); in fact 04-02 had already added it, so Task 2's spec.lua step was already satisfied (verified, not re-added).
- Plan prescribed three atomic commits (test/feat/refactor); executed inline as one cohesive commit per the project's "prefer fewer, cohesive commits" rule. RED was still verified before GREEN.

## Issues Encountered
None. RED failed for exactly the expected reason; GREEN passed first try; full suite stayed green.

## Verification Evidence
- `lua5.4 cli/lib/scene_test.lua` → `scene_test: 53 passed, 0 failed`, exit 0
- `lua5.4 cli/commands/complete_test.lua` → `complete_test: 18 passed, 0 failed`, exit 0
- smoke-parse `scene new --layout tall --pane a --pane b --color blue --title x` → `command=scene scene_cmd=new layout=tall panes=2`
- `rg -n '"tall:mirrored"' cli/` → only production set-definition hit is `cli/lib/scene.lua:176` (M.LAYOUTS); lines 68/75 are `plan_splits` branch conditions, not a duplicate set
- `git diff --name-only cli/commands/completions.lua cli/wez.lua` → empty (D-16 + T-01-02: generated scripts and dispatcher untouched)
- Full suite: `run-tests: all 8 file(s) passed`

## User Setup Required
None — declarative argspec data + a closed-set completion context. No new dependencies, no I/O.

## Next Phase Readiness
- `wez scene new` is now fully spec-driven: dispatches to cli/commands/scene.lua, appears in `wez keys`, and completes `--layout <Tab>` (4 names) + `--<Tab>` flag names with zero edits to the generated completion scripts.
- Phase 5 (named scenes) can add a `scene-names` completion context following the exact `scene_layouts` pattern.
- No blockers.

## Self-Check: PASSED

- FOUND: cli/lib/scene.lua (M.LAYOUTS)
- FOUND: cli/commands/complete.lua (scene-layouts)
- FOUND: .planning/phases/04-ad-hoc-scenes/04-03-SUMMARY.md
- FOUND commit: b5217cb

---
*Phase: 04-ad-hoc-scenes*
*Completed: 2026-06-13*
