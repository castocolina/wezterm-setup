# Phase 2: Pane Identity - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-10
**Phase:** 2-pane-identity
**Areas discussed:** Visual rendering model, Hex/color input scope, Opacity, Pane title display, Target pane

---

## Area selection (initial)

User selected **all four** offered gray areas and added a freeform directive:
> "We can see ../wezterm-setup_ and copy the colors and transparency/opacity pattern and also
> how this was in ../kitty-setup, the important is we can set the color and opacity same time,
> the colors names must be autocompletable options; if rgba is provided but something prevents
> implementation the alpha needs to be stripped."

This pulled **opacity** into the discussion as a first-class concern and named two canonical
reference repos (`../wezterm-setup_`, `../kitty-setup`).

---

## Visual rendering model + Color/hex input

Researched both references. Found the proven prototype uses a **dual write** (OSC 11 real pane
background + OSC 1337 `SetUserVar` tab-bar accent) — PROJECT.md had recorded only the SetUserVar
half. kitty's `normalize_color` provided the input/validation model.

**User's choice:** Mirror the prototype's dual-write; adopt kitty-style normalization but keep
the curated 10-name palette (not kitty's 667-name superset), with hex/rgba as the escape hatch.
**Notes:** Named colors must be autocompletable (explicit requirement).

---

## Opacity

| Option | Description | Selected |
|--------|-------------|----------|
| Separate --opacity flag (spike first) | Flag-based; alpha-in-color always stripped; spike feasibility | |
| Alpha inside the color value | Honor alpha if possible, else strip; couples color+opacity | |
| Defer opacity to its own phase | Ship solid color+title on-spec; opacity later | |

**User's choice:** (no single option) — "we need to handle when the user provides opacity as
alpha in rgba AND also handle the additional flag." → **Accept BOTH input forms.** Opacity is
in scope (scope expansion flagged → proposed PANE-05).

### Opacity spike contract (follow-up question)

| Option | Description | Selected |
|--------|-------------|----------|
| Per-pane first, strip to solid if impossible | Spike per-pane; fallback = accept input, render solid, warn once | ✓ |
| Per-pane first, else window-scoped opacity | Fallback dims whole OS window (kitty rejected this) | |

**User's choice:** Per-pane first, strip-to-solid fallback. **Notes:** Never apply OS-window
opacity (rejected — kitty's `h26-perpane-opacity.md` rationale: dims unrelated panes/tabs).

---

## Pane title display

| Option | Description | Selected |
|--------|-------------|----------|
| Freeform text + emoji | Pane user var overrides tab title; on-spec PANE-03 | |
| Also port icon-name shortcuts | name→emoji map (docker→🐳, …) + completion | |
| You decide | Lock freeform, defer icon map | |

**User's choice:** (no single option) — "the reference project handles both as part of free
text and also as icon name." → **Port BOTH** freeform text+emoji AND the icon-name map
(extends PANE-03).

---

## Target pane

| Option | Description | Selected |
|--------|-------------|----------|
| Current pane only | OSC from calling pane; add --pane-id in Phase 4 | ✓ |
| Optional --pane-id now | Forward-compat but needs send-text --pane-id verified now | |
| You decide | Lock current-pane-only | |

**User's choice:** Current pane only. **Notes:** "but we need to be prepared for id because in
future we will need scenes and launch multiple panes and set color, opacity, icon, title and run
commands inside them." → Design internals for a droppable `--pane-id` target (Phase 4).

---

## Claude's Discretion

- Exact muted OSC-11 background hex per profile, CLI arg shape (positional vs flag for opacity),
  completion wiring into `cli/spec.lua`, and config topic-file split — planner's call under the
  locked decisions. Reference values embedded in CONTEXT `<code_context>`.

## Deferred Ideas

- `--pane-id` / arbitrary-pane targeting → Phase 4 (Ad-hoc Scenes).
- OS-window-scoped opacity → **rejected**, not deferred.
- kitty's 667-name X11/CSS color superset → not adopted (curated 10 + hex/rgba escape hatch).
