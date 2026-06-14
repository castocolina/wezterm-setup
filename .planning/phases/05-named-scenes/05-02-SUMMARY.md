---
phase: 05-named-scenes
plan: 02
subsystem: infra
tags: [lua, toml, installer, scenes, copy-if-absent, seeding]

# Dependency graph
requires:
  - phase: 05-01
    provides: cli/lib/recipe.lua + vendored tinytoml — the load_and_map round-trip that the seeds must satisfy
  - phase: 01-04
    provides: cli/commands/install_state.lua — read_all/write_all (CR-03) + shquote (CR-02) helper shapes reused by the seeder
  - phase: 01-01
    provides: cli/spec.lua single-source command contract + the hyphen->underscore dispatcher transform
provides:
  - 3 locked seed scene recipes (scenes/{dev,ai,docker}.toml) encoding the SCEN-06 table, OUTSIDE the cp -R config tree
  - wez seed-scenes copy-if-absent seeder (pure plan_seed + run() FS glue) with exact UI-SPEC messaging
  - seed-scenes registered in cli/spec.lua (parser + SUBCOMMANDS + CATEGORIES)
  - tools/setup.sh STEP 4b decision-free seeder invocation
  - README scenes path corrected to the co-located D-04 path
affects: [05-03, named-scenes, install, scene-launch]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure-decision + run()-glue split for the seeder (mirrors install_state.lua)"
    - "Copy-if-absent with TOCTOU re-check at write time (never overwrites a user edit)"
    - "Seeds live outside config/wezterm-setup/ so the wholesale cp -R cannot clobber them (D-06)"

key-files:
  created:
    - scenes/dev.toml
    - scenes/ai.toml
    - scenes/docker.toml
    - cli/commands/seed_scenes.lua
    - tests/cli/seed_scenes_test.lua
  modified:
    - cli/spec.lua
    - tools/setup.sh
    - README.md

key-decisions:
  - "Seeder dest dir resolver honors WEZTERM_SETUP_DIR -> WEZTERM_CONFIG_DIR -> XDG_CONFIG_HOME/wezterm -> ~/.config/wezterm, then /scenes"
  - "Repo seed dir resolves relative to the running script, with WEZ_SEED_SRC_DIR override (setup.sh sets it so the bundled binary finds the repo seeds)"
  - "Shell panes encode as command = \"shell\" and round-trip to the literal --pane shell (no auto-title injected)"
  - "STEP 4b mirrors STEP 6's decision-free install-state delegation; setup.sh adds NO copy/keep branching"

patterns-established:
  - "Pure plan_seed(repo_names, dest_names) -> {name, action=seed|keep} is fixture-testable with no FS"
  - "run() RE-CHECKS dest absence at write time (TOCTOU guard) and demotes a racing seed to keep messaging"

requirements-completed: [SCEN-06]

# Metrics
duration: 18min
completed: 2026-06-13
---

# Phase 5 Plan 02: Copy-if-absent Install Seeding Summary

**`wez seed-scenes` copy-if-absent seeder ships the 3 locked SCEN-06 recipes (dev/ai/docker) into the co-located scenes dir, preserving user edits byte-identical across reinstalls, with all copy/keep decisions in Lua and setup.sh STEP 4b as decision-free glue.**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-06-13T23:27Z
- **Completed:** 2026-06-13T23:45Z
- **Tasks:** 3
- **Files modified:** 8 (5 created, 3 modified)

## Accomplishments
- 3 seed recipes (`scenes/{dev,ai,docker}.toml`) encode EXACTLY the SCEN-06 table and round-trip through `recipe.load_and_map` to the expected args (dev→tall/green/2 shell; ai→tall/purple/2 shell; docker→grid/teal/[docker stats, docker ps, docker compose logs -f, shell]).
- `cli/commands/seed_scenes.lua`: pure `plan_seed` + `run()` FS glue mirroring `install_state.lua`; copy-if-absent with a TOCTOU re-check that never overwrites a user-edited recipe (D-06 INVARIANT / T-05-05).
- Exact UI-SPEC messaging: `seeded scene recipe: <name>` / `kept existing scene recipe: <name>` — never "skipped".
- `seed-scenes` registered in `cli/spec.lua` (parser command + SUBCOMMANDS allow-list + CATEGORIES=install); dispatchable and completion-visible.
- `tools/setup.sh` STEP 4b invokes `wez seed-scenes` decision-free; the `cp -R` config tree is untouched so it can never clobber `scenes/`.
- README scene-recipe path corrected to the co-located D-04 path `~/.config/wezterm/wezterm-setup/scenes/`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Author the 3 locked seed recipes outside the cp -R tree** - `a46ec88` (feat)
2. **Task 2: wez seed-scenes copy-if-absent seeder + spec registration** - `17d844a` (feat)
3. **Task 3: Wire setup.sh STEP 4b + fix README scenes path** - `5213314` (feat)

## Files Created/Modified
- `scenes/dev.toml` - Seed recipe: tall/green, 2 shell panes
- `scenes/ai.toml` - Seed recipe: tall/purple, 2 shell panes
- `scenes/docker.toml` - Seed recipe: grid/teal, 4 panes (docker stats/ps/compose logs/shell)
- `cli/commands/seed_scenes.lua` - Copy-if-absent seeder: pure `plan_seed` + `run()` FS glue, dest/src resolvers, TOCTOU guard
- `tests/cli/seed_scenes_test.lua` - Pure plan_seed cases + scratch-FS edit-survives-reinstall gate (14 assertions)
- `cli/spec.lua` - Registered `seed-scenes` (parser + SUBCOMMANDS + CATEGORIES)
- `tools/setup.sh` - New STEP 4b decision-free seeder invocation
- `README.md` - Scene recipe path corrected to the co-located D-04 path

## Decisions Made
- **Dest resolver precedence**: `WEZTERM_SETUP_DIR` → `WEZTERM_CONFIG_DIR/wezterm-setup` → `XDG_CONFIG_HOME/wezterm/wezterm-setup` → `~/.config/wezterm/wezterm-setup`, then `/scenes` — honors the same dogfood/test override `uninstall_state.default_setup_dir` uses.
- **Src resolver**: relative to the running script (`debug.getinfo` source path) with a `WEZ_SEED_SRC_DIR` override; STEP 4b sets `WEZ_SEED_SRC_DIR=${REPO_ROOT}/scenes` so the (possibly luastatic-bundled) binary finds the repo seeds.
- **TOCTOU demotion**: a seed whose dest appears between the listing and the write is demoted to `kept existing scene recipe:` messaging rather than overwritten.

## Deviations from Plan

None - plan executed exactly as written. The threat-model mitigations (T-05-05 copy-if-absent + TOCTOU, T-05-06 shquote'd io.popen, T-05-07 user-path-only writes) were all implemented as specified.

## Issues Encountered
- Standard `lua5.4` has no `os.setenv`, so the run() FS test cannot mutate process env in-process. Resolved by giving the test a portable child-process fallback (`io.popen` with `WEZ_SEED_SRC_DIR=... WEZTERM_SETUP_DIR=... lua5.4 -e 'require(...).run({})'`) that runs the seeder twice and asserts on its stdout + the resulting files. 14/14 assertions green.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The seeded recipes are on disk and round-trip-verified; 05-03 (launch IO-shell) can resolve `<name>.toml` from the co-located scenes dir and feed `load_and_map` → `run_new`.
- `dist/wez seed-scenes` verified dispatching against a scratch `WEZTERM_SETUP_DIR` (first run seeds 3, second run keeps 3, exit 0).
- Linux-verified; macOS parity is part of the batched cross-platform pass before closing the milestone.

## Self-Check: PASSED

All 6 created files verified present; all 3 task commits (a46ec88, 17d844a, 5213314) verified in git history.

---
*Phase: 05-named-scenes*
*Completed: 2026-06-13*
