---
phase: 01-foundation
plan: 01
subsystem: cli-foundation
tags: [cli, lua, argparse, build, packaging, platform-detection]
dependency_graph:
  requires: []
  provides:
    - "cli/spec.lua build_parser() — the single source-of-truth argparse contract for the full Phase 1 command surface (consumed by Plans 04/05/06/07 without edits)"
    - "cli/wez.lua main(argv) — entry point + lazy allow-list dispatch propagating numeric exit codes (D-15 prerequisite)"
    - "cli/vendor/argparse.lua + cli/vendor/dkjson.lua — vendored pure-Lua deps"
    - "tools/lib/platform.sh — sourceable OS/arch/Ubuntu-base detection (reused by Plan 02 bootstrap + Plan 04 installer)"
    - "tools/build.sh — luastatic build + pinned/checksummed release-download fallback (+ dev launcher)"
    - "tools/run-tests.sh — lua5.4 test harness (honors WEZTERM_INTEGRATION=1)"
  affects:
    - "Plans 04/05/06/07 implement cli/commands/<name>.lua against the registered spec contract"
tech_stack:
  added:
    - "Lua 5.4 (system lua5.4 5.4.6 for dev/test)"
    - "argparse (vendored, MIT, mpeterv) — declarative arg parsing"
    - "dkjson v2.5 (vendored, MIT, David Kolf) — JSON encode/decode"
  patterns:
    - "Interface-first contract: full command surface registered upfront in one spec module (D-16)"
    - "Allow-list dispatch: subcommand resolved against the closed spec set before lazy require (T-01-02)"
    - "Glue-only bash: scripts make only toolchain-presence decisions; all behavior logic in the Lua binary (D-01)"
key_files:
  created:
    - "cli/wez.lua"
    - "cli/spec.lua"
    - "cli/commands/version.lua"
    - "cli/vendor/argparse.lua"
    - "cli/vendor/dkjson.lua"
    - "tools/build.sh"
    - "tools/lib/platform.sh"
    - "tools/run-tests.sh"
    - "tests/cli/spec_test.lua"
  modified:
    - ".gitignore"
decisions:
  - "Top-level --version is a plain argparse flag (not add_version) so it never os.exit()s mid-parse and stays observable in the result table; the entry point routes it to the version command"
  - "Entry point uses argparse pparse() (returns ok,result — no os.exit) so dispatch is unit-testable and parse errors map to exit code 2"
  - "build.sh gained a third 'dev source-launcher' path (Rule 3) so dist/wez stays runnable when luastatic is absent and no release is published — keeps verification green without auto-installing an unverified package"
metrics:
  duration: "~13 min"
  completed: "2026-06-09T14:09:00Z"
  tasks: 3
  files_created: 9
  files_modified: 1
  commits: 5
---

# Phase 1 Plan 01: CLI Foundation Summary

JIT-free Lua 5.4 `wez` CLI scaffold — a single source-of-truth argparse spec registering the full Phase 1 command tree, vendored pure-Lua deps (argparse + dkjson), a working `version` command with allow-list lazy dispatch, and a luastatic build pipeline with a pinned, checksum-verified release-download fallback.

## What Was Built

- **`cli/spec.lua`** — `build_parser()` returns an argparse parser registering EVERY Phase 1 subcommand as the interface-first contract (D-16): `version`, `doctor`, `keys --json`, `install-state --force/--restore/--skip`, `uninstall-state --keep-config/--keep-backup/--keep-cli`, `completions <shell>`, hidden `__complete <context>`. Also exposes `subcommand_names()` (closed allow-list) and `categories()` for the completion generator + `wez keys`. `command_target("command")` + `require_command(false)` make a bare `wez`/`--version` valid and give the dispatcher the chosen command name.
- **`cli/wez.lua`** — `main(argv)` loads the spec, parses via `pparse` (no `os.exit`), resolves the chosen command against the closed allow-list (T-01-02), lazily `require`s `cli/commands/<name>.lua`, and propagates its numeric exit code (D-15 prerequisite). Unimplemented stubs exit non-zero with a clean message (no traceback); unknown commands exit 2; bare `wez` prints usage and exits 0. `os.exit` only when run as the main chunk.
- **`cli/commands/version.lua`** — `run(args)` prints `wez <VERSION>` (read from `spec.VERSION`, the single stamp point) and returns 0.
- **Vendored deps** — `cli/vendor/argparse.lua` (MIT, mpeterv, 1527-line canonical) and `cli/vendor/dkjson.lua` (MIT, David Kolf v2.5, 714-line canonical), each with an upstream-provenance header (T-01-SC).
- **`tools/lib/platform.sh`** — sourceable; `platform_os`/`platform_arch`/`platform_ubuntu_base`. Maps Ubuntu codenames so derivatives (Pop!_OS `noble` → `24.04`) resolve correctly; never hard-fails on a non-Ubuntu distro (D-18); no `/proc` assumptions.
- **`tools/build.sh`** — glue-only (D-01), three paths: (1) luastatic static single-binary when the toolchain is present (D-02); (2) **pinned** release-download fallback that **verifies SHA-256 before `chmod +x` and aborts on mismatch** (T-01-01); (3) dev source-launcher so `dist/wez` stays runnable locally.
- **`tools/run-tests.sh`** — discovers `tests/**/*_test.lua`, runs each under `lua5.4`, per-file pass/fail, non-zero on any failure, honors `WEZTERM_INTEGRATION=1`.
- **`tests/cli/spec_test.lua`** — 30 assertions: arg parsing, every subcommand's presence, `keys --json`, dkjson round-trip, version-command behavior, entry-point dispatch incl. unimplemented-stub handling.

## Verification

- `dist/wez version` and `dist/wez --version` exit 0 printing `wez 0.1.0`.
- `bash tools/run-tests.sh` → 30/30 assertions pass, exit 0.
- `tools/lib/platform.sh` sourceable; detects `os=linux arch=x86_64 ubuntu_base=24.04` on this Pop!_OS host.
- `tools/build.sh` contains both the luastatic invocation and the checksum-verified download fallback (grep-visible).
- `shellcheck` clean on all three tools scripts.

## TDD Gate Compliance

Tasks 1 and 2 followed RED → GREEN. Test commits (`test(01-01): ...`) precede their implementation commits (`feat(01-01): ...`) in git history. Task 3 was `tdd="false"` (build/glue tooling) per the plan.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] luastatic absent on the dev host — added a dev source-launcher build path**
- **Found during:** Task 3
- **Issue:** `luastatic` is not installed (only `lua5.4`, `luarocks`, `cc`). The plan's two build paths are luastatic-build and release-download, but no releases exist yet, so neither could produce a runnable `dist/wez` for the acceptance check `bash tools/build.sh && ./dist/wez version`. Per the Rule 3 package-install exclusion, I did NOT auto-install luastatic via luarocks.
- **Fix:** Added a third, clearly-labeled "dev source-launcher" path that emits a tiny `dist/wez` shim execing `lua5.4` against the in-repo sources. The luastatic and download paths remain fully present and grep-visible; the launcher is explicitly NOT a release artifact.
- **Files modified:** `tools/build.sh`
- **Commit:** f38f086

**2. [Rule 2 - Critical] Hardened the download fallback per threat T-01-01**
- **Found during:** Task 3
- **Issue:** A naive download-then-chmod fallback runs untrusted bytes. The threat register marks T-01-01 `mitigate`.
- **Fix:** The fallback pins the release tag (never "latest"), downloads `SHA256SUMS`, verifies the asset's checksum BEFORE `chmod +x`, and aborts non-zero on a missing entry or mismatch.
- **Files modified:** `tools/build.sh`
- **Commit:** f38f086

**3. [Rule 1 - Bug] argparse `--version` and `require_command` interactions**
- **Found during:** Task 1/2
- **Issue:** Using argparse `add_version` exits the process mid-parse; default `require_command(true)` errored on a bare `wez`/`--version`.
- **Fix:** Registered `--version` as a plain flag (observable in the result table) and set `require_command(false)`; the entry point routes `--version` to the version command and prints usage for a bare invocation.
- **Files modified:** `cli/spec.lua`, `cli/wez.lua`
- **Commit:** bd632bf, 93659e0

## Threat Flags

None — no new trust-boundary surface beyond the two already in the plan's threat model (network→build host, args→CLI), both mitigated above.

## Known Stubs

`doctor`, `keys`, `install-state`, `uninstall-state`, `completions`, `__complete` are registered in the spec but their `cli/commands/<name>.lua` modules do not exist yet. This is the INTENDED interface-first contract (D-16): each is implemented by its owning downstream plan (04/05/06/07). The dispatcher handles the absent modules gracefully (clean "not implemented yet" message, exit 3). No stub returns fake data to a UI; nothing is misrepresented as complete.

## Notes for Downstream Plans

- Implement only `cli/commands/<name>.lua` with a `run(args) -> number`; do NOT edit `cli/spec.lua`.
- `require` the vendored JSON as `cli.vendor.dkjson` (the spec already uses the in-tree path with a bare-name fallback).
- `tools/lib/platform.sh` is ready for the Plan 02 WezTerm bootstrap and the Plan 04 installer.
- Before shipping, install `luastatic` in CI so `tools/build.sh` takes path 1 (the dev launcher is local-only).

## Self-Check: PASSED
