---
quick_id: 260623-gbk
slug: macos-dev-launcher-lua-resolve
type: tdd
subsystem: build/dev-launcher
tags: [macos, build.sh, lua@5.4, keg-only, dev-launcher, INST-08]
requirements: [INST-08]
key-files:
  created:
    - tests/cli/build_dev_launcher_test.lua
  modified:
    - tools/build.sh
decisions:
  - "Resolve the dev launcher's Lua 5.4 interpreter at BUILD time and bake the resolved absolute path into the generated exec line (mirrors the REPO_ROOT bake and the static path's keg idiom), rather than emitting a bare `exec lua5.4`."
  - "Resolution order: PATH lua5.4 -> $(brew --prefix lua@5.4)/bin/lua5.4 -> a `lua` reporting 5.4; fail loud (return 1) when none is found so the build aborts instead of generating an inert launcher."
metrics:
  duration: ~12min
  tasks: 2
  files: 2
  completed: 2026-06-23
---

# Quick 260623-gbk: macOS dev-launcher Lua 5.4 resolution Summary

Fixed the macOS dev-launcher build failure: `tools/build.sh build_dev_launcher()` now resolves a Lua 5.4 interpreter at build time (PATH `lua5.4` -> Homebrew `lua@5.4` keg -> a `lua` reporting 5.4) and bakes the resolved absolute path into the generated launcher's `exec` line, closing the exit-127 regression on macOS where `lua@5.4` is keg-only and `lua5.4` is not on the default PATH.

## What changed

- **`tools/build.sh`**: added `resolve_dev_lua()` — a 4-arm, fail-loud Lua 5.4 resolver, and rewired `build_dev_launcher()` to resolve once (`DEV_LUA="$(resolve_dev_lua)" || exit 1`) and bake `${DEV_LUA}` into the heredoc's exec line (build-time-expanded, while `${REPO_ROOT}` and `$@` stay runtime-escaped as before). Updated the launcher's header comment to say it execs the resolved Lua 5.4 interpreter. `have_luastatic()` and the luastatic static path were left untouched (out of scope).
- **`tests/cli/build_dev_launcher_test.lua`** (new): RED-first regression. TEXT guards (no non-comment bare `exec lua5.4 `; `resolve_dev_lua` present) + sourced-behavior harness (with a `lua5.4` shim on PATH the launcher bakes the shim's absolute path; with lua/lua5.4/brew scrubbed but coreutils retained the generator exits non-zero). Mirrors `build_channel_test.lua` + `setup_dev_test.lua` style.

## TDD gate compliance

- **RED** (`59f803e`, `test(...)`): the new test failed 5/7 against the bare-heredoc `build_dev_launcher` — the four target assertions (bare-`exec lua5.4` guard, `resolve_dev_lua` presence, resolved-exec-line, fail-loud) plus the resolved-path read all failed for the right reasons; the run reported no Lua syntax/harness errors. The fail-loud assertion was hardened mid-RED so its scrub PATH retains the coreutils the source + heredoc need (`dirname pwd cat chmod ...`), making the failure attributable to the missing Lua 5.4 interpreter rather than a missing coreutil.
- **GREEN** (`39aa3b6`, `fix(...)`): after adding `resolve_dev_lua` + the bake, the test passes 7/7.

## Verification (VERIFY-BEFORE-DONE, real output)

Keg-only macOS state confirmed (`lua5.4` NOT on bare PATH; default `lua -v` = `Lua 5.5.0`), luastatic absent so the dev-launcher path runs:

- `./tools/build.sh` (bare PATH):
  - `[build] built dev launcher: .../dist/wez (interpreter: /usr/local/opt/lua@5.4/bin/lua5.4)`
  - `[build] verify: '.../dist/wez version' OK (wez 0.1.0)`
  - build `EXIT=0`
- Generated exec line: `exec "/usr/local/opt/lua@5.4/bin/lua5.4" "${REPO_ROOT}/cli/wez.lua" "$@"` (resolved absolute path, NOT bare `lua5.4`).
- `./dist/wez version` -> `wez 0.1.0`, **`EXIT=0`** (was exit 127 `exec: lua5.4: not found` before the fix).
- Full suite `PATH="$(brew --prefix lua@5.4)/bin:$PATH" ./tools/run-tests.sh`: **32/32 passed, exit 0** (no regressions; `build_channel_test.lua`, which touches the same file, still exits 0). `bash -n tools/build.sh` OK.

## Deviations from Plan

None — plan executed as written. The mid-RED hardening of the fail-loud assertion's scrub PATH (retaining coreutils) is a within-task refinement to keep the RED failure correctly attributable, not a plan deviation.

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: `tests/cli/build_dev_launcher_test.lua`
- FOUND commit: `59f803e` (RED, test)
- FOUND commit: `39aa3b6` (GREEN, fix)
