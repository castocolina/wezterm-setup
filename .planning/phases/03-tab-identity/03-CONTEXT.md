# Phase 3: Tab Identity - Context

**Gathered:** 2026-06-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 3 delivers per-tab visual identity through the `wez tab` CLI surface, plus the
config-layer rendering that makes a tab's stored color actually paint:

- `wez tab color <name>` — set the tab accent color (TAB-01), visible on focused **and**
  unfocused tabs.
- `wez tab color <name> --title "<text>"` — set color + title in one command (TAB-03).
- `wez tab title "<text>"` — standalone title command (success criterion #5), with icon-name
  parity to `wez pane title` (D-03).
- `wez tab color reset` — clear the accent, keep the title (D-04).
- Empty `wez tab title` — clear the title, keep the accent (D-04).
- Completion updated: `wez tab color <Tab>` → color profiles; `wez tab title` + `--title` →
  icon names (success #5).

**Mechanism is proven; rendering is NOT yet wired.** The `set-tab-title "color:title"` prefix
encoding is proven (2026-06-07) and locked in `tab-title-format.md`. BUT the Phase 2 formatter
(`config/wezterm-setup/format-tab-title.lua`) currently reads only the **pane** user vars
(`WEZTERM_TAB_COLOR` / `WEZTERM_TAB_TITLE`) and treats `tab.tab_title` as a literal string — it
does **not** parse the `color:` prefix. **Phase 3 must extend the formatter to parse the prefix**
so tab-level color renders. This is the central integration task, on top of the `wez tab` CLI.

**Behavior matrix to verify** (roadmap note): TAB-04 pane-color-over-tab-color priority and
TAB-05 active-tab distinction are already implemented in the formatter; Phase 3 verifies the full
matrix once tab-prefix parsing is added.

**macOS:** Linux-first, designed cross-platform (D-18). Both `set-tab-title` and the formatter
are emulator-level / platform-agnostic; macOS verified in the deferred Mac pass.
</domain>

<decisions>
## Implementation Decisions

### Merge behavior — read-modify-write (TAB-01, TAB-02, TAB-03)
- **D-01:** `wez tab color` and `wez tab title` **preserve the other half** of the tab's identity.
  `wez tab color blue` on a tab currently `"green:api"` → `"blue:api"` (title kept); `wez tab title
  "api"` on a `"blue:"` tab keeps the color. This requires **read-modify-write**: read the current
  tab title (via `wezterm cli list --format json`, see `wezterm-cli-surface.md`), parse the existing
  `color:title`, swap only the requested half, write back with `set-tab-title`. Clobber was
  **rejected** — losing the title on every recolor is surprising.

### Storage encoding — always write the colon (TAB-01, TAB-03)
- **D-02:** The stored tab-title form is **always** `<color>:<title>` with **either side allowed
  empty**: `":api"` = title only (no accent), `"blue:"` = color only (no title), `"blue:api"` = both.
  The colon is the structural marker. This disambiguates a title-without-color from a bare color
  name (the locked parse rule treats a **no-colon** token as a *color*, so a no-colon `"api"` would
  otherwise be misread as a color → default profile + lost title). **Rejected:** a formatter
  heuristic ("is this token a known profile name?" — a tab literally titled "blue" would render as a
  color) and "always carry a color" (a title-only tab would get an unwanted accent).

### Formatter extension (TAB-02, TAB-04, TAB-05)
- **D-03a:** Extend `format-tab-title.lua` to parse `tab.tab_title` into `(tabColor, tabTitle)` by
  splitting on the **first** `:` (empty-left → default profile). Resolution precedence is **locked
  by pane-priority (TAB-04)**, not a new decision:
  - **accent** = pane `WEZTERM_TAB_COLOR` → else tab-prefix color → else default profile.
  - **title** = pane `WEZTERM_TAB_TITLE` → else tab-prefix title → else `tab.active_pane.title`.
  - Active-tab `●->` indicator + bold (TAB-05) is already shipped; keep it regardless of accent.

### `wez tab title` command + icon parity (success #5, D-03 mirror)
- **D-03:** Ship `wez tab title "<text>"` as a standalone command **and** the combined
  `wez tab color <name> --title "<text>"` flag. Both accept the **same icon-name shortcuts** as
  Phase 2's `wez pane title` (docker→🐳, rust→🦀; the existing icon-name map; first token = known icon name →
  prepend the glyph, else whole input is title text). **Factor the Phase 2 icon resolver into a
  shared lib** (e.g. `cli/lib/`) so `tab.lua` and `pane.lua` share one map rather than duplicating it.

### Reset / clear — mirror Phase 2 (D-04)
- **D-04:** Per-attribute clears, same verbs as `wez pane`:
  - `wez tab color reset` → write `":title"` (accent removed, title kept).
  - `wez tab title` with empty/no args → write `"color:"` (title removed, accent kept).
  Both go through the D-01 read-modify-write path so the other half survives. **Rejected:** a single
  coarse `wez tab reset` clear-all (can't drop just one attribute).

### Target tab — current now, `--tab-id`-ready (D-05 mirror)
- **D-05:** Act on the **active tab** this phase (no flag needed; `set-tab-title` defaults to the
  active tab). Design internals so a `--tab-id` sink drops in for Phase 4 scenes without rework —
  keep tab-id resolution separate from the read-modify-write/write logic. `set-tab-title --pane-id`/
  tab targeting exists (`wezterm-cli-surface.md`). **No `--tab-id` surface ships in Phase 3.**

### Color input parity (carried from Phase 2 D-01)
- **D-06:** `wez tab color` accepts the same input model as `wez pane color`: the 10 curated named
  profiles (case-insensitive, autocompletable) as the primary path. Hex/rgba parity for tabs is the
  planner's call (tab accent is a named-profile lookup in the formatter; named profiles are the
  documented surface for TAB-01). **Validate-before-emit:** an unknown color errors to stderr and
  exits non-zero **before** any `set-tab-title` write (no half-applied state) — mirror Phase 2.

### Claude's Discretion
- Exact CLI arg shape (positional vs flag), the shared icon-resolver lib location, the
  read-modify-write parse helper placement, completion wiring into `cli/spec.lua` (D-16
  auto-generation), and whether `wez tab color` accepts raw hex/rgba beyond named profiles —
  planner's to propose under the decisions above.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### In-repo locked decisions (read first)
- `.planning/decisions/tab-title-format.md` — the **locked** `"color:title"` prefix encoding,
  the first-`:` parse rule, the bare-token-is-a-color rule (the basis for D-02), and the 10 color
  profiles. Phase 3 writes this format via `set-tab-title`.
- `.planning/decisions/wezterm-cli-surface.md` — `set-tab-title` exists and targets the active tab
  by default / accepts a tab target (D-05 forward path); `wezterm cli list --format json` is the
  read path for current tab state (D-01); **no `set-user-var`** subcommand.
- `.planning/decisions/cli-language.md` — Lua 5.4 CLI, luastatic single-binary (relative `require`
  constraint for a new `cli/commands/tab.lua` and any shared `cli/lib/` module).
- `.planning/phases/02-pane-identity/02-CONTEXT.md` — the **direct template** to mirror: color input
  model (D-01), icon-name map (D-04), reset conventions, `--id`-ready internals (D-05).
- `.planning/phases/01-foundation/01-CONTEXT.md` — D-16 (completions auto-generated from
  `cli/spec.lua`), D-17 (config AUGMENT model — formatter changes merge via `apply`).

### In-repo code to extend / mirror
- `config/wezterm-setup/format-tab-title.lua` — the formatter to extend with `color:` prefix
  parsing (currently reads pane user vars only; lines 98–113 are the handler, `resolve_profile`
  lines 40–53, `color_profiles` lines 22–35).
- `cli/commands/pane.lua` (+ `cli/commands/pane_test.lua`) — the command-module + icon-resolver +
  validate-before-emit pattern `tab.lua` mirrors; source of the icon map to factor into shared lib.
- `cli/spec.lua` — add the `tab` namespace (`color`/`title` subcommands + `--title` flag);
  completion + `wez keys` pick it up automatically (D-16). `tab` namespace is intentionally OPEN.

### Sibling reference repo (proven prototype)
> Sibling repo, not in this tree — read directly if available for full fidelity.
- `../wezterm-setup_/bin/wez-tab` — the proven `set-tab-title "color:title"` dual-path, the
  icon-name map, the 10-color list.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `cli/spec.lua` — single source of truth; add the `tab` namespace here (mirror the `pane` block at
  lines 116–126). Completion + `wez keys` extend automatically (D-16).
- `cli/commands/pane.lua` — established command-module pattern (allow-list dispatch, no dispatcher
  edit, T-01-02). Add `cli/commands/tab.lua` the same way. **Icon resolver + color normalizer here
  should be lifted into a shared `cli/lib/` module** for `tab.lua` to reuse (D-03/D-06).
- `cli/vendor/argparse.lua`, `cli/vendor/dkjson.lua` — vendored; reuse for arg parsing and for
  parsing `wezterm cli list --format json` (the D-01 read step).
- `config/wezterm-setup/format-tab-title.lua` — extend, don't replace (D-17 AUGMENT); add prefix
  parsing to the handler + a pure split helper (unit-testable under plain lua5.4, no `wezterm` dep).

### Established Patterns
- **Config = AUGMENT** (D-17): formatter changes are additive and import-safe (guard the `wezterm`
  global, as the module already does at lines 92–95).
- **Validate-before-emit** (Phase 2 D-01): reject unknown colors before any write — no half-applied
  tab title.
- **Pure helpers + thin live wrapper**: `resolve_profile`/`format_label`/`build_runs` are already
  `wezterm`-free and unit-tested; add the prefix-split helper in the same style.
- **Hypothesis policy**: color + title here are **document-and-port** (proven in `../wezterm-setup_`),
  so lighter proof than a spike — a manual repro of the full behavior matrix is the bar.

### Integration Points
- **Write path:** `wez tab color/title` → read current title (`wezterm cli list --format json`) →
  merge → `wezterm cli set-tab-title "<color>:<title>"` (active tab).
- **Render path:** `format-tab-title.lua` handler reads `tab.tab_title`, splits on first `:`,
  resolves accent (pane var > tab prefix > default), resolves title (pane var > tab prefix > pane
  title).
</code_context>

<specifics>
## Specific Ideas

- "Preserve my title when I change the color" — the headline ergonomic decision (D-01).
- "Full parity with `wez pane`" — same icon shortcuts, same reset verbs, same input model (D-03/D-04/D-06).
- Keep internals ready for a future per-tab target so Phase 4 scenes can style tabs without rework (D-05).
</specifics>

<deferred>
## Deferred Ideas

- **`--tab-id` / arbitrary-tab targeting** → Phase 4 (Ad-hoc Scenes). Mechanism known
  (`set-tab-title` tab targeting); internals designed for it now (D-05), surface added there.
- **Single coarse `wez tab reset` clear-all** → rejected, not deferred (D-04 chose per-attribute
  clears). Revisit only with a new decision.
- **`wez tab` styling beyond color + title** (e.g. tab-level icons separate from title) → not in
  scope; not requested.

None — discussion stayed within phase scope.
</deferred>

---

*Phase: 3-tab-identity*
*Context gathered: 2026-06-11*
