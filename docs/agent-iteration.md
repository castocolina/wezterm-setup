# Agent Iteration Playbook

This is the operating manual for advancing wezterm-setup one behavior at a time.
Read this before opening a GSD plan or picking the next item from
[.planning/REQUIREMENTS.md](../.planning/REQUIREMENTS.md). The rules here are not
aspirational — they are how the previous bash attempt failed, and how this one will not.

## Operating principles

### R1 — Investigate first

No code lands in `config/`, `cli/`, or `tests/` until a hypothesis in
`.tmp/h<NN>-<slug>/` is green against a real WezTerm session.
The experiments directory is the only place where speculative code is allowed to live.

### R2 — Verify before declaring done

A behavior is "ready" only when `wez doctor` exits 0 and its output is captured into
the GSD change's verify report or handoff. "Should work", "compiles", "looks right"
are not evidence. The output of the verifying command, with its exit code, is.

### R3 — Config layer is composable

Each behavior lives in its own `~/.config/wezterm/wezterm-setup/<topic>.lua` file and
is `dofile()`-included from the main entry point. No file grows past a single coherent
responsibility. Any file that starts doing two unrelated things is split.

### R4 — Dogfood the install

The installer and sentinel-block mechanism are themselves proven via hypothesis before
any user-facing behavior is built on top of them. We do not assume our own scaffolding works.

### R5 — No promotion shortcut

`.tmp/` is gitignored for experiment outputs (`actual.json`,
`actual.txt`, scratch files). Promotion is a manual rewrite, never a copy or symlink.
Config migrates to `~/.config/wezterm/wezterm-setup/<topic>.lua`. The repro doc moves
to `docs/repro/h<NN>.md`. The experiment directory is then deleted.

### R6 — Probe before assume

Any task that depends on the behavior of a WezTerm CLI command, an escape sequence,
a Lua API call, or an OS-level contract requires a probe artefact in
`.tmp/probes/<change-id>/<NN>-<slug>.md` *before* the task is executed.
The probe captures six fields: assumption (one line), command or snippet, exit code or
observable result, relevant output, verdict (`holds` / `fails` / `partial-with-workaround`),
and the design decision or code path that uses it.

Probes are scratch evidence. Their findings flow into `Why:` lines in GSD design notes,
into commit messages, or into source-code comments at the call site that depends on them.
Once encoded, the probe artefact can be deleted.

The bash predecessor skipped this: the non-existent `wezterm cli set-user-var` surface,
the surprising tab-title persistence behavior across pane switches, and several escape
sequences all forced rework. R6 closes that gap.

### R7 — Test behavior, not assumptions

Integration tests exercise a real WezTerm session (via `wezterm cli`). Unit tests for
the companion CLI may stub WezTerm calls only when:

1. A probe per R6 confirms the real shape of the command being stubbed.
2. At least one integration test exercises the real command for the same code path.

If an integration test cannot be written today, the stub is *provisional* and the task
list MUST include "build probe + integration test before promotion."

## Probes vs hypotheses

| Question shape | Artefact | Lives in | Size |
|---|---|---|---|
| "Does this CLI flag exist? What does this escape sequence do?" | **Probe** (R6) | `.tmp/probes/<change>/<NN>-<slug>.md` | One screen, six fields |
| "Does this Lua config produce this observable tab/pane behavior?" | **Hypothesis** (R1) | `.tmp/h<NN>-<slug>/` (directory) | repro.md + run script + actual output |

A probe answers a narrow factual question about external-system shape. A hypothesis
answers a broader question about how our configuration drives WezTerm to produce the
behavior the user wants. If a probe grows past ~50 lines or asks more than one question,
it is a hypothesis in disguise — move it.

## The loop

For every phase item, repeat:

1. **Pick the next item** from [.planning/REQUIREMENTS.md](../.planning/REQUIREMENTS.md)
   in the order the roadmap documents. Skip an item only with a written reason in the
   GSD plan.

2. **Open a GSD plan** for the item with `/gsd-plan-phase`. One change per Phase item
   (or a coherent group of tightly related items). Scaffold proposal, design notes, and
   tasks before any code is written.

3. **Probe external assumptions first.** Before the hypothesis directory is populated,
   walk the planned tasks and identify every WezTerm API, CLI command, or escape sequence
   assumption. For each one, write a probe at
   `.tmp/probes/<change>/<NN>-<slug>.md` per R6. Wrong-shape probes get
   fixed in minutes here instead of being fossilised into config that has to be ripped
   out later. List each probe + verdict in the GSD design notes.

4. **Drop scratch** into `.tmp/h<NN>-<slug>/`:
   - `repro.md` — what the behavior is, the manual repro steps, the expected observable
     outcome (which tab changes color, which pane title appears, etc.).
   - `run.sh` (or `run.lua` / `run.py` — language resolved in Phase 0) — an autonomous
     script that drives a real WezTerm session via `wezterm cli` and asserts the expected
     outcome.
   - `expected.txt` — a structured form of the expected outcome (e.g. `wezterm cli list`
     output subset, or expected escape sequence response).
   - `actual.txt` — captured by the run script on the latest run; gitignored.
   - `draft.lua` — the candidate WezTerm config snippet being iterated on.

5. **Iterate** the candidate `draft.lua` until the run script is green. Capture the green
   `actual.txt` so the next agent can see what was observed.

6. **Promote** by hand:
   - Move the proven snippet into `~/.config/wezterm/wezterm-setup/<topic>.lua`
     (creating the file if needed). Wire it into the main entry point.
     **File basename = behavior category.** `tab-bar.lua` → tab rendering;
     `keybindings.lua` → all key actions; `cwd.lua` → cwd inheritance.
   - Move `repro.md` into `docs/repro/h<NN>-<slug>.md`.
   - Rewrite the run script as a proper integration test once the test harness is settled.
   - Encode every probe finding from step 3 into a durable location (design note `Why:`
     line, inline comment, or commit message paragraph) per R6.
   - Delete the `.tmp/h<NN>-<slug>/` directory.

7. **Verify** end-to-end: `wez doctor` exits 0. Capture the output into the GSD verify
   report.

8. **Close** the GSD phase with `/gsd-progress` or the appropriate transition command.

## Hand-off across agents

The agent that writes a hypothesis is *not* the same agent that promotes it. This is
the spec-first rule applied to the hypothesis layer. Concretely:

- The agent that authors `.tmp/h<NN>-<slug>/run.sh` and gets it green
  leaves the green `actual.txt` and an updated `repro.md` describing what it observed.
- A separate agent reads the green hypothesis, decides whether the captured evidence
  justifies promotion, and performs the manual rewrite into `config/`, `docs/repro/`,
  and `tests/`.
- If the second agent disagrees with the hypothesis, it amends `repro.md` with the
  disagreement and the change goes back to step 4 with a new hypothesis.

## What to do when the run script disagrees with the manual repro

The autonomous run script is the source of truth. If the manual repro says a behavior
works and the run script says it does not, the behavior does not ship. Either the script
is wrong (fix the script) or the behavior is wrong (fix the config). The manual repro is
documentation; the run script is the gate.

## What to do when WezTerm itself blocks a behavior

Some behaviors may not be reachable from `wezterm cli` (out-of-process). When the run
script cannot drive the surface from outside WezTerm, capture the gap in `repro.md`,
archive the hypothesis as `.tmp/h<NN>-<slug>/blocked.md`, and open a
follow-up GSD item to scope an in-process approach (Lua event handler, pane user var
via OSC escape, or `wezterm.action`). Do not paper over the gap with a wrapper script.
