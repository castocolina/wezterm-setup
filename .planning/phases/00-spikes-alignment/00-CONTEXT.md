# Phase 0: Spikes & Alignment - Context

**Gathered:** 2026-06-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 0 resolves the open engineering decisions that every later phase depends on, each
backed by a working evidence artifact. It produces **decisions and a reference catalogue**,
not shipped features (no REQUIREMENTS.md items map here).

Validation targets (from ROADMAP.md):
1. CLI language — Lua 5.4 standalone vs. Python/uv fallback
2. CWD inheritance mechanism — which approach survives pane splits cross-platform
3. `wezterm cli` command-surface audit — what exists and is stable on both platforms
4. Tab-title prefix convention — already proven (`"color:title"`); document and lock the format

</domain>

<decisions>
## Implementation Decisions

### CLI Language Spike
- **D-01:** Decision is **evidence-driven, then judgment** — not a fixed pass/fail threshold.
  The spike builds a minimal prototype in BOTH Lua 5.4 standalone and Python/uv, then the user
  picks based on the evidence collected.
- **D-02 (revised 2026-06-07):** **Primary criterion = code ergonomics + stack coherence.**
  The companion CLI `wez` is an EXTERNAL process to WezTerm (talks via `wezterm cli` + OSC
  escapes); it does NOT run inside WezTerm's in-process Lua VM. So "native integration with the
  emulator" is a near-empty tiebreaker for the CLI layer — both languages just spawn `wezterm cli`
  and parse its output. Decide instead on: (a) **ergonomics** — how clean/maintainable the real
  operations are (parsing `wezterm cli` JSON, building OSC escapes, spawning panes) across 5
  phases; and (b) **stack coherence** — the cognitive benefit of one language (Lua) across config
  + CLI, weighed against Lua's poorer stdlib. **Performance is explicitly a non-factor** (IO-bound,
  sub-second `wezterm cli` calls dominate). Distribution/install is a MINOR tiebreaker only, and is
  further neutralized by the decision that the installer detects a missing Lua and provisions it
  (see Specific Ideas). *Supersedes the original "distribution simplicity" tie-breaker.*
- **D-03:** The spike is bounded by a **fixed proof-scope script** (no open-ended polishing).
  Each language prototype must exercise the same required capabilities: argument parsing, at
  least one real `wezterm cli` call, JSON handling, and file I/O. The spike is done when both
  prototypes run that scope — completeness of the script, not "which feels nicer," is the stop
  condition.

### macOS Validation Strategy
- **D-04:** macOS access is **later/intermittent**. Phase 0 proceeds **Linux-first**: prove
  everything on Linux now, design for macOS parity, and **batch macOS verification into a single
  later pass before Phase 1 closes**.
- **D-05:** The CLI language decision (which locks at Phase 0 close) is **committed on Linux
  evidence + macOS research/docs now** ("commit, verify later") so Phase 1 can start. macOS
  distribution behavior becomes an explicit **verification checkpoint** in the batched Mac pass
  that can trigger reconsideration if it fails.

### Spike Artifact Layout
- **D-06:** The hypothesis playbook (`docs/agent-iteration.md`) is **authoritative** over the
  CLAUDE.md summary. Scratch experiments live under `.tmp/` — probes in
  `.tmp/probes/<change>/<NN>-<slug>.md`, hypotheses in `.tmp/h<NN>-<slug>/` — gitignored and
  deleted after manual promotion.
- **D-07:** Committed **decision records** for Phase 0 live in `.planning/decisions/`, then get
  promoted to PROJECT.md Key Decisions on phase completion (per ROADMAP). Promoted reproductions
  go to `docs/repro/h<NN>-<slug>.md`. These three locations are distinct purposes, not duplicates.
- **D-08:** The stale CLAUDE.md line (`scripts/experiments/`) was corrected to point at the
  `.tmp/` convention. **(Edit already applied to `CLAUDE.md`; not yet committed — pending the
  user's explicit go-ahead per the No-auto-commit rule.)**

### `wezterm cli` Audit Scope
- **D-09:** **Full surface sweep** — catalogue the entire `wezterm cli` command surface as a
  durable, committed reference (not just the subcommands Phases 1-5 need). Bounded naturally by
  what `wezterm cli --help` enumerates. Linux columns filled now; macOS columns filled on the
  batched Mac pass (per D-04).

### Claude's Discretion
- The `<change>` identifier used in the `.tmp/probes/<change>/` path for Phase 0 (no GSD change
  exists yet for a validation phase) — researcher/planner may choose a sensible label (e.g.
  `phase-0` or the plan id).
- Exact structure/columns of the full `wezterm cli` reference catalogue document.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Process & Methodology
- `docs/agent-iteration.md` — **Authoritative** hypothesis/probe playbook. Defines R1–R7, the
  probe-vs-hypothesis distinction, `.tmp/` layout, promotion rules, and the per-item loop.
  Overrides any conflicting summary in CLAUDE.md.
- `CLAUDE.md` — Project agent rules (No-auto-commit, hypothesis-before-implementation,
  verify-before-done). Note: the experiments-location line now points at `.tmp/` (D-08).

### Scope & Decisions
- `.planning/ROADMAP.md` §"Phase 0: Spikes & Alignment" — validation targets, success criteria,
  and the `.planning/decisions/` → PROJECT.md promotion path.
- `.planning/PROJECT.md` §"Key Decisions" — already-proven items (tab-color prefix, OSC 1337
  pane var) and the pending CLI-language decision this phase resolves.
- `.planning/REQUIREMENTS.md` — v1 scope (Phases 1-5) that the audit sweep and language choice
  must support.

### Proven Prior Art (reference only)
- `~/.config/wezterm/wezterm.lua` — ACTIVE config; contains the proven tab-color prefix and
  OSC 1337 pane-var mechanisms.
- `~/git/cco/wezterm-setup_/` — legacy bash attempt; escape-sequence/color reference only,
  does not scale cross-platform.
- `kitty-setup` (Python CLI) — reference for the Python/uv fallback path and hypothesis-driven
  methodology.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Proven WezTerm mechanisms in the active config: tab-level color via `set-tab-title` prefix
  (`"color:title"`); pane-level color via `WEZTERM_TAB_COLOR` user var set through OSC 1337.
  These are validated and do NOT need re-proving in Phase 0 — only the format gets documented/locked.

### Established Patterns
- Hypothesis-first development (`.tmp/` scratch → manual promotion → `docs/repro/`), per
  `docs/agent-iteration.md`. Phase 0 spikes follow this even though they produce decisions
  rather than config.
- Config layer is composable: one behavior per `~/.config/wezterm/wezterm-setup/<topic>.lua`.

### Integration Points
- The repo currently has no source code (`config/`, `cli/`, `tests/` not yet created). Phase 0
  output (the language decision) determines the CLI runtime that Phase 1 scaffolds.

### Known External Constraints (already discovered)
- `wezterm cli set-user-var` does NOT exist — pane user vars require the OSC 1337 escape.
- WezTerm hot-reloads `~/.config/wezterm/wezterm.lua` on save; no restart needed during dev.

</code_context>

<specifics>
## Specific Ideas

- The CLI-language proof scope is concrete and fixed: arg parsing + one real `wezterm cli`
  call + JSON + file I/O, implemented in both Lua and Python/uv.
- The audit deliverable is a committed catalogue document the whole project can lean on, with
  a Linux column now and a macOS column added on the later Mac pass.
- **Installer provisions Lua (Phase 1 design input):** the wezterm-setup installer must DETECT a
  missing Lua runtime and install it before setting up wezterm-setup. This means a target machine
  lacking Lua is NOT an argument against choosing Lua — provisioning is the installer's job, not a
  language-selection criterion. (Confirmed by observation: a clean Pop!_OS box had no `lua5.4`,
  no `luarocks`, and Lua ships no JSON stdlib — relevant as ergonomics evidence, not as a
  distribution veto.)

</specifics>

<deferred>
## Deferred Ideas

- **CLAUDE.md fix (D-08): DONE** — committed in `3eac165`. (The original "No auto-commit" rule
  was later replaced by a "prefer fewer commits + amend" discipline, so this is no longer pending.)
- **macOS verification pass:** full both-platform proof for CWD mechanism, audit catalogue, and
  language distribution is deferred to a single batched Mac session before Phase 1 closes (D-04/D-05).

None of these are scope creep — they are sequencing/timing decisions within Phase 0's mandate.

</deferred>

---

*Phase: 0-spikes-alignment*
*Context gathered: 2026-06-07*
