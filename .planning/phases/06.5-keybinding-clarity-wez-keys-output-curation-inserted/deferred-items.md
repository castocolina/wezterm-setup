# Deferred Items — Phase 06.5

Out-of-scope discoveries found during execution. NOT fixed here (scope boundary:
only auto-fix issues directly caused by the current plan's own files).

## Pre-existing test failure — `cli/lib/recipe_test.lua` 2.9d

- **Found during:** Plan 06.5-01 (full-suite gate after the new `cli/lib/ansi.lua`).
- **Failure:** `FAIL: 2.9d ai.toml maps to the D-03/D-05/D-14 args` — `recipe_test: 64 passed, 1 failed`.
- **Out of scope because:** unrelated to this plan's two files (`cli/lib/ansi.lua`,
  `cli/lib/ansi_test.lua`). Reproduces identically with the `ansi.*` files stashed out,
  so it is pre-existing — first noted in the 06.3-01 session's `deferred-items.md`.
- **Action:** logged, not fixed. Belongs to a recipe/scene plan, not the ANSI helper.
- **Still present after Plan 06.5-02** (curated-first `wez keys` renderer): the only
  `make test` failure remains `recipe_test 2.9d`; all six of Plan 02's files are green.
  Unchanged by this plan (touches none of the recipe code). Still out of scope.
