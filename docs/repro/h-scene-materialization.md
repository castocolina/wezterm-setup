# Manual repro — `wez scene new` materialization (Plan 04-02)

**Date:** 2026-06-13
**WezTerm session:** Isolated headless `wezterm-mux-server` (XDG_RUNTIME_DIR=/tmp/wez-e2e, minimal
config, `zsh -f` panes), driven via `lua5.4 cli/wez.lua scene new ...`; current pane supplied via
`WEZTERM_PANE`; topology from `wezterm cli list --format json`.
**Verifies:** SCEN-01 (live build), D-10 (reuse current tab when it has exactly 1 pane),
D-11 (new tab in the same window when current tab has ≥2 panes), D-12 (final pane count = exactly
N, never N+1), never a new OS window.

## Method

Two sub-cases, same command in both:

```
wez scene new --layout tall --pane shell --pane shell
```

(N=2. `shell` panes so nothing styles/runs — this isolates the materialization decision and the
final pane count.)

### Case (a) — reuse (D-10)

Start from a tab that currently has **exactly 1 pane** (close extra panes first; confirm via
`wezterm cli list --format json` that the active tab has a single pane). Run the command.

### Case (b) — new-tab (D-11/D-12)

Start from a tab that currently has **≥2 panes** (split once first). Note the current tab's id and
pane ids. Run the command.

## Expected behavior

### Case (a) — reuse
- The scene builds **in the current tab**, absorbing the existing pane as pane 1 (cwd preserved).
- Final pane count in that tab is **exactly 2** (never 3) — the original pane became pane 1, one
  split added pane 2.
- No new tab and no new OS window are created.
- Focus on pane 1 (the original pane).

### Case (b) — new-tab
- A **new tab is created in the SAME OS window** and selected; the scene builds there (2 panes).
- The **original multi-pane tab is left completely untouched** (same panes, same ids, same
  contents).
- Final pane count in the new tab is **exactly 2**.
- No new OS window is created.

## Observed

### Case (a) — reuse (WEZTERM_PANE=0, tab0 had exactly 1 pane)

```
BEFORE: windows=1 tabs=1 panes=1   win0 tab0 (1 pane): pane0
AFTER:  windows=1 tabs=1 panes=2   win0 tab0 (2 panes): pane0 (col0,LEFT,active) | pane1 (col40,RIGHT)
```

- Built **in place** in the same `tab0` (same tab id); the original pane0 became pane 1 of the
  scene (col 0, focused). Final count **exactly 2** (not 3). No new tab, no new window.

### Case (b) — new-tab (WEZTERM_PANE=0, but tab0 now had 2 panes)

```
AFTER: windows=1 tabs=2 panes=4
  win0 tab0 (2 panes): pane0, pane1     <- ORIGINAL tab, completely untouched (same ids)
  win0 tab1 (2 panes): pane2, pane3     <- NEW tab, same window, the scene
```

- A **new tab (tab1)** appeared in the **same OS window** (`windows=1` unchanged); the original
  multi-pane `tab0` was left intact (same pane ids 0/1). New tab has **exactly 2 panes**.

## Verdict

**PASS** for both sub-cases. (a) reuse kept the same tab and ended at exactly N=2; (b) new-tab was
same-window, left the original tab intact, ended at exactly N=2; neither opened a new OS window
(D-10 / D-11 / D-12 all hold). No deviation.
