# Plan 03-02 Summary — `wez tab color` CLI surface

**Phase:** 03-tab-identity
**Plan:** 03-02 (`wez tab color <name|hex>` / `reset`, read-modify-write)
**Status:** Complete
**Requirements touched:** TAB-01, TAB-02

## Goal

Ship the first half of the `wez tab` namespace: set a tab's accent color by writing the proven
`"<color>:<title>"` prefix to the tab's stored title via `wezterm cli set-tab-title`, preserving any
existing title (D-01 read-modify-write). The accent then renders through the Plan 03-01 formatter.

## What was built

**Task 1 — pure helpers (`cli/commands/tab.lua`, TDD).**
- `M.validate_color` — validate-before-emit gate (D-06): the 10 curated names (case-insensitive),
  hex (`#rgb`/`#rrggbb`, alpha stripped), and `reset`; unknown input returns `(false, error)`. Ported
  from `pane.lua` minus the opacity/muted-bg/OSC concerns.
- `M.parse_stored` — first-colon split (locked `tab-title-format.md`), empty sides → nil, bare token
  is the color (`"blue"` → `("blue", nil)`).
- `M.merge_title` — read-modify-write builder; the colon is ALWAYS present (D-02); `set_color=""`
  clears the color (reset).

**Task 2 — I/O layer (D-05 seam).**
- `M.read_current_tab` — `wezterm cli list --format json` via `io.popen` + vendored dkjson; picks the
  `is_active` entry; degrades to `{tab_id=nil, tab_title=""}` on no session / decode failure.
- `M.write_tab_title(str, tab_id)` — `wezterm cli set-tab-title` with a shell-quoted arg; `tab_id` is
  the D-05 seam (always called nil this phase → active tab).
- `M.run_color` — validate → (bail before any read/write on invalid) → read → parse → merge → write.
- `M.run` — dispatches `args.tab_cmd == "color"`; `title` reserved for 03-03.
- The ONLY subprocess calls are in `read_current_tab`/`write_tab_title` (verified by grep) — the pure
  helpers stay subprocess-free and unit-testable.

**Task 3 — spec wiring (`cli/spec.lua`).**
- Added `tab` to `CATEGORIES` (`identity`) and `SUBCOMMANDS` (the closed allow-list the dispatcher
  reads), plus the `tab` → `color <value>` parser block mirroring `pane`. `cli/wez.lua` unmodified —
  `tab` dispatches through the existing allow-list + `-`→`_` module mapping. No `--title`/`title`
  surface yet (reserved for 03-03).

## Verification

**Automated:**
- `lua5.4 cli/commands/tab_test.lua` → **20 passed, 0 failed** (validate_color/parse_stored/merge_title,
  including the always-one-colon structural checks).
- Spec parse: `{"tab","color","blue"}` → `command=tab, tab_cmd=color, value=blue`.
- `tab` present in `subcommand_names()` (dispatcher allow-list).
- Full suite `./tools/run-tests.sh` → **all 8 files passed**; colocated `pane_test`,
  `format-tab-title_test` still green (no regressions).

**Live manual repro** (recorded in `docs/repro/h-tab-color.md`, real WezTerm session):
- `wez tab color blue` on stored `green:api` → `blue:api` (exit 0) — color swapped, title kept (D-01).
- `wez tab color reset` on `blue:api` → `:api` (exit 0) — accent cleared, title kept (D-04).
- `wez tab color mauve` → stderr error, exit 2, stored `green:api` **unchanged** (D-06, no write ran).

## Commits

- `test(03-02): add validate_color/parse_stored/merge_title fixtures (RED)`
- `feat(03-02): add tab.lua pure helpers (validate_color/parse_stored/merge_title)` (GREEN)
- `feat(03-02): tab color read-modify-write I/O + run_color dispatch`
- `feat(03-02): register tab namespace + color subcommand in spec`

## Notes for downstream plans

- **03-03** adds `wez tab title <words>` and the combined `wez tab color <name> --title <words>` —
  it extends `M.run` with a `title` branch (and a `--title` flag on the spec `color` subcommand), and
  introduces the shared `cli/lib/title.lua` icon resolver. The `set_title` arm of `merge_title` is
  already wired and waiting; `run_color`/`merge_title` need no change for the title-only path.
- The `tab_id` seam in `write_tab_title` is the Phase 4 (`--tab-id`) drop-in point; do not widen it here.
- `depends_on: ["03-01"]` is end-to-end observability ordering — 03-02's own tests + repro are
  formatter-independent (confirmed: they pass without inspecting the rendered bar).

## Files changed

- `cli/commands/tab.lua` — NEW: pure helpers + I/O layer + dispatch
- `cli/commands/tab_test.lua` — NEW: 20 fixture cases
- `cli/spec.lua` — `tab` namespace + `color` subcommand; allow-list + category entries
- `docs/repro/h-tab-color.md` — NEW: recorded live repro
