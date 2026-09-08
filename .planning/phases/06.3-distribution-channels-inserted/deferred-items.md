# Deferred Items — Phase 06.3

Out-of-scope discoveries logged during execution (not fixed; outside the current
plan's task changes per the executor scope boundary).

## D-1: `cli/lib/recipe_test.lua` — `2.9d ai.toml` assertion fails (pre-existing)

- **Found during:** Plan 06.3-01, Task 3 full-suite verify (`./tools/run-tests.sh`).
- **Failure:** `FAIL: 2.9d ai.toml maps to the D-03/D-05/D-14 args` — the test's
  expected arg mapping no longer matches the committed `scenes/ai.toml` content
  (got `{color=yellow, follow_pane_color=true, icon=ai, layout=tall, pane={...},
  title=@{cwd} AI work}`).
- **Why out of scope:** The failure is in `cli/lib/recipe_test.lua` vs.
  `scenes/ai.toml`, neither of which Plan 06.3-01 touches (this plan only changed
  `cli/spec.lua`, `cli/commands/uninstall.lua`, `tools/uninstall.sh`, and
  `tests/cli/uninstall_test.lua`). Confirmed pre-existing: the failure reproduces
  with the uninstall changes stashed out. `scenes/ai.toml` was last modified by an
  earlier commit (`723af62 chore: scenes ai`), independent of this plan.
- **Status:** NOT fixed (scope boundary). The seed-recipe / recipe_test owners
  should reconcile the `ai.toml` recipe content with the `recipe_test.lua`
  expectation (likely the test fixture expectations drifted from the refreshed
  seed recipe). Track under the scenes/recipe work, not the distribution-channels
  phase.
- **Disposition:** RESOLVED in Phase 06.4 (see
  `.planning/phases/06.4-user-documentation-audit-and-refactor/deferred-items.md`,
  marked RESOLVED 2026-06-19). Root cause was a stale test expectation, not a
  behavior bug: `recipe_test.lua` block 2.9d still asserted the pre-refresh
  `color = "pink"` / `follow_pane_color = false` values against the
  already-updated `scenes/ai.toml` seed (`color = "yellow"`,
  `follow_pane_color = true`); the fixture was corrected to match the shipped
  seed. Re-verified live (2026-09-08): `lua5.4 cli/lib/recipe_test.lua` ->
  `recipe_test: 65 passed, 0 failed`, exit 0.
