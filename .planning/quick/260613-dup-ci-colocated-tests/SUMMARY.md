---
quick_id: 260613-dup
slug: ci-colocated-tests
status: complete
created: 2026-06-13
completed: 2026-06-13
files_modified:
  - tools/run-tests.sh
  - config/wezterm-setup/format-tab-title_test.lua
commit: 77b76bb
---

# Quick Task SUMMARY: discover co-located *_test.lua files in CI

## What
Extended `tools/run-tests.sh` discovery from `tests/` only to the `tests/ cli/
config/` source roots, and made `config/wezterm-setup/format-tab-title_test.lua`
self-locating so its bare require resolves from any CWD.

## Why
6 co-located suites were invisible to `make test` (passed when run directly but
never in CI): `cli/commands/{complete,pane,tab}_test.lua`,
`cli/lib/{scene,title}_test.lua`, `config/wezterm-setup/format-tab-title_test.lua`.
Phase 2 (pane), Phase 3 (tab), title and scene coverage all ran outside CI — a
regression in any could slip past `make test`. Surfaced by the Phase 4 verifier.

## How verified
- `make test` → `run-tests: all 14 file(s) passed` (was 8); each previously-orphaned
  file listed as PASS (complete 18, pane 49, tab 23, scene 53, title 19,
  format-tab-title 42).
- `WEZTERM_INTEGRATION=1 ./tools/run-tests.sh` → 15 files, all green (the gated
  integration test still picked up only in integration mode).
- `config/wezterm-setup/format-tab-title_test.lua` passes from its own dir AND from
  the repo root (42/0 both).

## Decisions
- EXTEND discovery roots, not relocate — honors the co-located-tests convention.
- Discovery roots are existence-guarded (`tests cli config`); integration filtering
  (`*_integration_test.lua`, `tests/integration/*`) is unchanged and still gates
  live tests behind `WEZTERM_INTEGRATION=1`.

## Self-check: PASSED
- FOUND: tools/run-tests.sh (TEST_ROOTS discovery)
- FOUND: config/wezterm-setup/format-tab-title_test.lua (self-locating preamble)
- FOUND commit: 77b76bb
