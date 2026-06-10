---
phase: 01-foundation
plan: 03
subsystem: config-layer
tags: [lua, keybindings, cwd, osc7, shell-integration, augment-model]
requires:
  - "Phase 0 cwd-mechanism decision (OSC 7 primary + OS-read backstop)"
  - "Phase 0 wezterm-cli-surface audit (available pane/tab actions)"
provides:
  - "require('wezterm-setup').apply(config) augment entry point (INST-01, D-17)"
  - "Curated mapped: keybinding table + disabled-defaults list as data (FOUND-02..05)"
  - "OSC 7 cwd reporters for bash and zsh (FOUND-01)"
  - "keybindings.lua contract consumed by wez keys (Plan 05)"
affects:
  - "Plan 04 installer: sources shell-integration files + injects sentinel apply() call"
  - "Plan 05 wez keys: classifies live table against keybindings.lua + disabled_defaults"
tech-stack:
  added: []
  patterns:
    - "R3 composable topic files behind one apply() entry point"
    - "Declarative action specs in keybindings.lua resolved to wezterm.action in init.lua (testable under plain lua5.4)"
    - "Augment-by-reference: apply(config) mutates and returns the same table"
key-files:
  created:
    - config/wezterm-setup/init.lua
    - config/wezterm-setup/keybindings.lua
    - config/wezterm-setup/cwd.lua
    - config/wezterm-setup/shell-integration/osc7.sh
    - config/wezterm-setup/shell-integration/osc7.zsh
    - tests/config/keybindings_test.lua
    - tests/config/apply_test.lua
  modified: []
decisions:
  - "Replaced README backslash split chord (Alt+Shift+\\) with layout-stable Alt+Shift+H/V (D-10)"
  - "Action specs kept declarative in keybindings.lua so the module loads standalone under lua5.4"
  - "cwd.lua apply() is intentionally a no-op augment (inheritance is WezTerm default)"
metrics:
  duration: ~4 min
  completed: 2026-06-09
  tasks: 3
  files: 7
---

# Phase 1 Plan 03: Config Layer (augment entry point, keybindings, cwd, OSC 7) Summary

Pure-Lua config layer shipping the non-destructive `require('wezterm-setup').apply(config)` augment entry point (D-17), a curated layout-stable `mapped:` keybinding table with explicit disabled-defaults, and idempotent OSC 7 cwd reporters for bash and zsh that mechanize Linux cwd inheritance (FOUND-01).

## What Was Built

- **`config/wezterm-setup/keybindings.lua`** — single source of truth: `key_map_preference="Mapped"` (D-09), a curated key table covering every FOUND-03 category (tabs, panes, font zoom, word nav), the locked `Super+K`/`Cmd+K` clear-screen-and-scrollback binding (FOUND-02), and a `disabled_defaults` list (D-12). All chords are layout-stable (letters/digits/named keys); no bracket/brace/slash/backslash/semicolon (D-10). Cmd-vs-Super is the only platform delta (FOUND-05, D-18). Returned as data so both `apply()` and `wez keys` (Plan 05) consume the same source.
- **`config/wezterm-setup/init.lua`** — `M.apply(config)`: requires `keybindings` + `cwd`, sets `key_map_preference`, **appends** our key bindings to the user's existing `config.keys` (never reassigns — T-03-01), adds `DisableDefaultAssignment` entries for replaced defaults, applies cwd, and returns the **same** mutated config object (augment, never replace — D-17). Import-safe under plain lua5.4 (the `wezterm` global is optional; action specs stay declarative when it is absent).
- **`config/wezterm-setup/cwd.lua`** — `M.apply(config)` intentional no-op: cwd inheritance is WezTerm default; the shipped OSC 7 integration supplies the accurate cwd. No custom split/spawn handler (cwd-mechanism.md).
- **`config/wezterm-setup/shell-integration/osc7.sh` / `osc7.zsh`** — emit `ESC]7;file://HOST/<url-encoded-path>ST` on each prompt (bash `PROMPT_COMMAND`) / prompt + dir change (zsh `precmd`/`chpwd`). TTY-guarded (T-03-02), single fast printf with no hot-path subshell (T-03-03), idempotent registration, builtin URL-encoding, no `/proc`, no GNU-only flags (D-18).
- **Tests** — `keybindings_test.lua` (9 assertions) and `apply_test.lua` (5 assertions), both green under `lua5.4`.

## How It Works

The installer (Plan 04) will source the shell-integration files from the user's rc and inject a sentinel block that calls `require('wezterm-setup').apply(config)` before the user's `return config`. Because `apply` mutates the passed table by reference, the user's config variable NAME is irrelevant (R6 probe verdict: `holds`). The OSC 7 emitters make WezTerm read the active pane's cwd (`file://HOST/path`), so new tabs/panes inherit it via WezTerm's default split/spawn behavior.

## Verification

| Check | Result |
|-------|--------|
| `lua5.4 tests/config/keybindings_test.lua` | exit 0, 9/9 assertions pass |
| `lua5.4 tests/config/apply_test.lua` | exit 0, 5/5 assertions pass |
| `apply` returns same table, adds `key_map_preference="Mapped"` + non-empty `keys` | verified |
| User's pre-existing field + key binding survive `apply` | verified (T-03-01) |
| No forbidden punctuation chord | test-enforced (D-10) |
| bash/zsh emitters source cleanly, emit `file://host/path` over a pty | verified (`file://pop-os/tmp/wez%20sp` with URL-encoding) |
| bash re-source → 1 `PROMPT_COMMAND` hook; zsh → 1 precmd + 1 chpwd | verified (idempotent) |
| No `/proc`, no GNU-only flags | verified (rg scan) |

macOS cwd + keybinding re-verification deferred to the Mac pass (D-18).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Spec adherence] README keybinding draft violated D-10**
- **Found during:** Task 1
- **Issue:** The README draft chord table used `Alt+Shift+\` (split horizontal) — backslash is a forbidden punctuation key under D-10. `Alt+-` (split vertical) reused a key wanted for font zoom.
- **Fix:** Substituted layout-stable letter chords `Alt+Shift+H` (split horizontal) / `Alt+Shift+V` (split vertical); font zoom keeps `+`/`-`/`0` (named/digit keys, D-10-allowed). Substitution recorded in a comment at the top of `keybindings.lua` as the plan instructed.
- **Files modified:** `config/wezterm-setup/keybindings.lua`
- **Commit:** 0d96c5c

No other deviations — plan executed as written.

## R6 Probe (scratch, gitignored)

`.tmp/probes/phase-1/03-config-var-name.md` — verdict **`holds`**: taking `config` as the `apply(config)` parameter and mutating by reference sidesteps the user-config-variable-name-varies risk flagged in D-17. Per R6, the finding is encoded into `init.lua` source comments at the call site; the scratch probe stays in gitignored `.tmp/` (project rule).

## Known Stubs

`cwd.lua :: apply()` returns the config unchanged. This is **intentional, not a stub**: cwd inheritance is WezTerm default behavior (cwd-mechanism.md) and the OSC 7 shell integration supplies the cwd. The module is the documented seam for any future intentional cwd policy. No data-wiring gap exists.

## Self-Check: PASSED

- All 7 created files exist on disk (verified).
- All 3 task commits exist: 0d96c5c, 695aa6b, 87e79ca (verified via git log).
- Both test suites exit 0.
