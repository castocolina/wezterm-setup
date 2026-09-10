---
phase: 07-macos-parity
plan: 01
subsystem: testing
tags: [lua54, macos, bash-3.2, verify-macos, run-tests]

requires:
  - phase: 06.9-e2e-tier-3-firing-tier-4-visuals-local-permission-bound-clos
    provides: Linux-complete suite and verify-macos.sh auto-gate that this tracer re-runs on real Mac hardware
provides:
  - split_kv_segments compiles under Lua 5.4+ implicit-const loop vars
  - verify-macos.sh 3-step Lua 5.4 resolver (never exports LUA_BIN=lua on faith)
  - run-tests.sh auto-detects Homebrew lua@5.4 keg
  - D-08 harness-portability probes as real PASS/FAIL (mapfile/readarray absence, sha256sum/shasum co-occurrence)
  - macos-verification.md LUA_BIN / mapfile guidance corrected in all four stale spots
affects: [07-macos-parity]

actuals:
  tokens: 2300
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - Lua 5.4 resolver order PATH lua5.4 → brew --prefix lua@5.4 keg → bare lua only if lua -v reports 5.4
    - grep-gate hygiene: comment-filter first; assemble banned tokens so the gate file does not self-match

key-files:
  created: []
  modified:
    - cli/lib/scene.lua
    - tools/run-tests.sh
    - tools/verify-macos.sh
    - docs/macos-verification.md

key-decisions:
  - "Lua 5.4 resolution is the same 3-step order in run-tests.sh and verify-macos.sh as build.sh resolve_dev_lua"
  - "verify-macos.sh keg hit prepends keg/bin onto PATH so child lua5.4 -e tests inherit a real 5.4"
  - "Never export LUA_BIN=lua unless lua -v self-reports Lua 5.4"

patterns-established:
  - "Generic-for loop control variables are never reassigned (Lua 5.4+ implicit const)"
  - "Harness portability invariants are pass/fail, not note()"

requirements-completed: [DIAG-05, SCEN-03, SCEN-04, SCEN-06]

coverage:
  - id: D1
    description: split_kv_segments no longer assigns to its generic-for control variable; scene.lua compiles under Lua 5.4 and 5.5
    requirement: SCEN-03
    verification:
      - kind: unit
        ref: cli/lib/scene_test.lua (77 passed, 0 failed under /usr/local/opt/lua@5.4/bin/lua5.4)
        status: pass
      - kind: unit
        ref: cli/lib/recipe_test.lua (65 passed, 0 failed)
        status: pass
    human_judgment: false
  - id: D2
    description: verify-macos.sh resolves Lua 5.4 via PATH → Homebrew lua@5.4 keg → lua -v 5.4, and asserts D-08 portability as PASS/FAIL
    requirement: DIAG-05
    verification:
      - kind: other
        ref: bash tools/verify-macos.sh → PASS=29 FAIL=0 SKIP=9
        status: pass
    human_judgment: false
  - id: D3
    description: run-tests.sh auto-detects a genuine Lua 5.4 instead of blindly trusting lua
    requirement: DIAG-05
    verification:
      - kind: other
        ref: bash tools/verify-macos.sh unit suite (all 35 file) under keg-resolved lua5.4
        status: pass
    human_judgment: false
  - id: D4
    description: macos-verification.md no longer recommends LUA_BIN=lua or claims the harness uses mapfile (four spots)
    verification:
      - kind: other
        ref: grep -qE 'LUA_BIN=lua( |$)' docs/macos-verification.md (no match)
        status: pass
    human_judgment: false
  - id: D5
    description: seed-scenes copy-if-absent and scene launch error-contract auto-checks still green on this Mac
    requirement: SCEN-06
    verification:
      - kind: other
        ref: verify-macos.sh sections 4–5 (scene launch + seed-scenes) inside FAIL=0 run
        status: pass
    human_judgment: false

duration: 25min
completed: 2026-09-10
status: complete
---

# Phase 07 Plan 01: macOS tracer — Lua 5.4+ compile fix + auto-gate hardening

**scene.lua compiles under Lua 5.4+/5.5; verify-macos.sh and run-tests.sh resolve a real Lua 5.4 on this Mac; D-08 portability is a hard gate; runbook LUA_BIN=lua guidance is gone.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-09-10
- **Completed:** 2026-09-10
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- `cli/lib/scene.lua` `split_kv_segments` no longer mutates its generic-`for` control variable (Lua 5.4+ implicit `<const>`).
- `tools/run-tests.sh` and `tools/verify-macos.sh` share the 3-step Lua 5.4 resolver (PATH `lua5.4` → Homebrew `lua@5.4` keg → bare `lua` only if `lua -v` reports 5.4). The auto-gate never exports `LUA_BIN=lua` on faith.
- D-08 harness portability is `pass`/`fail` (comment-filtered `mapfile`/`readarray` absence; `sha256sum` files must also mention `shasum`). The informational `sha256sum` NOTE is unchanged.
- `docs/macos-verification.md` corrected in all four stale spots (pre-flight Lua bullet, Section 1 unit-suite + mapfile callout, deviations checklist, Appendix).

## Task Commits

1. **Task 1: Fix Lua 5.4+ const-reassignment in scene.lua** - `559446c` (fix)
2. **Task 2: Harden verify-macos.sh + Lua 5.4 auto-detect + runbook** - `15bc680` (fix)

**Plan metadata:** this file (docs: summary)

## Task 1 verify (actual output)

Resolver picked the Homebrew keg (`lua5.4` not on PATH; `lua -v` is 5.5.1):

```
LB=/usr/local/opt/lua@5.4/bin/lua5.4
Lua 5.4.8  Copyright (C) 1994-2025 Lua.org, PUC-Rio
scene_test: 77 passed, 0 failed
```

`require("cli.lib.scene")` succeeded under both keg Lua 5.4.8 and Homebrew `lua` 5.5.1.

`LUA_BIN="${LB}" ./tools/run-tests.sh 2>&1 | tail -5` ended:

```
183 passed, 0 failed
PASS  tests/docs_drift_test.lua

run-tests: 3 file(s) failed
```

The three failures were pre-existing child-process `lua5.4: command not found` in `complete_test.lua`, `scene_launch_test.lua`, and `seed_scenes_test.lua` — not regressions of `scene_test.lua` (77/0) or `recipe_test.lua` (65/0). They went to zero once Task 2 prepended the keg `bin` onto `PATH` for the auto-gate.

## Task 2 verify (actual output)

Static checks (`mc=0`, no `LUA_BIN=lua( |$)` in the runbook) passed, then:

```
  PASS  lua5.4 present (Homebrew lua@5.4 keg)
  PASS  tools/*.sh: no non-comment bash-4 array-read builtins (D-08)
  PASS  build.sh: sha256sum has shasum fallback
  PASS  publish.sh: sha256sum has shasum fallback
  PASS  verify-macos.sh: sha256sum has shasum fallback
  PASS  unit suite (all 35 file)

=== Summary ===
  PASS=29  FAIL=0  SKIP=9
verify-macos: auto-checks OK — now drive docs/macos-verification.md for the live/visual steps.
```

`grep -oE 'FAIL=[0-9]+' ... | tail -1 | grep -qx 'FAIL=0'` → exit 0.

## Files Created/Modified

- `cli/lib/scene.lua` — loop var renamed `raw_segment`; trimmed value bound as `local segment`
- `tools/run-tests.sh` — 3-step Lua 5.4 auto-detect; fail message names `brew install lua@5.4`
- `tools/verify-macos.sh` — same resolver (keg hit exports `LUA_BIN` + prepends PATH); D-08 `pass`/`fail` probes
- `docs/macos-verification.md` — four stale `LUA_BIN=lua` / `mapfile` spots corrected

## Decisions Made

- Resolver order copied from `tools/build.sh` `resolve_dev_lua()`, not invented.
- Keg hit in `verify-macos.sh` prepends `"${keg}/bin"` onto `PATH` so later `bash tools/run-tests.sh` and child `lua5.4 -e` tests see a real 5.4.
- D-08 `mapfile`/`readarray` pattern is assembled (`'map''file|read''array'`) so `verify-macos.sh` itself does not contain those contiguous tokens on non-comment lines (the Task 2 verify grep would otherwise self-fail).

## Deviations from Plan

None in scope or algorithm. Two implementation notes:

1. **Task 1 suite tail showed 3 pre-existing failures** (`lua5.4` not on PATH for child `lua5.4 -e`). Not caused by the loop-var fix. Cleared by Task 2's PATH prepend; auto-gate unit suite = all 35 files.
2. **Banned-token assembly** in the D-08 grep (see Decisions) so the gate file does not self-match. Required for the plan's own verify command to pass.

**Total deviations:** 0 scope changes
**Impact on plan:** none

## Issues Encountered

This Mac has no `lua5.4` on PATH. Homebrew `lua` is 5.5.1. The keg `$(brew --prefix lua@5.4)/bin/lua5.4` (5.4.8) is present. That is exactly the gap this plan closes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Tracer is green on real macOS hardware. Later 07-macos-parity plans can rely on `bash tools/verify-macos.sh` reporting `FAIL=0` and on `tools/run-tests.sh` resolving Lua 5.4 without `LUA_BIN=lua`.

---
*Phase: 07-macos-parity*
*Completed: 2026-09-10*
