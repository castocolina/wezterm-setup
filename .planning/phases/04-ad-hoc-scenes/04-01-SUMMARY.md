---
phase: 04-ad-hoc-scenes
plan: 01
subsystem: cli
tags: [lua, wezterm, scene, split-pane, layout, tdd, pure-functions]

# Dependency graph
requires:
  - phase: 03 (tab/pane title)
    provides: cli/lib/title.lua module style (local M = {} / return M, --- doc comments) mirrored here
provides:
  - cli/lib/scene.lua pure logic core for `wez scene new`
  - plan_splits (equal-share split sequencer for tall/tall:mirrored/grid/horizontal)
  - parse_pane_spec (--pane key=value grammar parser with validate-before-emit errors)
  - validate_layout / validate_color (exact UI-SPEC error strings)
  - validate_pane_id / validate_tab_id (integer coercion + range)
  - decide_materialization (D-10 reuse vs D-11 new-tab decider)
affects: [04-02 (live wez cli wiring), 04-03 (cli/spec.lua command wiring)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure-logic module isolation: no mux global / shell-out, fully unit-testable under plain lua5.4"
    - "Equal-share split sequencing: round_pct(remaining) = floor(100/remaining + 0.5) as single rounding site"
    - "Creation-order pane-index targeting: original = 0, each split creates the next index"

key-files:
  created:
    - cli/lib/scene.lua
    - cli/lib/scene_test.lua
  modified: []

key-decisions:
  - "decide_materialization mode driven SOLELY by tab_pane_count == 1 (per plan body + acceptance criteria), NOT the research sketch's tab_pane_count==1 AND N==1 — n is accepted for signature symmetry only"
  - "parse_pane_spec does NOT require cli.lib.title — auto-title resolution (D-07) is a live-wrapper (04-02) concern; this module only carries the raw title= value through"
  - "validate_pane_id and validate_tab_id share one integer contract (M.validate_tab_id = M.validate_pane_id alias) since both ids have identical validation"
  - "Reworded module doc comments to avoid literal 'wezterm'/'io.popen'/'os.execute' tokens so the purity acceptance grep returns 0 matches"

patterns-established:
  - "round_pct(remaining) private helper is the sole math.floor(100/...) rounding site"
  - "split_kv_segments(spec) private helper consolidates comma + first-equals parsing"
  - "Test harness mirrors cli/lib/title_test.lua: check/eq + added recursive deep_eq/teq for table-returning functions"

requirements-completed: [SCEN-02]

# Metrics
duration: 2min
completed: 2026-06-13
---

# Phase 04 Plan 01: Scene Pure-Logic Core Summary

**Pure Lua 5.4 split-sequence planner (4 layouts), --pane spec parser, layout/color validators, and D-10/D-11 materialization decider — fully unit-tested under plain lua5.4 with zero mux/IO dependency.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-13T01:38:44Z
- **Completed:** 2026-06-13T01:41:00Z (approx)
- **Tasks:** 3 (RED / GREEN / REFACTOR)
- **Files modified:** 2 (both net-new)

## Accomplishments
- `cli/lib/scene.lua`: pure-logic core exporting `plan_splits`, `parse_pane_spec`, `validate_layout`, `validate_color`, `validate_pane_id`/`validate_tab_id`, `decide_materialization`
- Equal-share split sequencer covering all 4 layouts (tall, tall:mirrored, grid, horizontal) at arbitrary N, including the N=1 empty-plan special case and non-square grids
- `cli/lib/scene_test.lua`: 49-assertion fixture suite runnable under plain `lua5.4`, mirroring the `cli/lib/title_test.lua` harness (plus a recursive `deep_eq`/`teq` for table-returning functions)
- Module is provably pure — `rg -c 'wezterm|io.popen|os.execute' cli/lib/scene.lua` returns 0 matches — so its full behavior is covered without a live WezTerm session

## Task Commits

Full TDD RED -> GREEN -> REFACTOR sequence, each committed atomically:

1. **Task 1 (RED): failing fixture tests** - `4a77af2` (test)
2. **Task 2 (GREEN): implement scene.lua** - `19a8b38` (feat)
3. **Task 3 (REFACTOR): edge-case fixtures** - `eff22e8` (refactor)

**Plan metadata:** (final docs commit — see below)

## Files Created/Modified
- `cli/lib/scene.lua` - Pure scene-building helpers: split-sequence planner (4 layouts), --pane spec parser, layout/color validators, pane/tab-id validator, materialization decider
- `cli/lib/scene_test.lua` - 49 fixture assertions across all 6 exported function groups, runnable under plain lua5.4

## Decisions Made
- **Materialization mode:** driven solely by `tab_pane_count == 1` (reuse) vs `>= 1` other (new-tab), matching the plan body and acceptance criteria. The research sketch's `tab_pane_count == 1 AND N == 1` guard was NOT used — `decide_materialization(panes, current_pane_id, 3)` with a 1-pane current tab still returns `reuse`, per the plan's explicit D-10/D-12 reading. `n` is accepted for signature symmetry / future validation only.
- **No `cli.lib.title` dependency:** per D-07, auto-title resolution happens at spawn time (04-02), so this module keeps its dependency surface minimal and carries the raw `title=` value through unmodified. Noted in a `scene.lua` comment for 04-02.
- **`validate_tab_id` as an alias** of `validate_pane_id` — identical integer contract, exported under both names so call sites read intent-clearly.
- **Doc-comment wording:** module comments were phrased to avoid the literal tokens `wezterm`/`io.popen`/`os.execute` so the purity acceptance grep returns exactly 0 (the comments describe "terminal multiplexer global" / "process-spawning or shell-out primitives" instead).

## Deviations from Plan

None - plan executed exactly as written. The structural extractions specified for the REFACTOR task (`round_pct`, `split_kv_segments`) were written directly into the GREEN implementation as the natural clean form, so REFACTOR added only the new edge-case fixtures (tall N=2, horizontal N=2, grid N=4, empty-spec) — the helpers were already sole-sited and verified by the REFACTOR acceptance greps (`round_pct` count 1, `math.floor(100` count 1).

## Issues Encountered
- Initial GREEN purity grep returned 3 (matches inside doc comments referencing the banned APIs by name). Resolved by rewording the comments to describe the banned APIs without using their literal tokens; suite stayed green throughout (44 passed, 0 failed before and after the reword).

## TDD Gate Compliance
- RED commit `4a77af2` (`test(04-01)`): suite fails non-zero (module absent).
- GREEN commit `19a8b38` (`feat(04-01)`): 44 passed, 0 failed.
- REFACTOR commit `eff22e8` (`refactor(04-01)`): 49 passed, 0 failed (strictly more).
- Gate sequence test -> feat -> refactor present and ordered. Compliant.

## Verification Evidence
- `lua5.4 cli/lib/scene_test.lua` -> `scene_test: 49 passed, 0 failed`, exit 0
- `rg -c 'wezterm|io.popen|os.execute' cli/lib/scene.lua` -> 0 matches (purity)
- `rg -c 'function round_pct' cli/lib/scene.lua` -> 1
- `rg -c 'math.floor\(100' cli/lib/scene.lua` -> 1
- `M.plan_splits("grid", 5)` -> 4 steps, first `{direction="bottom", percent=50, target=0}`
- `M.decide_materialization({{pane_id=1,tab_id=10}}, 1, 1)` -> `{mode="reuse", target_tab_id=10, first_pane_id=1}`
- `M.decide_materialization({{pane_id=1,tab_id=10},{pane_id=2,tab_id=10}}, 1, 3)` -> `{mode="new-tab", target_tab_id=nil, first_pane_id=nil}`

## User Setup Required
None - no external service configuration required. Pure stdlib Lua, no new dependencies.

## Next Phase Readiness
- 04-02 can consume these already-tested pure helpers for the live `wezterm cli` wiring (inventory -> decide -> split-all -> style-each -> tab-title -> activate).
- 04-02 owns the I/O trust boundary: it must call `validate_pane_id`/`validate_tab_id` on every id read from `wezterm cli list` JSON before shelling out, and resolve auto pane-titles via `cli/lib/title.lua` at spawn time (this module deliberately does not).
- No blockers.

## Self-Check: PASSED

- FOUND: cli/lib/scene.lua
- FOUND: cli/lib/scene_test.lua
- FOUND: .planning/phases/04-ad-hoc-scenes/04-01-SUMMARY.md
- FOUND commit: 4a77af2 (RED)
- FOUND commit: 19a8b38 (GREEN)
- FOUND commit: eff22e8 (REFACTOR)

---
*Phase: 04-ad-hoc-scenes*
*Completed: 2026-06-13*
