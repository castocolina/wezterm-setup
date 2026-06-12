# Manual repro — `wez tab` dynamic shell completion (Plan 03-04)

**Date:** 2026-06-12
**Verifies:** ROADMAP Phase 3 success #5 (tab completion), D-16 (spec-driven), D-03 (shared icon map).

## Method

`wez` is not installed on PATH in this environment, so a shim forwarding to `lua5.4 cli/wez.lua`
stands in. The generated `wez.bash` is sourced and bash's completion function `_wez` is driven
directly (set `COMP_WORDS`/`COMP_CWORD`, call `_wez`, inspect `COMPREPLY`) — a functional repro of
what Tab expansion produces, without an interactive terminal. The zsh script is parse-verified
(`zsh -n`) and routes to the same `wez __complete tab-*` backend.

## Observed

| Completion point | COMPREPLY |
|------------------|-----------|
| `wez tab color <Tab>` | `red orange yellow green teal cyan blue navy purple pink reset` (11) |
| `wez tab title <Tab>` | `ai alert build config db debug deploy docker edit fire git go k8s log node python rust search server shell ssh test` (22 icon names) |
| `wez pane color <Tab>` (regression) | `red orange yellow green teal cyan blue navy purple pink reset` — unchanged |

Generated-script checks:
- `wez completions zsh` contains `wez __complete tab-colors` / `tab-icons` in a `tab)` nested
  dispatch; `zsh -n` parses clean.
- `wez completions bash` contains the same two `__complete tab-*` calls in a `tab)` case;
  `bash -n` parses clean.

## Verdict

- `wez tab color <Tab>` offers the named profiles + `reset`; `wez tab title <Tab>` offers the icon
  shortcuts. ✓
- Candidates derive from `tab.COLOR_NAMES` + `cli/lib/title.lua` `ICONS` (the same tables the commands
  use) — no second hardcoded list; `tab-icons` is byte-identical to `pane-icons` (D-03). ✓
- Pane completion is unaffected. ✓
