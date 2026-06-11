# Phase 2: Pane Identity - Context

**Gathered:** 2026-06-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 2 delivers per-pane visual identity through the `wez pane` CLI surface:

- `wez pane color <name|hex|rgba>` — set the pane background color
- `wez pane color reset` — restore the default background (PANE-02)
- `wez pane opacity <0..1>` and/or alpha-in-`rgba` — set per-pane translucency **(scope expansion — see D-03; spike-gated)**
- `wez pane title "<text|icon-name text>"` — set a custom title shown in the tab bar when the pane is focused (PANE-03), incl. icon-name shortcuts **(extends PANE-03 — see D-04)**
- Completion updated: named color profiles + `reset` + `title` + (new) opacity (PANE-04 / success #4)
- Color + title (+ opacity) **persist across focus changes** within the tab (PANE-04, success #3)

**Two layers ship together:** the `wez pane` CLI **and** the config-layer rendering it
depends on. The shipped `config/wezterm-setup/` currently has **no** tab-bar formatter and
**no** user-var/color handler — that rendering was proven only in the user's personal config
(`../wezterm-setup_`) pre-Phase-0. Phase 2 must port it into the distribution.

**Scope expansion flagged:** opacity (D-03) and icon-name shortcuts (D-04) go beyond
PANE-01..04 as written. Recommend formalizing in REQUIREMENTS.md as **PANE-05 (per-pane
opacity)** and extending **PANE-03** to include icon-name input. Captured here so planning
stays honest; the roadmap/requirements edit is a follow-up the user owns.

**macOS:** Linux-first, designed cross-platform (per D-18). Both OSC escapes are
terminal-emulator-level and platform-agnostic; macOS verified in the deferred Mac pass.
</domain>

<decisions>
## Implementation Decisions

### Color input model (PANE-01)
- **D-01:** The CLI accepts **three input forms**, normalized kitty-style before any escape
  is emitted (mirror `../kitty-setup` `scenes/colors.py`):
  1. **Named colors** — the 10 curated profiles (`red orange yellow green teal cyan blue navy
     purple pink`), case-insensitive, **autocompletable**.
  2. **Hex** — `#rgb` / `#rrggbb` (and `#rgba` / `#rrggbbaa`, alpha handled per D-03),
     `#`-optional, lowercased.
  3. **`rgba()` / `rgb()`** — accepted; passed through / parsed for the alpha component.
  **Validate-before-emit:** an unrecognized color errors to stderr with a friendly message
  and exits non-zero **before** any OSC escape is written (no half-applied state). Do **not**
  adopt kitty's 667-name X11 superset — keep the tight curated 10 for completion; full
  hex/rgba is the escape hatch for arbitrary colors.

### Rendering mechanism — dual write (PANE-01, PANE-04)
- **D-02:** Mirror the **proven prototype** (`../wezterm-setup_/bin/wez-tab` +
  `config/wezterm.lua`). Two escapes per `color` invocation, because "each pane is its own
  terminal":
  1. **OSC 11** — `\033]11;<hex>\033\\` sets the **actual per-pane background tint** to a
     dark muted variant of the chosen color (the visible "pane background").
  2. **OSC 1337 `SetUserVar=WEZTERM_TAB_COLOR=<base64>`** — drives the **tab-bar accent**
     read by the config-layer `format-tab-title` handler. Pane var **overrides** tab-level
     color (pane priority — locked in `tab-title-format.md`).
  `reset` (PANE-02) restores the default background (OSC 11 to the theme default + clears the
  user var). The config layer gains the `format-tab-title` event handler + the color-profile
  table (neither ships today — both ported from `../wezterm-setup_/config/wezterm.lua`).
  **There is no `wezterm cli set-user-var`** — the OSC escape is the only path
  (`wezterm-cli-surface.md`).

### Opacity — scope expansion, spike-gated (NEW: PANE-05 proposed)
- **D-03:** The user wants to **set color and opacity together**. Opacity is accepted **two
  ways**: (a) the **alpha channel** of an `rgba`/`#rrggbbaa` color, and (b) a **separate
  `--opacity <0..1>` flag** (or `wez pane opacity <0..1>`). **No proven per-pane opacity
  mechanism exists** in either reference: `../wezterm-setup_` does not handle opacity at all,
  and `../kitty-setup` (`docs/repro/h26-perpane-opacity.md`) proved opacity is
  **OS-window-scoped only**. Therefore this capability is **hypothesis-first** (project rule):
  - **D-06 (spike contract):** Spike **per-pane translucency first** (investigate
    `window:set_config_overrides`, OSC variants, any pane-scoped path).
    - **If achievable** → real per-pane opacity (`wez pane opacity 0.7` affects only that pane).
    - **If NOT achievable** → **accept the input but strip the alpha and render solid**,
      warn once. This is the user's explicit "strip the alpha" fallback.
  - **REJECTED alternative:** falling back to **OS-window-scoped** opacity. Rationale (kitty,
    `h26-perpane-opacity.md`): it dims unrelated panes/tabs sharing the window — a surprising
    side effect. **Never touch the OS window opacity** from `wez pane`.

### Title input (PANE-03)
- **D-04:** Title accepts **both** plain freeform **text + emoji** **and** the prototype's
  **icon-name shortcuts** (e.g. `docker`→🐳, `rust`→🦀, `git`→🔀; ~40 names, full map in
  `../wezterm-setup_/bin/wez-tab` `_weztab_icon`). `wez pane title docker "compose up"` →
  `🐳 compose up`; if the first token isn't a known icon name, the whole input is title text.
  Stored as the pane user var **`WEZTERM_TAB_TITLE`** (OSC 1337), which **overrides the tab's
  displayed title while the pane is active**. Empty string / `reset` clears it back to the
  auto title. Icon names are **autocompletable** alongside colors.

### Target pane & forward-compat (PANE-04)
- **D-05:** Phase 2 targets the **current pane only** — the OSC escapes are emitted from the
  calling pane, the natural and simplest target. **But design the internals to accept a pane
  target cleanly** so Phase 4 (scenes) can add `--pane-id` without rework: scenes will spawn
  multiple panes and set color + opacity + icon + title + run a command in each. The proven
  injection path for a non-current pane is **`wezterm cli send-text --pane-id <id>`** writing
  the raw OSC sequence (`wezterm-cli-surface.md`) — keep the escape-building logic separate
  from the "write to current pane's stdout" sink so a `--pane-id` sink drops in later.

### Claude's Discretion
- The **exact muted OSC-11 background hex** per color profile, the **CLI argument shape**
  (positional vs flag for opacity), the **completion wiring** into `cli/spec.lua` (D-16
  auto-generation), and the **config topic-file split** for the new formatter are the
  planner's to propose under the decisions above. Reference values are embedded in
  `<code_context>` below.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### In-repo locked decisions (read first)
- `.planning/decisions/tab-title-format.md` — pane color **takes priority** over tab color;
  OSC 1337 `SetUserVar=WEZTERM_TAB_COLOR` is the pane-color path; 10 color profile names.
- `.planning/decisions/wezterm-cli-surface.md` — **no `set-user-var` subcommand** (use OSC);
  `send-text --pane-id` exists (Phase 4 forward path); `set-tab-title --pane-id`; `split-pane`/
  `spawn` print new pane-ids; cwd inheritance is default on split/spawn.
- `.planning/decisions/cli-language.md` — Lua 5.4 CLI, luastatic single-binary packaging
  (relative `require` constraint for any new `cli/commands/pane.lua`).
- `.planning/phases/01-foundation/01-CONTEXT.md` — D-16 (completions auto-generated from
  `cli/spec.lua`), D-17 (config AUGMENT model — new config topic files merge via `apply`).

### Sibling reference repos (proven prototype + color/opacity model)
> These are **sibling repos**, not in this tree. Their critical data is embedded in
> `<code_context>` so planning does not depend on external access — but read them directly
> if available for full fidelity.
- `../wezterm-setup_/bin/wez-tab` — proven dual-write (OSC 11 + OSC 1337), the icon-name map,
  the 10-color list, the muted per-pane background hex table.
- `../wezterm-setup_/config/wezterm.lua` (lines 13–95) — the `format-tab-title` handler +
  `color_profiles` (tab-bar bg/fg) table to port into `config/wezterm-setup/`.
- `../kitty-setup/src/kitty_setup/scenes/colors.py` — `normalize_color`: validate-before-emit,
  alpha-strip (`_strip_alpha`), named lookup, `rgb()/rgba()` passthrough.
- `../kitty-setup/docs/repro/h26-perpane-opacity.md` — empirical proof opacity is
  OS-window-scoped only (the basis for D-03/D-06's strip-to-solid fallback).
- `../kitty-setup/docs/repro/friendly-color-input.md` — the friendly color-input UX rationale.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `cli/spec.lua` — single source of truth for the command tree (D-16). Add the `pane`
  namespace here (`color` / `title` subcommands + opacity flag); completion + `wez keys`
  pick it up automatically. The `pane`/`tab`/`scene` namespaces are intentionally left OPEN.
- `cli/vendor/argparse.lua`, `cli/vendor/dkjson.lua` — vendored; reuse for arg parsing / JSON.
- `cli/commands/*.lua` — established command-module pattern; add `cli/commands/pane.lua`
  WITHOUT editing the dispatcher (allow-list lookup by name, T-01-02 security).
- `config/wezterm-setup/init.lua` — `apply(config)` AUGMENT entry point (D-17); register the
  new `format-tab-title` handler as a new R3 topic module merged here.

### Established Patterns
- **Config = AUGMENT, never replace** (D-17): the new tab-bar formatter must be additive and
  import-safe under plain lua5.4 (guard the `wezterm` global, as `init.lua` does).
- **Hypothesis-first** (CLAUDE.md): opacity (D-03/D-06) starts as a spike in
  `.tmp/h<NN>-<slug>/` with a manual repro before integration. Color/title are already proven
  in `../wezterm-setup_` (document-and-port, lighter proof).
- **Lua relative `require`** (cli-language.md) for luastatic bundling.

### Integration Points / embedded reference data
- **OSC escapes** (from `wez-tab`):
  - Pane bg: `printf '\033]11;<hex>\033\\'`
  - Pane color user var: `printf '\033]1337;SetUserVar=WEZTERM_TAB_COLOR=%s\007' <base64(name)>`
  - Pane title user var: `printf '\033]1337;SetUserVar=WEZTERM_TAB_TITLE=%s\007' <base64(text)>`
- **Muted per-pane OSC-11 background hex** (proven values to port): red `#1f1617`,
  orange `#1f1916`, yellow `#1c1c16`, green `#161c17`, teal `#151b1a`, cyan `#161c1c`,
  blue `#161a1f`, navy `#14151c`, purple `#1a161f`, pink `#1f1619`.
- **Tab-bar `color_profiles` (bg/fg)** to port into the config formatter: red `{#5f1e1e,#f0c8c8}`,
  orange `{#5f3a1e,#f0d8c8}`, yellow `{#5f5f1e,#f0f0c8}`, green `{#1e5f2e,#c8f0d0}`,
  teal `{#1e4f4a,#c8f0e8}`, cyan `{#1e5f5f,#c8f0f0}`, blue `{#1e3a5f,#c8ddf0}`,
  navy `{#1a2040,#c8cce0}`, purple `{#3f1e5f,#d8c8f0}`, pink `{#5f1e4a,#f0c8e0}`;
  default `{#333333,#c0c0c0}`.
- **kitty alpha-strip rule** to mirror: 4-digit `#rgba`→`#rgb` (drop last nibble),
  8-digit `#rrggbbaa`→`#rrggbb` (drop last byte); 3/6-digit pass through.

</code_context>

<specifics>
## Specific Ideas

- "Copy the colors and transparency/opacity pattern from `../wezterm-setup_` and
  `../kitty-setup`." — the user explicitly wants these two references followed.
- "Set the color and opacity at the same time" is the headline ergonomic goal (D-03).
- "Named colors must be autocompletable" (D-01) — completion is a first-class requirement.
- "Accept rgba; if the alpha can't be honored, strip it" — verbatim fallback rule (D-06).
- Prepare the internals for a future pane-id target (scenes will set color+opacity+icon+title
  and run commands per pane) — D-05.

</specifics>

<deferred>
## Deferred Ideas

- **`--pane-id` / arbitrary-pane targeting** → Phase 4 (Ad-hoc Scenes). Mechanism known
  (`send-text --pane-id`); internals designed for it now (D-05), surface added there.
- **OS-window-scoped opacity** → explicitly **rejected**, not deferred (kitty rationale,
  D-03). Do not revive without a new decision.
- **kitty's 667-name X11/CSS color superset** → not adopted; the curated 10 + hex/rgba escape
  hatch is the deliberate choice (D-01).

</deferred>

---

*Phase: 2-pane-identity*
*Context gathered: 2026-06-10*
