---
phase: 05-named-scenes
plan: 03
subsystem: cli
tags: [lua, scenes, scene-launch, recipe, equivalence, completion-provider]

# Dependency graph
requires:
  - phase: 05-01
    provides: cli/lib/recipe.lua — load_and_map + guard_name (the recipe parse/map/guard the launch IO-shell delegates to)
  - phase: 05-02
    provides: scenes/*.toml seeds + the scenes-dir resolver precedent the launch resolver reuses
  - phase: 04
    provides: cli/commands/scene.lua M.run_new — the in-process orchestration the launch path delegates to (single code path)
provides:
  - wez scene launch <name> — the SCEN-04 structural-equivalence seam (file read -> guard_name -> load_and_map -> M.run_new)
  - M.scenes_dir() — the ONE co-located scenes-dir resolver (D-04), shared with completion + seeder
  - M.list_recipe_names(dir) — the single recipe-listing provider feeding BOTH the launch error hint and (next) scene-names completion
  - scene launch <name> registered under the scene command in cli/spec.lua (D-16 completion spec-walk picks it up)
affects: [05-04, named-scenes, scene-completion]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Thin IO-shell over the pure core: launch does file I/O + guard, then delegates ALL scene-building to M.run_new (no reimplementation)"
    - "Single-provider listing (M.list_recipe_names) shared by the error hint and completion to prevent drift"
    - "guard_name runs BEFORE any io.open — path-traversal mitigation at the IO boundary (T-05-08)"

key-files:
  created:
    - tests/cli/scene_launch_test.lua
  modified:
    - cli/commands/scene.lua
    - cli/spec.lua

key-decisions:
  - "run_launch builds the {layout, pane[], color, title} args table and returns M.run_new(args) — equivalence is structural, not a re-quoted shell-out"
  - "All 4 UI-SPEC error paths use exact copy + exit codes: no-name -> 2, no-recipes -> 2, unknown name -> 1, malformed/invalid recipe -> 1"
  - "Unknown-name hint lists recipe basenames SORTED via the single provider; the try-line uses the first sorted name"
  - "scenes_dir resolver reuses the same env precedence (WEZTERM_SETUP_DIR -> ... -> ~/.config/wezterm/wezterm-setup) as the seeder, so launch/completion/seed never diverge"

patterns-established:
  - "IO-shell front-end pattern for recipe-backed commands: resolve dir -> guard name -> read -> load_and_map -> delegate to the pure orchestrator"

requirements-completed: [SCEN-03, SCEN-04]

# Metrics
duration: ~20min (incl. session-limit interruption + resume)
completed: 2026-06-14
---

# Phase 5 Plan 03: `wez scene launch <name>` Summary

**`wez scene launch <name>` resolves `<scenes-dir>/<name>.toml`, guards the name before any filesystem access, maps it through the Phase-5 recipe core, and delegates to `M.run_new` — making launch contractually equivalent to `scene new` by sharing one code path (SCEN-04), with all four UI-SPEC error paths exact.**

## Performance

- **Duration:** ~20 min (Task 1 committed, then a session-limit interruption mid-Task-2; resumed and closed out)
- **Completed:** 2026-06-14
- **Tasks:** 2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- `M.run_launch(args)` is a thin IO-shell: `M.scenes_dir()` → `guard_name` (before `io.open`) → read file → `recipe.load_and_map` → **`return M.run_new(args_table)`**. Launch reimplements zero scene-building — equivalence with `scene new` is structural (SCEN-04, D-03).
- `M.scenes_dir()` is the single co-located resolver (D-04) honoring `WEZTERM_SETUP_DIR → WEZTERM_CONFIG_DIR → XDG_CONFIG_HOME/wezterm → ~/.config/wezterm`, then `/wezterm-setup/scenes`.
- `M.list_recipe_names(dir)` is the single sorted recipe-name provider — used by the launch error hint now, and by `scene-names` completion in 05-04 (no drift).
- All 4 UI-SPEC error paths exact (verified by tests): no name → exit 2 + usage/no-recipes guidance; unknown name → exit 1 + not-found copy + sorted available-recipes hint block + try-line; malformed/invalid recipe → exit 1 + recipe-is-invalid copy naming the parse failure, building ZERO panes; path-traversal name → exit 1 via `guard_name` before `io.open`.
- `scene launch <name>` registered under the `scene` command in `cli/spec.lua`, so the D-16 completion spec-walk discovers it automatically (sets up 05-04).

## Task Commits

1. **Task 1: shared scenes-dir resolver + single-provider listing + run_launch + dispatch** — `fb397eb` (feat) — `cli/commands/scene.lua` (+146)
2. **Task 2: scene launch registration + full error-path/delegation test suite** — `41a3338` (feat) — `cli/spec.lua` (+6), `tests/cli/scene_launch_test.lua` (+236)

## Files Created/Modified
- `cli/commands/scene.lua` — `M.scenes_dir`, `M.list_recipe_names`, `M.run_launch`, and `launch` dispatch in `M.run`
- `cli/spec.lua` — registered `scene launch <name>` (positional recipe basename) under the `scene` command
- `tests/cli/scene_launch_test.lua` — 20 assertions: all 4 error paths (exact copy + exit codes 2/2/1/1), path-traversal guard, sorted-hint ordering, and `run_new` delegation (proves the single code path: layout/color/mapped pane specs flow through)

## Decisions Made
- **Single code path for equivalence**: `run_launch` returns `M.run_new(args)` directly rather than constructing and exec'ing a `wez scene new ...` command line — no subprocess, no re-quoting surface.
- **Guard before I/O**: `guard_name` (rejecting empty / `/` / `..`) is called before the resolved `<scenes_dir>/<name>.toml` path ever reaches `io.open` (T-05-08).
- **Shared listing provider**: the unknown-name hint and the upcoming completion both read `M.list_recipe_names(M.scenes_dir())` so the two surfaces can never disagree.

## Deviations from Plan
- **Resumed after a session-limit interruption.** Task 1 (`fb397eb`) had landed; Task 2's implementation (spec.lua registration + the test file) was complete on disk but uncommitted when the prior executor's session limit hit. The work was independently re-verified (20/20 launch assertions, full suite 17/17 green) and committed as `41a3338` to close out the plan. No code was rewritten — only verified and committed. Plan content executed exactly as written.

## Issues Encountered
- Session-limit interruption mid-Task-2 (see Deviations). Resolved via the safe-resume close-out path: inspect on-disk state → run tests → commit the verified remainder → write SUMMARY + tracking.

## User Setup Required
None.

## Next Phase Readiness
- 05-04 (dynamic completion) can now wire a `scene-names` `__complete` context to the **already-built** `M.list_recipe_names(M.scenes_dir())` provider, and add the nested `scene)` → `launch)` arm to the generated zsh/bash scripts.
- Linux-verified; macOS parity is part of the batched cross-platform pass before milestone close (see `docs/macos-verification.md`).

## Self-Check: PASSED

`cli/commands/scene.lua` contains `M.run_launch`/`M.scenes_dir`/`M.list_recipe_names`; `scene launch` present in `cli/spec.lua`; both commits (`fb397eb`, `41a3338`) in git history; `scene_launch_test.lua` 20/20 and full suite 17/17 green.

---
*Phase: 05-named-scenes*
*Completed: 2026-06-14*
