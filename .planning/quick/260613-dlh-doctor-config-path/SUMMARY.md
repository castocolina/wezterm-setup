---
quick_id: 260613-dlh
slug: doctor-config-path
status: complete
created: 2026-06-13
completed: 2026-06-13
files_modified:
  - cli/commands/doctor.lua
  - tests/cli/doctor_test.lua
commit: aace2ff
---

# Quick Task SUMMARY: fix `wez doctor` GATE 3 false-FAIL on the installed config

## What
`cli/commands/doctor.lua` `gate_config_dofiles` now temporarily prepends the
config dir (`<config-dir>/?.lua;<config-dir>/?/init.lua;`) to `package.path`
around the `loadfile`+`pcall`, then restores it on every exit path — faithfully
replicating WezTerm's `<config-dir>/?.lua` module resolution so the installed
init.lua's dotted requires resolve.

## Why
GATE 3 loaded the installed `init.lua` under bare lua5.4, so its dotted requires
(`require("wezterm-setup.keybindings")` / `.cwd` / `.format-tab-title`) did not
resolve and `wez doctor` reported `[FAIL] config dofiles cleanly` — a FALSE
negative on a config WezTerm loads fine (single window). User-visible defect
surfaced by the Phase 4 verifier.

## How verified
- `lua5.4 tests/cli/doctor_test.lua` → 18 passed, 0 failed (was RED first: the new
  dotted-requires assertion failed before the fix).
- `make test` → all files green; the live-doctor run inside the suite now prints
  `[PASS] config dofiles cleanly` (0 config-dofiles FAILs).
- `lua5.4 cli/wez.lua doctor` against the REAL installed config → all 4 core gates
  `[PASS]`, exit 0 (only the advisory headless live-session probe FAILs, which
  never affects the exit code).

## Tests added
`tests/cli/doctor_test.lua`: hermetic temp-dir fixture (`<tmp>/wezterm-setup/`
with a dotted `require("wezterm-setup.dttest_sibling")`) asserting the gate PASSES;
a genuinely-missing module still FAILS (no masking); `package.path` restored (no
leak).

## Guardrails honored
- `opts.loader` injection path untouched (still used by aggregation tests).
- T-06-02: still loads only the managed init.lua chunk — no user wezterm.lua side
  effects.

## Out of scope (tracked separately)
`cli/lib/scene_test.lua` + `cli/commands/complete_test.lua` are not discovered by
`run-tests.sh` (globs `tests/**`). Not addressed here.

## Self-check: PASSED
- FOUND: cli/commands/doctor.lua (path-replication block)
- FOUND: tests/cli/doctor_test.lua (3 new assertions)
- FOUND commit: aace2ff
