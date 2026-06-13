---
phase: 04-ad-hoc-scenes
plan: 02
subsystem: cli
tags: [lua, wezterm, scene, live-orchestration, wezterm-cli, e2e, osc, materialization]

# Dependency graph
requires:
  - phase: 04 (plan 01)
    provides: cli/lib/scene.lua pure core (plan_splits, parse_pane_spec, validators, decide_materialization)
  - phase: 03
    provides: cli/lib/title.lua resolve_title_str (per-pane + tab title resolution, D-07)
  - phase: 02
    provides: cli/lib/pane.lua OSC builders (build_osc11 bg color, build_osc1337 SetUserVar)
provides:
  - cli/commands/scene.lua live orchestrator for `wez scene new`
  - cli/spec.lua scene namespace argspec (--layout, repeated --pane, --color, --title)
  - docs/repro/h-scene-{tall,tall-mirrored,grid,horizontal,materialization}.md verified e2e repros
affects: [04-03 (M.LAYOUTS export + scene-layouts completion)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Live orchestration phases: read_topology -> decide_materialization -> spawn/split (PHASE A) -> style-each (PHASE B) -> set-tab-title -> activate main pane"
    - "Per-pane id captured from each `wezterm cli split-pane` stdout (T-04-01) and validated via scenelib.validate_pane_id before any further shell-out"
    - "D-09 clean panes: per-pane OSC styling emitted by having the shell EXECUTE `printf '<octal>'; clear; <cmd>` so the escape bytes reach the terminal PARSER, never the shell line editor (raw send-text to a shell PTY is swallowed/echoed as garbage)"

key-files:
  created:
    - cli/commands/scene.lua
    - docs/repro/h-scene-tall.md
    - docs/repro/h-scene-tall-mirrored.md
    - docs/repro/h-scene-grid.md
    - docs/repro/h-scene-horizontal.md
    - docs/repro/h-scene-materialization.md
  modified:
    - cli/spec.lua
    - cli/lib/scene.lua
    - cli/lib/scene_test.lua

key-decisions:
  - "Current pane resolved from WEZTERM_PANE (os.getenv); empty topology => current_pane_id unknown => new-tab path (safe default)"
  - "Two-phase build: spawn/split ALL panes first (creation-order pane_ids array), THEN style each — keeps the split geometry deterministic before any styling I/O"
  - "Per-pane styling sent as `printf '<octal-escaped OSC bytes>'; clear; <cmd>` (D-09), NOT raw OSC via send-text — the raw form leaks `11;#..1337;SetU..` garbage into the reused shell pane"
  - "Final pane count asserted == N (D-12); a count mismatch aborts with an error rather than leaving a malformed scene"

patterns-established:
  - "Headless e2e harness: isolated `wezterm-mux-server` under a throwaway XDG_RUNTIME_DIR + minimal config verifies topology/counts/geometry/materialization without a GUI; rendered colors still need GUI eyes"

requirements-completed: [SCEN-01, SCEN-02]

# Metrics
duration: "executed 2026-06-12; e2e-hardened + verified 2026-06-13"
completed: 2026-06-13
---

# Phase 04 Plan 02: Scene Live Orchestration Summary

**`wez scene new` live orchestrator — reads the running WezTerm topology, decides reuse-vs-new-tab,
spawns/splits the exact pane geometry for all 4 layouts, styles each pane (bg color + title) cleanly
via a printf-driven OSC path, sets the tab `color:title`, and focuses the main pane. Verified end to
end against a real headless mux for all 5 repro scenarios; per-pane colors signed off in a live GUI.**

## Accomplishments
- `cli/commands/scene.lua` (`M.run_new`): full live pipeline — `read_topology` (parse `wezterm cli
  list --format json`) → `decide_materialization` → PHASE A spawn/split → PHASE B per-pane styling →
  `set-tab-title` → `activate-pane` on the main pane
- `cli/spec.lua`: scene namespace argspec (`--layout` required, repeated `--pane` via `count("*")`,
  optional `--color`/`--title`) routing to cli/commands/scene.lua via the unchanged dispatcher
- 5 manual-repro docs created **and filled with real verified results** (geometry, materialization,
  D-09 clean panes) — not just templates

## Task Commits
- `e73c23e feat(04-02): wez scene new live orchestration` (scene.lua + spec.lua argspec)
- `8a56d38 docs(04-02): scene repro templates` (the 5 repro skeletons)
- `cab0a55 fix(04-01): correct tall/tall:mirrored split side + trim --pane whitespace` (e2e finding)
- `497550e fix(04-02): emit per-pane OSC styling via printf, not raw send-text (D-09)` (e2e finding)
- (this docs commit: repro docs filled with verified observations + valid `cmd=` grammar)

## The e2e blind spot this plan closed
04-02's unit tests passed while **three** real bugs were live — caught only by running the scenes in
a real WezTerm:
1. **tall/tall:mirrored geometry swapped** — `wezterm split-pane --<dir>` places the NEW pane on
   `<dir>`, so keeping the main pane on the left needs the *inverse* first-split direction. Unit
   tests "passed" because they asserted the planner's own inverted model. Fixed (cab0a55) + tests
   corrected.
2. **`--pane` whitespace not trimmed** — D-06's own readable form `'cmd=docker stats, color=teal,
   title=stats'` failed to parse. Fixed (cab0a55) + test 2g added.
3. **Per-pane OSC styling leaked as garbage** — raw escape bytes sent via `send-text` go to the
   shell line editor (zsh swallows them; bash echoes the printable tail), so the color never applied
   and `11;#..1337;SetU..` appeared as text. Fixed (497550e) with the printf+clear pattern.

(These, plus two Phase-1 install/config bugs found in the same session, are recorded in the resolved
debug session `.planning/debug/resolved/install-config-e2e.md`.)

## Verification Evidence (headless mux, 2026-06-13)
- **Materialization** — reuse: `tab0` 1→2 panes, same tab, focus on original, exactly N=2, no new
  window. new-tab: new `tab1` in the SAME window, original `tab0` untouched, exactly N=2.
- **tall N=3** — main pane LEFT full-height (col 0), 2 stacked right (col 40, rows 0 & 12),
  `tab_title='teal:Dev Scene'`, htop running, focus main.
- **tall:mirrored N=3** — main pane RIGHT (col 41 full-height, focused), stack LEFT — exact mirror.
- **grid N=5** — 3×2 grid, top row 3 cols, bottom row 2 cols left-aligned, NO placeholder, exactly
  5 panes (D-12), focus top-left.
- **horizontal N=4** — 4 full-height columns 19/19/19/20 (equal-share, not a cascade), focus left.
- **D-09 clean** — `get-text` on a styled `echo hello` pane shows only the command + output; zero
  raw escape bytes (`grep -E '11;#|1337;|SetUserVar'` → no match).
- **Per-pane rendered colors** — confirmed visually in a live GUI session (user sign-off).

See `docs/repro/h-scene-*.md` for the full per-scenario records.

## Deviations from Plan
- The repro docs shipped as templates (8a56d38) with `Observed`/`Verdict` = TODO, and one repro
  command used the invalid bare-command-plus-attributes form (`'echo hello,color=blue'`, rejected by
  D-06). Both corrected here: valid `cmd=` grammar + real verified observations recorded.
- Geometry/materialization were verified headlessly (mux topology) rather than purely by-eye; this is
  stronger evidence and is now the documented harness for scene e2e.

## Next Phase Readiness
- 04-03 (done) registered `M.LAYOUTS` + the `scene-layouts` completion context; the scene argspec
  this plan added to spec.lua already drives dispatch + `wez keys`.
- No blockers. Phase 4 feature-complete on Linux.

## Self-Check: PASSED
- FOUND: cli/commands/scene.lua
- FOUND: cli/spec.lua scene block
- FOUND: docs/repro/h-scene-{tall,tall-mirrored,grid,horizontal,materialization}.md (all with verdicts)
- FOUND commit: e73c23e (feat), 497550e + cab0a55 (e2e fixes)

---
*Phase: 04-ad-hoc-scenes*
*Completed: 2026-06-13*
