# Phase 07 — Deferred Items (out-of-scope discoveries)

Logged by the executor per the SCOPE BOUNDARY rule. These are NOT fixed in their
discovering plan; they are pre-existing or belong to another plan's scope.

## 07-02

### Stock-macOS harness portability — `tools/run-tests.sh` pins `lua5.4` (D-08)

- **Discovered during:** 07-02 GREEN verification on the live Intel Mac.
- **Symptom:** `bash tools/run-tests.sh` aborts with
  `run-tests: 'lua5.4' not found on PATH` because this Mac ships Homebrew Lua 5.5
  (the keg-only `lua@5.4` toolchain provisioning is CI/Plan 07-01 scope, not local).
  The harness honors a `LUA_BIN` override (line 28), so `LUA_BIN=lua bash
  tools/run-tests.sh` runs the suite.
- **Scope:** D-08 harness portability is a SEPARATE Phase 7 plan. Not 07-02.

### Pre-existing Lua 5.5 incompatibilities in unrelated tests

- **Discovered during:** running the suite under `LUA_BIN=lua` (Lua 5.5).
- **Symptom:** 8 unrelated test files fail under Lua 5.5 — e.g.
  `cli/lib/scene.lua:42: attempt to assign to const variable 'segment'`
  (Lua 5.5 made `<const>` reassignment a hard error). Failing files:
  `cli/commands/complete_test.lua`, `cli/commands/scene_test.lua`,
  `cli/lib/recipe_test.lua`, `cli/lib/scene_test.lua`,
  `tests/cli/completions_test.lua`, `tests/cli/keys_test.lua`,
  `tests/cli/scene_launch_test.lua`, `tests/cli/seed_scenes_test.lua`.
- **Not caused by 07-02:** my commits touched only
  `tools/lib/wezterm-release.sh`, `tools/bootstrap-wezterm.sh`, and
  `tests/cli/bootstrap_macos_test.lua`. Both bootstrap tests PASS in the suite.
- **Scope:** these are runtime-version drift in the CONFIG/CLI layer (Lua 5.5 vs
  the project's pinned Lua 5.4), unrelated to the macOS bootstrap. Belongs to a
  separate Lua-5.5-compat or toolchain follow-up, not the macOS parity gate.
