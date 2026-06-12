# Plan 03-03 Summary — `wez tab title` + shared icon resolver

**Phase:** 03-tab-identity
**Plan:** 03-03 (`wez tab title`, combined `--title`, shared `cli/lib/title.lua`)
**Status:** Complete
**Requirements touched:** TAB-03

## Goal

Ship the title half of `wez tab`: standalone `wez tab title "<text>"`, the combined
`wez tab color <name> --title "<text>"`, and icon-name parity with `wez pane title` — all routed
through a NEW shared `cli/lib/title.lua` so the icon map lives in exactly one place (D-03).

## What was built

**Task 1 — `cli/lib/title.lua` (shared resolver, TDD).**
- `M.ICONS` + `M.resolve_title(words)` lifted **verbatim** from `pane.lua` (byte-identical — verified
  by diffing the maps).
- NEW `M.resolve_title_str(s)` for the single-string `--title` flag: splits first token from rest,
  then behaves like `resolve_title` (icon glyph + rest, `reset`/empty → "", else trimmed input).
- Pure — no `wezterm`/`io`/`os`.

**Task 2 — pane.lua refactor (no behavior change).**
- `pane.lua` now `require("cli.lib.title")` and re-exports `M.ICONS = title.ICONS` /
  `M.resolve_title = title.resolve_title`; the local 22-entry map + function body are deleted.
- `pane_test.lua` (49 assertions) passes unchanged — `wez pane title` is byte-identical.

**Task 3 — tab title + combined form (TDD + spec).**
- `M.run_title` — resolve via shared lib → read → `merge_title{set_title=resolved}` → write (keeps
  color; empty/reset clears the title → `"color:"`).
- `M.run_color` extended: when `args.title` is present, resolve via `resolve_title_str` and pass BOTH
  `set_color` and `set_title` into one `merge_title` + one `set-tab-title` write (TAB-03 combined).
- `M.run` dispatches `tab_cmd == "title"`.
- `cli/spec.lua`: added the `tab title` subcommand (`words:args("*")`) and `--title` on `tab color`.

## Deviation from plan (recorded)

Task 3's action text said `tab_color:flag("--title", ...)`, but the plan's own behavior + verification
require `result.title == "api"` (a captured value). A `:flag` is a boolean switch and cannot carry a
value, so I used **`tab_color:option("--title", ...)`** — the only form that makes
`wez tab color blue --title api` work. Functionally correct per the behavior spec; differs only from
the literal `:flag` token in the action prose.

## Verification

**Automated:**
- `lua5.4 cli/lib/title_test.lua` → **19 passed, 0 failed** (resolve_title ports + resolve_title_str + ICONS glyphs).
- `lua5.4 cli/commands/tab_test.lua` → **23 passed, 0 failed** (added both-halves merge cases 20–22).
- `lua5.4 cli/commands/pane_test.lua` → **49 passed, 0 failed** (refactor, no regression).
- Spec parse: `{tab,title,docker,up}` → `tab_cmd=title, words={docker,up}`;
  `{tab,color,blue,--title,api}` → `value=blue, title=api`. `tests/cli/spec_test.lua` green.
- Full `./tools/run-tests.sh` → all 8 files pass.

**Live manual repro** (appended to `docs/repro/h-tab-color.md`, real session):
- `wez tab title api` on `blue:old` → `blue:api` (D-01, color kept).
- `wez tab title docker compose up` → `blue:🐳 compose up` (D-03 icon parity).
- `wez tab title reset` → `blue:` (D-04, color kept).
- `wez tab color green --title api` (fresh) → `green:api` (TAB-03, one write).

## Commits

- `test(03-03): add cli/lib/title.lua resolver fixtures (RED)`
- `feat(03-03): add shared cli/lib/title.lua icon resolver` (GREEN)
- `refactor(03-03): pane.lua sources icon resolver from cli/lib/title.lua`
- `feat(03-03): wez tab title + combined --title via shared resolver`

## Notes for downstream plans

- **03-04** (tab completion) is spec-driven (D-16): the `tab`/`color`/`title` surface is already in
  `cli/spec.lua`, so completion should pick it up without a generator edit. The dynamic value
  completion (color names) mirrors `wez pane color`'s `__complete` context.

## Files changed

- `cli/lib/title.lua`, `cli/lib/title_test.lua` — NEW shared resolver + tests
- `cli/commands/pane.lua` — sources icon resolver from the lib (re-export)
- `cli/commands/tab.lua`, `cli/commands/tab_test.lua` — `run_title` + combined `--title`
- `cli/spec.lua` — `tab title` subcommand + `--title` option
- `docs/repro/h-tab-color.md` — appended 03-03 live repro
