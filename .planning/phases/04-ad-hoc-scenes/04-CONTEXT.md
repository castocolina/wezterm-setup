# Phase 4: Ad-hoc Scenes - Context

**Gathered:** 2026-06-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 4 delivers `wez scene new` — a single command that materializes a fully configured
multi-pane tab without any recipe file:

- A **layout** (`tall`, `tall:mirrored`, `grid`, `horizontal`) — SCEN-02.
- **N panes**, where N is **derived from the number of `--pane` entries** (no separate count flag).
- A **per-pane startup command** (sent into each pane's shell) — SCEN-01.
- **Per-pane background color + title** and a **tab-level color + title** — SCEN-01.
- **Completion** for `--layout` (layout names) and all `wez scene new` flags — success #3.

**This is the ORCHESTRATION phase.** It invents no new escape mechanism — it composes the
already-proven surfaces:
- `wez pane` color/title (Phase 2) and `wez tab` color/title (Phase 3), both built with
  `--pane-id`/`--tab-id`-ready internals **specifically for this phase** (Phase 2 D-05, Phase 3 D-05).
- `wezterm cli spawn` (new tab, prints pane-id), `split-pane --pane-id ... --percent/--cells`
  (prints new pane-id), `send-text --pane-id` (inject OSC escapes + type commands into a pane).

**No prototype to port.** Unlike Phases 2–3, `../wezterm-setup_` has **no scene/layout code**
(only `wez-tab`). Scenes are genuinely new territory → hypothesis-first applies (a manual repro of
each layout + the materialization logic is the integration bar, per CLAUDE.md).

**Saved/named recipes, `wez scene launch`, seeded examples, and dynamic recipe-name completion are
Phase 5 — explicitly out of scope here.**

**macOS:** Linux-first, designed cross-platform (D-18). All mechanisms are `wezterm cli` /
emulator-level; macOS verified in the deferred Mac pass.
</domain>

<decisions>
## Implementation Decisions

### Pane count & layout scaling (SCEN-01, SCEN-02)
- **D-01:** **Pane count is derived from the number of `--pane` entries** — no separate `--panes`
  flag. `wez scene new --layout grid --pane '…' --pane '…' --pane shell` → 3 panes. Count and
  content come from one ordered list. **Rejected:** an explicit `--panes N` flag and a "both,
  --panes optional override" hybrid — the derived form is the simplest honest reading and keeps a
  single source of truth for "how many panes."
- **D-02:** **All four layouts adapt to an arbitrary N** (no fixed canonical count). Conceptually:
  `tall` = 1 main + (N-1) stacked; `tall:mirrored` = tall flipped; `grid` = roughly-square N×M;
  `horizontal` = N side-by-side. **Rejected:** fixed per-layout counts and a "minimums" guard —
  layouts should just scale. (Exact split geometry / percent math is the planner's; the **invariant**
  is the requested layout shape at the requested N.)

### Per-pane command surface (SCEN-01)
- **D-03:** **Repeated `--pane` flag, flag order = pane order** (pane 1, 2, 3 …). Chosen over a
  positional list after `--` (mixes badly with per-pane styling, harder to extend) and over a `-p`
  shorthand as the primary form. A short alias MAY be added as secondary (planner's call), but
  `--pane` is the canonical surface.
- **D-04:** A pane with **no startup command is written as the literal keyword `shell`** —
  `--pane shell` → a plain interactive shell. Chosen over empty-string and "all forms accepted"; a
  program literally named `shell` is a rare edge handled by normal quoting/escaping.

### Per-pane + tab styling (SCEN-01)
- **D-05:** `wez scene new` styles **both levels**: a **tab-level** color + title for the whole
  scene **and** a **per-pane** background color + title for each pane. (User's explicit steer —
  "tab color, pane color bg, title". This is the *richer* reading of SCEN-01's "N styled panes",
  beyond the tab-only minimum.)
- **D-06:** Per-pane attributes attach via an **inline `key=value` form inside the `--pane` value**,
  backward-compatible with D-03/D-04:
  - `--pane 'docker stats'` → command only (bare value = the command).
  - `--pane shell` → plain shell (D-04 keyword preserved).
  - `--pane 'cmd=docker stats, color=teal, title=stats'` → command + per-pane bg color + title.
  - `color=` and `title=` are optional; keys order-independent.
  **Rejected:** positional paired flags (`--pane … --pane-color … --pane-title …` mapped by index)
  — three lists to keep aligned, a missing entry shifts everything. (Exact delimiter/parse rules and
  whether `cmd=` is required vs implied-by-bare-value are the planner's, under this shape.)
- **D-07:** **Auto pane title from the command** when `title=` is omitted — a pane running
  `docker stats` is titled from its command. Uses the Phase 2 pane-title path under the hood.
  Explicit `title=` overrides the auto title.

### Command lifecycle — run in shell, pane persists (SCEN-01)
- **D-08:** Each pane **spawns the user's shell**; the startup command is **sent into that shell**
  (`send-text` + newline), so the **pane stays alive** after the command finishes. One-shots
  (`docker ps`) leave their output visible and a working shell behind; long-runners (`logs -f`)
  run normally. **Rejected:** running the command AS the pane program (`split-pane -- PROG`), which
  kills the pane the instant a one-shot exits and needs a separate path for the color escapes.
  No `exec=`-style run-as-program opt-in this phase (can revisit later with a new decision).
- **D-09:** **Panes must end up visually clean** — the styling escapes (per-pane bg color via OSC 11,
  user vars via OSC 1337, etc.) are injected by command, but must leave **no visible escape residue**
  in the pane; the pane should look "as if nothing happened" before the command's own output. (User's
  explicit requirement. Mechanism — quiet emission and/or a clear after injection — is the planner's.)

### Scene materialization — where the tab opens (NEW area, SCEN-01)
- **D-10:** `wez scene new` **inspects the current tab's pane count** and decides where to build:
  - **Current tab has exactly 1 pane** → build the scene **in the current tab**, **absorbing the
    current pane into the scene** as pane 1 (preferred: reuse it — it inherits its cwd; acceptable:
    drop/replace it during render). The **mechanism is the planner's discretion; the invariant is not**.
  - **Current tab has ≥2 panes** → **spawn a new tab** (same window) and build the scene there,
    leaving the existing multi-pane tab untouched.
- **D-11:** **Exact final pane count, never +1.** A 2-pane scene launched from a 1-pane tab ends with
  **exactly 2 panes** — the current pane counts as one of the requested panes, it is never left as an
  extra. The reuse-vs-drop choice (D-10) must preserve this invariant.
- **D-12:** **Same OS window, always** — the ≥2-panes case opens a new **tab**, never a new **window**.
  **No override flags this phase** (no `--new-tab` / `--here`): materialization is 100% automatic.
  Forcing flags can be revisited later with a new decision.

### Claude's Discretion (planner to propose under the decisions above)
- The exact flag shape for the **tab-level color + title** of the scene (reusing the Phase 3
  `wez tab` color/title path; `"color:title"` encoding is locked in `tab-title-format.md`).
- Which pane is **focused** when the scene finishes building (pane 1 / the layout's main pane / last).
- The **split geometry** (percent/cells per layout at N), the **`--pane` value parse rules**
  (delimiter, `cmd=` implicit-vs-explicit), and any **settle/timing** needed before `send-text`
  reaches a freshly spawned shell.
- **Completion wiring** for `wez scene new` (auto-generated from `cli/spec.lua` per D-16; `--layout`
  candidate values via the hidden `wez __complete` hook — the single dynamic-value extension point).
- Whether the per-pane styling reuses `wez pane` via a shipped **`--pane-id` surface** or stays
  scene-internal by calling the shared escape-builders directly (Phase 2/3 left both paths open).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### In-repo locked decisions (read first)
- `.planning/decisions/wezterm-cli-surface.md` — the orchestration toolbox: `spawn` (new tab, prints
  new pane-id), `split-pane` (`--pane-id`, `--left/right/top/bottom/horizontal`, `--cells`,
  `--percent`, `--cwd`, prints new pane-id), `send-text --pane-id` (inject OSC escapes + type
  commands), `set-tab-title --tab-id/--pane-id`, `activate-pane --pane-id`, `list --format json`
  (read current tab/pane topology for D-10), `kill-pane` (if D-10 chooses drop). **cwd inheritance is
  default on split/spawn** (relevant to reusing the current pane's cwd). **No `set-user-var`** → OSC 1337.
- `.planning/decisions/tab-title-format.md` — locked `"color:title"` tab encoding, first-`:` parse
  rule, 10 color profiles, **pane color > tab color** priority (governs how scene per-pane vs tab
  color resolve in the formatter).
- `.planning/decisions/cwd-mechanism.md` — cwd inheritance is WezTerm-default on split/spawn; the
  reused current pane (D-10) keeps its cwd for free.
- `.planning/decisions/cli-language.md` — Lua 5.4 CLI, luastatic single-binary (relative `require`
  constraint for a new `cli/commands/scene.lua` and any shared layout/parse lib).

### Prior phase contexts (the direct templates this phase composes)
- `.planning/phases/02-pane-identity/02-CONTEXT.md` — **D-05 `--pane-id`-ready internals** (escape-build
  separated from the write sink; `send-text --pane-id` is the proven non-current-pane path), the OSC 11
  + OSC 1337 dual-write, the muted per-pane bg hex table, the 10 color profiles, the icon-name map,
  validate-before-emit.
- `.planning/phases/03-tab-identity/03-CONTEXT.md` — **D-05 `--tab-id`-ready internals**, read-modify-write
  of the tab title, the `wez tab color/title` path the scene's tab styling reuses.
- `.planning/phases/01-foundation/01-CONTEXT.md` — **D-16** (completion + `wez keys` auto-generated from
  `cli/spec.lua`; the `scene` namespace is already reserved + OPEN), **D-17** (config AUGMENT model).

### In-repo code to extend / mirror
- `cli/spec.lua` — add the `scene` namespace here (`new` subcommand + `--layout` + repeated `--pane`
  + tab `--color`/`--title`). Completion + `wez keys` extend automatically (D-16). Mirror the `pane`
  block (lines 118–128) and `tab` block (lines 130–145).
- `cli/commands/pane.lua` (+ `pane_test.lua`) — the command-module pattern (allow-list dispatch, no
  dispatcher edit, T-01-02); the per-pane color/title escape-builder + `--pane-id`-ready sink the
  scene drives for each pane.
- `cli/commands/tab.lua` (+ `tab_test.lua`) — the tab color/title read-modify-write the scene reuses
  for tab-level styling.
- `cli/lib/title.lua` (+ `title_test.lua`) — the shared icon-name resolver (auto pane title D-07,
  explicit `title=` D-06).
- `config/wezterm-setup/format-tab-title.lua` — the formatter that renders the per-pane and tab
  colors the scene sets (pane var > tab prefix > default; already shipped from Phases 2–3).

### Sibling reference repo
> Sibling repo, not in this tree — read directly if available. **Has NO scene/layout prototype.**
- `../wezterm-setup_/bin/wez-tab` — proven OSC escape patterns + icon map + color list only; scene
  orchestration is new work with no port source.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `cli/spec.lua` — single source of truth; the `pane`/`tab`/**`scene`** namespaces are deliberately
  OPEN (spec.lua line ~20 note). Add `scene new` here; completion (D-16) + `wez keys` pick it up with
  no generator edit.
- `cli/commands/pane.lua` + `cli/commands/tab.lua` — the scene **orchestrates these**. Both were built
  with the escape-builder separated from the "write to current pane" sink (Phase 2/3 D-05) precisely so
  the scene can target spawned panes via `send-text --pane-id`.
- `cli/lib/title.lua` — shared icon-name → glyph map (D-07 auto titles, D-06 explicit titles).
- `cli/vendor/argparse.lua`, `cli/vendor/dkjson.lua` — arg parsing + parsing `wezterm cli list --format
  json` (read current-tab topology for the D-10 materialization decision).

### Established Patterns
- **Escape-build / write-sink separation** (Phase 2/3 D-05) — the single most important reuse: per-pane
  color + title escapes are built pure, then written to a target pane via `send-text --pane-id`. The
  scene is the first consumer of the non-current-pane sink.
- **Validate-before-emit** (Phase 2 D-01) — reject an unknown layout name and any unknown per-pane/tab
  color **before** spawning anything (no half-built scene).
- **Config = AUGMENT** (D-17) — no formatter change needed; Phases 2–3 already render the colors the
  scene sets.
- **Spec-driven completion** (D-16) — `--layout` candidate values route through the hidden
  `wez __complete <context>` hook (the single dynamic-value extension point), same as color names.
- **Hypothesis-first** (CLAUDE.md) — layouts + materialization are NEW (no port source): prove the
  4 layouts and the 1-pane-reuse / ≥2-pane-new-tab logic via a manual repro before integration.

### Integration Points
- **Build path (per scene):** read current tab topology (`list --format json`) → decide target
  (D-10: reuse current pane vs new tab) → `spawn`/`split-pane` per layout (D-02) collecting pane-ids →
  for each pane: `send-text --pane-id` the per-pane color/title OSC escapes (D-05/D-06, clean per D-09)
  → `set-tab-title` the tab color/title → `send-text --pane-id` the startup command + newline (D-08) →
  activate the focus pane.
- **Render path:** unchanged — `format-tab-title.lua` already resolves pane var > tab prefix > default.
</code_context>

<specifics>
## Specific Ideas

- "Si llamo `wez scene --pane '…' --pane '…'` espero que se abran dos panes en el mismo tab
  ejecutando dos comandos; si no paso comando, me quedo con la shell para hacer lo que quiera." —
  the headline ergonomic model (D-01/D-03/D-04/D-08).
- "Como wezterm hace todo con comandos (no por socket como kitty), la personalización se inyecta con
  comandos, pero el pane tiene que quedar **limpio, como si nada hubiera pasado**." — the clean-pane
  requirement (D-09).
- "Detectar cuántos panes hay en el tab: si es 1, armar acá tomando el pane actual como parte del
  target; si tiene ≥2, abrir un tab nuevo." — the materialization rule (D-10/D-11/D-12).
- "El final tiene que ser exactamente los panes deseados (2, no 3) — reusar el actual (ideal) o
  descartarlo durante el render." — the exact-count invariant (D-11).
- "Misma ventana del SO, simple, sin overrides." — (D-12).
</specifics>

<deferred>
## Deferred Ideas

- **Named/saved scene recipes, `wez scene launch <name>`, seeded example recipes, dynamic recipe-name
  completion** → Phase 5 (Named Scenes). Out of scope here (SCEN-03..06).
- **`exec=`-style run-as-program panes** (pane closes on command exit) → not this phase (D-08 chose
  run-in-shell uniformly). Revisit only with a new decision.
- **Materialization override flags** (`--new-tab` / `--here` to force placement) → not this phase
  (D-12 chose 100% automatic). Revisit with a new decision.
- **New OS window for a scene** → rejected, not deferred (D-12: same window, new tab only).

None beyond the above — discussion stayed within phase scope.
</deferred>

---

*Phase: 4-ad-hoc-scenes*
*Context gathered: 2026-06-12*
