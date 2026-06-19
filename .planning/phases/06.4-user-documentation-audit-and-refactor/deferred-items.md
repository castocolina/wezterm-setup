# Phase 06.4 — Deferred Items

Out-of-scope discoveries logged during execution. NOT fixed in this phase per the
executor scope boundary (only auto-fix issues directly caused by the current task).

## Pre-existing test failure: `cli/lib/recipe_test.lua` — "2.9d ai.toml maps to ..."

- **Found during:** Plan 06.4-01 Task 2 (`make test` run for the docs drift-check).
- **Status:** PRE-EXISTING — reproduced at commit `ab8716d` and earlier, before any
  06.4-01 change. NOT caused by the new `tests/docs_drift_test.lua`.
- **Symptom:** one assertion fails:
  `FAIL: 2.9d ai.toml maps to the D-03/D-05/D-14 args` — the recipe→args expectation
  for the seeded `ai.toml` (icon=ai, follow_pane_color=true, per-pane `@{cwd}` titles)
  does not match the test's expected arg table.
- **Scope boundary:** unrelated to documentation drift; it is a recipe/seed↔test
  expectation mismatch in the scene-recipe layer. Fixing it would be feature/seed work
  outside the doc-audit phase (06.4-CONTEXT D-10 keeps the phase doc-scoped).
- **Disposition:** RESOLVED 2026-06-19 (maintainer-approved during 06.4 execution). Root
  cause was a STALE TEST EXPECTATION, not a behavior bug: the shipped `scenes/ai.toml` seed
  carries `color = "yellow"` + `follow_pane_color = true`, but `recipe_test.lua` block 2.9d
  still asserted the old `color = "pink"` / `follow_pane_color = false`. The shipped seed is
  the source of truth, so the 2-value test expectation was corrected to match. Trivial
  truth-restoring fix per D-10; `make test` now exits 0 (all 31 files).
- **Effect on this plan:** `tests/docs_drift_test.lua` itself passes 71/71 (exit 0). The
  drift-check's own acceptance (discovered by `make test`, green, fires on planted bad
  references) is fully met; the suite-level `make test` non-zero is solely this
  pre-existing recipe_test failure.
