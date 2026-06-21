---
phase: quick-260620-t9k
plan: 01
subsystem: cli/tests
tags: [test-fixture, recipe, scenes, reconciliation]
requires: [scenes/ai.toml, cli/lib/recipe.lua]
provides: ["2.9d ai.toml expected fixture reconciled to canonical seed"]
affects: [cli/lib/recipe_test.lua]
tech-stack:
  added: []
  patterns: ["seed-is-canonical: drift is fixed on the TEST side, never the shipped seed"]
key-files:
  created: []
  modified: [cli/lib/recipe_test.lua]
decisions:
  - "Seed scenes/ai.toml is the locked source of truth; the test fixture was the drifted side and was reconciled to it."
metrics:
  duration: "~3m"
  completed: "2026-06-20"
---

# Quick 260620-t9k: Reconcile the failing cli/lib/recipe_test.lua fixture Summary

Reconciled the lone red assertion `2.9d ai.toml` in `cli/lib/recipe_test.lua` to the canonical
shipped seed `scenes/ai.toml` by editing only the test fixture (two fields + a stale comment),
leaving the seed and all production Lua byte-identical.

## What changed

`cli/lib/recipe_test.lua`, the `2.9d ai.toml maps to the D-03/D-05/D-14 args` expected table:

- `color = "pink"` -> `color = "yellow"` (matches `scenes/ai.toml` line 53)
- `follow_pane_color = false` -> `follow_pane_color = true` (matches `scenes/ai.toml` line 55)
- Rewrote the stale block comment that claimed `follow_pane_color=false` was "the documented
  default, written out" — it now describes the real seed (yellow tab; `follow_pane_color=true`
  opt-in is ON, here informational because the tab also has an explicit color).

All other fields of the expected table were left unchanged: `layout = "tall"`,
`title = "@{cwd} AI work"`, `cwd = nil`, `icon = "ai"`, and both `pane` specs
(`cmd=claude, color=purple, title=@{cwd} AI Session, focus=true, icon=ai` and
`cmd=shell, color=red, title=@{cwd} AI Shell, icon=shell`).

## Verification (structural — live suite DEFERRED)

This Intel Mac has NO Lua interpreter (Phase 7 gap C-1: `lua`/`lua5.4` absent), so
`./tools/run-tests.sh` cannot run here. Verified by inspection instead:

- (a) Field-for-field against `scenes/ai.toml`: `color = "yellow"` (line 53),
  `follow_pane_color = true` (line 55), `icon = "ai"` (line 54), `title = "@{cwd} AI work"`
  (line 56), and the two pane specs match the `[[panes]]` blocks (claude/purple/focus/ai;
  shell/red/shell). All confirmed matching.
- (b) Expected-table shape matches `recipe.lua` `recipe_to_args` (lines 138-160): top-level
  `color`/`title`/`cwd`/`icon`/`follow_pane_color` carried verbatim, panes emitted under the
  `pane` key (not `panes`), `follow_pane_color` carried as a boolean. Confirmed.
- (c) `git diff --stat` shows the commit touched ONLY `cli/lib/recipe_test.lua`.

**The live full-suite run (expected: `recipe_test` green, `2.9d` passing) is DEFERRED to CI /
a Lua-capable host.** This machine cannot run the suite; no green-suite claim is asserted from
here — only that the fixture now matches the seed and the real `recipe_to_args` output shape by
inspection.

## Deviations from Plan

None — plan executed exactly as written.

## Commits

- `395586f`: test(quick-260620-t9k): reconcile 2.9d ai.toml fixture with shipped seed

## Notes

- This closes deferred item D-1 in
  `.planning/phases/06.3-distribution-channels-inserted/deferred-items.md`.
- A pre-existing unstaged working-tree change to
  `.planning/phases/07-macos-parity/07-CONTEXT.md` was deliberately left untouched and
  unstaged per the task constraints.

## Self-Check: PASSED

- FOUND: `cli/lib/recipe_test.lua`
- FOUND commit: `395586f`
