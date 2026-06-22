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

## 07-05 (Task 1 — harness drive)

### `wez keys --json` (DIAG-04) fails — vendored `dkjson` not on the require path

- **Discovered during:** 07-05 Task 1, runbook §4 (DIAG-04), on this Intel Mac.
- **Symptom:** `wez keys --json` exits **1** with EMPTY stdout and a Lua traceback on
  stderr: `[string "cli.commands.keys"]:262: module 'dkjson' not found … no module
  'dkjson' in luastatic bundle`.
- **Root cause:** `cli/commands/keys.lua:262` does `require("dkjson")` (bare name), but
  the vendored module lives at `cli/vendor/dkjson.lua`. The bare require resolves in
  NEITHER the luastatic single-binary bundle (installed `~/.local/bin/wez`,
  `wez-macos-x86_64`) NOR the dev source-launcher (`dist/wez`), and `dkjson` is not on
  the LuaRocks tree either.
- **CROSS-PLATFORM, NOT a macOS divergence:** reproduced identically on (a) the installed
  CI-built standalone binary and (b) the local dev launcher. The Linux baseline has the
  same defect. Parity = same behavior both platforms; here both are equally broken, so
  this is NOT a macOS parity gap — it is a pre-existing cross-platform DIAG-04 bug.
- **Likely fix (FOLLOW-UP, not this verification task):** `require("dkjson")` →
  `require("cli.vendor.dkjson")` in `cli/commands/keys.lua`, ensure `cli/vendor/dkjson.lua`
  is in the luastatic bundle file list, and add a `wez keys --json` parse regression test.
- **Disposition:** DEFER to a dedicated bugfix (`/gsd-quick` or a Phase 7 gap-closure plan).
  DIAG-04 recorded as a deviation in the runbook; DIAG-02/03/05 (which pass) carry the DIAG-*
  evidence. Because DIAG-05 is the requirement actually mapped to the macOS flip (RESEARCH Test
  Map), this bug does not by itself block the DIAG-05 flip — but DIAG-04 cannot be claimed PASS.

### `tools/setup-dev.sh` keg PATH is subshell-local (auto gate RED until exported)

- **Discovered during:** 07-05 Task 1 — the FIRST `verify-macos.sh` run was RED (FAIL=12)
  purely because `lua5.4`/`luastatic` were not on PATH; `dist/wez` (dev launcher) is inert
  without `lua5.4` (`exec: lua5.4: not found`, exit 127 across §2/§4/§5).
- **Fix applied in-session (Rule 3 blocking-issue):** ran the project's own sudo-free
  `tools/setup-dev.sh` (autonomy #1; `lua@5.4` + `luarocks` already brew-installed,
  `luastatic` installed `--local`), then exported the keg PATH in the executor's own shell:
  `export PATH="$(brew --prefix lua@5.4)/bin:$HOME/.luarocks/bin:$PATH"`. Re-run → GREEN
  (PASS=26 FAIL=0 exit 0).
- **Sharp edge:** `setup-dev.sh` exports PATH only inside its own process, so a fresh dev who
  runs `make setup` then `bash tools/verify-macos.sh` in the SAME shell still fails until they
  export the keg bin. Consider having `make setup` print an `eval`-able `export PATH=…` line.
- **Disposition:** DEFER (low priority). Does not affect the shipped artifact — the CI-built
  `wez` is a standalone Mach-O needing no `lua5.4` at runtime (`env -i … wez version` works).
