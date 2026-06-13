---
quick_id: 260613-dup
slug: ci-colocated-tests
created: 2026-06-13
type: quick
files_modified:
  - tools/run-tests.sh
  - config/wezterm-setup/format-tab-title_test.lua
---

# Quick Task: discover co-located *_test.lua files in CI

## Problem
`tools/run-tests.sh` globbed only `find tests -name '*_test.lua'`, so SIX
co-located unit suites never ran in `make test` (they passed when run directly):
`cli/commands/{complete,pane,tab}_test.lua`, `cli/lib/{scene,title}_test.lua`,
`config/wezterm-setup/format-tab-title_test.lua`. The project convention is tests
next to source, so the fix extends the runner's roots rather than relocating files.

## Fix
1. `tools/run-tests.sh`: discover under `tests/ cli/ config/` (existence-guarded
   ROOTS list), integration gating unchanged.
2. `config/wezterm-setup/format-tab-title_test.lua`: self-locating preamble
   (`package.path` += its own dir) so the bare `require("format-tab-title")`
   resolves from any CWD.

## Verify
- `make test` → 14 files (was 8), all green; the 6 orphans appear as PASS.
- `WEZTERM_INTEGRATION=1 ./tools/run-tests.sh` → 15 files, all green.
- config test passes from its own dir AND repo root.

Surfaced by Phase 4 verification (gsd-verifier warning #1).
