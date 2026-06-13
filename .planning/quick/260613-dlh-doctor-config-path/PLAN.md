---
quick_id: 260613-dlh
slug: doctor-config-path
created: 2026-06-13
type: quick
files_modified:
  - cli/commands/doctor.lua
  - tests/cli/doctor_test.lua
---

# Quick Task: fix `wez doctor` GATE 3 false-FAIL on the installed config

## Problem (root cause already proven)

`wez doctor` core GATE 3 ("config dofiles cleanly", `cli/commands/doctor.lua`
`gate_config_dofiles`) does `loadfile(init_path)` + `pcall(chunk)` under plain
lua5.4 **without** replicating WezTerm's `<config-dir>/?.lua` module-resolution
template. The installed `config/wezterm-setup/init.lua` uses dotted requires
(`require("wezterm-setup.keybindings")` / `.cwd` / `.format-tab-title`) that only
resolve when the config dir (`~/.config/wezterm`) is on `package.path` as
`<config-dir>/?.lua`. Result: doctor reports `[FAIL] config dofiles cleanly` even
though WezTerm loads the config fine (single window — BUG2 already fixed).

Decisive repro: bare `lua5.4 loadfile(~/.config/wezterm/wezterm-setup/init.lua)`
+ pcall FAILS `module 'wezterm-setup.keybindings' not found`; the SAME load with
`package.path = ~/.config/wezterm/?.lua` prepended LOADS CLEAN.

Discovered during Phase 4 verification (gsd-verifier warning #2).

## Fix

In `gate_config_dofiles`, around the real `loadfile`+`pcall` (NOT the injectable
`opts.loader` path), temporarily prepend the config-dir template to
`package.path` so WezTerm's resolution is faithfully replicated, then restore
`package.path` in all exit paths. config-dir = parent of init.lua's directory
(`init_path` = `<config-dir>/wezterm-setup/init.lua`). Prepend
`<config-dir>/?.lua;<config-dir>/?/init.lua;`. Must NOT execute the user's
`wezterm.lua` side effects (T-06-02) — still loads only the managed init.lua chunk.

## Test

`tests/cli/doctor_test.lua`: add a hermetic fixture (`<tmp>/wezterm-setup/init.lua`
with a dotted `require("wezterm-setup.<sibling>")` that resolves only via the
config-dir template) and assert `gate_config_dofiles` now PASSES; assert a
genuinely-missing module still FAILS (no masking); assert `package.path` is
restored (no leak).

## Verify

- `lua5.4 tests/cli/doctor_test.lua` green
- `make test` green (no `[FAIL] config dofiles cleanly` from the live doctor run)
- `lua5.4 cli/wez.lua doctor` against the real installed config shows
  `[PASS] config dofiles cleanly`

## Out of scope (tracked separately)

`cli/lib/scene_test.lua` + `cli/commands/complete_test.lua` not discovered by
`run-tests.sh` (globs `tests/**`). Not fixed here.
