# Roadmap: wezterm-setup

**Milestone:** v1  
**Granularity:** Coarse  
**Coverage:** 32/32 v1 requirements mapped + Phase 0 (validation, no REQUIREMENTS.md items)

---

## Phases

- [x] **Phase 0: Spikes & Alignment** - Lock open engineering decisions before building begins
- [x] **Phase 1: Foundation** - Install/uninstall, CWD, clear keybinding, curated bindings, doctor, keys (completed 2026-06-10)
- [x] **Phase 2: Pane Identity** - Per-pane background color and title via `wez pane` (completed 2026-06-11)
- [x] **Phase 3: Tab Identity** - Per-tab accent color and title via `wez tab` (mechanism proven) (completed 2026-06-12)
- [x] **Phase 4: Ad-hoc Scenes** - `wez scene new` with layout and styled panes (completed 2026-06-13, Linux; macOS deferred)
- [x] **Phase 5: Named Scenes** - Named recipes, `wez scene launch <name>`, shell completion
- [ ] **Phase 6: Ergonomic Installer** - One-line `curl|bash` remote bootstrap (temp clone → install/update WezTerm → copy assets → `wez doctor`) + README install/config docs
- [ ] **Phase 7: macOS Parity Pass (D-18)** - Verify every shipped feature on macOS and close the deferred platform gaps; final gate before v1 close

> **macOS parity is now Phase 7 (D-18).** All features are Linux-verified; the batched macOS pass
> is scheduled as a real phase. Pending work (macOS gaps + UX backlog) is tracked in
> [`.planning/MACOS-PARITY-AND-FOLLOWUPS.md`](MACOS-PARITY-AND-FOLLOWUPS.md); drive it with
> `bash tools/verify-macos.sh` (auto) + `docs/macos-verification.md` (step-by-step on a Mac).
> Phase 6 (ergonomic installer) lands first so the macOS pass also covers it.

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
**Requirements**: INST-01, INST-02, INST-03, INST-04, INST-05, INST-06, FOUND-01, FOUND-02, FOUND-03, FOUND-04, FOUND-05, DIAG-01, DIAG-02, DIAG-03, DIAG-04, DIAG-05

**Success Criteria** (what must be TRUE):

1. Running the installer on a clean machine injects a single managed block into `wezterm.lua`, creates a timestamped backup, and leaves everything else untouched — re-running prompts rather than silently overwriting
2. Running the uninstaller (with optional granular flags) leaves the system in the state the user selects — managed config, CLI binary, and sentinel block each removable independently
3. New tabs and panes open in the cwd of the previously active pane **on Linux** without any manual configuration (macOS verified in the deferred Mac pass before v1 done)
4. `wez doctor` exits 0 on a healthy install; `wez keys` lists all active bindings grouped by category, flags conflicts, and supports `--json` output
5. Shell completion scripts are installed and registered for zsh and bash; `wez <Tab>` completes subcommands, `wez doctor` and `wez keys` flags complete
6. The installer bootstraps the WezTerm emulator sudo-free into a user path (Linux `.tar.xz` → `~/.local`, no AppImage/FUSE), reusing an existing install that meets the minimum version; an interactive version selection is offered when missing/outdated, with a pinned known-good default when non-interactive (macOS `.app` → `~/Applications` verified in the deferred Mac pass)

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

1. A **TOML** recipe file in `~/.config/wezterm/wezterm-setup/scenes/` is launchable by name via `wez scene launch <name>` and produces the same result as an equivalent `wez scene new` call (TOML-only per CONTEXT D-01 — supersedes the original "TOML or Lua" phrasing)
2. `wez scene launch <Tab>` dynamically completes recipe names from `~/.config/wezterm/wezterm-setup/scenes/` — adding or removing a recipe file updates completion without any manual step
3. A fresh install seeds three example recipes (`ai`, `docker`, `dev`) using copy-if-absent — reinstalling does not overwrite user edits to those files

**Plans**: 4 plans

Plans:

- [x] 05-01-PLAN.md — Vendor tinytoml + pure recipe loader/mapper/name-guard (SCEN-03) ✓ 2026-06-13
- [x] 05-02-PLAN.md — Copy-if-absent seeder + 3 seed recipes + spec/installer wiring (SCEN-06) ✓ 2026-06-13
- [x] 05-03-PLAN.md — `wez scene launch <name>` reuse seam + scenes-dir resolver + listing provider (SCEN-03/04)
- [x] 05-04-PLAN.md — Dynamic `scene-names` completion context + nested `scene)→launch)` arm (SCEN-05) ✓ 2026-06-14

---

### Phase 6: Ergonomic Installer

**Goal**: A new user can install and configure wezterm-setup with a single pasted command — no manual git clone, no multi-step setup
**Depends on**: Phase 5
**Requirements**: INST-07 (builds on the INST-06 WezTerm bootstrap + the existing `tools/setup.sh` asset placement + `wez doctor`)

**Success Criteria** (what must be TRUE):

1. A single `curl -fsSL <raw-github-url> | bash` (and a `wget -qO- … | bash` variant) downloads the repo to a temporary path and runs the full setup unattended
2. The bootstrap installs or updates WezTerm sudo-free (reusing INST-06), copies the managed assets via `tools/setup.sh`, and finishes by running `wez doctor` with a clear pass/fail
3. The temp checkout is cleaned up — nothing is left behind after a successful run
4. README.md documents the one-line install plus post-install/config steps, with both the `curl|bash` and `wget` variants
5. The pipe-to-bash entry point ships with a documented trust model (inspect-before-run guidance, integrity verification) — captured as a threat model at plan time

**Plans**: TBD

---

### Phase 7: macOS Parity Pass (D-18)

**Goal**: Every shipped feature is verified working on macOS (Apple Silicon + Intel) and the platform-deferred gaps are closed — the final gate before v1 is declared done
**Depends on**: Phase 6
**Requirements**: macOS verification (D-18) of all platform-sensitive requirements — INST-01/06/07, FOUND-01, DIAG-05, PANE-01..04, SCEN-03..06 (no new requirement IDs; flips their "macOS deferred" status to Done)

**Success Criteria** (what must be TRUE):

1. `bash tools/verify-macos.sh` passes its auto gate on a real Mac (build, suite, all `__complete` contexts, completion `-n`, scene-launch exit codes, copy-if-absent seeding)
2. The full `docs/macos-verification.md` runbook is driven top-to-bottom and every capability section passes — visual/UX steps reviewed with `agent-ui-ux-designer`
3. Deferred macOS gaps closed: Gatekeeper/quarantine, Apple Silicon ad-hoc codesign of the built binary, `install_macos` real `.app` placement (INST-06), `sha256sum`→`shasum`, `mapfile`/bash-3.2 in the test harness
4. Every "macOS deferred D-18" status in REQUIREMENTS.md / coverage is flipped to Done with recorded evidence (incl. the A-1 `scene new --layout/--color` completion confirmed in zsh on macOS)

**Plans**: TBD
**Reference**: `.planning/MACOS-PARITY-AND-FOLLOWUPS.md`, `docs/macos-verification.md`, `tools/verify-macos.sh`

---

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 0. Spikes & Alignment | 4/4 | Complete | 2026-06-07 |
| 1. Foundation | 7/7 | Complete    | 2026-06-10 |
| 2. Pane Identity | 5/5 | Complete | 2026-06-11 |
| 3. Tab Identity | 4/4 | Complete    | 2026-06-12 |
| 4. Ad-hoc Scenes | 3/3 | Complete | 2026-06-13 |
| 5. Named Scenes | 4/4 | Complete | 2026-06-14 |
| 6. Ergonomic Installer | 0/? | Not started | - |
| 7. macOS Parity Pass (D-18) | 0/? | Not started | - |

---

## Coverage

| Requirement | Phase | Status |
|-------------|-------|--------|
| INST-01 | Phase 1 | Done (01-04, Linux; macOS deferred D-18) |
| INST-02 | Phase 1 | Done (01-04) |
| INST-03 | Phase 1 | Done (01-04) |
| INST-04 | Phase 1 | Done (01-06) |
| INST-05 | Phase 1 | Done (01-06) |
| INST-06 | Phase 1 | Done (01-02, Linux; macOS deferred D-06/D-18) |
| FOUND-01 | Phase 1 | Done (01-03, Linux; macOS deferred D-18) |
| FOUND-02 | Phase 1 | Done (01-03) |
| FOUND-03 | Phase 1 | Done (01-03) |
| FOUND-04 | Phase 1 | Done (Plan 05 `wez keys` + Plan 04 installs config so `[setup]` labels resolve) |
| FOUND-05 | Phase 1 | Done (01-03) |
| DIAG-01 | Phase 1 | Done (01-06) |
| DIAG-02 | Phase 1 | Done (01-05) |
| DIAG-03 | Phase 1 | Done (01-05) |
| DIAG-04 | Phase 1 | Done (01-05) |
| DIAG-05 | Phase 1 | Done (01-07, Linux; macOS deferred D-18) |
| PANE-01 | Phase 2 | Done (02-02, 02-03; Linux, macOS deferred D-18) |
| PANE-02 | Phase 2 | Done (02-03) |
| PANE-03 | Phase 2 | Done (02-04) |
| PANE-04 | Phase 2 | Done (02-02, 02-04, 02-05) |
| TAB-01 | Phase 3 | Pending |
| TAB-02 | Phase 3 | Pending |
| TAB-03 | Phase 3 | Pending |
| TAB-04 | Phase 3 | Pending |
| TAB-05 | Phase 3 | Pending |
| SCEN-01 | Phase 4 | Pending |
| SCEN-02 | Phase 4 | Pending |
| SCEN-03 | Phase 5 | Done (05-01 recipe core + 05-03 launch wiring, Linux; macOS deferred D-18) |
| SCEN-04 | Phase 5 | Done (05-03 launch≡new structural equivalence, Linux; macOS deferred D-18) |
| SCEN-05 | Phase 5 | Done (05-04, Linux; macOS deferred D-18) |
| SCEN-06 | Phase 5 | Done (05-02, Linux; macOS deferred D-18) |

| INST-07 | Phase 6 | Pending (ergonomic one-line `curl\|bash` remote installer + README) |

**v1 coverage: 32/32 requirements mapped (INST-07 added 2026-06-14). Phase 0 carries validation work only (no REQUIREMENTS.md items). Phase 7 is the macOS verification gate (D-18) — no new IDs.**

---

*Roadmap created: 2026-06-07*  
*Last updated: 2026-06-14 — added Phase 6 (Ergonomic Installer, INST-07) + Phase 7 (macOS Parity Pass, D-18)*
