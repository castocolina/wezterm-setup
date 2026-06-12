# Plan 03-04 Summary — `wez tab` dynamic shell completion

**Phase:** 03-tab-identity
**Plan:** 03-04 (`tab-colors`/`tab-icons` completion contexts + zsh/bash generators)
**Status:** Complete
**Requirements touched:** TAB-01, TAB-03

## Goal

Give `wez tab color <Tab>` / `wez tab title <Tab>` dynamic value completion, mirroring the Phase 2
pane completion (02-05). Static subcommand/flag completion already flows from the spec walk (D-16);
this plan adds only the dynamic candidate sets, derived from the canonical tables (no duplication).

## What was built

**Task 1 — `cli/commands/complete.lua`.**
- Added `tab_colors()` (iterates `tab.COLOR_NAMES`, appends `reset`) and `tab_icons()` (sorted keys of
  the shared `cli/lib/title.lua` `ICONS`), registered as `tab-colors`/`tab-icons` in `CONTEXTS`.
- Candidates derive via `require` of `cli.commands.tab` / `cli.lib.title` — no inline literal list.

**Task 2 — `cli/commands/completions.lua`.**
- Added a `tab)` nested dispatch to BOTH `gen_zsh` and `gen_bash`, mirroring the `pane)` block, routing
  `color) → tab-colors` and `title) → tab-icons`. Everything static stays spec-driven.

## Verification

**Automated (run from repo root — the plan's `cd cli` cwd breaks `cli.*` requires):**
- `wez __complete tab-colors` → 11 lines (10 names + `reset`), matching `tab.COLOR_NAMES`.
- `wez __complete tab-icons` → 22 icon names, **byte-identical** to `wez __complete pane-icons` (both
  now from `cli/lib/title.lua`, D-03). Note: 22 icons — confirms the HIGH-1 review fix (not ~40).
- Unknown context (`bogus`) → no output, exit 0.
- Generated `wez.zsh` / `wez.bash` both contain `__complete tab-colors`/`tab-icons`; `zsh -n` and
  `bash -n` parse both clean. Pane completion still present (no regression).
- Full `./tools/run-tests.sh` → all 8 files pass.

**Live functional repro** (recorded in `docs/repro/h-tab-completion.md`):
Drove bash's `_wez` completion function directly (sourced the generated script, set `COMP_WORDS`,
inspected `COMPREPLY`) via a `wez`→`lua5.4 cli/wez.lua` shim (no `wez` on PATH here):
- `wez tab color <Tab>` → 10 profiles + `reset`.
- `wez tab title <Tab>` → 22 icon names.
- `wez pane color <Tab>` → unchanged (regression check).

## Note on the manual repro scope

The plan's manual step assumes an installed `wez` and an interactive shell. With no `wez` on PATH and
no interactive TTY, I used a forwarding shim + programmatic `_wez`/`COMPREPLY` drive — a functional
equivalent that exercises the real generated script and the real `__complete` backend end-to-end. The
zsh path is parse-verified (`zsh -n`) and uses the identical `__complete tab-*` backend; an
interactive zsh `compadd` press was not exercised headlessly.

## Commits

- `feat(03-04): add tab-colors + tab-icons __complete contexts`
- `feat(03-04): wire tab color/title dynamic completion (zsh + bash)`

## Files changed

- `cli/commands/complete.lua` — `tab-colors`/`tab-icons` providers + CONTEXTS entries
- `cli/commands/completions.lua` — `tab)` nested dispatch in zsh + bash generators
- `docs/repro/h-tab-completion.md` — NEW: recorded functional completion repro
