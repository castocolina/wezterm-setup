# Requirements: wezterm-setup

**Defined:** 2026-06-07  
**Core Value:** A working WezTerm install that is easy to understand, audit, and extend — every shipped behavior verified against a real session before it integrates.

## v1 Requirements

### Installation

- [ ] **INST-01**: Install injects a single `dofile(...)` line in `wezterm.lua` between sentinel comments, without touching anything else
- [ ] **INST-02**: Install creates a timestamped backup of the original `wezterm.lua`
- [ ] **INST-03**: Re-install detects an existing managed block and prompts: override / restore backup / skip
- [ ] **INST-04**: Uninstall removes managed config, companion CLI, and sentinel block with no trace
- [ ] **INST-05**: Uninstall supports granular flags: `--keep-config`, `--keep-backup`, `--keep-cli`

### Foundation Behaviors

- [ ] **FOUND-01**: New tabs and panes open in the cwd of the active pane (Linux + macOS)
- [ ] **FOUND-02**: One keybinding clears screen + scrollback instantly (`Super+K` Linux / `Cmd+K` macOS)
- [ ] **FOUND-03**: A curated keybinding set covers: tabs (new/close/next/prev/move), panes (split/close/zoom/navigate), font zoom, word navigation
- [ ] **FOUND-04**: Every shipped binding is verifiable at runtime — no chord declared but silently ignored
- [ ] **FOUND-05**: Keybindings are cross-platform identical except for OS-native modifier differences (Cmd vs Super)

### Diagnostics

- [ ] **DIAG-01**: `wez doctor` exits 0 on a healthy install and prints failure details with exit code != 0
- [ ] **DIAG-02**: `wez keys` lists all active bindings grouped by category (Tabs, Panes, Navigation, etc.)
- [ ] **DIAG-03**: `wez keys` flags conflicts and distinguishes wezterm-setup vs user-defined vs WezTerm default bindings
- [ ] **DIAG-04**: `wez keys` supports `--json` output
- [ ] **DIAG-05**: The companion CLI ships shell completion scripts for zsh and bash; `make install` registers them automatically. Completion covers all subcommands and top-level options; coverage expands with each phase that adds new commands or context-sensitive values (color names, layout names, scene names)

### Pane Identity

- [ ] **PANE-01**: `wez pane color <name|hex>` sets the pane background using named palette or hex value
- [ ] **PANE-02**: `wez pane color reset` restores the default pane background
- [ ] **PANE-03**: `wez pane title "<text>"` sets a custom title (text + emoji) visible in the tab bar when the pane is active
- [ ] **PANE-04**: Pane color and title persist across focus changes within the pane

### Tab Identity

- [ ] **TAB-01**: `wez tab color <name>` sets the tab accent color, visible on both focused and unfocused tab
- [ ] **TAB-02**: Tab accent color persists when the active pane switches within the tab
- [ ] **TAB-03**: `wez tab color <name> --title "<text>"` sets both color and title in one command
- [ ] **TAB-04**: Pane-level color takes priority over tab-level color when both are set
- [ ] **TAB-05**: The active tab is visually distinct from inactive tabs regardless of accent color

### Scenes

- [ ] **SCEN-01**: `wez scene new` opens a new tab with a specified layout, N styled panes, per-pane startup commands, tab color, and tab title
- [ ] **SCEN-02**: Supported layouts at minimum: `tall`, `tall:mirrored`, `grid`, `horizontal`
- [ ] **SCEN-03**: Scene recipes in `~/.config/wezterm-setup/scenes/` are TOML or Lua files loaded by name
- [ ] **SCEN-04**: `wez scene launch <name>` produces the same result as an equivalent `wez scene new` call
- [ ] **SCEN-05**: Scene names dynamically complete in zsh and bash based on recipe files present in `~/.config/wezterm-setup/scenes/` — no manual update needed when adding or removing recipes
- [ ] **SCEN-06**: Installer seeds three example recipes using copy-if-absent; user edits survive reinstall

  | Recipe | Layout | Color | Panes | Startup commands |
  |--------|--------|-------|-------|------------------|
  | `dev` | `tall` | `green` | 2 | shell (cwd), shell (cwd) |
  | `ai` | `tall` | `purple` | 2 | shell (cwd), shell (cwd) |
  | `docker` | `grid` | `teal` | 4 | `docker stats`, `docker ps`, `docker compose logs -f`, shell |

## v2 Requirements

*(None identified — PRD scope is complete as defined)*

## Out of Scope

| Feature | Reason |
|---------|--------|
| Status bar widgets (clock, git branch) | Not requested; adds complexity with low daily value |
| Workspace/session persistence | Outside terminal identity scope |
| SSH domain integration | Not part of local terminal identity |
| Broadcast input | Niche use case; not in any defined scenario |
| WezTerm kitten/plugin packaging | This is a config distribution, not a plugin |
| GUI configuration tool | CLI-first; GUI adds surface area without benefit |

## Traceability

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

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 30
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-07*  
*Last updated: 2026-06-07 after initial definition*
