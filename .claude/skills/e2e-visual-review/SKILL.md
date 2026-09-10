---
name: e2e-visual-review
description: >-
  Agent-performed visual review of WezTerm E2E screenshots against the PRD
  Appendix A.4 checklist (tab titles, escape leak, focused pane, pane tints,
  emoji icons, active vs inactive tabs) — never a scripted vision API. Must
  use when reviewing or approving Tier 4 visual baselines, after running
  WEZ_E2E_VISUAL=1 make e2e-visual, when promoting captures with APPROVE=1,
  or when asked to visually verify WezTerm scene, tab bar, pane tint, or
  emoji icon rendering (screenshot, baseline, visual regression).
---

# E2E Visual Review

RMSE answers "same bytes as last time?"; A.4 answers "would a human
accept this screen?" Do not substitute one for the other.

Looks wrong but is not an A.4 defect: glyph-edge hinting, subpixel LCD
fringes on white text, a one-frame compositor lag (recapture).
Looks right but is a defect: every pane the same charcoal because tints
washed out; an escape leak that reads as prompt color until you see `^[`
or `quote>`; an emoji that looks 2 cells wide but is tofu in the title
string; active vs inactive tabs that only differ by a 1px underline.

- **fire(B)** — local, best-effort, out of CI. Not a CI job.
- **D-01** — the agent reads the PNG; never a scripted vision API.
- **D-02** — the user picks the model; never a silent pick.
- **D-03** — A.4 is per-item pass/fail, not a percentage.

Do NOT load the PRD or `tests/e2e/tier4/visual_diff_e2e_test.lua`.

## Before each step, ask

- **Capture:** Real PNGs, or a loud SKIP / non-zero make?
- **Vision:** Did Read return pixels, or raw bytes?
- **Each A.4 item:** N/A, stale frame, or defect? (Human-dirty vs
  anti-aliasing is RMSE's job — do not FAIL A.4 for hinting noise.)
- **Approve:** Every applicable item PASS, and manifest `PASS` or `NO BASELINE`?

## Step 1 — Capture

If `${TMPDIR:-/tmp}/wez-e2e-visual-latest/manifest.txt` is readable and
its `RUN_ID` is younger than 3600s, skip the make unless the user asked
for a fresh capture. Otherwise:

```bash
WEZ_E2E_VISUAL=1 make e2e-visual
```

Loud SKIP is exit 0 with a line matching either:

- `<label>: SKIP (<FLAG> != 1)` — e.g. `tier4 visuals: SKIP (WEZ_E2E_VISUAL != 1)`
- `<label>: SKIPPED (reason=...)` — e.g. `tier4 visuals: SKIPPED (reason=external wezterm cli mux mutations do not visually repaint the GUI window on this host)`

A loud SKIP is not a review: report the line and stop. Any other non-zero
make exit: print stdout/stderr and stop. Exit 0 with a missing or
unreadable `${TMPDIR:-/tmp}/wez-e2e-visual-latest/manifest.txt`: print
make output and stop. A manifest line with the wrong field count, or a
`RUN_ID` that is not a plain integer: treat the manifest as unreadable —
print make output and stop. Do not judge leftover PNGs from an older
`RUN_ID`. Do not invoke `make e2e-visual` without `WEZ_E2E_VISUAL=1` and
expect a real capture — the bare form self-skips by design.

Read that manifest — never guess a path:

```
RUN_ID=<unix-epoch>
<scenario>|<png-path>|<WxH>|<PASS|FAIL|NO BASELINE>|<baseline-path|NONE>
```

Default scenarios: `dev`, `ai`, `docker`, `tabbar`. `WxH` of `0x0`, or
equal to the desktop (e.g. `1920x1080` on a 1920×1080 display), is a
wrong window → **stop**. A committed-but-wrong baseline RMSE-PASSes
forever.
`NO BASELINE` means nothing to diff, not a visual pass. Judge only rows
whose `png-path` exists.

## Step 2 — Prove this session & shortlist (D-02)

Read one manifest PNG. Let `CMD` = `.planning/config.json`
`workflow.cross_ai_command` (may be unset). Parse `-m` or `--model`
`<id>` from `CMD` when present (they are equivalent). Do not hardcode a
path or id. `CMD` is **opencode** iff the first-token basename is
`opencode`.

Pixels-visible = Read returned an image of this WezTerm window. A 0-byte
PNG, raw bytes with no image, a full desktop, another app, or empty
chrome is not. Wrong window → **stop**. Never send a PNG to test
reachability.

One lookup, keyed by the real end-state — this is what you present to
the user in Step 3, and it already names where each pick goes next:

| End-state | Shortlist (print each row as `` <name-or-id> — <stamp> ``) | Suggested pick | If picked "use this session" | If picked an external id |
|---|---|---|---|---|
| pixels + no `CMD` | `use this session — confirmed reachable and vision-capable` | use this session | Step 5 | (not on shortlist — n/a) |
| pixels + `CMD` set | `use this session — confirmed reachable and vision-capable`, plus `<id> — catalog-listed, vision support inferred from the model name` | use this session | Step 5 | Step 4, then Step 5 |
| no pixels + `CMD` set | `<id> — catalog-listed, vision support inferred from the model name`. If `CMD` is opencode, run `opencode models` once (present/absent, one line); the id stays catalog-listed. | `<id>` | **Refuse.** Return to Step 3 — pick cannot invent pixels. | Step 4, then Step 5 |
| no pixels + no `CMD` | **Stop.** Empty shortlist. | — | — | — |

If the shortlist is non-empty, go to Step 3 with that row's shortlist +
suggested pick. Otherwise already stopped.

## Step 3 — Ask the user (checkpoint — never bypass)

Present the shortlist and suggested pick from Step 2's table — **one**
suggestion, never a silent pick. If `CMD` is not opencode, ask for that
CLI's attach invocation in the same turn. Ask the user which candidate to
use. The user chooses. If the user cannot answer this turn: print the
shortlist and **stop**. Do not pick.

User may name an id not on the shortlist; treat it as catalog-listed until
they attest a prior PNG attach (then confirmed) — then apply Step 2's
table as if that id had been on the shortlist all along.

Pick chooses the path; it does not override pixels — Step 2's "Refuse"
row still applies even to a user-named id. If this session also saw the
PNG, Step 4's contradiction rule still applies.

## Step 4 — Dispatch (only when the user picked an external id)

**MANDATORY — READ ENTIRE FILE:** [`references/dispatch.md`](references/dispatch.md)
(~60 lines) before invoking any external CLI. Do not set range limits.

**Do NOT load** `references/dispatch.md` when the user picked **use this
session**.

```bash
opencode run --model <id> --file <screenshot.png> "<prompt>"
```

The prompt (A.4 items + Applies + FAIL observables the child model
cannot see otherwise), free-form retry, contradiction rule, and
non-opencode attach contract are in that file.

## Step 5 — Judge pixels

For each applicable item: **N/A**, **stale frame** (re-capture once), or
**defect** (FAIL). Apply the looks-wrong / looks-right pairs at the top.

Extra/unknown manifest names with a real PNG still get A.4; tabbar-only
clauses stay N/A unless the name is `tabbar`.

**Stale frame vs defect.** A capture taken mid-render, before the
compositor's frame settles, can show a stale/blank pane that looks like a
real rendering bug. If a tint or title looks WRONG, re-run
`WEZ_E2E_VISUAL=1 make e2e-visual` once. If the second capture still
looks wrong, FAIL — a settled wrong frame is a defect.

### Required verdict shape

```
SCENARIO=<name>
<n> | PASS|FAIL|N/A | <one-line reason>
```

On `dev`/`ai`/`docker`, score item 1 for legibility only (even-width is
`tabbar`-only — compare chrome widths only when two same-title tabs are
in frame). A 2-cell emoji is roughly square in the title row; tofu is a
1-cell box; a gap is empty cells after the icon. Do not nest an N/A
clause inside a PASS line.

Always six lines, `SCENARIO=` first. N/A is a line, not an omitted row.

```
SCENARIO=dev
1 | PASS | titles fully legible
2 | PASS | no CSI/OSC/quote> in any pane
3 | PASS | focused pane shows a clean prompt
4 | PASS | three panes, three distinct tints
5 | PASS | icons sit two cells wide on the title row
6 | N/A  | not tabbar
```

### PRD Appendix A.4 (verbatim) + FAIL observable

| # | Item (verbatim) | Applies | FAIL looks like |
|---|---|---|---|
| 1 | Tab titles fully legible and even-width across same-title tabs (AI-vision) | Legibility: `dev`/`ai`/`docker`/`tabbar`. **Even-width: `tabbar` only.** | Truncated/ellipsized/overlapping titles; two same-title tabs at different widths. |
| 2 | No raw escape characters visible in any pane after a scene launch (AI-vision) | `dev`/`ai`/`docker`/`tabbar` | Literal CSI/`^[`/`OSC` bytes, `printf '` fragments, `\nnn` octal runs, or a stuck `quote>` prompt. |
| 3 | Focused/first pane is clean after `wez scene launch` (AI-vision) | `dev`/`ai`/`docker`/`tabbar` | Leftover command echo, incomplete prompt, or stray glyphs in the focused pane. |
| 4 | Distinct per-pane background tints render (AI-vision / snapshot) | `dev`/`ai`/`docker`. `tabbar` only if tints are in frame. | Every pane the same background; tint only on chrome, not content. |
| 5 | Emoji icons occupy two cells and align (AI-vision) | `dev`/`ai`/`docker`/`tabbar` (all four: `dev`/`ai`/`docker` recipes set `icon =`; `tabbar` launches `dev`) | Clipped to one cell, sitting on the title baseline, tofu/replacement box, or 3+ cells with a gap. |
| 6 | Fancy tab active vs inactive visual distinction (snapshot) | **`tabbar` only** | Both tabs identical chrome (same bg/underline/weight). |

## Step 6 — Approve or reject

If the user asked only for a review, stop after the verdict table. Run
`APPROVE=1` only when they asked to promote or approve.

Include a name in `SCENARIOS=` only if every applicable A.4 item PASS
**and** the manifest is `PASS` or `NO BASELINE`. Omit A.4-FAIL and RMSE
`FAIL` names. If the list is empty, do not run `APPROVE=1`. Replacing a
drifted baseline is outside this path; the user must ask in so many words.

```bash
make e2e-visual APPROVE=1 SCENARIOS=<exact comma-separated names>
```

Example: `make e2e-visual APPROVE=1 SCENARIOS=dev,tabbar`

`APPROVE=1` is a Make variable, never a dashed double-hyphen flag pasted
onto the command line — Make treats an unknown flag spelling as an
unrecognized option and never promotes. `APPROVE=1` is the only valid
approval invocation. Promotion copies the manifest's exact,
checksum-verified bytes.

## NEVER

- Silently pick a model (D-02) — a silently-chosen model is unaccountable
  when a baseline is later disputed. The user chooses.
- Call a scripted vision API (D-01) — `make e2e` must never grow a vendor
  vision dependency; judgment is an agent reading a PNG.
- Average A.4 into a percentage or pass rate (D-03) — "4/6 is close enough"
  promotes a broken baseline.
- Approve a scenario with any applicable FAIL, or because RMSE passed.
  A review-only ask is not permission to promote.
- Treat a catalog-listed model as confirmed-reachable without the user's
  confirmation. Catalog ≠ credentials ≠ PNG-attachment support. Do not
  grep `vision` in an id or dump a provider catalog into the shortlist.
- Send a screenshot to a model "just to test" reachability.
- Pretend a loud SKIP was a review, guess a PNG path, or mark `tabbar`-only
  items PASS on `dev`/`ai`/`docker`. A skip is the driver refusing to
  capture; inventing a review from it promotes nothing-as-baseline.
- Invent verdicts from a second free-form dispatch reply, or retry a
  different model after attach failure.
- Judge in this session when Read returned no pixels. Pick cannot invent
  vision; return to Step 3 or stop.
- Pick a model when the user cannot answer this turn. Print the shortlist
  and stop.
