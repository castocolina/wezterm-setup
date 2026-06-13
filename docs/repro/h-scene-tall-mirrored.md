# Manual repro — `wez scene new --layout tall:mirrored` (Plan 04-02)

**Date:** 2026-06-13
**WezTerm session:** Isolated headless `wezterm-mux-server` (XDG_RUNTIME_DIR=/tmp/wez-e2e, minimal
config, `zsh -f` panes), driven via `lua5.4 cli/wez.lua scene new ...`; topology from
`wezterm cli list --format json`. Rendered colors confirmed visually in a live GUI session.
**Verifies:** SCEN-01 (live build), D-02 (tall:mirrored geometry — main pane on the RIGHT),
D-05 (tab + per-pane styling), D-07 (titles), D-08 (startup-cmd persistence), D-09 (clean panes),
focus on main pane.

## Method

From a tab with **≥2 panes** (new-tab path), run the same N=3 spec as `h-scene-tall.md` but with
the mirrored layout:

```
wez scene new --layout tall:mirrored \
  --pane 'cmd=htop,color=red,title=Monitor' \
  --pane 'cmd=echo hello,color=blue' \
  --pane shell \
  --color teal --title "Dev Scene"
```

## Expected behavior

- Same as `h-scene-tall.md` EXCEPT geometry is **mirrored**: the 50% main pane is on the
  **right**, the two stacked panes are in the **left** 50%. Split plan: `--right 50%` off
  pane 0 (the only `--left`/`--right` difference from `tall`), then `--bottom 50%`.
- Pane 1 = the right-hand main pane (red, `Monitor`, htop, persists, focused).
- Panes 2/3 stacked on the left (blue auto-titled `echo` pane; untouched `shell` pane).
- Tab accent `teal` + title `Dev Scene`.
- **D-09 clean-pane bar** holds for every pane.
- **Focus** on **pane 1** (the right-hand main pane).

## Observed

Run from a 2-pane tab (new-tab path), same window. Resulting tab topology:

```
tab3 (3 panes)  tab_title='teal:Dev Scene'
  pane 8  col=  0 row= 0  40x11  active=False  <- stack top, LEFT
  pane 9  col=  0 row=12  40x12  active=False  <- stack bottom, LEFT
  pane 7  col= 41 row= 0  39x24  active=True   <- main, RIGHT, full height, focused
```

- **Geometry mirrored:** the main pane (pane 7) is on the **right** (col 41, full 24-row height),
  the two stacked panes are in the **left** 50% (col 0, rows 0–10 and 12–23). This is the exact
  mirror of `tall` and the ONLY difference from it — confirming the `--left`/`--right` first-split
  swap (commit cab0a55).
- **Tab styling (D-05):** `tab_title='teal:Dev Scene'`.
- **Focus:** on the right-hand main pane (pane 7 `active=True`).
- **D-09 / colors:** same clean-pane + per-pane color result as `h-scene-tall.md` (shared styling
  path); rendered colors confirmed in the live GUI session.

## Verdict

**PASS.** The `--left`/`--right` swap produced a right-side main pane; everything else is identical
to `tall`. No deviation.
