# Decision: Tab-title color-prefix format (locked)

**Decision:** A tab's accent color is encoded as a **prefix in the tab title string**, in the form
`color:title` (or bare `color` when no title is set). This is the format all phases read/write via
`wezterm cli set-tab-title`.

**Status:** **Proven 2026-06-07** (pre-Phase-0; validated in the active config). This is a
**document-and-lock** decision — no re-proving needed (CONTEXT code_context).

**Serves:** TAB-01..TAB-05. **Phase 0 plan:** `00-04-PLAN.md`.

## Format spec

- **Encoding:** the tab title string is `"<color>:<title>"`. With no title: `"<color>"`.
- **Parse rule:** split on the **first** `:`. Left of it = color profile name; right of it = display
  title. A title may itself contain `:` — only the first separator is structural.
- **Supported color profiles:** `red`, `orange`, `yellow`, `green`, `teal`, `cyan`, `blue`, `navy`,
  `purple`, `pink`.
- **Why this mechanism:** `tab.tab_title` survives pane switches within the tab, whereas pane user
  vars do not — so storing the color in the tab title makes the accent persist correctly. (Proven;
  see PROJECT.md Key Decisions.)
- **Rendering:** the config layer's tab-bar formatter reads the prefix, maps the color name to its
  palette value, strips the prefix, and renders the remaining title text with the accent.

## Companion: pane-level color override
Pane-level color (which takes priority over tab color) is set via the **OSC 1337 `SetUserVar`
escape** writing `WEZTERM_TAB_COLOR` — NOT via `wezterm cli` (there is no `set-user-var` subcommand;
see `wezterm-cli-surface.md`). Already proven.

## Phase implications
- Phase 3 (`wez tab color`) writes the `color:title` string via `set-tab-title`.
- Phase 2 (`wez pane color`) writes the OSC 1337 user var.
- No new mechanism needed — both paths are proven; these phases wire them into the CLI surface.
