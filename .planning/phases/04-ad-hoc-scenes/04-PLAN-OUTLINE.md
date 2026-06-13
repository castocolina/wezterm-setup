| Plan ID | Objective | Wave | Depends On | Requirements |
|---------|-----------|------|------------|---------------|
| 04-01 | Pure-logic core (TDD, plain lua5.4): layout->split-sequence planner with the equal-share `100/(remaining)`% formula for tall/tall:mirrored/grid/horizontal at arbitrary N (incl. N=1 special case); `--pane` key=value parser (bare=cmd, `shell` keyword, `cmd=`/`color=`/`title=` keys, D-06); layout/color validation (validate-before-emit, D-01-style); materialization decider (1-pane-reuse vs >=2-new-tab, D-10/D-11/D-12) from parsed `wezterm cli list --format json` topology; pane-id/tab-id integer validation. No `wezterm` runtime dependency. | 1 | (none) | SCEN-02 |
| 04-02 | Live orchestration (hypothesis-first, manual repro): `wez scene new` command wiring 04-01's planner to `wezterm cli spawn`/`split-pane`/`send-text` per the build-path sequence (topology read -> materialize decision -> spawn/split-pane collecting pane-ids -> per-pane clean OSC 11/1337 styling injection, D-09 -> tab-level `set-tab-title`/color via Phase 3 path -> startup command send-text+newline, D-08 -> focus via `activate-pane`); minimal `cli/spec.lua` registration for dispatch. Records `docs/repro/h-scene-*.md` for the 4 layouts plus both materialization cases. | 2 | 04-01 | SCEN-01 |
| 04-03 | Completion/spec wiring: complete the `scene new` entry in `cli/spec.lua` (mirroring `pane`/`tab` blocks) with full `--layout`, repeated `--pane`, `--color`, `--title` argspec; wire `--layout` candidate values (tall, tall:mirrored, grid, horizontal) and `--pane`/`--color` completions through the `wez __complete` hook (D-16, success criterion #3). | 3 | 04-02 | SCEN-01, SCEN-02 |

## OUTLINE COMPLETE

3 plans
