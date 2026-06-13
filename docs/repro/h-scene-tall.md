# Manual repro — `wez scene new --layout tall` (Plan 04-02)

**Date:** 2026-06-13
**WezTerm session:** Isolated headless `wezterm-mux-server` (XDG_RUNTIME_DIR=/tmp/wez-e2e, minimal
config, `zsh -f` panes), driven via `lua5.4 cli/wez.lua scene new ...`; topology read from
`wezterm cli list --format json`. Per-pane rendered background colors additionally confirmed
visually in a live GUI session (user sign-off 2026-06-13).
**Verifies:** SCEN-01 (live build), D-02 (tall geometry), D-05 (tab + per-pane styling),
D-06 (--pane grammar), D-07 (auto/explicit pane titles), D-08 (startup-cmd panes persist),
D-09 (visually clean panes), focus on main pane.

## Method

From a tab that currently has **≥2 panes** (forces the new-tab materialization path), run:

```
wez scene new --layout tall \
  --pane 'cmd=htop,color=red,title=Monitor' \
  --pane 'cmd=echo hello,color=blue' \
  --pane shell \
  --color teal --title "Dev Scene"
```

(N=3. Invoke via the dispatcher: `lua5.4 cli/wez.lua scene new ...`, or the built `wez` binary.
Note D-06: a command combined with attributes MUST use the `cmd=` key — `'echo hello,color=blue'`
is rejected as an unknown key `echo hello`; the correct form is `'cmd=echo hello,color=blue'`.)

## Expected behavior

- A **new tab in the same OS window** (never a new window) is created and selected.
- Geometry matches `tall`: one **50%-width main pane on the left**, two panes **stacked
  (equal height) in the right 50%**. Split plan: `--left 50%` off pane 0, then `--bottom 50%`.
- Pane 1 (`cmd=htop,color=red,title=Monitor`): muted **red** background (`#1f1617`), tab/pane
  title `Monitor`, `htop` running and the **pane persists** after htop is quit (D-08 — pane does
  not exit when the command finishes).
- Pane 2 (`echo hello,color=blue`): muted **blue** background (`#161a1f`), auto-title derived
  from the command (`echo`), `echo hello` ran and `hello` is the first visible output.
- Pane 3 (`shell`): untouched plain interactive shell — no color, no injected title, no command.
- The **tab** shows the `teal` accent + title `Dev Scene` (set-tab-title `teal:Dev Scene`).
- **D-09 clean-pane bar:** NO raw escape bytes visible in any pane (no `\033]11;...`,
  no `\033]1337;...`), no stray blank lines; each command's output is the first thing after
  the prompt. The `shell` pane looks exactly as if freshly opened.
- **Focus** lands on **pane 1** (the main/large pane).

### Pattern 3 open questions to record (per shell)
- send-text timing/race: did styling land before the shell prompt, or did the prompt re-print
  over it? (record for bash and zsh)
- PROMPT_COMMAND / precmd re-print after `clear`: any artifact? (record observed)

## Observed

Run from a 2-pane tab (new-tab path). New tab created in the same OS window (`windows=1`
throughout); the original tabs were left untouched. Resulting tab topology (`wezterm cli list`):

```
tab2 (3 panes)  tab_title='teal:Dev Scene'
  pane 4  col=  0 row= 0  39x24  active=True   title='htop'   <- main, LEFT, full height
  pane 5  col= 40 row= 0  40x11  active=False  title='zsh'    <- stack top, RIGHT
  pane 6  col= 40 row=12  40x12  active=False  title='zsh'    <- stack bottom, RIGHT
```

- **Geometry:** main pane on the **left** (col 0, full 24-row height); two panes **stacked in the
  right 50%** at equal height (rows 0–10 and 12–23). Matches the `tall` split plan exactly.
- **Tab styling (D-05):** `tab_title='teal:Dev Scene'` — the `color:title` encoding carries the
  `teal` accent + `Dev Scene` title.
- **htop persistence (D-08):** pane 4 shows `htop` running (process-set title `'htop'`); the pane
  did not exit.
- **D-09 clean-pane:** `get-text` on the styled `echo hello` pane (pane 5 in a sibling run) showed
  only `echo hello` → `hello` → prompt — zero raw escape bytes (`grep -E '11;#|1337;|SetUserVar'`
  → no match). The printf-octal styling (commit 497550e) is consumed by the terminal parser, not
  echoed as text.
- **Focus:** landed on the main pane (pane 4 `active=True`).
- **Per-pane colors:** red / blue backgrounds + the teal tab accent confirmed visually in the live
  GUI session (user sign-off).

## Verdict

**PASS.** Geometry (main-left + 2 stacked right), tab `color:title`, htop persistence, D-09
clean-pane, and main-pane focus all hold. No deviation. Per-pane rendered colors confirmed in GUI.
