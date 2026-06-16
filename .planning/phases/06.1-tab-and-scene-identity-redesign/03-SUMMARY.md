---
phase: 06.1-tab-and-scene-identity-redesign
plan: 03
subsystem: cli-color
tags: [tab, pane, color, osc, decouple, entropy-reduction, d-01, d-09]
requires:
  - cli/lib/color.lua (Plan 01 — shared palette/normalize/validate/OSC builders)
  - cli/lib/title.lua (shared icon-name resolver)
provides:
  - "wez tab color emits WEZTERM_TAB_COLOR via OSC 1337 (no <color>:<title> prefix)"
  - "wez tab title writes pure title text via set-tab-title"
  - "tab.lua + pane.lua consume cli/lib/color (duplicate color logic deleted)"
  - "#RRGGBBAA accepted + preserved end-to-end (D-09)"
affects:
  - cli/commands/scene.lua (Plan 04 — still consumes parse_stored/merge_title migration helpers)
  - config/wezterm-setup/format-tab-title.lua (renderer reads WEZTERM_TAB_COLOR; prefix fallback to be demoted)
tech-stack:
  added: []
  patterns:
    - "Re-export shared module functions to preserve public surface while deleting duplication (D-01)"
    - "Active-pane io.write OSC emit for tab color (same channel as wez pane color)"
    - "Migration parse-and-warn: legacy helpers kept callable, removed from steady-state write path (D-04)"
key-files:
  created: []
  modified:
    - cli/commands/pane.lua
    - cli/commands/pane_test.lua
    - cli/commands/tab.lua
    - cli/commands/tab_test.lua
decisions:
  - "D-01: deleted duplicated strip_alpha/normalize_color/validate_color + base64/OSC builders from pane.lua and tab.lua; both now require cli/lib/color and re-export to keep the public surface stable"
  - "D-02/D-03: wez tab color emits WEZTERM_TAB_COLOR via OSC 1337 to the active pane TTY (io.write), the same channel wez pane color already uses"
  - "D-04: parse_stored/merge_title demoted to migration-only helpers (kept callable for scene.lua until Plan 04); run_color warns once when it reads a legacy <color>:<title> live tab"
  - "D-09: #RRGGBBAA validates and is preserved verbatim everywhere; the --opacity caveat reworded to 'alpha renders only with window transparency' (Pitfall 4)"
metrics:
  duration: ~25m
  completed: 2026-06-15
  tasks: 2
  files: 4
  net_source_lines: "-80 (130 insertions / 210 deletions across pane.lua + tab.lua)"
---

# Phase 06.1 Plan 03: Decouple Tab Color from Title + Consolidate Color Logic Summary

Decoupled `wez tab` color from title — color now emits `WEZTERM_TAB_COLOR` via OSC 1337 (killing the `<color>:<title>` prefix encoding that caused the `cyan:` literal bug) while title writes pure text — and collapsed the duplicated color logic in `pane.lua`/`tab.lua` into the shared `cli/lib/color.lua` (net -80 source lines), with `#RRGGBBAA` now preserved end-to-end.

## What Was Built

### Task 1 — pane.lua consumes cli/lib/color (D-01/D-09)
- Deleted the local `COLOR_NAMES`, `MUTED_BG`, `strip_alpha`, `normalize_color`, `validate_color`, the pure-Lua base64 encoder, and the `build_osc11`/`build_reset_osc11`/`build_osc1337` builders.
- Added `local color = require("cli.lib.color")` and re-exported the public surface (`M.COLOR_NAMES`, `M.MUTED_BG`, `M.normalize_color`, `M.validate_color`, `M.build_osc11`, `M.build_reset_osc11`, `M.build_osc1337`, `M._base64`) so existing callers and the test fixtures are unchanged.
- D-09: `#RRGGBBAA` (and `#RGBA`) now validate and are preserved — the 8th hex pair is no longer stripped. The `--opacity` soft-degrade warning was reworded from "applied without transparency" to "alpha renders only with window transparency" (Pitfall 4: WezTerm ignores alpha except for selection unless the window is transparent).

### Task 2 — decouple tab color (OSC) from title (D-02/D-03/D-04)
- `wez tab color <c>` now validates via the shared `color.validate_color`, then `io.write(color.build_osc1337("WEZTERM_TAB_COLOR", normalized))` to the active pane TTY — the SAME channel `wez pane color` uses. No `set-tab-title` write, no `<color>:<title>` prefix. `reset` emits an empty payload to clear the accent.
- `wez tab color <c> --title <text>` performs TWO independent writes: the OSC color accent AND a pure-text `set-tab-title` via the shared title resolver.
- `wez tab title <text>` writes PURE resolved title text via `set-tab-title` (no color prefix, no read-modify-write). `reset`/empty clears it.
- `parse_stored`/`merge_title` are demoted to migration-only helpers: kept callable (scene.lua still depends on them until Plan 04), removed from this module's steady-state write path. `run_color` now warns ONCE (D-04 / Open Q3) when it reads a legacy-prefixed live tab.
- Validate-before-emit preserved (T-06.1-07): an invalid color exits 2 with ZERO writes.

## TDD Gate Compliance

Both tasks followed RED → GREEN:
- `test(06.1-03)`: c6fdff4 (pane RED), ef70b12 (tab RED)
- `refactor(06.1-03)`: 80f55cc (pane GREEN — refactor, no new behavior, pure consolidation)
- `feat(06.1-03)`: caffe44 (tab GREEN — new OSC-decoupled behavior)

A `refactor` commit was used for the pane GREEN gate (it is a pure D-01 consolidation that preserves behavior except for D-09 alpha preservation), and `feat` for the tab GREEN gate (genuinely new decoupled behavior). No standalone REFACTOR pass was needed — the deletion IS the consolidation.

## Verification

- `lua5.4 cli/commands/pane_test.lua` → 46 passed, 0 failed.
- `lua5.4 cli/commands/tab_test.lua` → 40 passed, 0 failed.
- `./tools/run-tests.sh` → all 23 files passed (scene tests included — confirms `parse_stored`/`merge_title` survive for the Plan 04 dependency).
- D-01 gate: `grep` for local `function M.(strip_alpha|normalize_color|validate_color|build_osc11|build_reset_osc11|build_osc1337)` in both modules returns ZERO.
- Both modules `require("cli.lib.color")`.
- `WEZTERM_TAB_COLOR` emit present in tab.lua; no non-comment `merge_title` CALL inside `run_color`/`run_title` (only the kept function definition remains).
- Net source delta: 130 insertions / 210 deletions across pane.lua + tab.lua = **-80 lines** (D-01 entropy reduction confirmed).
- Live repro (`wez tab color cyan` shows the accent with NO `cyan:` literal) is deferred to Plan 07 e2e per the plan's verification note.

## Threat Surface

All threat-register mitigations preserved:
- **T-06.1-05** (OSC injection): the accent value is base64-encoded by `color.build_osc1337` (control/ESC bytes neutralized).
- **T-06.1-06** (set-tab-title injection): the pure-text title is `shquote`'d before `os.execute`; resolved through the shared title resolver (no new code path).
- **T-06.1-07** (validate-before-emit): invalid color bails exit 2 with zero writes — asserted in test 23.

No new security surface introduced.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] pane_test test 18 hint string**
- **Found during:** Task 1 RED authoring.
- **Issue:** the old error-message assertion checked for `#rrggbb`; the shared module's friendly error lists `#rrggbbaa` too, but still contains the `#rrggbb` substring, so no change was needed — the assertion passes as-is. No code change; noted for traceability.

Otherwise the plan executed as written. The `merge_title`/`parse_stored` retention (callable migration helpers) follows the plan's explicit `<cross_plan_note>` to keep Wave 2 parallel-safe with Plan 04.

## Known Stubs

None. The legacy `parse_stored`/`merge_title` are not stubs — they are intentional migration helpers with a documented owner (Plan 04 removes scene.lua's dependency, after which the symbols can be deleted).

## Self-Check: PASSED

- `cli/commands/pane.lua` — FOUND (modified, requires cli.lib.color, 0 local color defs)
- `cli/commands/tab.lua` — FOUND (modified, emits WEZTERM_TAB_COLOR, requires cli.lib.color)
- `cli/commands/pane_test.lua` / `cli/commands/tab_test.lua` — FOUND (both green)
- Commits c6fdff4, 80f55cc, ef70b12, caffe44 — all FOUND in git log.
