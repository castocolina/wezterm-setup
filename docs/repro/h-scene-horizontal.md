# Manual repro — `wez scene new --layout horizontal` (Plan 04-02)

**Date:** 2026-06-13
**WezTerm session:** Isolated headless `wezterm-mux-server` (XDG_RUNTIME_DIR=/tmp/wez-e2e, minimal
config, `zsh -f` panes), driven via `lua5.4 cli/wez.lua scene new ...`; topology from
`wezterm cli list --format json`. Rendered colors confirmed visually in a live GUI session.
**Verifies:** SCEN-01 (live build), D-02 (horizontal geometry, equal-width invariant),
D-09 (clean panes), focus on pane 1.

## Method

From a tab with **≥2 panes** (new-tab path), run an **N=4** horizontal scene:

```
wez scene new --layout horizontal \
  --pane 'cmd=echo a,color=red' \
  --pane 'cmd=echo b,color=green' \
  --pane 'cmd=echo c,color=blue' \
  --pane 'cmd=echo d,color=purple'
```

## Expected behavior

- **4 equal-width panes side-by-side**, each 25% width. Equal-share split percent sequence is
  `[25, 33, 50]` (each split carves the smallest piece off pane 0's remainder:
  `round(100/4)=25`, `round(100/3)=33`, `round(100/2)=50`), all `--right` off pane 0.
- Each pane shows its muted background (red/green/blue/purple) and an auto-title from its `echo`
  command; `echo` output is the first visible line (D-09).
- **Focus** on **pane 1** (leftmost).

## Observed

Run from a 2-pane tab (new-tab path). Resulting tab topology:

```
tab5 (4 panes)  — all full height (24 rows), single row
  pane15 col=  0 19w  active=True   <- leftmost, focused
  pane18 col= 20 19w
  pane17 col= 40 19w
  pane16 col= 60 20w
```

- **Equal width:** 4 side-by-side full-height columns at **19 / 19 / 19 / 20** cols on an 80-col
  terminal (80 ÷ 4 = 20; the ±1 is integer rounding of the `[25, 33, 50]` percent sequence). This
  is the **equal-share invariant** — NOT a `50 / 25 / 12.5` cascade where panes shrink rightward.
- **Focus:** leftmost pane (pane15 `active=True`).
- **Colors / D-09:** per-pane backgrounds (red/green/blue/purple) confirmed in the live GUI;
  styled-pane content clean (shared printf path).

## Verdict

**PASS.** All 4 panes ended effectively equal width (19/19/19/20, rounding only), confirming the
equal-share invariant — no rightward cascade. Focus leftmost. No deviation.
