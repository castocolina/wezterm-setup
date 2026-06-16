---
phase: 06.1-tab-and-scene-identity-redesign
plan: 02
subsystem: cli
tags: [lua, cwd, path-resolution, security, pure-module, tdd]

# Dependency graph
requires:
  - phase: 06.1-tab-and-scene-identity-redesign
    provides: "pure-module / IO-shell split convention (cli/lib/scene.lua, cli/lib/color.lua) + check/eq fixture harness"
provides:
  - "cli/lib/cwd.lua — the single pure resolver for the locked cwd grammar (D-01/D-07/D-08)"
  - "M.resolve(value, launch_dir, env): nil/'.'/'..'/~/$ENV/abs/relative -> absolute path"
  - "M.validate(value, env): validate-before-emit rejection of $(...), backticks, and unset $ENV"
affects: [scene-launch, scene-new, cwd-flag, wezterm-cli-spawn, plan-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure resolver + injected env table (no os.getenv inside) so the module stays testable under plain lua5.4"
    - "validate-before-emit: shell command substitution rejected in Lua, never handed to a shell (T-06.1-03)"

key-files:
  created:
    - cli/lib/cwd.lua
    - cli/lib/cwd_test.lua
  modified: []

key-decisions:
  - "Resolver takes an injected env table argument (not os.getenv) to keep the module pure and the suite deterministic"
  - "Empty string '' is treated as omitted -> launch dir (same as nil), per D-07"
  - "dirname collapses a slash-less / root path to '/' so '..' never yields an empty string"
  - "Followed the existing 02-SUMMARY.md filename convention (matches 01-SUMMARY.md), not the verbose 06.1-02 form in the plan output tag"

patterns-established:
  - "cwd grammar resolution lives in ONE shared pure module (D-01) — scene launch, scene new, and any --cwd flag share identical edge handling and the same no-shell-eval security posture"
  - "Security lock encoded as a fixture assertion: validate('$(...)') must return false (RESEARCH Security Domain)"

requirements-completed: [D-01, D-07, D-08]

# Metrics
duration: ~8min
completed: 2026-06-15
---

# Phase 06.1 Plan 02: Shared cwd Resolver Summary

**Pure `cli/lib/cwd.lua` resolving the locked cwd grammar (literal | ~ | $ENV | relative, with `.`=launch dir and `..`=dirname) to an absolute path, with validate-before-emit rejection of `$(...)`/backticks/unset `$ENV` — no shell eval.**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-06-15 (TDD RED → GREEN)
- **Completed:** 2026-06-15
- **Tasks:** 2
- **Files modified:** 2 (both created)

## Accomplishments
- Single shared pure resolver for cwd resolution (D-01) so the `--cwd` CLI flag and the `.toml` `cwd` field (Wave 2/3 consumers) share identical edge handling.
- Full locked-grammar coverage: omitted/`.` → launch dir (D-07), `..` → dirname(launch dir), `~`/`~/x` → HOME, `$ENV/...` → env expansion, literal absolute pass-through, relative joined to launch dir.
- Security lock enforced (T-06.1-03): `M.validate` rejects shell command substitution (`$(...)`, backticks) and unset `$ENV` references before emit — the value never reaches a shell, and expansion happens purely in Lua.
- Pure under plain `lua5.4` (purity grep = 0): env injected as a table arg; no `os.getenv`/`os.execute`/`io.`/`wezterm`.

## Task Commits

Each task was committed atomically (TDD RED → GREEN):

1. **Task 1: RED — author cli/lib/cwd_test.lua** - `7127ce5` (test)
2. **Task 2: GREEN — implement pure cli/lib/cwd.lua** - `aadba28` (feat)

_REFACTOR: not needed — the implementation was minimal from the start (the `dirname` helper was extracted up front; no path-normalization beyond the spec was added)._

## Files Created/Modified
- `cli/lib/cwd.lua` - Pure cwd-grammar resolver exporting `M.resolve(value, launch_dir, env)` and `M.validate(value, env)`.
- `cli/lib/cwd_test.lua` - RED-first fixture suite (21 assertions) mirroring `scene_test.lua`'s check/eq harness; covers happy grammar paths and the three rejection paths.

## Decisions Made
- **Injected env table over `os.getenv`:** keeps the module pure and the suite deterministic; Plan 04's IO-shell passes a real env snapshot. (Follows the established `scene.lua`/`color.lua` pure-core / IO-shell split.)
- **Empty string `""` treated as omitted:** resolves to the launch dir, same as `nil` (D-07 default). Added an explicit fixture (`1b`) beyond the plan's bullet list as a correctness guard.
- **`dirname` collapses to `/`:** a slash-less or root path returns `/` so `..` never yields an empty string.
- **Filename convention:** wrote `02-SUMMARY.md` (matches the existing `01-SUMMARY.md`), not the `06.1-02-SUMMARY.md` form in the plan's `<output>` tag.

## Deviations from Plan

None - plan executed exactly as written. (One extra defensive assertion `1b` for `resolve("")` was added; it is within the resolver's documented `nil/empty -> launch_dir` contract, not a behavior change.)

## Issues Encountered
None.

## User Setup Required
None - pure module, zero external dependencies, no consumer wiring (Plan 04 consumes it).

## Next Phase Readiness
- `cli/lib/cwd.lua` is ready for Plan 04 to wire into the live `--cwd` flag and `.toml` `cwd` field.
- Reminder for Plan 04 (T-06.1-04): this module produces only the resolved STRING — the IO-shell MUST shquote it before `os.execute` / `wezterm cli spawn --cwd`.
- Full suite green (23 files); purity grep 0.

## Self-Check: PASSED

---
*Phase: 06.1-tab-and-scene-identity-redesign*
*Completed: 2026-06-15*
