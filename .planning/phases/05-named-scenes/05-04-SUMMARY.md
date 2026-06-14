---
phase: 05-named-scenes
plan: 04
subsystem: cli-completion
tags: [completion, scene, dynamic, zsh, bash, SCEN-05]
requires:
  - "cli/commands/scene.lua M.list_recipe_names + M.scenes_dir (05-03)"
  - "cli/commands/complete.lua CONTEXTS dispatch + run() loop (Phase 1/2)"
  - "cli/commands/completions.lua gen_zsh/gen_bash spec walk + nested arm idiom (Phase 1/2)"
provides:
  - "scene-names __complete context (dynamic recipe-name provider)"
  - "nested scene)->launch) completion arm in both zsh + bash generators"
affects:
  - "wez scene launch <Tab> recipe-name completion in zsh and bash"
tech-stack:
  added: []
  patterns:
    - "single recipe-listing provider reused by completion + launch (Pitfall 6 / D-16)"
    - "nested generator arm REPLACES generic flag arm when a command has BOTH top-level flags and subcommands"
    - "child lua5.4 -e + WEZTERM_SETUP_DIR for env-dependent provider tests"
    - "bash -n / zsh -n syntax check on generated scripts as recorded verify-before-done proof"
key-files:
  created: []
  modified:
    - cli/commands/complete.lua
    - cli/commands/complete_test.lua
    - cli/commands/completions.lua
    - tests/cli/completions_test.lua
decisions:
  - "scene-names reuses scene.list_recipe_names(scene.scenes_dir()) — the SAME provider launch uses; no second lister (Pitfall 6 / D-16)"
  - "nested scene) arm REPLACES the generic flag arm (ratified Open Q3): launch->scene-names, new->flags, *->new launch — scene has top-level flags unlike pane/tab"
metrics:
  duration: ~3.5m
  completed: 2026-06-14
  tasks: 2
  files: 4
---

# Phase 05 Plan 04: Dynamic scene-name Completion Summary

Dynamic `wez scene launch <Tab>` recipe-name completion (SCEN-05): a `scene-names` `__complete` context backed by the single `scene.list_recipe_names(scene.scenes_dir())` provider that `scene launch` already uses, plus a nested `scene) -> launch)` dispatch arm in both the zsh and bash generators that routes launch to `wez __complete scene-names` and replaces the generic flag arm.

## What Was Built

### Task 1 — `scene-names` `__complete` context (commit 677c811)
- `cli/commands/complete.lua` now requires the COMMAND module `cli.commands.scene` (alongside the existing `cli.lib.scene` used for `scene-layouts`) and adds a `scene_names()` provider returning `scene_cmd.list_recipe_names(scene_cmd.scenes_dir())`, read DYNAMICALLY at Tab time (no caching).
- Registered `["scene-names"] = scene_names` in the `CONTEXTS` table. The existing `run()` loop emits the already-sorted basenames one-per-line and no-ops on unknown context, so an empty/missing scenes dir yields `{}` -> nothing emitted, exit 0 (the Tab-time-never-fails contract, T-05-13).
- No second listing function authored — the single provider is reused (Pitfall 6 / single source of truth, so completion can never advertise a recipe set that launch resolves differently, T-05-14).
- `cli/commands/complete_test.lua`: added 8 assertions driven through a child `lua5.4 -e` with `WEZTERM_SETUP_DIR` set (lua5.4 has no `os.setenv`; this mirrors `scene_launch_test.lua`/`seed_scenes_test.lua`). Proves: sorted basenames without `.toml`, non-`.toml` files ignored, a NEW recipe file appears on re-run with NO regeneration (dynamic), and both empty-dir and missing-dir emit nothing and exit 0.

### Task 2 — nested `scene) -> launch)` arm in both generators (commit d6a0279)
- `cli/commands/completions.lua`: the generic flag loop in BOTH `gen_zsh` and `gen_bash` now skips `c.name == "scene"`, and a hand-written nested `scene)` arm is emitted beside the `pane)`/`tab)` arms:
  - zsh dispatches on `$line[2]`: `launch) compadd ${(f)"$(wez __complete scene-names 2>/dev/null)"}`, `new) compadd --layout --pane --color --title`, `*) compadd new launch`.
  - bash dispatches on `${COMP_WORDS[2]}`: `launch) ... compgen -W "$(wez __complete scene-names ...)"`, `new) ... --layout --pane --color --title`, `*) ... new launch`.
- This REPLACES the generic flag arm (ratified Open Q3): `scene` has top-level flags AND subcommands, so it cannot reuse the flagless pane/tab template — emitting both would produce a duplicate `scene)` case.
- Recipe names are never hardcoded; they flow through `wez __complete scene-names` (D-09/D-16).
- `tests/cli/completions_test.lua`: added 14 assertions — exactly ONE `scene)` arm in each script (no duplicate generic arm), the `launch)`->`scene-names` routing, the `new)`->flags case, the bare `*)`->`new launch` case, dynamic (no hardcoded recipe candidate in the arm), plus `bash -n` (mandatory) and `zsh -n` (skipped gracefully if zsh absent) syntax checks on the generated scripts written to temp files.

## Verification

- `lua5.4 cli/commands/complete_test.lua` -> 26 passed, 0 failed (was 18; +8).
- `lua5.4 tests/cli/completions_test.lua` -> 69 passed, 0 failed (was 55; +14).
- `make test` -> all 17 file(s) passed.
- Real binary end-to-end: `WEZTERM_SETUP_DIR=<scratch> ./dist/wez __complete scene-names` prints sorted basenames; adding a `.toml` and re-running adds it with no regeneration.
- `./dist/wez completions bash | bash -n` and `./dist/wez completions zsh | zsh -n` both clean.

## Deviations from Plan

None — plan executed exactly as written. Both tasks committed individually; no Rule 1-4 deviations and no authentication gates.

One in-test correction (not a plan deviation): the initial "no hardcoded recipe names (dev/ai/docker)" assertion used a raw substring search, which false-matched `dev` inside `2>/dev/null`. Replaced with a precise check that the `scene)` arm's `launch)` case body contains only the `scene-names` shell-out (no literal recipe candidate) — a more correct expression of the same D-16 invariant.

## Known Stubs

None. The completion path is fully wired to live data — recipe names are read from the real scenes dir at Tab time.

## Self-Check: PASSED

- FOUND: cli/commands/complete.lua (scene-names context + scene_names provider)
- FOUND: cli/commands/complete_test.lua (scene-names child-env cases)
- FOUND: cli/commands/completions.lua (nested scene)->launch) arm, zsh + bash)
- FOUND: tests/cli/completions_test.lua (nested arm + bash -n/zsh -n)
- FOUND commit 677c811 (feat 05-04: scene-names context)
- FOUND commit d6a0279 (feat 05-04: nested scene) arm)
