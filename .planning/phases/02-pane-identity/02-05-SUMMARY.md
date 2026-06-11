# Plan 02-05 Summary — Completion for the `pane` surface

**Phase:** 02-pane-identity
**Plan:** 02-05
**Status:** Complete
**Requirements:** PANE-04 (completion updated — success criterion #4)

## What shipped

- **`cli/commands/complete.lua`** (MODIFIED) — two new `__complete` contexts, sourced from the
  canonical tables in `cli/commands/pane.lua` (single source of truth, no duplicated literals):
  - `pane-colors` → the 10 curated color names + `reset`.
  - `pane-icons` → the icon-name keys (sorted, stable).
- **`cli/commands/completions.lua`** (MODIFIED) — nested `pane` dispatch added to both `gen_zsh`
  and `gen_bash`: `wez pane color <Tab>` shells out to `wez __complete pane-colors`,
  `wez pane title <Tab>` to `wez __complete pane-icons`, else offers `color`/`title`. (`pane`
  has no top-level flags, so the generic flag loop emits no conflicting `pane)` arm.)
- **`cli/commands/complete_test.lua`** (NEW) — 14 assertions for the new contexts.
- Static completion of `pane`, `color`, `title`, `--opacity`, `reset` flows automatically from
  the `cli/spec.lua` registration (D-16) — no duplication.

## Verification (autonomous — functional)

- **complete_test: 14/14 pass** — `pane-colors` (10 names + reset, derived from
  `pane.COLOR_NAMES`), `pane-icons` (sorted, matches `pane.ICONS`), unknown context → empty +
  exit 0, and a regression that `subcommands` now includes `pane` and excludes `__complete`.
- **Dynamic contexts:** `wez __complete pane-colors` → `red … pink reset`;
  `wez __complete pane-icons` → the sorted icon names.
- **Generated scripts** pass `bash -n` and `zsh -n`; both contain the `pane)` arm calling
  `wez __complete pane-colors` / `pane-icons`.
- **Functional (real bash):** sourced the generated `wez.bash` with `wez` on PATH and simulated:
  - `wez pane color <Tab>` → `red orange yellow green teal cyan blue navy purple pink reset`
  - `wez pane title <Tab>` → the icon names
  - `wez pane color na<Tab>` → `navy` (prefix filtering works)
- **Single source of truth:** no hardcoded color/icon list exists in the completion modules
  (grep-verified) — they derive from `pane.lua`.

## Artifacts this phase produces

- `cli/commands/complete.lua` — `pane-colors` / `pane-icons` `__complete` contexts
- `cli/commands/completions.lua` — nested `pane color` / `pane title` dispatch in zsh + bash
- `cli/commands/complete_test.lua` — context fixtures
- CLI surface: `wez __complete pane-colors`, `wez __complete pane-icons`

## Notes

- Adding the `pane` namespace to `spec.lua` (02-03/02-04) made it appear in the static
  subcommand completion automatically (D-16) — this plan only added the dynamic value contexts +
  the nested dispatch.
