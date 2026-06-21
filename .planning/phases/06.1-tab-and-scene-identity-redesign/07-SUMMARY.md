---
phase: 06.1-tab-and-scene-identity-redesign
plan: 07
subsystem: scenes
tags: [lua, scenes, seeds, toml, integration-test, cwd, tab-color, repro, backfill, retroactive]

# Dependency graph
requires:
  - phase: 06.1-04 (scene/recipe model + clean-pane --cwd spawn)
    provides: "recipe.load_and_map + scene.run_new spawn-with-cwd path the refreshed seeds round-trip through"
  - phase: 06.1-05 (render active-pane color + #RRGGBBAA + RotatePanes)
    provides: "format-tab-title render layer the config-load guard exercises"
  - phase: 06.1-06 (doctor shadow-detection core gate)
    provides: "wez doctor gate_no_shadowing reproduced live in the repro (check 7)"
provides:
  - "Refreshed ai + dev seed scenes on the rich schema ({cwd} titles, per-pane colors/icons), delivered copy-if-absent (D-13/D-14/D-15)"
  - "Live spawn --cwd integration test (tests/integration/scene_cwd_integration_test.lua) proving clean-pane cwd (D-08)"
  - "Config-load integration guard in install_config_load_integration_test.lua catching render-layer regressions"
  - "Recorded live-WezTerm UAT (06.1-UAT.md) covering every 6.1 behavior change — the verify-before-done evidence"
affects: [scenes, seed-recipes, integration-tests, 06.2-seeds]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "WEZTERM_INTEGRATION=1-gated integration tests that skip cleanly (exit 0) when headless or when `wezterm cli list` is unreachable, so CI stays green"
    - "Read-back verification: spawn with --cwd, then parse `wezterm cli list --format json` to assert the live pane cwd (clean-pane proof, D-08)"
    - "Seed recipes are repo-controlled content delivered copy-if-absent — only the in-repo seed CONTENT evolves; the seeder is never edited (D-15)"

key-files:
  created:
    - tests/integration/scene_cwd_integration_test.lua
  modified:
    - scenes/ai.toml
    - scenes/dev.toml
    - tests/integration/install_config_load_integration_test.lua

key-decisions:
  - "SUMMARY filename is 07-SUMMARY.md (the phase's bare NN-SUMMARY.md convention — recorded explicitly in 06-SUMMARY.md — NOT the plan <output> literal 06.1-07-SUMMARY.md)"
  - "This SUMMARY is a RETROACTIVE BACKFILL written 2026-06-20 for an executed-but-unsummarized plan; it cites the compacted commits rather than fabricating atomic per-task hashes (CLAUDE.md commit discipline compacts per logical unit)"
  - "Editor/git pane commands chosen for cross-platform availability and kept comma-free (Pitfall 5 comma-safety in the --pane round-trip)"

patterns-established:
  - "Every shipped scene seed must round-trip through recipe.load_and_map with no parse/validate error and stay comma-free; the integration layer proves the live spawn cwd, the recorded repro proves the GPU render"

requirements-completed: [D-01, D-02, D-08, D-11, D-12, D-13, D-14, D-15]

# Metrics
duration: reconstructed (original work landed 2026-06-15; not separately timed)
completed: 2026-06-15
---

# Phase 06.1 Plan 07: Refresh ai/dev Seeds + Live spawn --cwd Integration + Recorded Repro Summary

**Refreshed the `ai` and `dev` seed scenes onto the rich Phase 6.1 schema ({cwd} titles, per-pane colors/icons) delivered copy-if-absent, added a `WEZTERM_INTEGRATION`-gated live `spawn --cwd` round-trip test that reads back the pane cwd via `wezterm cli list --format json` to prove the clean-pane behavior (D-08), guarded the render layer in the install/config integration test, and verified every 6.1 behavior change against a live WezTerm session (8/8 UAT PASS).**

> **⚠ RETROACTIVE BACKFILL (written 2026-06-20).** Plan 06.1-07 was *executed* on 2026-06-15
> (its deliverables — refreshed seeds, integration tests, and the live UAT — are all present in
> the repo and git history) but was never summarized at the time. This SUMMARY reconstructs the
> plan from `07-PLAN.md`, the rich STATE.md Session Continuity notes, the recorded `06.1-UAT.md`,
> and git history (quick task 260620-tf0). Where a precise figure could not be traced to the plan,
> STATE, or git, the deliverable is described qualitatively and flagged as reconstructed.

## Performance

- **Duration:** reconstructed — the original work landed 2026-06-15 alongside the rest of Phase 6.1; it was not separately timed.
- **Completed:** 2026-06-15 (work landed); 2026-06-20 (this SUMMARY backfilled).
- **Tasks:** 3 (2 auto + 1 `checkpoint:human-verify`).
- **Files:** 1 created, 2 modified (+ the recorded live repro / UAT evidence).

## Accomplishments

- **Refreshed `ai` + `dev` seeds to the rich schema (D-13/D-14/D-15).** `scenes/dev.toml` became
  `tall:mirrored`, green tab (build icon), title `@{cwd} Dev`, with 3 styled panes — `$EDITOR`
  (green/edit) + a working `shell` (teal/shell) + `git status` (cyan/git). `scenes/ai.toml` became
  `tall`, yellow tab (ai icon, `follow_pane_color = true`), title `@{cwd} AI work`, with 2 panes —
  `claude` (purple/ai, `focus = true`) + a working `shell` (red/shell). Both mirror the proven
  `docker` seed's structure, are comma-free (Pitfall 5), inherit the launch dir (cwd omitted →
  D-07/D-08), and round-trip cleanly through `recipe.load_and_map`. Delivered copy-if-absent so a
  user's edited recipe is never overwritten — only the in-repo seed CONTENT changed, the seeder is
  unchanged (D-15).
- **Live `spawn --cwd` integration test (D-08).** `tests/integration/scene_cwd_integration_test.lua`
  is `WEZTERM_INTEGRATION=1`-gated and skips cleanly (exit 0) when unset or when `wezterm cli list`
  is unreachable. When live, it spawns through the scene path with a known `--cwd`, reads back
  `wezterm cli list --format json`, and asserts the spawned pane's cwd matches the resolved target —
  proving the clean-pane spawn (no `cd` line in scrollback, D-08).
- **Config-load integration guard.** `tests/integration/install_config_load_integration_test.lua`
  was extended to load the refreshed `format-tab-title` render layer under a WezTerm-like
  `package.path` and assert the managed block still loads cleanly — catching a render-layer
  regression from Plan 05 while staying pure-skip when headless.
- **Recorded live-WezTerm repro (the verify-before-done evidence, CLAUDE.md).** The Task-3
  `checkpoint:human-verify` drove all seven live checks against a real session: tab-color decouple +
  active-pane-wins (no literal `cyan:` text, D-02); clean-pane cwd with no visible `cd` (D-08);
  RotatePanes `Alt+Shift+R`/`Alt+Shift+E` + zoom retained (D-12); the embraced search overlay
  (`Ctrl+Shift+F` + `Ctrl+R` case toggle); `#RRGGBBAA` accepted (renders with transparency caveat,
  D-09); refreshed scenes round-tripping `launch ≡ new` (D-13/D-14, SCEN-04); and `wez doctor`
  shadow-detection failing on a planted handler and passing once removed (D-11). Result: **8/8
  happy-path PASS**, recorded in `06.1-UAT.md`.

## Task Commits

> **Compaction note (CLAUDE.md commit discipline).** The Phase 6.1 work was compacted into cohesive
> logical commits spanning `37d61cc..e184392` rather than one commit per tiny chunk. This backfill
> cites the compacted commit(s) below instead of fabricating atomic per-task hashes that never
> existed.

1. **Task 1 (refresh ai + dev seeds, D-13/D-14):** `1b039b9` — `feat(06.1): refresh dev + ai seed
   scenes with {cwd} titles (D-13/D-14)`. *(The seeds were later refined again in Phase 6.2 —
   `c573424`/`3fa6231` — to add the explicit `icon` attribute and the full schema reference header;
   that evolution is Phase 6.2's, not this plan's.)*
2. **Task 2 (integration tests):** the live `scene_cwd_integration_test.lua` + the rich scene model
   it exercises landed within the compacted scene-model commit `6e8228a` — `feat(06.1): rich
   scene/recipe model + clean-pane spawn (D-04/D-06/D-07/D-08)`; the config-load guard rides the same
   06.1 render/integration work. *(Exact per-file commit boundaries are reconstructed from the
   compacted history.)*
3. **Task 3 (live repro / UAT):** the recorded live verification is captured in
   `.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-UAT.md` (8/8 PASS), with the planning
   artifacts compacted into `e184392` — `docs(06.1): phase planning artifacts — context, research, 7
   plans, UAT`.

## Files Created/Modified

- `scenes/dev.toml` — refreshed to `tall:mirrored`, green (build icon), `@{cwd} Dev`, 3 styled panes
  ($EDITOR green/edit, shell teal/shell, `git status` cyan/git); cwd omitted → inherits launch dir.
- `scenes/ai.toml` — refreshed to `tall`, yellow (ai icon, `follow_pane_color = true`), `@{cwd} AI
  work`, 2 panes (`claude` purple/ai focus, shell red/shell).
- `tests/integration/scene_cwd_integration_test.lua` — new live spawn `--cwd` round-trip test (D-08),
  `WEZTERM_INTEGRATION`-gated, pure-skip when headless.
- `tests/integration/install_config_load_integration_test.lua` — extended with a render-layer
  config-load guard.

## Decisions Made

- **Filename convention (confirmed):** the 06.1 phase uses the bare `NN-SUMMARY.md` form (e.g.
  `06-SUMMARY.md`) — `06-SUMMARY.md` records this decision explicitly. The plan to backfill is
  `07-PLAN.md`, so this SUMMARY is `07-SUMMARY.md`, NOT `06.1-07-SUMMARY.md`.
- **Cite compacted commits, not fabricated atomic hashes:** per CLAUDE.md commit discipline the work
  was compacted; this backfill points at the real compacted commit(s) (seed-refresh = `1b039b9`)
  rather than inventing per-task hashes.
- **Cross-platform, comma-free pane commands:** editor/git/AI commands chosen for portability and
  kept comma-free so the multi-field `--pane` color round-trip stays valid (Pitfall 5).

## Deviations from Plan

This SUMMARY is itself the deviation record: the plan was executed without a contemporaneous SUMMARY,
so it is reconstructed here on 2026-06-20. No deviation in the *delivered behavior* is known — the
seeds, integration tests, and live UAT all match the plan's `must_haves`. Per-task commit boundaries
and any per-file timings are reconstructed from compacted history and are flagged as such above.

## Deferred Design Gaps (routed onward from the 06.1 UAT)

Two design gaps surfaced in the live UAT (NOT defects — current behavior matched the locked
D-02/D-03/D-04) were routed to Phase 6.2:

- **G-1 — icon should be its own attribute** (CLI + recipe), decoupled from the title's first word.
- **G-2 — tab color vs pane color** shared one `WEZTERM_TAB_COLOR` var → split into a tab-own var + a
  per-pane var (explicit tab color wins), with an opt-in `follow_pane_color` / `adopt_active_pane_color`
  toggle.

Both were delivered in Phase 6.2 (Identity Orthogonality).

## Verification

- Both refreshed seeds round-trip through `recipe.load_and_map` with no parse/validate error and are
  comma-free (Pitfall 5) — asserted by the plan's lua5.4 round-trip one-liner.
- `lua5.4 tests/integration/scene_cwd_integration_test.lua` exits 0 (skips cleanly when
  `WEZTERM_INTEGRATION` is unset).
- Under `WEZTERM_INTEGRATION=1` against a live WezTerm, the test spawns with `--cwd` and asserts the
  read-back pane cwd matches the target (D-08).
- The live UAT recorded **8/8 happy-path PASS** in `06.1-UAT.md` — the recorded repro IS the
  acceptance evidence (CLAUDE.md verify-before-done).

## Self-Check: PASSED

- FOUND: scenes/dev.toml (tall:mirrored, green)
- FOUND: scenes/ai.toml (tall, purple/yellow, follow_pane_color)
- FOUND: tests/integration/scene_cwd_integration_test.lua
- FOUND: tests/integration/install_config_load_integration_test.lua
- FOUND: .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-UAT.md (live repro / 8/8 PASS)
- FOUND commit: 1b039b9 (seed refresh, D-13/D-14)
- FOUND commit: 6e8228a (rich scene model + clean-pane spawn, D-08 integration test)
- FOUND compaction range: 37d61cc..e184392

---
*Phase: 06.1-tab-and-scene-identity-redesign*
*Plan executed: 2026-06-15 · SUMMARY backfilled: 2026-06-20 (retroactive)*
