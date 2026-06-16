---
phase: 06.1-tab-and-scene-identity-redesign
plan: 01
subsystem: cli
tags: [lua, color, osc, base64, tdd, reducing-entropy]

# Dependency graph
requires:
  - phase: 02-pane-identity
    provides: "pane.lua color normalize/validate, base64, OSC 11/1337 builders (the canonical source lifted here)"
  - phase: 04-scenes
    provides: "scene.lua printf '\\nnn' octal send-text idiom (generalized into build_user_var_octal)"
provides:
  - "cli/lib/color.lua — single shared color module: COLOR_NAMES palette, MUTED_BG map, normalize_color/validate_color, base64, build_osc11/build_reset_osc11/build_osc1337/build_user_var_octal"
  - "D-09 alpha behavior at the source: #RRGGBBAA accepted and preserved (strip_alpha removed)"
  - "cli/lib/color_test.lua — RED-first fixture suite locking the shared contract"
affects: [tab-color, pane-color, scene-render, format-tab-title, plan-03-rewire]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure-core module (local M = {}; return M) with zero wezterm/io/os refs — loads under plain lua5.4"
    - "One shared color emitter consumed by every entry point (D-01 / reducing-entropy)"

key-files:
  created:
    - cli/lib/color.lua
    - cli/lib/color_test.lua
  modified: []

key-decisions:
  - "rgba() left REJECTED cleanly (D-09 floor is #RRGGBBAA; rgba parsing is discretionary and deferred)"
  - "strip_alpha removed entirely rather than kept (no remaining path needs a forced-6-digit color; D-09)"
  - "build_user_var_octal returns the bare \\nnn octal payload (caller wraps in printf), generalizing the scene.lua idiom into one emitter"

patterns-established:
  - "Pure pure-Lua shared lib in cli/lib/ with a co-located *_test.lua run under lua5.4"
  - "OSC value safety via base64 in build_osc1337 — no raw user bytes enter the escape stream (T-06.1-01)"

requirements-completed: [D-01, D-03, D-09]

# Metrics
duration: ~8min
completed: 2026-06-15
---

# Phase 06.1 Plan 01: Shared color module Summary

**A single pure `cli/lib/color.lua` consolidating the palette, normalize/validate, base64, and OSC 11/1337 + octal emitters — with D-09 landed (#RRGGBBAA accepted and preserved, alpha no longer stripped).**

## Performance

- **Duration:** ~8 min
- **Completed:** 2026-06-15
- **Tasks:** 2 (TDD RED → GREEN)
- **Files modified:** 2 created

## Accomplishments
- New shared `cli/lib/color.lua` (125 lines) owns the 10-name palette + muted-bg map, `normalize_color`/`validate_color`, pure-Lua base64, and `build_osc11`/`build_reset_osc11`/`build_osc1337`/`build_user_var_octal` — the one implementation Wave-2 consumers (pane, tab, scene, recipe render) will share (D-01).
- D-09 landed at the source: `#RRGGBBAA` (and 4-digit `#RGBA`) now validate and are preserved verbatim; `strip_alpha` is gone, so the alpha-stripping defect can never diverge again.
- `build_user_var_octal` generalizes the proven `scene.lua` Pitfall-2 octal idiom into one emitter for pane-targeted `send-text` writes.
- Module is pure (zero wezterm/io/os refs) — loads and is fully testable under plain `lua5.4`.

## Task Commits

Each task committed atomically (TDD gate sequence):

1. **Task 1: RED — author cli/lib/color_test.lua** - `f2d167d` (test)
2. **Task 2: GREEN — implement cli/lib/color.lua** - `8be8f33` (feat)

No REFACTOR commit: the lifted code was already clean; no restructuring needed after GREEN.

_TDD gate verified: `test(...)` (RED, proven failing before impl) precedes `feat(...)` (GREEN) in git log._

## Files Created/Modified
- `cli/lib/color.lua` - Shared pure color module: palette, MUTED_BG, normalize/validate, base64, OSC 11/1337 builders, octal user-var emitter (D-01 consolidation; D-09 alpha-preserving).
- `cli/lib/color_test.lua` - 36-assertion fixture suite (scene_test harness) locking the shared contract, incl. the D-09 8-digit regression lock and build_user_var_octal↔build_osc1337 coupling.

## Decisions Made
- **rgba() rejected cleanly (discretion, D-09):** the committed floor is `#RRGGBBAA`. Adding rgba() validation is a small pure extension to `validate_color` deferred to a future plan; rejecting it now returns `(false, error_string)` with no traceback. Documented in the module header.
- **strip_alpha removed, not kept:** RESEARCH A3 confirmed no remaining path needs a forced 6-digit color, so the function was deleted rather than left dead. `normalize_color` now only lowercases + passes `reset` through.
- **build_user_var_octal returns the bare `\nnn` payload** (caller adds `printf '...'`), matching how `scene.lua` constructs the line — keeps the emitter caller-agnostic.

## Deviations from Plan

None - plan executed exactly as written. The RED test went non-zero (module absent), the implementation made all 36 assertions pass GREEN, purity grep returned 0, and the full suite (22 files) stayed green with no consumer rewiring (Plan 03 owns the duplicate deletion).

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The shared module is ready for Wave-2 consumers. Plan 03 will DELETE the duplicate `strip_alpha`/`normalize_color`/`validate_color` (and pane.lua's base64/OSC builders) and re-export from `cli/lib/color.lua` — that is where the net-deletion win of `/reducing-entropy` is realized.
- Caveat to carry forward (Pitfall 4 / D-09): WezTerm ignores alpha except for selection_fg/selection_bg, so `#RRGGBBAA` only renders with window transparency. Documented in the module header.
- No blockers.

## Self-Check: PASSED

---
*Phase: 06.1-tab-and-scene-identity-redesign*
*Completed: 2026-06-15*
