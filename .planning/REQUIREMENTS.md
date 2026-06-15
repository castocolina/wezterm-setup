# Requirements: wezterm-setup

**Defined:** 2026-06-07  
**Core Value:** A working WezTerm install that is easy to understand, audit, and extend — every shipped behavior verified against a real session before it integrates.

## v1 Requirements

### Installation

- [x] **INST-01**: Install injects a single managed block (sentinel-bounded) in `wezterm.lua` without touching anything else — augment model `require('wezterm-setup').apply(config)` per D-17 (supersedes the original `dofile(...)` phrasing)
- [x] **INST-02**: Install creates a timestamped backup of the original `wezterm.lua`
- [x] **INST-03**: Re-install detects an existing managed block and prompts override / restore / skip (TTY); aborts non-zero with explicit-flag guidance when no TTY (D-03)
- [x] **INST-04**: Uninstall removes managed config, companion CLI, and sentinel block with no trace — 01-06 (`wez uninstall-state` excises the block leaving user lines byte-identical; T-06-01)
- [x] **INST-05**: Uninstall supports granular flags: `--keep-config`, `--keep-backup`, `--keep-cli` — 01-06 (`plan_removal` honors each keep-flag; sudo-free glue via `tools/uninstall.sh`)
- [x] **INST-06**: Install bootstraps the WezTerm emulator itself, sudo-free, into a user path (Linux: `*.Ubuntu<base>.tar.xz` extracted to `~/.local`; macOS: `.app` to `~/Applications`). Reuses an existing WezTerm that meets a minimum version (non-destructive — never touches a system install); otherwise offers an interactive version selection (rolling `nightly` + last 5 dated releases) with a pinned known-good dated release as the non-interactive default. AppImage is explicitly avoided (libfuse2 dependency)
- [ ] **INST-07**: An ergonomic one-line remote installer — `curl -fsSL <raw-url> | bash` (with a `wget -qO- … | bash` variant) — downloads the repo to a temporary path, installs/updates WezTerm sudo-free (INST-06), copies the managed assets via the existing setup, runs `wez doctor`, and cleans up the temp checkout. README.md documents the one-liner plus post-install/config steps. The pipe-to-bash entry point ships with a documented trust model (inspect-before-run guidance, integrity verification). The installer reads interactive prompts from `/dev/tty` so re-install (INST-03) and version selection stay interactive under the pipe; a genuinely headless run keeps the non-zero abort. *(Added 2026-06-14; Phase 6.)*
- [ ] **INST-08**: The `wez` binary is produced by a cross-platform build-and-publish pipeline. A GitHub Actions matrix builds and publishes a per-OS/arch release asset (`linux-x86_64`, `darwin-x86_64`/Intel, `darwin-aarch64`/Apple Silicon — the Silicon asset ad-hoc-codesigned). A maintainer can equally build, dogfood-install (downloads WezTerm + uses the locally built `wez`), and publish the asset for their own platform from **either Linux or macOS** via `make build` / `make install` / `make publish`. The remote installer (INST-07) selects the asset by detected OS+arch and errors clearly when none exists for the platform. No AppImage/Flatpak, sudo-free, user-path only. *(Added 2026-06-14; Phase 6.)*
- [ ] **INST-09**: A `wez update` subcommand checks for and applies updates without retyping the remote URL — it invokes the **same GitHub launcher** the `curl|bash` one-liner uses (single entry point) to refresh the `wez` binary, the managed config assets, and (when a newer `nightly` is available) the WezTerm emulator. It honors the same constraints: sudo-free, never modifies a system install, update-in-place only for the project-managed user-path install (INST-08/P6-D09), and the same trust model (INST-07). It is a clear no-op when already current, and is completion-wired via the spec (DIAG-05/D-16). *(Added 2026-06-14; Phase 6.)*

### Foundation Behaviors

- [x] **FOUND-01**: New tabs and panes open in the cwd of the active pane (Linux + macOS) — Linux mechanism shipped (01-03: OSC 7 emitters + cwd.lua); macOS verify deferred (D-18)
- [x] **FOUND-02**: One keybinding clears screen + scrollback instantly (`Super+K` Linux / `Cmd+K` macOS) — 01-03
- [x] **FOUND-03**: A curated keybinding set covers: tabs (new/close/next/prev/move), panes (split/close/zoom/navigate), font zoom, word navigation — 01-03
- [x] **FOUND-04**: Every shipped binding is verifiable at runtime — no chord declared but silently ignored — `wez keys` (Plan 05) + Plan 04 installs the config so `[setup]` labels resolve
- [x] **FOUND-05**: Keybindings are cross-platform identical except for OS-native modifier differences (Cmd vs Super) — 01-03

### Diagnostics

- [x] **DIAG-01**: `wez doctor` exits 0 on a healthy install and prints failure details with exit code != 0 — 01-06 (four core integrity gates gate the exit code; advisory probes never flip exit 0, D-15)
- [x] **DIAG-02**: `wez keys` lists all active bindings grouped by category (Tabs, Panes, Navigation, etc.)
- [x] **DIAG-03**: `wez keys` flags conflicts and distinguishes wezterm-setup vs user-defined vs WezTerm default bindings
- [x] **DIAG-04**: `wez keys` supports `--json` output
- [x] **DIAG-05**: The companion CLI ships shell completion scripts for zsh and bash; `make install` registers them automatically. Completion covers all subcommands and top-level options; coverage expands with each phase that adds new commands or context-sensitive values (color names, layout names, scene names)

### Pane Identity

- [ ] **PANE-01**: `wez pane color <name|hex>` sets the pane background using named palette or hex value
- [ ] **PANE-02**: `wez pane color reset` restores the default pane background
- [ ] **PANE-03**: `wez pane title "<text>"` sets a custom title (text + emoji) visible in the tab bar when the pane is active
- [ ] **PANE-04**: Pane color and title persist across focus changes within the pane

### Tab Identity

- [x] **TAB-01**: `wez tab color <name>` sets the tab accent color, visible on both focused and unfocused tab
- [x] **TAB-02**: Tab accent color persists when the active pane switches within the tab
- [x] **TAB-03**: `wez tab color <name> --title "<text>"` sets both color and title in one command
- [x] **TAB-04**: Pane-level color takes priority over tab-level color when both are set
- [x] **TAB-05**: The active tab is visually distinct from inactive tabs regardless of accent color

### Scenes

- [ ] **SCEN-01**: `wez scene new` opens a new tab with a specified layout, N styled panes, per-pane startup commands, tab color, and tab title
- [ ] **SCEN-02**: Supported layouts at minimum: `tall`, `tall:mirrored`, `grid`, `horizontal`
- [ ] **SCEN-03**: Scene recipes in `~/.config/wezterm/wezterm-setup/scenes/` are TOML or Lua files loaded by name
- [ ] **SCEN-04**: `wez scene launch <name>` produces the same result as an equivalent `wez scene new` call
- [x] **SCEN-05**: Scene names dynamically complete in zsh and bash based on recipe files present in `~/.config/wezterm/wezterm-setup/scenes/` — no manual update needed when adding or removing recipes
- [x] **SCEN-06**: Installer seeds three example recipes using copy-if-absent; user edits survive reinstall

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
| INST-01 | Phase 1 | Done (01-04, Linux; macOS deferred D-18) |
| INST-02 | Phase 1 | Done (01-04) |
| INST-03 | Phase 1 | Done (01-04) |
| INST-04 | Phase 1 | Done (01-06) |
| INST-05 | Phase 1 | Done (01-06) |
| INST-06 | Phase 1 | Done (01-02, Linux; macOS deferred D-06/D-18) |
| INST-07 | Phase 6 | Pending (ergonomic one-line installer + README) |
| INST-08 | Phase 6 | Pending (cross-platform CI + local `make build/install/publish`) |
| INST-09 | Phase 6 | Pending (`wez update` self-update via the shared launcher) |
| FOUND-01 | Phase 1 | Done (01-03, Linux; macOS deferred D-18) |
| FOUND-02 | Phase 1 | Done (01-03) |
| FOUND-03 | Phase 1 | Done (01-03) |
| FOUND-04 | Phase 1 | Done (Plan 05 `wez keys` + Plan 04 config install) |
| FOUND-05 | Phase 1 | Done (01-03) |
| DIAG-01 | Phase 1 | Done (01-06) |
| DIAG-02 | Phase 1 | Done (Plan 05) |
| DIAG-03 | Phase 1 | Done (Plan 05) |
| DIAG-04 | Phase 1 | Done (Plan 05) |
| DIAG-05 | Phase 1 | Done (Plan 07) |
| PANE-01 | Phase 2 | Pending |
| PANE-02 | Phase 2 | Pending |
| PANE-03 | Phase 2 | Pending |
| PANE-04 | Phase 2 | Pending |
| TAB-01 | Phase 3 | Complete |
| TAB-02 | Phase 3 | Complete |
| TAB-03 | Phase 3 | Complete |
| TAB-04 | Phase 3 | Complete |
| TAB-05 | Phase 3 | Complete |
| SCEN-01 | Phase 4 | Pending |
| SCEN-02 | Phase 4 | Pending |
| SCEN-03 | Phase 5 | Pending |
| SCEN-04 | Phase 5 | Pending |
| SCEN-05 | Phase 5 | Done (05-04, Linux; macOS deferred D-18) |
| SCEN-06 | Phase 5 | Pending |

**Coverage:**

- v1 requirements: 34 total (INST-07 + INST-08 + INST-09 added 2026-06-14)
- Mapped to phases: 34
- Unmapped: 0 ✓
- Note: Phase 7 (macOS Parity, D-18) is a verification gate over the platform-sensitive subset — it adds no new requirement IDs.

---
*Requirements defined: 2026-06-07*  
*Last updated: 2026-06-07 after initial definition*
