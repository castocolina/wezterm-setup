# wezterm-setup — Product Requirements Document (PRD)

**Version**: 1.0  
**Created**: 2026-06-07  
**Quality Score**: 84/100  
**Clarification Rounds**: 2  

---

## Requirements Description

### Background

**Business Problem**: WezTerm is a capable terminal emulator with a powerful Lua configuration API, but a
vanilla install produces an ambiguous, friction-heavy experience: keybindings are hard to introspect,
new tabs/panes land in `$HOME`, visual identity between tabs and panes is absent, and there is no way to
summon a pre-styled workspace by name. A prior bash-based attempt (`wezterm-setup_`) proved that the
runtime control surface works but that unstructured bash scripts do not scale across platforms.

A parallel project (`kitty-setup`) established the methodology that applies here: prove every capability
as a standalone script against a real running terminal before integrating anything. That project
also confirmed that non-destructive install (sentinel-block injection, backup, granular uninstall) is
not optional — it is the foundation of user trust.

**Target Users**: Solo developer on Linux (Pop!_OS / COSMIC / Wayland) and macOS, daily-driving WezTerm
as a full multiplexer. No multi-user, no CI, no remote deployment.

**Value Proposition**: A WezTerm distribution that ships daily-friction fixes, rich visual identity at
the pane and tab level, a scene launcher for named workspaces, and the tooling to understand and audit
what is installed — all without touching the user's existing `wezterm.lua` beyond a single injected
`require` line.

---

### Feature Overview

**Core Features** (in delivery order):

1. Non-destructive install and granular uninstall
2. Curated, conflict-free, cross-platform keybindings
3. CWD inheritance for new tabs and panes
4. Instant screen + scrollback clear
5. Per-pane visual identity (background color, title with emoji)
6. Per-tab visual identity (accent color, title with emoji, persists across pane switches)
7. Custom ad-hoc scene launch (layout + N styled panes, one command)
8. Named scene launch from declarative recipe files
9. Doctor health check
10. Keybinding introspection

**Feature Boundaries**:

- In scope: Linux (Wayland/X11) and macOS parity for all features.
- In scope: visual identity (colors, titles). All color primitives apply per-pane; tab color is a
  tab-level override that individual panes can supersede.
- Out of scope (this version): status bar widgets (clock, git branch), workspace/session management,
  SSH domain integration, multiplexer persistence, broadcast input.
- Out of scope: kitten-style packaging — this is not a WezTerm plugin. It is a config distribution
  with a companion CLI.

**User Scenarios**:

- Open WezTerm for the first time after install: six foundation behaviors work immediately.
- Mark a pane as a production shell: one command sets its background to red and title to "PROD 🔴".
- Mark a tab as an AI workflow: one command sets its accent to orange and title to "ai ✨".
- Launch a pre-defined `docker` scene: one command opens a new tab with three styled panes,
  each running its startup command.
- Run `wez doctor`: see a health report confirming config is loaded, remote control is reachable,
  and no unintended keybinding conflicts exist.
- Run `wez keys`: see every active binding grouped by category, with intentional overrides annotated.

---

### Detailed Requirements

#### Foundation (Phase 1)

**F-01 — Non-destructive install**  
Install injects a single `require` or `dofile` line into the user's existing `wezterm.lua` wrapped in
sentinel comments. The user's original file is backed up with a timestamped suffix. On re-install,
the user can choose: override existing installation, restore from backup, or skip if already present.

**F-02 — Granular uninstall**  
Uninstall removes the sentinel block, the managed config directory, and the companion CLI from
`~/.local/bin`. Flags: `--keep-config` (leave managed Lua files), `--keep-backup` (leave `.bak.*`
files), `--keep-cli` (leave companion binary). Full uninstall leaves no trace.

**F-03 — CWD inheritance**  
New tabs and panes inherit the working directory of the active pane. Must work on both Linux (Wayland
and X11) and macOS. WezTerm's `default_cwd` and pane `pane_id`-based cwd detection are candidate
mechanisms — to be confirmed in a hypothesis script before wiring into config.

**F-04 — Instant clear**  
One keybinding clears the visible screen and scrollback buffer instantly, without `reset` delay.
Linux default: `Super+K`. macOS default: `Cmd+K`. Parity with iTerm's Cmd+K behavior.

**F-05 — Curated keybindings**  
A curated set covering: tabs (new, close, next, prev, move left/right), panes (split horizontal,
split vertical, close, zoom toggle, navigate by direction), font zoom (increase, decrease, reset),
word navigation (Alt+Left/Right). Constraints:

- No vi-style modal bindings. No less-style search overlay.
- Every chord must be verifiable via `wez keys` before it is declared shipped.
- Cross-platform: identical bindings except OS-native chords (Cmd vs Super/Ctrl).
- The ambiguity problem from the prior attempt (chord declared in config but not honored at runtime)
  must be resolved: every binding in Phase 1 gets a manual repro documented next to it.

---

#### Pane Identity (Phase 2)

**P-01 — Per-pane background color**  
Set a named or hex background color on any pane via the companion CLI. Named palette: red, orange,
yellow, green, teal, cyan, blue, navy, purple, pink. Colors must render visibly without requiring
background opacity changes — WezTerm's per-pane color support is confirmed to render better than
Kitty's approach. Reset command restores default.

**P-02 — Per-pane title**  
Set a custom title (text, emoji, or both) on the active pane. Title appears in the tab bar via
`format-tab-title` when that pane is active. Does not override the tab-level title if one is set.

---

#### Tab Identity (Phase 3)

**T-01 — Per-tab accent color**  
Set a named accent color on a tab. Color is stored at the tab level (via `set-tab-title` prefix
convention, proven in spike today: `"color:title"` or `"color"` alone). Persists when the active
pane switches within the tab. Pane-level color takes priority over tab-level when both are set.

**T-02 — Per-tab title**  
Set a custom title (text + emoji) on a tab, independent of pane titles. Can be combined with a
color prefix in one command.

**T-03 — Active tab visual differentiation**  
The active tab renders visually distinct from inactive tabs regardless of color. The indicator and
text weight must make it immediately clear which tab is active.

---

#### Ad-hoc Scene Launch (Phase 4)

**S-01 — Scene launch from CLI**  
One command opens a new tab with a chosen layout, N styled panes, per-pane startup commands,
tab color, and tab title. All properties are optional except the tab (which is always created).
Example: `wez scene new --tab-color navy --tab-title "docker 🐳" --layout tall \
  --pane "docker ps" --pane "docker stats" --pane ""`.

**S-02 — Layout support**  
Supported layouts at minimum: `tall`, `tall:mirrored`, `grid`, `horizontal`. Additional layouts
available if WezTerm's mux supports them. Layout names must be verified via a hypothesis script.

---

#### Named Scenes (Phase 5)

**N-01 — Declarative recipe files**  
Scene recipes are Lua or TOML files in `~/.config/wezterm-setup/scenes/`. Each recipe defines:
tab title, tab accent color, layout, and an ordered list of panes (each with: title, startup
command, cwd, background color). Format decision (Lua vs TOML) is a spike item.

**N-02 — Named scene launch**  
`wez scene launch <name>` reads the matching recipe and produces the same result as an ad-hoc
scene. Scene names tab-complete in the shell.

**N-03 — Bundled example scenes**  
Installer seeds `~/.config/wezterm-setup/scenes/` with three recipes (copy-if-absent, never
overwritten). User-edited recipes survive reinstall.

| Recipe | Layout | Color | Panes | Startup commands |
|--------|--------|-------|-------|------------------|
| `dev` | `tall` | `green` | 2 | shell (cwd), shell (cwd) |
| `ai` | `tall` | `purple` | 2 | shell (cwd), shell (cwd) |
| `docker` | `grid` | `teal` | 4 | `docker stats`, `docker ps`, `docker compose logs -f`, shell |

All three recipes are valid, launchable out-of-the-box with no user editing required.

---

#### Doctor & Introspection (Phase 1 + evolves)

**D-01 — Doctor health check**  
`wez doctor` reports: config loaded (no parse errors), managed include block present, remote
control reachable, companion CLI version, keybinding conflicts detected. Exit code 0 = healthy.

**D-02 — Keybinding introspection**  
`wez keys` lists every active binding grouped by category (Tabs, Panes, Navigation, Copy/Paste,
Scroll, Window, Other). Annotates which bindings are managed by wezterm-setup vs user-defined vs
WezTerm defaults. Flags unintended conflicts. Supports `--json` output.

**D-03 — Shell completion**  
The CLI ships completion scripts for zsh and bash. `make install` registers them automatically
(no manual `source` step beyond the shell's standard completion setup). Coverage at each phase:

| Phase ships | Completion covers |
|-------------|-------------------|
| Phase 1 | `wez`, all Phase 1 subcommands, `--json` and `--help` flags |
| Phase 2 | `wez pane color [name\|hex]` with named color profiles, `wez pane title`, `reset` |
| Phase 3 | `wez tab color [name]` with named color profiles, `wez tab title`, `--title` flag |
| Phase 4 | `wez scene new --layout [tall\|tall:mirrored\|grid\|horizontal]`, all scene flags |
| Phase 5 | `wez scene launch [name]` dynamic from `~/.config/wezterm-setup/scenes/` contents |

---

### Edge Cases

- **Config already exists**: install detects existing managed block; prompts override/backup/skip.
- **wezterm CLI not found**: doctor and companion CLI degrade gracefully with a clear error message
  pointing to the WezTerm binary location.
- **Remote control unavailable**: tab/pane color and scene commands require `allow_remote_control`
  and a `unix_listen_domain`. Doctor flags this explicitly. Install offers to add these to config.
- **Color on inactive pane**: pane color set from another pane requires specifying `--pane-id`.
  Default behavior targets the current pane (via `$WEZTERM_PANE` env var).
- **macOS vs Linux keybinding parity**: any chord that behaves differently per OS must have a
  documented platform condition and a repro test on both.

---

## Design Decisions

### Technical Approach

**Architecture**:

Two independent layers with a clean separation contract:

1. **Config layer** (`~/.config/wezterm/wezterm-setup/`): Pure Lua modules, loaded via a single
   `dofile` injected into the user's `wezterm.lua`. Hot-reloads without restarting WezTerm. Covers
   all visual customization, keybindings, and event handlers. No external dependencies.

2. **Companion CLI** (`wez`): A standalone tool for runtime control (doctor, scene launch, key
   introspection, pane/tab identity from the shell). Installed to `~/.local/bin/wez`. Language
   decision: **Lua preferred over Bash for cross-platform correctness** — but requires standalone
   `lua` (5.4) on the system. This is a spike item: validate whether WezTerm's bundled Lua is
   accessible as a standalone interpreter before committing to Lua CLI. If not, evaluate Python
   via `uv` (same pattern as kitty-setup, proven cross-platform). Bash is not a candidate for
   the CLI tool due to portability constraints.

**Key Components**:

- `wezterm-setup/init.lua` — entry point, loads modules
- `wezterm-setup/keybindings.lua` — curated binding set
- `wezterm-setup/tab-bar.lua` — `format-tab-title` event handler, color profile table
- `wezterm-setup/defaults.lua` — foundation behaviors (CWD, clear, window chrome)
- `wezterm-setup/scenes/` — scene event handlers (Phase 4+)
- `bin/wez` — companion CLI entry point
- `scenes/` — user scene recipes (seeded by installer, user-owned)

**Hypothesis-driven development**:

Every capability in Phase 2 and beyond begins as a standalone script in `.tmp/`.
Each script has a top-of-file manual repro document. A capability graduates to the main config only
after its experiment script is confirmed working on both Linux and macOS. No speculative
abstractions — shared logic gets extracted only when duplication actually hurts.

### Constraints

- **No extra runtime for config layer**: Lua config runs inside WezTerm — zero external deps.
- **Companion CLI runtime**: TBD via spike (see above). Must be installable without `sudo` on both
  platforms.
- **No vi-style or less-style UX patterns** in any shipped keybinding or search behavior.
- **No kitten-style packaging** for this version. Companion CLI is a standalone binary/script, not
  a WezTerm plugin.
- **macOS + Linux parity**: every shipped feature must work on both platforms. Platform-specific
  code is allowed (e.g., `Cmd` vs `Super`) but must be documented and tested.

### Risk Assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| WezTerm's `wezterm cli` surface is insufficient for some scene primitives | Medium | Spike per primitive before committing to the approach |
| Standalone Lua not available / WezTerm's Lua not extractable | Low | Fallback to Python via uv (proven in kitty-setup) |
| Keybinding ambiguity (chord declared but not honored at runtime) | Medium | Manual repro required for every binding before shipping |
| CWD inheritance works differently on Wayland vs X11 vs macOS | Medium | Hypothesis script on each platform before integrating |
| Per-pane color lost when reconnecting to a mux session | Low | Document as known limitation; investigate persistence options |

---

## Acceptance Criteria

### Phase 1 — Foundation

- [ ] `make install` on a clean machine injects exactly one `dofile(...)` line in `wezterm.lua` between sentinel comments
- [ ] A backup of the original `wezterm.lua` is created with a timestamped suffix
- [ ] `make install` detects an existing managed block and prompts override/backup/skip
- [ ] `make uninstall` removes all managed files; `--keep-config` and `--keep-backup` flags work
- [ ] New tab and new pane open in the cwd of the active pane (verified on Linux and macOS)
- [ ] `Super+K` (Linux) / `Cmd+K` (macOS) clears screen + scrollback instantly
- [ ] `wez keys` lists all Phase 1 bindings grouped by category with no false conflicts
- [ ] `wez doctor` exits 0 on a healthy install, non-zero with clear messages on each failure mode
- [ ] Shell completion scripts are installed; `wez <Tab>` and `wez doctor --<Tab>` work in zsh and bash
- [ ] Every Phase 1 keybinding has a passing manual repro documented in `.tmp/`

### Phase 2 — Pane Identity

- [ ] `wez pane color <name>` sets the pane background using the named palette
- [ ] `wez pane color <hex>` sets the pane background using a hex color
- [ ] `wez pane color reset` restores the default background
- [ ] `wez pane title "<text>"` sets the pane title, visible in the tab bar when that pane is active
- [ ] Color and title persist across focus changes within the pane
- [ ] Both commands work on Linux (Wayland) and macOS
- [ ] `wez pane color <Tab>` completes named color profiles in zsh and bash

### Phase 3 — Tab Identity

- [ ] `wez tab color <name>` sets the tab accent color, visible on focused and unfocused tab
- [ ] Tab color persists when switching active pane within the tab
- [ ] `wez tab color <name> --title "<text>"` sets both in one command
- [ ] Pane-level color takes priority over tab-level color when both are set
- [ ] Active tab is visually distinct from inactive tabs regardless of accent color
- [ ] `wez tab color <Tab>` completes named color profiles in zsh and bash

### Phase 4 — Ad-hoc Scenes

- [ ] `wez scene new` creates a new tab with the specified layout and panes
- [ ] Each pane's startup command runs in the correct cwd
- [ ] Per-pane color and title are applied before the startup command runs
- [ ] Tab color and title are set on the new tab
- [ ] Command works on Linux and macOS
- [ ] `wez scene new --layout <Tab>` completes layout names in zsh and bash

### Phase 5 — Named Scenes

- [ ] Scene recipes in `~/.config/wezterm-setup/scenes/` are loaded by name
- [ ] `wez scene launch <name>` produces the same result as the equivalent `wez scene new` call
- [ ] `wez scene launch <Tab>` dynamically completes recipe names from `~/.config/wezterm-setup/scenes/`
- [ ] Bundled example scenes are seeded on install (copy-if-absent)
- [ ] User-edited recipes survive `make install` and `make update`

### Cross-cutting

- [ ] `wez doctor` reflects the health of whichever phases are installed
- [ ] `wez keys` reflects all active bindings from all installed phases
- [ ] No phase requires the next phase to be installed
- [ ] Removing any phase leaves no trace in the user's `wezterm.lua`

---

## Execution Phases

### Phase 0 — Spike & Align

**Goal**: Lock open decisions before building anything.

- [ ] Spike: validate whether WezTerm's bundled Lua is usable as a standalone interpreter
- [ ] Spike: confirm `wezterm cli` surface for pane background color (OSC escape vs remote control API)
- [ ] Spike: confirm CWD inheritance mechanism on Linux Wayland and macOS
- [ ] Spike: validate `set-tab-title` prefix convention for color persistence (already proven today — document it)
- [ ] Decision: companion CLI language (Lua standalone vs Python/uv)
- [ ] Lock `.tmp/` conventions: one script per hypothesis, top-of-file repro, exit non-zero on failure
- [ ] Spike: confirm shell completion registration mechanism on Linux (bash-completion, zsh fpath) and macOS (Homebrew completions path)

**Deliverables**: `docs/spikes/` directory with findings for each spike; language decision recorded in `docs/decisions/cli-language.md`

---

### Phase 1 — Foundation

**Goal**: Six daily-friction fixes + install/uninstall + doctor + keybinding introspection. Dogfooded for at least one week before Phase 2 starts.

- [ ] Non-destructive install with backup/override/skip
- [ ] Granular uninstall
- [ ] CWD inheritance (Linux + macOS)
- [ ] Instant clear keybinding (platform-specific chord)
- [ ] Curated keybinding set — tabs, panes, font zoom, word navigation
- [ ] `wez doctor` (initial: config loaded, remote control reachable, no conflicts)
- [ ] `wez keys` (initial: list all bindings, flag conflicts)
- [ ] Shell completion scripts for zsh and bash; `make install` registers them
- [ ] Manual repro for every binding, committed to `.tmp/`

**Deliverables**: Working install on Linux and macOS, all Phase 1 acceptance criteria green.

---

### Phase 2 — Pane Identity

**Goal**: Visual identity at the pane level. Each capability starts as an experiment script.

- [ ] Experiment script: pane background color via OSC escape
- [ ] Experiment script: pane title via OSC escape  
- [ ] Integrate into companion CLI: `wez pane color`, `wez pane title`
- [ ] Update `format-tab-title` to reflect pane title when pane is active
- [ ] Update completion scripts: color profile names and `reset` for `wez pane color`
- [ ] Update `wez doctor` and `wez keys` to reflect Phase 2 additions

**Deliverables**: `wez pane` subcommands working on Linux and macOS; experiment scripts in `.tmp/`.

---

### Phase 3 — Tab Identity

**Goal**: Visual identity at the tab level, persisting across pane switches.

- [ ] Experiment script: tab accent color via `set-tab-title` prefix (already proven — formalize)
- [ ] Integrate into companion CLI: `wez tab color`, `wez tab title`
- [ ] Update `format-tab-title`: parse color prefix, pane-level takes priority
- [ ] Update completion scripts: color profile names for `wez tab color`, `--title` flag
- [ ] Verify color persistence on pane switch (already demonstrated today)

**Deliverables**: `wez tab` subcommands working; tab color persists correctly; Phase 3 acceptance criteria green.

---

### Phase 4 — Ad-hoc Scene Launch

**Goal**: One command launches a styled multi-pane tab.

- [ ] Experiment script: spawn N panes in a new tab with specified layout
- [ ] Experiment script: set pane color + title before startup command runs
- [ ] Integrate into companion CLI: `wez scene new`
- [ ] Update completion scripts: layout names for `--layout`, all `wez scene new` flags
- [ ] Verify on Linux and macOS

**Deliverables**: `wez scene new` working end-to-end; Phase 4 acceptance criteria green.

---

### Phase 5 — Named Scenes

**Goal**: Declarative recipe files for named workspace launch.

- [ ] Decide recipe format (Lua module vs TOML) — spike if needed
- [ ] Implement recipe loader
- [ ] Integrate into companion CLI: `wez scene launch <name>`, `wez scene list`
- [ ] Dynamic completion for scene names: reads `~/.config/wezterm-setup/scenes/` at completion time
- [ ] Seed bundled example scenes: `ai`, `docker`, `dev`
- [ ] Verify user recipes survive reinstall

**Deliverables**: Named scene launch working; example scenes ship with installer; Phase 5 acceptance criteria green.

---

## What is Not This Project

- No status bar widgets (clock, git branch, workspace name display)
- No workspace/session persistence or named workspace management
- No SSH domain integration
- No broadcast input (mirror keystrokes to all panes)
- No kitten or WezTerm plugin packaging
- No GUI configuration tool
- These are candidates for a v2 scope discussion after Phase 5 ships.

---

**Document Version**: 1.0  
**Created**: 2026-06-07  
**Clarification Rounds**: 2  
**Quality Score**: 84/100
