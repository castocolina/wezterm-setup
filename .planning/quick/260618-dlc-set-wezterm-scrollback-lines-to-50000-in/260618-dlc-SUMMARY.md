---
quick_id: 260618-dlc
type: execute
subsystem: config-layer
description: Set WezTerm scrollback_lines to 50000 via a labeled config-layer knob
tags: [config, scrollback, terminal-options, augment, D-17]
key-files:
  created: []
  modified:
    - config/wezterm-setup/init.lua
    - tests/config/apply_test.lua
  synced:
    - ~/.config/wezterm/wezterm-setup/init.lua
decisions:
  - "scrollback_lines lives in a single labeled module-level knob (local SCROLLBACK_LINES = 50000) so future changes are a one-line edit"
  - "Set as a new general/terminal-options step (5) in M.apply() via AUGMENT (config.scrollback_lines = SCROLLBACK_LINES) — single field set, never a table replacement (D-17)"
metrics:
  duration: ~1min
  tasks: 2
  files: 2
  completed: 2026-06-18T13:49:33Z
---

# Quick Task 260618-dlc: WezTerm scrollback_lines → 50000 Summary

Raised the WezTerm scrollback buffer from the 3500 default to 50000 lines via a labeled
one-line knob in the config layer, wired through `M.apply()` as an AUGMENT (D-17), asserted
in the apply test, and synced to the installed copy so it takes effect on the next config touch.

## What Changed

### Task 1 — SCROLLBACK_LINES knob + apply() wiring (commit `4817f43`)

- `config/wezterm-setup/init.lua`:
  - Added a labeled module-level constant near the top, immediately after `local M = {}`:
    ```lua
    -- Scrollback buffer depth (lines). Change here to adjust; WezTerm default is 3500.
    local SCROLLBACK_LINES = 50000
    ```
  - Added a new clearly-commented general/terminal-options step (numbered **5**) inside
    `M.apply(config)` that sets `config.scrollback_lines = SCROLLBACK_LINES`. This is a pure
    AUGMENT — a single field set on the passed-in `config` table; the table is never
    reassigned or replaced, and the existing `return config` (same object) is preserved (D-17).
  - Renumbered the subsequent `format_tab_title.apply(config)` step from 5 → 6 so the inline
    step numbering stays coherent.
- `tests/config/apply_test.lua`:
  - Added assertion 5b: `config.scrollback_lines == 50000` after `apply()` runs on a fresh
    config table.

### Task 2 — Sync to the installed copy (no repo files)

- Mirrored the installer's copy mechanism (`tools/setup.sh` STEP 4 uses
  `cp -R config/wezterm-setup/. ${SETUP_DIR}/`), scoped to the single changed file:
  `cp config/wezterm-setup/init.lua ~/.config/wezterm/wezterm-setup/init.lua`.
- Did NOT touch `~/.config/wezterm/wezterm.lua` (the user's top-level file) or the
  `~/.config/wezterm/wezterm-setup/scenes/` directory — both verified intact afterward.

## Verification

- `lua5.4 tests/config/apply_test.lua` → **exit 0**, all 10 assertions pass (including the new
  `config.scrollback_lines == 50000`).
- `grep -c 'local SCROLLBACK_LINES = 50000' config/wezterm-setup/init.lua` → **1**.
- `grep -c 'config.scrollback_lines = SCROLLBACK_LINES' config/wezterm-setup/init.lua` → **1**.
- `./tools/run-tests.sh` → **1 file failed**, and that failure is exactly the known
  out-of-scope baseline `cli/lib/recipe_test.lua → 2.9d ai.toml` (commit 723af62, `scenes/ai.toml`).
  No NEW failures introduced; every other suite green, including `apply_test`.
- `grep -c 'SCROLLBACK_LINES = 50000' ~/.config/wezterm/wezterm-setup/init.lua` → **1**
  (installed copy carries the change; WezTerm hot-reloads on next config touch).
- `~/.config/wezterm/wezterm.lua` has no `scrollback` reference (untouched); `scenes/` still
  holds `ai.toml`, `dev.toml`, `docker.toml`.

## Deviations from Plan

None - plan executed exactly as written. (Step numbering in `M.apply()` was bumped 5→6 for the
existing tab-title step to keep the inline comments coherent — a cosmetic comment-only adjustment
implied by inserting the new step, not a behavior change.)

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: config/wezterm-setup/init.lua (SCROLLBACK_LINES knob + apply() wiring)
- FOUND: tests/config/apply_test.lua (scrollback_lines == 50000 assertion)
- FOUND: ~/.config/wezterm/wezterm-setup/init.lua (synced copy carries the change)
- FOUND: commit 4817f43 (feat(quick-260618-dlc): raise scrollback_lines to 50000 via config knob)
