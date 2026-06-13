# Phase 4: Ad-hoc Scenes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-12
**Phase:** 4-ad-hoc-scenes
**Areas discussed:** Layout ↔ pane count, Per-pane command surface, Per-pane styling scope, Startup command lifecycle, Scene materialization (emergent)

---

## Layout ↔ pane count

### Pane count

| Option | Description | Selected |
|--------|-------------|----------|
| Derived from commands | Count = number of per-pane commands; no separate count flag | ✓ |
| Explicit --panes N | Distinct flag sets count; commands fill panes in order | |
| Both: --panes optional override | Default = command count; --panes pads with shell panes | |

### Layout scaling

| Option | Description | Selected |
|--------|-------------|----------|
| Adapt to any N | tall/grid/horizontal/mirrored all scale to arbitrary N | ✓ |
| Fixed canonical count | Each layout implies a count; mismatch errors | |
| Adapt, with sane minimums | Adapt but enforce per-layout minimums | |

**User's choice:** Derived from commands + Adapt to any N.
**Notes:** Count and content come from one ordered list. Exact split geometry left to planner; the invariant is "requested layout shape at requested N."

---

## Per-pane command surface

### Command shape

| Option | Description | Selected |
|--------|-------------|----------|
| Repeated --pane flag | `--pane '…' --pane '…'`; flag order = pane order | ✓ |
| Positional after -- | Everything after `--` is a pane command | |
| Repeated -p shorthand | Short `-p` as the primary form | |

### Shell pane

| Option | Description | Selected |
|--------|-------------|----------|
| Literal 'shell' keyword | `--pane shell` → plain interactive shell | ✓ |
| Empty string | `--pane ''` → plain shell | |
| Both accepted | shell / empty / omitted all mean plain shell | |

**User's choice:** Repeated `--pane` + literal `shell` keyword.
**Notes:** Flag order is pane order. A program literally named `shell` is a rare quoting edge.

---

## Per-pane styling scope

### Style scope

| Option | Description | Selected |
|--------|-------------|----------|
| Tab-level only | One tab color + title; panes just run commands | |
| Per-pane color + title too | Each pane carries color/title via a mini-DSL | |
| Tab color + auto pane titles | Tab color + auto-title each pane; no per-pane color | |
| **Other (free text)** | "tab color, pane color bg, title" | ✓ |

### Pane titles

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, auto from command | Pane titled from its startup command | ✓ |
| No, leave default | Keep WezTerm's default title | |

**User's choice:** Free-text — wants tab color **and** per-pane background color **and** title; auto pane title from command = yes.
**Notes:** Resolved the "how does per-pane color attach to `--pane`?" follow-up in plain text → agreed on an inline `key=value` form inside the `--pane` value (`cmd=`, `color=`, `title=`), backward-compatible with the bare-command and `shell` forms. Rejected positional paired flags (fragile index alignment).

---

## Startup command lifecycle

| Option | Description | Selected |
|--------|-------------|----------|
| In a shell (pane persists) | Command sent into a spawned shell; pane stays alive | ✓ (via free-text) |
| As the pane program (closes on exit) | `split-pane -- cmd`; pane dies on exit | |
| Shell default + exec= opt-in | Shell by default; `exec=true` runs-as-program | |

**User's choice:** Free-text confirming run-in-shell + pane persists, plus two new requirements (clean pane, smart materialization).
**Notes:** User clarified (Spanish): customization escapes are injected by command but the pane must end up **visually clean, "as if nothing happened"** (D-09). Also surfaced the materialization rule (below). No run-as-program opt-in this phase.

---

## Scene materialization (emergent area)

Surfaced from the user's lifecycle answer; confirmed in a plain-text follow-up.

**User's choice:**
- Current tab has 1 pane → build the scene in the current tab, absorbing the current pane as pane 1 (reuse preferred — keeps cwd; drop/replace acceptable).
- Current tab has ≥2 panes → spawn a new tab (same OS window) with the scene.
- Exact final pane count, never +1 (2-pane scene from a 1-pane tab = exactly 2).
- Same OS window always; no override flags this phase (100% automatic).

**Notes:** Captured as D-10/D-11/D-12. The reuse-vs-drop mechanism is the planner's; the exact-count invariant and same-window rule are locked.

---

## Claude's Discretion

- Exact flag shape for the scene's **tab-level** color + title (reusing Phase 3 `wez tab`).
- Which pane is **focused** when the scene finishes building.
- Split **geometry** (percent/cells per layout at N), `--pane` value **parse rules**, and any
  **send-text settle/timing** before a freshly spawned shell is ready.
- **Completion** wiring for `wez scene new` / `--layout` (auto-generated from `cli/spec.lua`, D-16).
- Whether per-pane styling ships a `--pane-id` surface on `wez pane` or stays scene-internal.

## Deferred Ideas

- Named/saved recipes, `wez scene launch`, seeded examples, dynamic recipe completion → Phase 5.
- `exec=` run-as-program panes → not this phase (revisit with a new decision).
- Materialization override flags (`--new-tab` / `--here`) → not this phase.
- New OS window for a scene → rejected (same window, new tab only).
