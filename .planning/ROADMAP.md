# Roadmap: wezterm-setup

**Milestone:** v1  
**Granularity:** Coarse  
**Coverage:** 30/30 v1 requirements mapped + Phase 0 (validation, no REQUIREMENTS.md items)

---

## Phases

- [x] **Phase 0: Spikes & Alignment** - Lock open engineering decisions before building begins
- [ ] **Phase 1: Foundation** - Install/uninstall, CWD, clear keybinding, curated bindings, doctor, keys
- [ ] **Phase 2: Pane Identity** - Per-pane background color and title via `wez pane`
- [ ] **Phase 3: Tab Identity** - Per-tab accent color and title via `wez tab` (mechanism proven)
- [ ] **Phase 4: Ad-hoc Scenes** - `wez scene new` with layout and styled panes
- [ ] **Phase 5: Named Scenes** - Named recipes, `wez scene launch <name>`, shell completion

---

## Phase Details

### Phase 0: Spikes & Alignment
**Goal**: All open engineering decisions are resolved with evidence before Phase 1 begins
**Depends on**: Nothing
**Requirements**: None — this phase produces decisions, not shipped features
> Phase 0 has no REQUIREMENTS.md items by design. It validates the engineering assumptions
> that every subsequent phase depends on. Outputs are logged to `.planning/decisions/` and
> promoted to PROJECT.md Key Decisions on completion.

**Validation targets:**
- CLI language: Lua 5.4 standalone viability (embed vs. system binary vs. Python/uv fallback)
- CWD mechanism: `wezterm cli get-pane-direction` vs. `$WEZTERM_PANE` env vs. OSC 7 — which survives pane splits on both platforms
- Remote control surface: confirm which `wezterm cli` subcommands exist and are stable on both Linux and macOS versions in daily use
- Tab-title prefix convention: already proven (`"color:title"`) — document and lock format

**Success Criteria** (what must be TRUE):
1. A decision is recorded for CLI language with a working prototype script demonstrating viability
2. CWD inheritance mechanism is proven on both Linux and macOS with a standalone experiment script
3. The full `wezterm cli` command surface is audited and any gaps (missing subcommands) are documented with workarounds
4. All Phase 0 decisions are written to PROJECT.md Key Decisions before Phase 1 planning begins

**Plans**: TBD

---

### Phase 1: Foundation
**Goal**: Users can install, configure, and diagnose a working wezterm-setup on any supported platform
**Depends on**: Phase 0
**Requirements**: INST-01, INST-02, INST-03, INST-04, INST-05, FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, DIAG-01, DIAG-02, DIAG-03, DIAG-04, DIAG-05

**Success Criteria** (what must be TRUE):
1. Running the installer on a clean machine injects a single managed block into `wezterm.lua`, creates a timestamped backup, and leaves everything else untouched — re-running prompts rather than silently overwriting
2. Running the uninstaller (with optional granular flags) leaves the system in the state the user selects — managed config, CLI binary, and sentinel block each removable independently
3. New tabs and panes open in the cwd of the previously active pane on both Linux and macOS without any manual configuration
4. `wez doctor` exits 0 on a healthy install; `wez keys` lists all active bindings grouped by category, flags conflicts, and supports `--json` output
5. Shell completion scripts are installed and registered for zsh and bash; `wez <Tab>` completes subcommands, `wez doctor` and `wez keys` flags complete

**Plans**: TBD

---

### Phase 2: Pane Identity
**Goal**: Users can assign a distinct background color and custom title to any pane via the CLI
**Depends on**: Phase 1
**Requirements**: PANE-01, PANE-02, PANE-03, PANE-04

**Success Criteria** (what must be TRUE):
1. `wez pane color <name|hex>` visibly changes the pane background; `wez pane color reset` restores the default — both verified on Linux and macOS
2. A custom pane title set via `wez pane title "<text>"` appears in the tab bar when that pane is focused
3. Pane color and title survive focus switches between panes within the same tab — no flicker or reset on focus change
4. Completion is updated: `wez pane color <Tab>` completes named color profiles; `wez pane title` and `wez pane color reset` complete

**Plans**: TBD
**UI hint**: yes

---

### Phase 3: Tab Identity
**Goal**: Users can assign a persistent accent color and title to any tab via the CLI
**Depends on**: Phase 2
**Requirements**: TAB-01, TAB-02, TAB-03, TAB-04, TAB-05

> Note: The color-via-`set-tab-title`-prefix mechanism is already proven (2026-06-07).
> This phase integrates it into the `wez tab` CLI surface and verifies the full behavior matrix.

**Success Criteria** (what must be TRUE):
1. `wez tab color <name>` sets the accent color visible on both focused and unfocused tabs; `wez tab color <name> --title "<text>"` sets both in one command
2. Tab accent color persists when the active pane changes within the tab — the color does not reset on pane switch
3. When both a pane color and a tab color are set on the same tab, the pane color takes visual priority
4. The active tab is always visually distinct from inactive tabs regardless of what accent color (or none) is applied
5. Completion is updated: `wez tab color <Tab>` completes named color profiles; `wez tab title` and combined `--title` flag complete

**Plans**: TBD
**UI hint**: yes

---

### Phase 4: Ad-hoc Scenes
**Goal**: Users can launch a fully configured multi-pane tab in one command without writing a recipe file
**Depends on**: Phase 3
**Requirements**: SCEN-01, SCEN-02

**Success Criteria** (what must be TRUE):
1. `wez scene new` accepts layout, pane count, per-pane startup commands, tab color, and tab title as arguments and produces a correctly configured tab
2. All four required layouts (`tall`, `tall:mirrored`, `grid`, `horizontal`) produce visually correct pane arrangements and accept per-pane startup commands
3. Completion is updated: `wez scene new --layout <Tab>` completes layout names; all `wez scene new` flags complete

**Plans**: TBD
**UI hint**: yes

---

### Phase 5: Named Scenes
**Goal**: Users can save and replay workspace layouts by name, with tab completion and seeded examples on install
**Depends on**: Phase 4
**Requirements**: SCEN-03, SCEN-04, SCEN-05, SCEN-06

**Success Criteria** (what must be TRUE):
1. A TOML or Lua recipe file in `~/.config/wezterm-setup/scenes/` is launchable by name via `wez scene launch <name>` and produces the same result as an equivalent `wez scene new` call
2. `wez scene launch <Tab>` dynamically completes recipe names from `~/.config/wezterm-setup/scenes/` — adding or removing a recipe file updates completion without any manual step
3. A fresh install seeds three example recipes (`ai`, `docker`, `dev`) using copy-if-absent — reinstalling does not overwrite user edits to those files

**Plans**: TBD

---

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. Spikes & Alignment | 4/4 | Complete | 2026-06-07 |
| 1. Foundation | 0/? | Not started | - |
| 2. Pane Identity | 0/? | Not started | - |
| 3. Tab Identity | 0/? | Not started | - |
| 4. Ad-hoc Scenes | 0/? | Not started | - |
| 5. Named Scenes | 0/? | Not started | - |

---

## Coverage

| Requirement | Phase | Status |
|-------------|-------|--------|
| INST-01 | Phase 1 | Pending |
| INST-02 | Phase 1 | Pending |
| INST-03 | Phase 1 | Pending |
| INST-04 | Phase 1 | Pending |
| INST-05 | Phase 1 | Pending |
| FOUND-01 | Phase 1 | Pending |
| FOUND-02 | Phase 1 | Pending |
| FOUND-03 | Phase 1 | Pending |
| FOUND-04 | Phase 1 | Pending |
| FOUND-05 | Phase 1 | Pending |
| DIAG-01 | Phase 1 | Pending |
| DIAG-02 | Phase 1 | Pending |
| DIAG-03 | Phase 1 | Pending |
| DIAG-04 | Phase 1 | Pending |
| DIAG-05 | Phase 1 | Pending |
| PANE-01 | Phase 2 | Pending |
| PANE-02 | Phase 2 | Pending |
| PANE-03 | Phase 2 | Pending |
| PANE-04 | Phase 2 | Pending |
| TAB-01 | Phase 3 | Pending |
| TAB-02 | Phase 3 | Pending |
| TAB-03 | Phase 3 | Pending |
| TAB-04 | Phase 3 | Pending |
| TAB-05 | Phase 3 | Pending |
| SCEN-01 | Phase 4 | Pending |
| SCEN-02 | Phase 4 | Pending |
| SCEN-03 | Phase 5 | Pending |
| SCEN-04 | Phase 5 | Pending |
| SCEN-05 | Phase 5 | Pending |
| SCEN-06 | Phase 5 | Pending |

**v1 coverage: 30/30 requirements mapped. Phase 0 carries validation work only (no REQUIREMENTS.md items).**

---

*Roadmap created: 2026-06-07*  
*Last updated: 2026-06-07 after initial roadmap creation*
