# Manual repro — `wez scene new --layout grid` (Plan 04-02)

**Date:** 2026-06-13
**WezTerm session:** Isolated headless `wezterm-mux-server` (XDG_RUNTIME_DIR=/tmp/wez-e2e, minimal
config, `zsh -f` panes), driven via `lua5.4 cli/wez.lua scene new ...`; topology from
`wezterm cli list --format json`. Rendered colors confirmed visually in a live GUI session.
**Verifies:** SCEN-01 (live build), D-02 (grid geometry, non-square N), D-12 (no placeholder
panes in the short last row), D-09 (clean panes), focus on pane 1.

## Method

From a tab with **≥2 panes** (new-tab path), run a **non-square N=5** grid (confirms 04-01's grid
step count of 4 = `rows-1` band splits + per-band column splits):

```
wez scene new --layout grid \
  --pane 'cmd=echo one,color=red' \
  --pane 'cmd=echo two,color=orange' \
  --pane 'cmd=echo three,color=yellow' \
  --pane 'cmd=echo four,color=green' \
  --pane 'cmd=echo five,color=teal'
```

(No tab-level `--color`/`--title` here — keeps the focus on geometry.)

## Expected behavior

- `cols = ceil(sqrt(5)) = 3`, `rows = ceil(5/3) = 2`. Geometry: **3 columns × 2 rows**, with
  **row 2 holding only 2 panes** (5 = 3 + 2), left-aligned, **no empty placeholder pane** in the
  missing row-2/col-3 slot (D-12).
- Total split steps = 4: one `--bottom 50%` band split (rows-1 = 1), then the per-band column
  splits (row 1: 2 `--right` splits; row 2: 1 `--right` split) — 1 + 2 + 1 = 4 splits → 5 panes.
- Each pane shows its muted background (red/orange/yellow/green/teal) and an auto-title from its
  `echo` command; each `echo` output is the first visible line (D-09).
- **Focus** on **pane 1** (top-left).

## Observed

Run from a 2-pane tab (new-tab path). Resulting tab had **exactly 5 panes** (not 6). Topology:

```
tab4 (5 panes)
  row 0 (top, 11 rows):  pane10 col= 0 26w | pane13 col=27 26w | pane12 col=54 26w   <- 3 columns
  row 1 (bot, 12 rows):  pane11 col= 0 39w | pane14 col=40 40w                        <- 2 columns
  focus: pane10 (top-left, active=True)
```

- **Grid shape:** `cols=ceil(sqrt 5)=3`, `rows=2`. Row 0 has **3 equal columns** (26 cols each);
  row 1 has **2 columns**, left-aligned (39 + 40 cols), and **no third placeholder pane** in the
  missing col-3 slot (D-12).
- **Pane count:** exactly **5** — no N+1 placeholder.
- **Focus:** top-left pane (pane10 `active=True`).
- **Colors / D-09:** per-pane backgrounds (red/orange/yellow/green/teal) confirmed in the live GUI;
  styled-pane content is clean (shared printf path, see `h-scene-tall.md` D-09 evidence).

## Verdict

**PASS.** 3×2 grid with a 2-pane last row, no placeholder (D-12), exactly 5 panes, focus top-left.
No deviation.
