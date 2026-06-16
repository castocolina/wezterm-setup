---
phase: 06.1-tab-and-scene-identity-redesign
plan: 05
subsystem: ui
tags: [wezterm, lua, tab-bar, keybindings, color, alpha, rotatepanes, tdd]

# Dependency graph
requires:
  - phase: 06.1-01
    provides: "shared cli/lib/color.lua (#RRGGBBAA accepted/preserved, strip_alpha removed) — the CLI-side parity for the render-side alpha acceptance landed here"
  - phase: 06.1-03
    provides: "tab color decoupled to WEZTERM_TAB_COLOR via OSC 1337; <color>:<title> prefix removed from the CLI write path (steady state)"
provides:
  - "Config-layer renderer reads the ACTIVE pane's WEZTERM_TAB_COLOR for the tab accent (D-02 active-pane-wins) and drops the <color>:<title> prefix from the steady-state accent (D-04 migration-only)"
  - "resolve_profile accepts a #RRGGBBAA (8-digit) accent without falling back to the default profile (D-09); malformed/over-long hex still defaults (T-06.1-12)"
  - "Arrange keys: Alt+Shift+R = RotatePanes Clockwise, Alt+Shift+E = RotatePanes CounterClockwise, with a lockstep init.lua resolve_action arm (Pitfall 3); Alt+Shift+Z zoom toggle retained (D-12)"
  - "Embraced search defaults documented: Ctrl+Shift+F Search + Ctrl+R CopyMode CycleMatchType (item 8)"
affects: [06.1-07, 06.2, macos-pass]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Config-layer color model mirrored independently of cli/lib/color (the config bundle is NOT luastatic-bundled and cannot require cli/) — the render-side palette is the intentional single render source"
    - "Declarative keybinding spec + lockstep resolve_action arm: every new spec.type MUST gain a matching arm in the same change or config load error()s (Pitfall 3), guarded by keybindings_test + apply_test"

key-files:
  created: []
  modified:
    - config/wezterm-setup/format-tab-title.lua
    - config/wezterm-setup/format-tab-title_test.lua
    - config/wezterm-setup/keybindings.lua
    - config/wezterm-setup/init.lua
    - tests/config/keybindings_test.lua
    - tests/config/apply_test.lua

key-decisions:
  - "Alt+Shift+R/E (and the existing Alt+Shift H/V/X/Z pane family) shadow NO WezTerm default chord, so no DisableDefaultAssignment entry is required — documented in disabled_defaults to keep `wez keys` truthful (D-12)"
  - "parse_tab_title kept (not deleted) as DISPLAY-only migration grace so a legacy `cyan:api` stored title still renders `api` without a per-paint warning; its color half is discarded (D-04, Open Q3)"

patterns-established:
  - "Pattern: render-side accent derives from active pane user var ONLY in steady state; legacy prefix is display-text migration grace, removed once no legacy titles remain"
  - "Pattern: keybinding spec <-> resolve_action arm lockstep, asserted under a wezterm stub in apply_test (proves the closed switch does not error on the new type)"

requirements-completed: [D-02, D-04, D-09, D-12]

# Metrics
duration: 3min
completed: 2026-06-15
---

# Phase 06.1 Plan 05: Render Active-Pane Color + Alpha + Arrange Keys Summary

**The in-VM config renderer now paints the active pane's WEZTERM_TAB_COLOR (accepting #RRGGBBAA), drops the legacy `<color>:<title>` accent prefix to display-only migration, and binds Alt+Shift+R/E RotatePanes with a lockstep resolve_action arm — config load stays error-free, full suite green.**

## Performance

- **Duration:** ~3 min (first task commit 18:50:58 → last task commit 18:53:06 local)
- **Started:** 2026-06-15T22:50:58Z
- **Completed:** 2026-06-15T22:53:23Z
- **Tasks:** 2 (both TDD: RED → GREEN)
- **Files modified:** 6

## Accomplishments
- `format-tab-title.lua` accent now reads the active pane's `WEZTERM_TAB_COLOR` only; the tab-prefix color fallback (`or tabColor`) is removed from the steady state (D-02/D-04).
- `resolve_profile` accepts an 8-digit `#RRGGBBAA` accent (extended the hex match with a `%x%x%x%x%x%x%x%x` branch) — no default-fallback; a malformed/over-long hex still defaults (D-09 + T-06.1-12 tamper safety).
- `parse_tab_title` demoted to display-only migration grace: a legacy `cyan:api` stored title still renders `api`, no per-paint warning; its color half is discarded (D-04, Open Q3).
- Arrange keys bound: `Alt+Shift+R` RotatePanes Clockwise + `Alt+Shift+E` CounterClockwise, with the matching `init.lua resolve_action` arm added in lockstep (Pitfall 3); `Alt+Shift+Z` zoom toggle retained (D-12).
- Embraced search defaults documented in the keybindings header: `Ctrl+Shift+F` Search + `Ctrl+R` CopyMode CycleMatchType — no binding added (item 8), relaxing the prior "no less-style search overlay" rule.

## Task Commits

Each task was committed atomically (TDD: RED test commit → GREEN implementation commit):

1. **Task 1: format-tab-title active-pane color + #RRGGBBAA + prefix demoted**
   - RED: `307cf6d` (test)
   - GREEN: `f8094f9` (feat)
2. **Task 2: RotatePanes keys + resolve_action lockstep + search docs**
   - RED: `fc563bb` (test)
   - GREEN: `860ee98` (feat)

**Plan metadata:** _(this docs commit)_

_No REFACTOR commits — implementations were clean at GREEN._

## Files Created/Modified
- `config/wezterm-setup/format-tab-title.lua` — `resolve_profile` accepts `#RRGGBBAA`; handler accent = active pane `WEZTERM_TAB_COLOR` only; `parse_tab_title` documented as migration-only and consumed for the display title only.
- `config/wezterm-setup/format-tab-title_test.lua` — new cases: `#RRGGBBAA` accepted (5a/5b), over-long hex defaults (5c), steady-state accent is active-pane-only with legacy prefix as display grace (24–27 rewritten), end-to-end 8-digit accent paint (29).
- `config/wezterm-setup/keybindings.lua` — `Alt+Shift+R`/`Alt+Shift+E` RotatePanes entries; header documents embraced `Ctrl+Shift+F`/`Ctrl+R`; `disabled_defaults` note explains why Arrange chords need no DisableDefaultAssignment.
- `config/wezterm-setup/init.lua` — `resolve_action` `RotatePanes` arm (`act.RotatePanes(spec.arg)`) in lockstep with keybindings (Pitfall 3).
- `tests/config/keybindings_test.lua` — assert both RotatePanes entries with correct mods/arg + `Alt+Shift+Z` retained.
- `tests/config/apply_test.lua` — assert RotatePanes spec merges into `config.keys`, and (under a wezterm stub) that `resolve_action` maps it to `wezterm.action.RotatePanes` without the closed switch error()ing.

## Decisions Made
- **No DisableDefaultAssignment for Arrange chords:** `Alt+Shift+R/E` (and the existing `Alt+Shift H/V/X/Z` family) do not shadow any WezTerm default assignment, so adding a disable entry would be untruthful. Documented inline in `disabled_defaults` so `wez keys` classification stays accurate (D-12).
- **Kept `parse_tab_title` rather than deleting it:** the plan's deletion win is removing the prefix from the *accent* path, not removing the parser — it survives as DISPLAY-only migration grace (D-04). Discarding the color half (`_legacyColor`) is the intentional shrink.

## Deviations from Plan

None - plan executed exactly as written. Both tasks followed the RED → GREEN TDD gate; no auto-fixes (Rules 1–3) and no architectural escalations (Rule 4) were needed.

## Issues Encountered
None. RED failed for exactly the expected assertions (5 in Task 1, 2+2 in Task 2), GREEN turned them green, and the full suite (`./tools/run-tests.sh`) reported all 23 files passed.

## TDD Gate Compliance
- Task 1: `test(06.1-05)` RED `307cf6d` → `feat(06.1-05)` GREEN `f8094f9` ✓
- Task 2: `test(06.1-05)` RED `fc563bb` → `feat(06.1-05)` GREEN `860ee98` ✓
- Each RED was observed failing for the intended assertions before its GREEN (no test passed unexpectedly during RED).

## User Setup Required
None - no external service configuration required.

## Known Stubs
None.

## Next Phase Readiness
- The render layer now agrees with the CLI's `WEZTERM_TAB_COLOR` carrier and accepts alpha; Arrange keys + embraced search are in place.
- **Render + RotatePanes live verification is owned by Plan 07** (recorded manual repro): GPU tab-bar render (accent paint, no `cyan:` prefix) and the visual pane rotation are not headlessly assertable. Alpha only renders with window transparency (Pitfall 4 caveat — accepted/stored, not promised to paint).
- Lockstep invariant guarded by `keybindings_test` + `apply_test`: any future `keybindings.lua` action type must add a matching `resolve_action` arm.

## Self-Check: PASSED
- Files verified on disk: `05-SUMMARY.md`, `format-tab-title.lua`, `keybindings.lua`, `init.lua` (all FOUND).
- Commits verified in git: `307cf6d`, `f8094f9`, `fc563bb`, `860ee98` (all FOUND).

---
*Phase: 06.1-tab-and-scene-identity-redesign*
*Completed: 2026-06-15*
