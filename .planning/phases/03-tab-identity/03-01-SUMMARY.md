# Plan 03-01 Summary — Tab-title formatter: parse + D-03a precedence

**Phase:** 03-tab-identity
**Plan:** 03-01 (tab-title formatter: `parse_tab_title` + handler rewire, TDD)
**Status:** Complete
**Requirements touched:** TAB-02, TAB-04, TAB-05

## Goal

Make `tab.tab_title` values of the form `"<color>:<title>"` (which `wez tab color`/`wez tab title`
will write in later plans) actually render, by (1) adding a pure parser and (2) rewiring the
`format-tab-title` handler to the D-03a resolution precedence. Without this, the rest of Phase 3
would write a value nothing reads.

## What was built

**Task 1 — `M.parse_tab_title(tab_title)` (pure helper).**
First-colon split per the LOCKED `tab-title-format.md` encoding: left = color, right = title (title
may itself contain `:`). Empty sides become `nil`. A no-colon non-empty token is the **color** with
no title (`parse_tab_title("blue")` → `("blue", nil)`) — the CRITICAL-1 review fix, consistent with
the UI-SPEC rendering matrix; an unknown bare color maps to the default profile downstream via
`resolve_profile`. Pure, no `wezterm` dependency, colocated with the other pure helpers.

**Task 2 — `format-tab-title` handler rewired to D-03a precedence.**
- **accent** = pane `WEZTERM_TAB_COLOR` (non-empty) → tab-prefix color → default profile (TAB-04 pane priority)
- **title** = pane `WEZTERM_TAB_TITLE` → tab-prefix title → `tab.active_pane.title` → `""`
- Empty-string pane var treated as unset, matching the existing title-fallback idiom.
- `format_label`/`build_runs`/`truncate_right` and the active-tab `●->` indicator (TAB-05) left untouched.
- Incidental: corrected the stale `build_runs` comment ("Active: navy/profile bg…" → "Active: profile bg…")
  flagged in `03-UI-SPEC.md`.

## Verification

`cd config/wezterm-setup && lua5.4 format-tab-title_test.lua` → **42 passed, 0 failed** (exit 0).

- Task 1: 7 `parse_tab_title` cases (17–23), including the locked bare-color case 18.
- Task 2: 5 precedence cases (24–28): tab-prefix accent+title, empty-color → default accent,
  empty-title → falls back to pane title, pane color overrides tab-prefix (TAB-04), active-tab
  indicator preserved (TAB-05). Pre-existing handler tests 12–16 still pass unchanged.
- Import-safety (D-17): `pcall(require, "wezterm")` guard intact; `M.apply({})` with a mocked
  `wezterm` registers the handler (test 11 passes).

TDD discipline followed per task: RED test commit → GREEN implementation commit, separately.

## Commits

- `test(03-01): add parse_tab_title fixture cases (RED)` — pre-existing working-tree RED, committed
- `feat(03-01): add parse_tab_title helper for <color>:<title> stored titles` — GREEN
- `test(03-01): add D-03a handler precedence cases (RED)`
- `feat(03-01): rewire format-tab-title handler for D-03a precedence` — GREEN + comment fix

## Notes for downstream plans

- The formatter now reads `"<color>:<title>"` from `tab.tab_title`. **03-02** (`wez tab color`) and
  **03-03** (`wez tab title`) must write exactly that encoding via `wezterm cli set-tab-title` for
  the accent/label to render. The dependency from 03-02 → 03-01 is end-to-end observability (you can
  only *see* a stored color through this formatter), not a build/test dependency.
- Pane `WEZTERM_TAB_COLOR`/`WEZTERM_TAB_TITLE` still win over the tab prefix (TAB-04) — verified by
  test 27.

## Files changed

- `config/wezterm-setup/format-tab-title.lua` — added `M.parse_tab_title`; rewired handler precedence; comment fix
- `config/wezterm-setup/format-tab-title_test.lua` — +12 fixture cases (parse + precedence)
