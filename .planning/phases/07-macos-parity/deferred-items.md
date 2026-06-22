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

## 07-03

### Same 8 Lua-5.5 incompatibilities reconfirmed (NOT touched by 07-03)

- **Discovered during:** 07-03 verification under `LUA_BIN=lua` (Lua 5.5) on this
  Intel Mac (no `lua5.4` present — the 07-02 D-08 deferral above).
- **Symptom:** the identical 8 files fail (`<const>` hard error). 07-03 changed
  only `tools/ci-setup-toolchain.sh`, `tools/build.sh`, `.github/workflows/release.yml`,
  and added `tests/cli/ci_macos_toolchain_test.lua` (which PASSES). The 8 failures
  reproduce with the 07-03 diff stashed.
- **Scope:** unchanged from the 07-02 entry — a separate Lua-5.5-compat follow-up.
  07-03's shell scripts are gated by `bash -n` + `shellcheck -x` in the suite (all
  PASS) and the new TEXT gate test, the correct verification path for shell glue.
