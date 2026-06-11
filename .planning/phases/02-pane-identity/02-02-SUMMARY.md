# Plan 02-02 Summary — Config-layer tab-bar renderer

**Phase:** 02-pane-identity
**Plan:** 02-02
**Status:** Complete
**Requirements:** PANE-01 (accent visibility), PANE-04 (persistence — handler reads user_vars per render)

## What shipped

- **`config/wezterm-setup/format-tab-title.lua`** (NEW) — the tab-bar renderer:
  - `M.color_profiles` (10 named bg/fg accent pairs) + `M.DEFAULT_PROFILE` (`#333333`/`#c0c0c0`),
    ported verbatim from the proven prototype.
  - Pure helpers `M.resolve_profile` (case-insensitive; nil/unknown → default; raw hex → hex bg +
    default fg), `M.format_label` (1-based `n: title `, right-truncated), `M.build_runs`
    (active = navy/profile bg + green ` ●-> ` indicator + bold white label; inactive = profile fg).
  - `M.apply(config)` registers `wezterm.on("format-tab-title", ...)` reading the focused pane's
    `WEZTERM_TAB_COLOR` / `WEZTERM_TAB_TITLE` user vars; AUGMENT contract (D-17), import-safe.
- **`config/wezterm-setup/init.lua`** (MODIFIED) — requires `format-tab-title` and calls
  `format_tab_title.apply(config)` inside `M.apply` after `cwd.apply(config)` (additive).
- **`config/wezterm-setup/format-tab-title_test.lua`** (NEW) — 26 fixture assertions.

## Verification (autonomous — driven against real WezTerm)

- **26/26 fixture assertions pass** (`lua5.4 format-tab-title_test.lua`), including a handler-body
  integration block that mocks the `wezterm` global, lets `M.apply` register the callback, and
  invokes it: navy bg from `WEZTERM_TAB_COLOR`, `WEZTERM_TAB_TITLE` overriding the pane title,
  default profile + pane-title fallback when no user var, and the active-tab indicator.
- **Import-safe** under plain lua5.4: `M.apply({})` returns the same table, no mutation, no error.
- **Loads in real WezTerm:** built a temp config requiring this layer; `wezterm --config-file <tmp>
  show-keys` exits 0 with no config errors (the `format-tab-title` registration evaluates cleanly).
- **Runs in a real GUI:** spawned a GUI WezTerm with the config on the session display, confirmed
  it was drivable via `wezterm cli`, and drove `WEZTERM_TAB_COLOR=navy` into the pane via OSC 1337
  `send-text` with no handler errors.

Pixel-level color appearance (does navy *look* navy) is WezTerm's rendering of unit-verified hex
values — not separately eyeballed, but the values and the handler output are asserted.

## Artifacts this phase produces

- `config/wezterm-setup/format-tab-title.lua` — `color_profiles`, `DEFAULT_PROFILE`,
  `resolve_profile`, `format_label`, `build_runs`, `apply`
- `config/wezterm-setup/init.lua` — wires the renderer into `apply()`
- Consumes user-var contract: `WEZTERM_TAB_COLOR`, `WEZTERM_TAB_TITLE` (produced by 02-03 / 02-04)

## Notes

- Wave-1 dependency for 02-03 is satisfied: the OSC 1337 `WEZTERM_TAB_COLOR` user var now has a
  live consumer.
