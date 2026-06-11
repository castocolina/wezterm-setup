# Plan 02-03 Summary — `wez pane color` + reset

**Phase:** 02-pane-identity
**Plan:** 02-03
**Status:** Complete
**Requirements:** PANE-01 (set pane color), PANE-02 (reset), PANE-04 (persistence, live-verified)

## What shipped

- **`cli/commands/pane.lua`** (NEW) — the `wez pane color` command:
  - `M.COLOR_NAMES` (curated 10) + `M.MUTED_BG` (per-name OSC-11 background hex).
  - Pure, fixture-tested: `M.strip_alpha`, `M.normalize_color`, `M.validate_color`
    (validate-before-emit gate, D-01), `M.build_osc11`, `M.build_reset_osc11`,
    `M.build_osc1337` (pure-Lua base64), `M._base64`.
  - `M.OPACITY_SUPPORTED = false` per the **02-01 spike verdict** (WezTerm has no per-pane
    opacity — verdict grounded in the live Mux probe + WezTerm's window-scoped opacity API).
  - `M.run` / `M.run_color`: validate-before-emit → dual write (OSC 11 muted bg + OSC 1337
    `WEZTERM_TAB_COLOR`) → `reset` (OSC 111 + clear var) → opacity soft-degrade (strip alpha,
    warn once, exit 0). Single `emit` write sink keeps the D-05 seam for a future `--pane-id`.
- **`cli/spec.lua`** (MODIFIED) — `pane` registered in `SUBCOMMANDS` + `CATEGORIES` (`identity`);
  `build_parser` registers `pane color <value> [--opacity]` with `pane:command_target("pane_cmd")`
  so the top-level dispatcher still routes on `command == "pane"`.
- **`cli/commands/pane_test.lua`** (NEW) — 36 fixture assertions.

## Verification (autonomous — against a real WezTerm)

- **36/36 fixture assertions pass** (`lua5.4 cli/commands/pane_test.lua`): normalization,
  alpha-strip, validate-before-emit, OSC builders, base64, and `M.run` (invalid → exit 2 + no
  stdout; navy → exact dual-write bytes; rgba+`--opacity` → alpha stripped + warning; reset).
- **Full dispatcher path** (`lua5.4 cli/wez.lua pane color ...`): `navy` emits
  `OSC 11 ;#14151c` + `OSC 1337 SetUserVar=WEZTERM_TAB_COLOR=bmF2eQ==`; `fuschia` → exit 2,
  stderr error, **zero** stdout bytes; `#1a2040cc --opacity` → OSC-11 `#1a2040` (alpha stripped)
  + warning; `reset` → `OSC 111` + cleared var.
- **Live end-to-end:** spawned a real GUI WezTerm (loading the 02-02 config) with a
  `user-var-changed` logger, ran the real `wez pane color navy` and `... teal` inside a pane via
  `wezterm cli send-text`. The log recorded `WEZTERM_TAB_COLOR=navy` then `=teal` — proving the
  OSC 1337 reaches WezTerm and sets the exact var that 02-02's `format-tab-title` consumes
  (base64 decoded correctly). No handler errors.

Pixel-level appearance of the muted background is WezTerm's native OSC-11 rendering of
unit-verified hex; the mechanism is proven end-to-end against a live instance.

## Artifacts this phase produces

- `cli/commands/pane.lua` — `COLOR_NAMES`, `MUTED_BG`, `OPACITY_SUPPORTED`, `strip_alpha`,
  `normalize_color`, `validate_color`, `build_osc11`, `build_reset_osc11`, `build_osc1337`,
  `run_color`, `run`
- `cli/spec.lua` — `pane` subcommand (`color <value> [--opacity]`)
- User-var produced: `WEZTERM_TAB_COLOR` (consumed by 02-02)
- CLI surface: `wez pane color <name|hex|rgba|reset> [--opacity]`

## Notes

- `M.OPACITY_SUPPORTED=false` is the locked default from 02-01. If a future WezTerm adds
  per-pane opacity, only that constant + the apply branch change (the CLI already accepts input).
- `pane.lua` is extended by 02-04 (the `title` subcommand) — `M.run` already branches on
  `args.pane_cmd`.
