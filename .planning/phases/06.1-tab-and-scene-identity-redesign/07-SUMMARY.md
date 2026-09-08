---
phase: 06.1-tab-and-scene-identity-redesign
plan: 07
subsystem: scenes, testing, docs
tags: [toml, integration-test, retroactive-closeout, tracking-reconciliation]

# Dependency graph
requires:
  - phase: 06.1-tab-and-scene-identity-redesign (Plan 04)
    provides: "rich scene/recipe model (cwd/focus/size) + clean-pane --cwd spawn"
  - phase: 06.1-tab-and-scene-identity-redesign (Plan 05)
    provides: "render layer reading WEZTERM_TAB_COLOR + #RRGGBBAA support"
provides:
  - "Refreshed ai/dev seed scenes exercising the rich schema (per-pane command/color/icon/title)"
  - "Live spawn --cwd read-back integration test (D-08) + render-layer config-load guard"
affects: [scenes, seed-recipes, install-integration-tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Integration tests self-skip cleanly (exit 0) under WEZTERM_INTEGRATION unset, live-assert under =1"

key-files:
  created: []
  modified:
    - scenes/ai.toml
    - scenes/dev.toml
    - tests/integration/scene_cwd_integration_test.lua
    - tests/integration/install_config_load_integration_test.lua

key-decisions:
  - "This SUMMARY is a RETROACTIVE close-out, written 2026-09-08 as part of a tracking-artifact reconciliation pass, for work completed 2026-06-15 — every claim below is verified against CURRENT file contents (re-read live), not restated from 07-PLAN.md's <behavior> blocks"
  - "D-14's ai.toml tab-level color has DRIFTED from the plan's locked `purple` to `yellow` today (later revised by 06.2 Identity Orthogonality's icon-attribute work + a standalone 'refresh seed recipes with @{cwd} titles + custom palette' pass) — cited as a deviation from the original plan text, not a defect; the AI-CLI pane's own color still matches purple exactly, and layout/pane-count for both seeds still match D-13/D-14 exactly"
  - "D-13's dev.toml git-pane color has also drifted from the plan's `yellow` to `cyan` today, same later-revision pattern"
  - "Task 3's named repro file docs/repro/h-06.1-tab-color-decouple.md was never created under that literal name; the functionally-equivalent live verification instead landed in 06.1-UAT.md (status: complete, 2026-06-15, frontmatter source: explicitly lists 07-PLAN.md, 8/8 happy-path checks) — cited as the record satisfying the checkpoint's intent, not a skipped checkpoint"

patterns-established: []

requirements-completed: [D-01, D-02, D-08, D-11, D-12, D-13, D-14, D-15]

# Metrics
duration: retroactive (original work 2026-06-15; this reconciliation pass ~15min)
completed: 2026-09-08
---

# Phase 06.1 Plan 07: Refreshed Seed Scenes + Integration Tests Summary

**RETROACTIVE close-out for already-shipped, already-working deliverables — dev/ai seed scenes on the rich schema, a live spawn --cwd read-back integration test, and a render-layer config-load guard — verified against current file contents on 2026-09-08, six months after they shipped (2026-06-15), as part of a tracking-artifact reconciliation pass.**

## Why this SUMMARY is retroactive

07-PLAN.md's Task 1 and Task 2 deliverables shipped and have worked correctly since 2026-06-15, but
no `07-SUMMARY.md` was ever written, so Phase 06.1 showed 7 plans / 6 summaries — a false-positive
gap flagged by `/gsd-health` (I001). This document closes that gap. Every factual claim below was
re-verified against the files as they exist TODAY (2026-09-08), not copied from the plan's behavior
specs — several values have drifted since the original 2026-06-15 work, and those drifts are called
out explicitly rather than glossed over.

## Accomplishments

### Task 1 — refreshed scenes/dev.toml + scenes/ai.toml (D-13/D-14/D-15)

Both seeds use the rich per-pane schema (command/color/icon/title) proven by `scenes/docker.toml`.
Current actual contents (re-read live, 2026-09-08):

- **`scenes/dev.toml`**: `layout = "tall:mirrored"`, tab `color = "green"` — matches D-13 exactly.
  3 panes: editor (`$EDITOR`, green), working shell (`shell`, teal), git pane (`git status`,
  **`color = "cyan"` today** — the plan's/D-13's locked spec said `yellow`; this is a DEVIATION from
  the original plan text, introduced by a later revision (see "Deviations" below), not a defect.
- **`scenes/ai.toml`**: `layout = "tall"`, 2 panes — matches D-14 exactly on layout/pane-count. The
  `claude` pane's `color = "purple"` matches D-14's per-pane spec exactly. The shell pane's
  `color = "red"` today (plan said `teal`) is a deviation. The one deviation this reconciliation
  pass was explicitly asked to call out: **ai.toml's TAB-LEVEL `color` is `"yellow"` today**, not the
  `purple` D-14 locked at the tab level.

Both files still round-trip cleanly through `recipe.load_and_map` (re-verified live in this pass —
see Verification below) and are comma-free (Pitfall 5 comma-safety holds).

**Why the drift:** later phases revised the palette after this plan shipped it — Phase 06.2's
(Identity Orthogonality) icon-attribute work, plus a standalone "refresh seed recipes with `@{cwd}`
titles + custom palette" commit, both touched these files after 2026-06-15. The seeder (`wez
seed-scenes`, D-15 copy-if-absent) is unchanged; only the in-repo seed content moved.

### Task 2 — integration tests (D-08 live spawn --cwd + render-layer guard)

`tests/integration/scene_cwd_integration_test.lua` exists and is fully functional: guarded by
`WEZTERM_INTEGRATION=1` plus a live-mux reachability self-skip (re-run live in this pass: `SKIP
(WEZTERM_INTEGRATION != 1)`, exit 0 — the correct headless behavior). When live, it spawns via the
clean-pane `--cwd` idiom and read-back-asserts the pane's cwd via `wezterm cli list --format json`,
proving D-08.

`tests/integration/install_config_load_integration_test.lua` carries the render-layer guard this
plan added — inline-tagged `RENDER-LAYER GUARD (06.1-07)` at three points in the file (re-confirmed
via `grep` in this pass). Re-run live in this pass: **15/15 assertions PASS, exit 0**, including
`format-tab-title registers + renders active-pane color (Plan 05 render layer)` and
`format-tab-title renders a #RRGGBBAA accent without error (D-09)`.

**Provenance note:** per `git blame`/`git log`, both tests landed inside OTHER 06.1-plan-numbered
commit subjects rather than a dedicated `06.1-07`-prefixed commit — `6e8228a feat(06.1): rich
scene/recipe model + clean-pane spawn (D-04/D-06/D-07/D-08)` for the cwd integration test, and
`f1601bf feat(06.1): render active-pane accent + RotatePanes keys (D-02/D-09/D-12)` for the render
guard. This is consistent with this project's commit-discipline norm of folding closely-related work
into the nearest cohesive commit — it is not evidence the work didn't happen; both commits are
verifiable in `git log --oneline --all`.

### Task 3 — live-WezTerm repro checkpoint

07-PLAN.md's Task 3 was a `checkpoint:human-verify gate="blocking"` asking for a recorded repro at
`docs/repro/h-06.1-tab-color-decouple.md`. That exact file was never created under that literal name
— confirmed absent from `git log` across the repo's history, including the Phase 06.4-04 prune-list
of 12 dated `docs/repro/h-*.md` files (which removed 12 OTHER files but never this one; it simply
never existed to prune).

The functional intent of the checkpoint — a maintainer-approved live verification of every 6.1
behavior change — was instead satisfied by
`.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-UAT.md`: `status: complete`, dated
2026-06-15, frontmatter `source:` explicitly lists `07-PLAN.md`, 8/8 happy-path checks recorded
including "Clean-pane cwd (D-07/D-08)" and "Refreshed dev + ai seed scenes (D-13/D-14, SCEN-04)",
both PASS. This is reported as the record satisfying the checkpoint's intent — not a claim that the
named repro file exists, and not a claim the checkpoint was skipped.

## Files Created/Modified

- `scenes/dev.toml` — refreshed to the rich schema (D-13); tab color/layout match, git-pane color
  has drifted from `yellow` to `cyan` since original ship
- `scenes/ai.toml` — refreshed to the rich schema (D-14); pane layout/count match, AI pane purple
  matches, tab color has drifted from `purple` to `yellow` and the shell pane from `teal` to `red`
  since original ship
- `tests/integration/scene_cwd_integration_test.lua` — live spawn --cwd read-back e2e (D-08),
  self-skips cleanly when headless
- `tests/integration/install_config_load_integration_test.lua` — extended with the render-layer
  guard (`RENDER-LAYER GUARD (06.1-07)`)

## Decisions Made

- D-13's git-pane color and D-14's tab/shell-pane colors are DEVIATED from their originally-locked
  values today (git: yellow→cyan; ai tab: purple→yellow; ai shell: teal→red) — cited as documented
  deviations from the original plan text, caused by later revision passes (06.2 + a standalone
  palette refresh), not defects. D-14's AI-CLI-pane purple and both files' layout/pane-count still
  match exactly.
- This SUMMARY documents work completed 2026-06-15 but is written now (2026-09-08) as part of a
  tracking-artifact reconciliation pass — all claims verified against current file contents, not
  restated from the plan.

## Deviations from Plan

### Documented (not auto-fixed — retroactive report only)

**1. [Palette drift] ai.toml tab-level color: purple (D-14) → yellow (current)**
- **Found during:** this reconciliation pass, re-reading `scenes/ai.toml`
- **Cause:** later revisions (Phase 06.2 Identity Orthogonality's icon-attribute work; a standalone
  "refresh seed recipes with @{cwd} titles + custom palette" commit) touched the file after this
  plan's original 2026-06-15 ship
- **Files:** `scenes/ai.toml`
- **Not fixed here:** this is a historical-record reconciliation task (bookkeeping only per
  260908-fav's objective) — no source/scene content changes are in scope

**2. [Palette drift] dev.toml git-pane color: yellow (D-13) → cyan (current); ai.toml shell-pane
color: teal → red (current)**
- Same cause/scope note as above.

**3. [Missing named repro file] `docs/repro/h-06.1-tab-color-decouple.md` never created**
- **Found during:** this reconciliation pass, `git log` search
- **Substitute record:** `06.1-UAT.md` (status: complete, 8/8 PASS, `source:` cites `07-PLAN.md`)
- **Not fixed here:** out of scope for this bookkeeping-only reconciliation

## Issues Encountered

None — this is a documentation-only retroactive close-out; no code changes were made in this plan
execution.

## Verification

Re-run live in this reconciliation pass (2026-09-08):

```
$ lua5.4 -e 'package.path="cli/?.lua;cli/lib/?.lua;"..package.path; local r=require("cli.lib.recipe"); for _,f in ipairs({"scenes/dev.toml","scenes/ai.toml"}) do local fh=io.open(f,"rb"); local raw=fh:read("*a"); fh:close(); local m,e=r.load_and_map(raw); assert(m, f.." -> "..tostring(e)) end; print("ROUNDTRIP_OK")'
ROUNDTRIP_OK

$ lua5.4 tests/integration/scene_cwd_integration_test.lua
scene_cwd_integration_test: SKIP (WEZTERM_INTEGRATION != 1)
exit=0

$ lua5.4 tests/integration/install_config_load_integration_test.lua
... 15 passed, 0 failed
exit=0
```

## Next Phase Readiness

None — this SUMMARY closes a historical gap only. Phase 06.1's plan/summary count is now 7/7.

## Self-Check: PASSED

- FOUND: scenes/dev.toml
- FOUND: scenes/ai.toml
- FOUND: tests/integration/scene_cwd_integration_test.lua
- FOUND: tests/integration/install_config_load_integration_test.lua
- FOUND commit: 6e8228a (feat(06.1): rich scene/recipe model + clean-pane spawn)
- FOUND commit: f1601bf (feat(06.1): render active-pane accent + RotatePanes keys)
- FOUND: 06.1-UAT.md (status: complete, source: cites 07-PLAN.md)

---
*Phase: 06.1-tab-and-scene-identity-redesign*
*Completed: 2026-06-15 (original work); this SUMMARY written 2026-09-08*
