# Phase 2 (Pane Identity) — Plan Outline

| Plan ID | Objective | Wave | Depends On | Requirements |
|---------|-----------|------|------------|---------------|
| 02-01 | Spike per-pane opacity feasibility (D-03/D-06): probe `window:set_inner_size`/pane-scoped opacity APIs in `.tmp/h<NN>-perpane-opacity/`, document real-vs-fallback decision before any CLI wiring depends on it | 1 | — | PANE-01 |
| 02-02 | Add `format-tab-title` Lua handler + color-profile table to `config/wezterm-setup/`, AUGMENT-wired via `init.lua` apply() (D-17) — config-layer dependency for tab-bar accent visibility, no user-visible CLI yet | 1 | — | PANE-01, PANE-04 |
| 02-03 | Implement `wez pane color <name|hex>` + `wez pane color reset` (D-01: validate-before-emit, dual-write OSC 11 + OSC 1337) in `cli/commands/pane.lua` + `cli/spec.lua`, wired to color-profile table from 02-02; verify color persists across focus switches | 2 | 02-01, 02-02 | PANE-01, PANE-02 |
| 02-04 | Implement `wez pane title "<text>"` (D-04: freeform text+emoji and icon-name map, WEZTERM_TAB_TITLE override, respects per-pane opacity outcome from 02-01) in `cli/commands/pane.lua` + `cli/spec.lua`; verify title appears in tab bar when focused and survives focus switches without flicker | 3 | 02-03 | PANE-03 |
| 02-05 | Wire dynamic completion for `pane` surface (D-16): `__complete pane-colors` (named profiles) and `__complete pane-icons` (icon-name map) in `cli/commands/complete.lua`, plus `color reset`/`title` flag completion | 4 | 02-03, 02-04 | PANE-04 |
