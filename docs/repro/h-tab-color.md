# Manual repro — `wez tab color` (Plan 03-02)

**Date:** 2026-06-11
**WezTerm session:** live session reachable (`wezterm cli list` OK)
**Verifies:** TAB-01 (set tab accent), D-01 (read-modify-write), D-04 (reset keeps title),
D-06 (validate-before-emit), D-05 (current tab only).

## Method

Drive `wez tab color` through the dispatcher (`lua5.4 cli/wez.lua tab color <v>`) against a live
WezTerm tab seeded with a known stored title, reading back the active tab's `tab_title` from
`wezterm cli list --format json` after each command.

## Observed

| Step | Command | tab_title before | tab_title after | Exit |
|------|---------|-------------------|-----------------|------|
| seed | `wezterm cli set-tab-title "green:api"` | — | `green:api` | — |
| recolor | `wez tab color blue` | `green:api` | `blue:api` | 0 |
| reset | `wez tab color reset` | `blue:api` | `:api` | 0 |
| invalid | `wez tab color mauve` | `green:api` (reseeded) | `green:api` (unchanged) | 2 |

Invalid-color stderr:

```
wez tab color: unknown color "mauve" — expected one of: red, orange, yellow, green, teal, cyan, blue, navy, purple, pink, a hex value (#rgb / #rrggbb), or "reset"
```

## Verdict

- **D-01 read-modify-write:** recolor swapped only the color half (`green`→`blue`), preserving `api`. ✓
- **D-04 reset:** cleared the accent, kept the title (`:api`). ✓
- **D-06 validate-before-emit:** unknown color exited 2 with an error and left `tab_title` untouched —
  no `set-tab-title` ran (the stored `green:api` was unchanged). ✓
- **D-05 current-tab-only:** the active tab (`tab_id=0`) was targeted with no `--tab-id`. ✓

The written `"blue:api"` renders the blue accent + `api` label through the Plan 03-01 formatter
(`format-tab-title.lua`, parse_tab_title → resolve_profile), which is covered by 03-01's handler
precedence tests 24–28.

---

# Manual repro — `wez tab title` + combined `--title` (Plan 03-03)

**Date:** 2026-06-11 · live session reachable
**Verifies:** TAB-03 (set tab title), D-01 (read-modify-write keeps color), D-03 (icon-name parity),
D-04 (reset keeps color).

| Step | Command | tab_title before | tab_title after | Exit |
|------|---------|-------------------|-----------------|------|
| title swap | `wez tab title api` | `blue:old` | `blue:api` | 0 |
| icon parity | `wez tab title docker compose up` | `blue:api` | `blue:🐳 compose up` | 0 |
| reset | `wez tab title reset` | `blue:🐳 compose up` | `blue:` | 0 |
| combined | `wez tab color green --title api` | `` (fresh) | `green:api` | 0 |

## Verdict

- **D-01:** `wez tab title api` swapped only the title half, keeping the `blue` accent. ✓
- **D-03:** the `docker` leading token resolved to 🐳 — identical to `wez pane title`, now via the
  shared `cli/lib/title.lua`. ✓
- **D-04:** `wez tab title reset` cleared the title, kept the color (`blue:`). ✓
- **TAB-03 combined:** `wez tab color green --title api` set both halves in a single `set-tab-title`
  write (`green:api`). ✓
