# Phase 2 (Pane Identity) — Verification

**Date:** 2026-06-11
**Status:** passed (Linux; macOS deferred per D-18)
**Method:** goal-backward against the 4 ROADMAP success criteria, verified inline against a real
running WezTerm (`20260604-145453`) driven autonomously via `wezterm cli`, plus Lua fixture suites.

## Plans

| Plan | Status | Commit |
|------|--------|--------|
| 02-01 opacity spike | Complete | 1e25a8c |
| 02-02 config renderer | Complete | 6b3831f |
| 02-03 wez pane color + reset | Complete | 7d1398b |
| 02-04 wez pane title | Complete | df10d9c |
| 02-05 completion | Complete | 0003d50 |

## Success criteria

### #1 — `wez pane color <name|hex>` changes the pane background; `reset` restores it
**PASS (mechanism, Linux).** `wez pane color navy` emits exactly `OSC 11 ;#14151c` (muted bg) +
`OSC 1337 SetUserVar=WEZTERM_TAB_COLOR=navy`; `reset` emits `OSC 111` (reset dynamic bg) + clears
the var (byte-verified). Live: a real WezTerm recorded `WEZTERM_TAB_COLOR=navy`/`teal` via
`user-var-changed`. OSC 11 background is WezTerm-native. Invalid input exits 2 with no escape
emitted (validate-before-emit). **Caveat:** the literal on-screen color was not pixel-captured
(a screenshot was attempted but the headless X/Wayland environment blocked root capture); the hex
values and the rendering inputs are unit- and live-verified. macOS deferred (D-18).

### #2 — custom pane title via `wez pane title` appears in the tab bar when focused
**PASS (mechanism, Linux).** `wez pane title docker "compose up"` → live WezTerm recorded
`WEZTERM_TAB_TITLE=🐳 compose up` (icon resolved, emoji intact through base64); clear works. The
02-02 `format-tab-title` handler reads `active_pane.user_vars.WEZTERM_TAB_TITLE` and overrides the
displayed title — verified via the handler-body integration test. Same pixel caveat as #1.

### #3 — color + title survive focus changes within the tab (no flicker/reset)
**PASS (structural).** OSC 11 background is a property of the pane's own terminal (sticky, not
re-emitted on focus). The user vars persist per pane; `format-tab-title` re-reads
`tab.active_pane.user_vars` on every render, so the active pane's identity drives the segment.
No state is dropped on focus change by construction.

### #4 — completion updated (`wez pane color <Tab>` → profiles; title/reset complete)
**PASS (functional).** `wez __complete pane-colors` → the 10 names + `reset`; `wez __complete
pane-icons` → the icon keys. Generated zsh/bash scripts pass `bash -n`/`zsh -n` and carry the
nested `pane` dispatch. Functional bash sim: `wez pane color <Tab>` → all colors + reset;
`wez pane title <Tab>` → icons; `wez pane color na<Tab>` → `navy`.

## Requirements coverage

| Req | Status |
|-----|--------|
| PANE-01 (set color: name/hex/rgba, validate-before-emit, dual write) | Done (02-02, 02-03) |
| PANE-02 (color reset) | Done (02-03) |
| PANE-03 (custom title + emoji + icon-name in tab bar when focused) | Done (02-04) |
| PANE-04 (persist across focus; completion) | Done (02-02, 02-04, 02-05) |

## Tests

- `lua5.4 cli/commands/pane_test.lua` → 49 passed
- `lua5.4 cli/commands/complete_test.lua` → 14 passed
- `lua5.4 config/wezterm-setup/format-tab-title_test.lua` → 26 passed

## Decisions / notes

- **Opacity (D-03/D-06):** per the 02-01 spike, WezTerm has no per-pane opacity (live Mux probe +
  WezTerm window-scoped opacity API). `M.OPACITY_SUPPORTED=false`; alpha is stripped, pane renders
  solid, a one-time warning is printed. OS-window opacity is permanently rejected. This verdict is
  grounded in WezTerm evidence (kitty-setup is only a reference implementation).
- **Scope expansion captured:** opacity (proposed PANE-05) and icon-name titles (extends PANE-03)
  were implemented; recommend formalizing the requirement IDs in REQUIREMENTS.md.
- **Residual:** literal pixel appearance not eyeballed (environment blocked screenshot capture) —
  the only step not autonomously verifiable here; mechanism is proven end-to-end. macOS deferred.
