# Roadmap: wezterm-setup

**Milestone:** v1  
**Granularity:** Coarse  
**Coverage:** 34/34 v1 requirements mapped + Phase 0 (validation, no REQUIREMENTS.md items)

---

## Phases

- [x] **Phase 0: Spikes & Alignment** - Lock open engineering decisions before building begins
- [x] **Phase 1: Foundation** - Install/uninstall, CWD, clear keybinding, curated bindings, doctor, keys (completed 2026-06-10)
- [x] **Phase 2: Pane Identity** - Per-pane background color and title via `wez pane` (completed 2026-06-11)
- [x] **Phase 3: Tab Identity** - Per-tab accent color and title via `wez tab` (mechanism proven) (completed 2026-06-12)
- [x] **Phase 4: Ad-hoc Scenes** - `wez scene new` with layout and styled panes (completed 2026-06-13, Linux; macOS deferred)
- [x] **Phase 5: Named Scenes** - Named recipes, `wez scene launch <name>`, shell completion
- [x] **Phase 6: Ergonomic Installer** - One-line `curl|bash` remote bootstrap (temp clone → install/update WezTerm → copy assets → `wez doctor`) + README install/config docs (completed 2026-06-15)
- [x] **Phase 6.1: Tab and Scene Identity Redesign** *(INSERTED)* - Decouple tab color from title (drop the `<color>:<title>` encoding), redesign the scene schema (tab/pane `color`/`title`/`cwd`/`focus`/`size`, alpha-aware), migrate the prototype `wezterm.lua` + `wez doctor` shadow-detection, arrange/RotatePanes, embrace search overlay, refresh ai/dev scenes (completed + UAT-verified 2026-06-15)
- [x] **Phase 6.2: Identity Orthogonality** *(INSERTED)* - Finish 6.1's decoupling: icon becomes its own attribute (CLI + recipe), not the title's first word (G-1); split tab color from pane color into two user vars so an explicit tab color always wins (G-2a); add an opt-in `adopt_active_pane_color` toggle/flag so "tab follows the focused pane" is explicit, not magic (G-2b); `{cwd}`-in-title auto-fallback (completed 2026-06-16)
- [x] **Phase 6.3: Distribution Channels** *(INSERTED)* - Scheduled nightly/latest rolling release + bootstrapper channel selector (tag vs latest/nightly); `wez uninstall` (binary-only and full) (completed 2026-06-18)
- [ ] **Phase 6.4: User Documentation Audit and Refactor** *(RENUMBERED from 6.2)* - Audit all user-facing docs (README first, then `docs/`) against shipped + 6.1/6.2/6.3 behavior; refactor README via `/agent-md-refactor`; drift-check every documented command/flag against `cli/spec.lua`
- [x] **Phase 7: macOS Parity Pass (D-18)** - Verify every shipped feature on macOS and close the deferred platform gaps; final gate before v1 close (completed 2026-06-22; verify-macos.sh PASS=26 FAIL=0, runbook driven agent-driven with §5/§6 ui-ux PASS, 13 D-18 IDs flipped to verified)

> **Execution = numeric order:** 6.1 ✓ → **6.2 (identity orthogonality, next)** → **6.3 (distribution channels)** → **6.4 (doc audit — runs LAST so it documents the final icon/color/install reality)** → 7 (macOS close gate). 6.2 and 6.3 are independent and could run in either order; 6.4 depends on both. *(The old 6.2 "doc audit" is renumbered to 6.4 — it had not started, so no execution artifacts move.)*

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
**Requirements**: INST-07 (ergonomic one-line remote installer + README), INST-08 (cross-platform build-and-publish pipeline — CI matrix + local `make build/install/publish`), INST-09 (`wez update` self-update via the shared launcher). Builds on the INST-06 WezTerm bootstrap, the existing `tools/setup.sh` asset placement, the dormant `WEZ_REMOTE_BOOTSTRAP=1` path in `tools/build.sh`, and `wez doctor`.

> Real remote configured: `github.com/castocolina/wezterm-setup` (default `main`) — raw base
> `raw.githubusercontent.com/castocolina/wezterm-setup/main/…`, releases at
> `github.com/castocolina/wezterm-setup/releases/download/…`.

**Success Criteria** (what must be TRUE):

1. A single `curl -fsSL <raw-github-url> | bash` (and a `wget -qO- … | bash` variant) downloads the repo to a temporary path and runs the full setup
2. The bootstrap installs or updates WezTerm sudo-free (reusing INST-06), downloads the matching `wez` release binary for the detected OS+arch, copies the managed assets via `tools/setup.sh`, and finishes by running `wez doctor` with a clear pass/fail
3. The temp checkout is cleaned up — nothing is left behind after a successful run
4. README.md documents the one-line install plus post-install/config steps (both `curl|bash` and `wget` variants), authored/reviewed with the `crafting-effective-readmes` skill
5. The pipe-to-bash entry point ships with a documented trust model (inspect-before-run guidance, pin-to-tag/commit, binary checksum) — captured as a threat model at plan time
6. Interactive prompts (re-install decision, version selection) work under the pipe by reading from `/dev/tty`; a genuinely headless run keeps the non-zero abort (D-03)
7. A GitHub Actions matrix builds and publishes per-OS/arch `wez` assets (`linux-x86_64`, `darwin-x86_64`, `darwin-aarch64`; Silicon ad-hoc-codesigned); a maintainer can equally `make build && make publish` from Linux or macOS. The launcher selects the asset by detected OS+arch and errors clearly when none exists. *(macOS asset build is wired here; its on-Mac verification is Phase 7.)*
8. `wez update` checks for and applies updates by invoking the same launcher as the one-liner — refreshing the `wez` binary, managed assets, and WezTerm (when a newer `nightly` exists); update-in-place only for the user-path install, never a system install; a clear no-op when current; completion-wired

**Plans**: 6 plans

Plans:

- [x] 06-01-PLAN.md — Spike the latest-nightly datestamp query (Open Q1) + per-asset .sha256 contract (Open Q2) [wave 1]
- [x] 06-02-PLAN.md — INST-08 supply side: repoint download_release() to castocolina + per-asset .sha256 + make build/publish [wave 2]
- [x] 06-03-PLAN.md — INST-08 CI: tag-triggered GitHub Actions release matrix (linux-x86_64, macos-15-intel, macos-14) [wave 2]
- [x] 06-06-PLAN.md — WezTerm nightly default + update-in-place + wezterm_install_is_user_path() predicate (P6-D09) [wave 2]
- [x] 06-04-PLAN.md — INST-07 consume side: pipe-safe tools/install.sh one-liner + README rewrite + trust model [wave 3]
- [x] 06-05-PLAN.md — INST-09: wez update (split semver/datestamp comparators) delegating to the shared launcher [wave 3]

**No-AppImage/No-Flatpak invariant** — every layer is plain user-path artifacts, sudo-free.
**Default target = `nightly`**, with update-in-place scoped to the project-managed user-path install only (a system install is never modified).

---

### Phase 06.1: Tab and Scene Identity Redesign (INSERTED) — ✅ COMPLETE (UAT-verified 2026-06-15)

**Goal:** Decouple tab COLOR from tab TITLE everywhere and remove the legacy `"<color>:<title>"` encoding (a pre-roadmap scripting shortcut), so tabs use the same clean two-user-var model panes already use — then extend the scene recipe model with the attributes daily use needs. This is the last cleanup before the macOS pass, so macOS verifies the redesigned behavior.

**Depends on:** Phase 6 (installer, complete)
**Requirements**: refines PANE-* / SCEN-* / TAB-* behavior (no new requirement IDs; supersedes the "tab color stored in tab-title prefix" decision).

**Scope (decisions locked with the maintainer):**

- [ ] **Decouple color/title (full unification)** — tab color is carried as the `WEZTERM_TAB_COLOR` user var emitted on the tab's panes; tab title is pure text via `set-tab-title`. The `format-tab-title` handler reads color by scanning all panes in the tab. Drop `parse_stored`/`merge_title` + the `<color>:<title>` encoding (parse-and-warn once for migration). Applies to BOTH scenes AND standalone `wez tab`/`wez pane`.
- [ ] **Scene TOML schema redesign** — tab attributes as top-level keys (`title`, `color`, `cwd`, optional `icon`); panes as `[[pane]]` arrays (`command`, `color`, `title`, `cwd`, `focus`, `size`). Tab vs pane scope is enforced by the table grammar; same attribute names, identical semantics. Deprecated top-level `color`/`title` accepted as aliases during migration.
- [ ] **New fields `cwd` / `focus` / `size`** — `cwd` resolves flexibly and safely (literal, `~`/`$ENV` expansion, and relative-to-launch where `.` = launch dir and `..` = `dirname $(pwd)`); NO shell `$(...)` evaluation. Same grammar for `--cwd` CLI flags and the `.toml` field. `focus` selects the active pane on spawn; `size` sets split fraction. Tested, with examples in recipes + docs.
- [ ] **Color model accepts alpha** — `#RRGGBBAA` / `rgba()` are accepted (stop stripping the 8th digit) so an IDE-inserted rgba never breaks; the opaque named palette stays the DEFAULT; document that alpha only renders with window transparency (cross-platform caveat, D-18).
- [ ] **Migrate the prototype `wezterm.lua`** — remove the inline `format-tab-title` handler + duplicate keybindings that shadow the managed block (root cause of the `cyan:`/no-color/no-cwd bug), keeping genuine personal settings. Backup is written by the installer.
- [ ] **`wez doctor` shadow-detection** — add a check that DETECTS a user-defined `format-tab-title` handler or duplicate keybindings shadowing wezterm-setup, so this class of bug surfaces loudly instead of silently.
- [ ] **Arrange actions (layout switching)** — bind `RotatePanes` (Clockwise/CounterClockwise), keep the zoom toggle, and frame scenes as launchable layout presets. NO kitty-style layout engine. Documented as "Arrange" (live) vs "Scenes" (presets).
- [ ] **Embrace the search overlay** — keep WezTerm's `Ctrl+Shift+F` search and document `Ctrl+R` (CopyMode `CycleMatchType`) to cycle case-sensitive / case-insensitive / regex. Relaxes the prior "no less-style search overlays" philosophy rule.
- [ ] **Refresh ai + dev seed scenes** — give them per-pane + tab colors (like the new docker scene).

**Plans:** 7/7 plans executed ✓ — compacted into 7 logical commits (`37d61cc`..`e184392`); UAT 8/8 happy-path PASS (`06.1-UAT.md`). Two follow-up design gaps deferred to Phase 6.3: G-1 (icon attr) + G-2 (tab/pane color split).
Plans:

- [x] 06.1-01-PLAN.md — Shared cli/lib/color.lua (consolidate normalize/validate + palette + OSC builders; accept #RRGGBBAA, D-01/D-09) [wave 1] ✓ 2026-06-15
- [x] 06.1-02-PLAN.md — Shared cli/lib/cwd.lua resolver (locked grammar, no $(...) eval; D-01/D-07/D-08) [wave 1] ✓ 2026-06-15
- [x] 06.1-03-PLAN.md — Decouple tab color->WEZTERM_TAB_COLOR via OSC + title pure text; rewire pane/tab to shared color (D-01/D-02/D-03/D-04/D-09) [wave 2] ✓ 2026-06-15
- [x] 06.1-04-PLAN.md — Scene/recipe cwd/focus/size + clean-pane --cwd spawn + OSC tab color + spec (D-01/D-05/D-06/D-07/D-08) [wave 3] ✓ 2026-06-15
- [x] 06.1-05-PLAN.md — Render active-pane color + #RRGGBBAA + RotatePanes Alt+Shift+R/E + search overlay docs (D-02/D-04/D-09/D-12) [wave 3] ✓ 2026-06-15
- [x] 06.1-06-PLAN.md — wez doctor shadow-detection core gate + migration doc (D-10/D-11) [wave 3] ✓ 2026-06-15
- [x] 06.1-07-PLAN.md — Refresh ai+dev seeds + live spawn --cwd integration test + recorded live repro (D-12/D-13/D-14/D-15) [wave 4] ✓ 2026-06-15

### Phase 06.2: Identity Orthogonality (INSERTED)

**Goal:** Finish the decoupling Phase 6.1 started. 6.1 separated tab COLOR from tab TITLE; 6.2 extends the same orthogonality principle to the two attributes that are still coupled — the icon (today inferred from the title's first word) and the tab-vs-pane color (today a single shared user var). After 6.2, color, title, and icon are three independent, explicit attributes, and a tab can hold a stable color of its own.

**Depends on:** Phase 6.1 (complete) — revises locked decisions D-02/D-03/D-04.
**Requirements**: refines PANE-* / TAB-* / SCEN-* identity behavior (no new requirement IDs; supersedes 6.1's D-02 active-pane-wins and D-03/D-04 icon-in-title).

**Scope (from 6.1 UAT gaps G-1/G-2 + maintainer direction):**

- [ ] **G-1 — Icon is its own attribute.** Add a dedicated `icon` attribute to BOTH the CLI (its own flag/position, like the old bash positional arg) and scene recipes (`icon` key at tab + `[[pane]]` level), decoupled from `title`. Render via a distinct carrier (e.g. `WEZTERM_TAB_ICON`) composed as `icon + title` so title text stays literal. Decide the fate of the first-word ICONS shortcut in `cli/lib/title.lua` (recommend: drop it; keep a parse-and-warn migration). Revises D-03/D-04.
- [ ] **G-2a — Split tab color from pane color.** Today `wez tab color` and `wez pane color` both write `WEZTERM_TAB_COLOR`, so the active pane clobbers an explicit tab color (confirmed our implementation, not a WezTerm limit). Split into `WEZTERM_TAB_COLOR` (tab's own, stable) + `WEZTERM_PANE_COLOR` (per-pane accent). `format-tab-title` precedence: an explicit tab color ALWAYS wins; the active pane's color is used only when the tab has none. Revises D-02.
- [ ] **G-2b — Explicit "follow active-pane color" toggle/flag.** The old auto-adopt behavior (tab follows the focused pane's color) becomes an OPT-IN, not a silent default: settable as a scene-recipe key (tab level, `follow_pane_color`) AND a `wez tab color` CLI flag (`--follow-pane-color`), default OFF, carried by the locked user var `WEZTERM_TAB_FOLLOW_PANE` (payload `"1"`/unset). When ON, a tab with no explicit color tracks its active pane; when OFF, a colorless tab stays neutral. Makes the behavior readable in the TOML/CLI instead of magic. (Optional sub-idea — a "similar color family" palette so a tab's panes read as a related group — was evaluated during discuss and DEFERRED as not necessary for 6.2.)
- [ ] **`{cwd}`-in-title auto-fallback.** When a title resolves to empty text, auto-fall-back to the launch-dir basename (the `{cwd}` token's value) so panes AND tabs self-label by directory without an explicit token. Builds on `cli/lib/title.lua expand_cwd`/`fallback_title`.
- [ ] **Migration (parse-and-warn only — NO doctor gate).** Lightweight one-time CLI stderr warn when a known icon-name is typed as the leading word of a literal title (suggesting `wez tab icon`), without swapping it. Per CONTEXT D-06 this is the ENTIRE migration surface: the earlier "extend `wez doctor` if a new shadowing/coupling class emerges" idea is deliberately NOT built (no doctor gate, advisory probe, auto-fix, or migration tracking) — maintainer: "we can remove the legacy behavior and forget about someone using legacy config." Refresh seed scenes to use the explicit `icon` attribute.

**Plans:** 5/5 plans complete
Plans:
**Wave 1**

- [x] 06.2-01-PLAN.md — Pure-core: title.resolve_icon (named-or-literal) + drop first-word swap + shared cwd-empty fallback (tabs+panes) (D-02/D-05/D-11/D-12/D-13) [wave 1] ✅ 2026-06-16

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 06.2-02-PLAN.md — CLI: wez tab/pane icon + --icon on title + color carrier split (WEZTERM_PANE_COLOR) + --follow-pane-color (WEZTERM_TAB_FOLLOW_PANE) + legacy icon-in-title warn + spec (D-01/D-03/D-06/D-07/D-09/D-16) [wave 2]
- [x] 06.2-03-PLAN.md — Render: format-tab-title icon compose + 3-step accent precedence + cwd fallback; drop legacy parser (D-04/D-08/D-10/D-11/D-13) [wave 2]

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 06.2-04-PLAN.md — Scene/recipe schema: icon + follow_pane_color keys, per-pane WEZTERM_TAB_ICON + WEZTERM_PANE_COLOR + per-pane cwd-basename fallback emit (D-03/D-07/D-09/D-12/D-13) [wave 3]

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 06.2-05-PLAN.md — Refresh seed scenes to explicit icon + full-suite gate + live-session repro (D-03/D-05; live D-04/D-08/D-09/D-11/D-13) [wave 4]

### Phase 06.3: Distribution Channels (INSERTED)

**Goal:** Make releases self-renewing and reversible: a scheduled rolling nightly/latest channel alongside pinned `v*` tags, a bootstrapper that lets the user choose which channel to install, and a first-class uninstall path that works even when only the binary was downloaded (no repo checkout).

**Depends on:** Phase 6 (installer/release infra, complete). Independent of 6.2.
**Requirements**: extends INST-07/08/09 distribution behavior (no new requirement IDs).

**Scope:**

- [x] **Nightly/latest rolling channel.** A scheduled GitHub Actions workflow (cron) builds and publishes a rolling `nightly`/`latest` release (release assets persist; only Actions *artifacts* expire at 90 days). Pinned `v*` tags remain the stable channel. *(Delivered: weekly cron + `github.ref` routing, datestamped `nightly-YYYYMMDD` prerelease, skip-if-unchanged, prune-to-5; live-verified via real Actions run.)*
- [x] **Bootstrapper channel selector.** `tools/bootstrap-wezterm.sh` / `tools/build.sh download_release` gain a channel knob (pinned tag vs `latest`/`nightly`), so the user decides which available build to pull instead of the hardcoded `v0.1.0` pin. *(Delivered: `WEZ_CHANNEL=nightly|stable|<vX.Y.Z>`, default nightly, `.sha256` gate preserved.)*
- [x] **`wez uninstall`.** A `wez uninstall` command (+ `make uninstall` parity) that cleanly removes the managed config block + installed binary, working in the binary-only case (no cloned repo) as well as the full-checkout case. Non-destructive to genuine personal settings; writes a backup. *(Delivered: front door over the `uninstall-state` engine, self-delete-last, TTY-confirm/`--yes`.)*

**Plans:** 3/3 plans complete

- [x] 06.3-01-PLAN.md — `wez uninstall` front door over the uninstall-state engine; binary-only, self-delete-last, --yes-on-pipe, repointed make/glue (D-09/D-10/D-11) [wave 1]
- [x] 06.3-02-PLAN.md — Rolling nightly channel in release.yml: schedule trigger + github.ref routing + datestamped nightly-YYYYMMDD prerelease + skip-if-unchanged + prune-to-5 (D-04..D-07/D-12) [wave 1]
- [x] 06.3-03-PLAN.md — Bootstrapper channel selector: WEZ_CHANNEL=nightly|stable|<vX.Y.Z> replacing the v0.1.0 pin in build.sh download_release(), checksum gate preserved (D-02/D-03/D-08) [wave 1]

### Phase 06.4: User Documentation Audit and Refactor (INSERTED, renumbered from 06.2)

**Goal:** Audit ALL user-facing documentation for accuracy and clarity against the shipped v0.1.0 reality and the Phase 6.1/6.2/6.3 redesign, then refactor it — starting with README.md — into clear, progressive-disclosure structure.

**Depends on:** Phase 6.1 + 6.2 + 6.3 (so docs describe the final decoupled icon/color model, scene schema, and install channels — not soon-to-change behavior). **Runs LAST among the 6.x deltas.**
**Requirements**: documentation quality (no new requirement IDs).

**Scope:**

- [ ] **README.md** — audit against actually-shipped behavior (the `curl|bash` one-liner, `wez` subcommands, keybindings incl. the new `Ctrl+Shift+K`, scenes, `wez doctor`/`wez keys`, `wez update`), then refactor it with the `/agent-md-refactor:agent-md-refactor` skill (progressive disclosure: lean top-level README linking to focused docs).
- [ ] **Other docs** — `docs/` (e.g. `docs/agent-iteration.md`, `docs/macos-verification.md`, `docs/plans/`), top-level guides, and any `*.md` a user reads: audit for staleness and accuracy; refactor/split where bloated.
- [ ] **Drift check** — verify every documented command/flag/keybinding/scene field actually exists, cross-checked against `cli/spec.lua` + `config/wezterm-setup/keybindings.lua` + the 6.1 scene schema. No documented-but-unimplemented (or implemented-but-undocumented) surface.
- [ ] **Reflect 6.1** — decoupled `color`/`title`, new scene schema (`cwd`/`focus`/`size`, alpha), arrange/RotatePanes, embraced search overlay (`Ctrl+R` case toggle) are all documented correctly.

Plans:

- [ ] TBD (run /gsd-discuss-phase 06.2 then /gsd-plan-phase 06.2 to break down)

### Phase 06.5: Keybinding Clarity & `wez keys` Output Curation (INSERTED)

**Goal:** Make `wez keys` output trustworthy and low-noise. Today it mixes TWO display
criteria — the produced CHARACTER (a Shift chord shown as `ALT+X`, the uppercase silently
implying Shift) and the physical KEY with explicit mods shown twice (`SHIFT|CTRL+Z` **and**
`SHIFT|CTRL+z`). The result is both ambiguous (is it `Alt+X` or `Alt+Shift+X`?) and noisy
(near-duplicate rows). Pick ONE consistent convention, render every chord unambiguously, and
present wezterm-setup's curated bindings first with inherited/default bindings clearly
separated. (Surfaced live 2026-06-16/17 while debugging close-pane/close-tab on Pop!_OS.)

**Depends on:** Phase 6.1/6.2 (keybindings.lua stable). **Should land BEFORE Phase 6.4 Doc
Audit** so the documented keybindings reflect the curated output (6.4 still runs last overall).
**Requirements**: keybinding/CLI UX clarity (no new requirement IDs).

**Scope:**

- [ ] **Curated-first output.** A clear "wezterm-setup managed" section listed FIRST; WezTerm
  defaults/inherited bindings listed after — or behind a `--all`/`--verbose` flag, curated-only
  by default — so the real curated combos are not buried in default noise.

- [ ] **One display convention.** Decide produced-character vs physical-key and apply it
  uniformly. A chord requiring Shift renders Shift EXPLICITLY (`ALT+SHIFT+X`), never implied by
  an uppercase letter. No row should be readable two different ways.

- [ ] **De-noise.** Collapse rows that represent the SAME effective chord (e.g. `SHIFT|CTRL+Z`
  + `SHIFT|CTRL+z`); one line per real binding.
- [ ] **Reconcile `mapped:` + Shift declarations** in `keybindings.lua` (e.g. close-pane
  `mapped:x` `ALT|SHIFT` resolves to `key='X' mods='ALT'`) so the declared form, the displayed
  chord, and the keys actually pressed all agree — normalize the inconsistent "declare both
  lower+upper" pattern.

- [ ] Regression tests for the new ordering + dedupe + unambiguous rendering.

**Plans:** TBD (run `/gsd-discuss-phase 06.5` → `/gsd-plan-phase 06.5`)

### Phase 7: macOS Parity Pass (D-18)

**Goal**: Every shipped feature is verified working on macOS (Apple Silicon + Intel) and the platform-deferred gaps are closed — the final gate before v1 is declared done
**Depends on**: Phase 6
**Requirements**: macOS verification (D-18) of all platform-sensitive requirements — INST-01/06/07, FOUND-01, DIAG-05, PANE-01..04, SCEN-03..06 (no new requirement IDs; flips their "macOS deferred" status to Done)

**Success Criteria** (what must be TRUE):

1. `bash tools/verify-macos.sh` passes its auto gate on a real Mac (build, suite, all `__complete` contexts, completion `-n`, scene-launch exit codes, copy-if-absent seeding)
2. The full `docs/macos-verification.md` runbook is driven top-to-bottom and every capability section passes — visual/UX steps reviewed with `agent-ui-ux-designer`
3. Deferred macOS gaps closed: Gatekeeper/quarantine, Apple Silicon ad-hoc codesign of the built binary, `install_macos` real `.app` placement (INST-06), `sha256sum`→`shasum`, `mapfile`/bash-3.2 in the test harness
4. Every "macOS deferred D-18" status in REQUIREMENTS.md / coverage is flipped to Done with recorded evidence (incl. the A-1 `scene new --layout/--color` completion confirmed in zsh on macOS)

**Plans**: 5 plans
Plans:
**Wave 1**

- [x] 07-01-PLAN.md — Wave 0: sudo-free macOS compile toolchain (lua@5.4 keg + luastatic, `make setup`) + bash-3.2-safe run-tests.sh (mapfile removed) + sha256 sweep [wave 0]
- [x] 07-02-PLAN.md — Real install_macos() .app placement to ~/Applications (integrity-gate-before-extract, ditto) + wezterm_macos_asset_url + unit test (INST-06, D-04/D-05/D-07) [wave 1]
- [x] 07-03-PLAN.md — CI/CD: re-introduce the 3-leg release.yml matrix (ubuntu/macos-15-intel/macos-14) + build-time ad-hoc codesign both arches + ci-setup-toolchain lua@5.4 fix + arm64 smoke + dispatch dry-run (D-01/D-06) [wave 1] (completed 2026-06-22; actionlint clean, TEXT gate 19/19; live dispatch is 07-04)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 07-04-PLAN.md — E2E loop: dispatch→`gh run watch`→real install→verify (integrity gate, doctor exit 0) + D-07 quarantine verify-then-decide + green-gated autonomous first-v*-tag push (INST-06/07, D-07/D-09/D-10/D-11) [wave 2] (completed 2026-06-22; D-09 loop 1 red→fixed→green; E2E doctor exit 0, version nightly-20260622+gsd-phase-07-macos-parity; D-07 no quarantine → install.sh unchanged; v1.0.0 auto-pushed, stable run 27971643099 green)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 07-05-PLAN.md — Parity verification + evidence: verify-macos.sh auto gate green (PASS=26 FAIL=0) + drove the full runbook + agent-ui-ux-designer §5/§6 PASS review + flipped all 13 D-18 statuses to Done with §-citations (D-02/D-03/D-09) [wave 3] (completed 2026-06-22)

> **Phase 7 / 7.1 split (CONTEXT D-01/D-01b, 2026-06-20):** Phase 7 is the v1 gate — it delivers the entire macOS build INCLUDING the arm64 asset (built + ad-hoc-codesigned via CI/CD) plus the full agent-driven ecosystem verification on the available **Intel** Mac. arm64 status flips on the shared CI/CD build + codesign + Intel-proven parity; **no Apple Silicon hardware run is required for the v1 close**. The Apple-Silicon end-user distribution check is the separate, **non-gating Phase 7.1** (out of scope here).

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
| 6. Ergonomic Installer | 6/6 | Complete   | 2026-06-15 |
| 6.1 Tab and Scene Identity Redesign | 7/7 | Complete (UAT-verified) | 2026-06-15 |
| 6.2 Identity Orthogonality (icons G-1 + color split/adopt-toggle G-2) | 5/5 | Complete   | 2026-06-16 |
| 6.3 Distribution Channels (nightly/latest + uninstall) | 3/3 | Complete   | 2026-06-18 |
| 6.5 Keybinding Clarity & `wez keys` Output Curation | 0/? | Not started (before 6.4) | - |
| 6.4 User Documentation Audit and Refactor | 0/? | Not started (after 6.2/6.3/6.5) | - |
| 7. macOS Parity Pass (D-18) | 5/5 | Complete | 2026-06-22 |

---

## Coverage

| Requirement | Phase | Status |
|-------------|-------|--------|
| INST-01 | Phase 1 | Done (01-04, Linux; macOS verified D-18 (§2)) |
| INST-02 | Phase 1 | Done (01-04) |
| INST-03 | Phase 1 | Done (01-04) |
| INST-04 | Phase 1 | Done (01-06) |
| INST-05 | Phase 1 | Done (01-06) |
| INST-06 | Phase 1 | Done (01-02 Linux; macOS .app placement closed 07-02 — real install_macos, integrity-gated, live-verified on Intel) |
| FOUND-01 | Phase 1 | Done (01-03, Linux; macOS verified D-18 (§3 CWD)) |
| FOUND-02 | Phase 1 | Done (01-03) |
| FOUND-03 | Phase 1 | Done (01-03) |
| FOUND-04 | Phase 1 | Done (Plan 05 `wez keys` + Plan 04 config install) |
| FOUND-05 | Phase 1 | Done (01-03) |
| DIAG-01 | Phase 1 | Done (01-06) |
| DIAG-02 | Phase 1 | Done (Plan 05) |
| DIAG-03 | Phase 1 | Done (Plan 05) |
| DIAG-04 | Phase 1 | Done (Plan 05) |
| DIAG-05 | Phase 1 | Done (Plan 07, Linux; macOS verified D-18 (§4 completions + verify-macos §2/§3)) |
| PANE-01 | Phase 2 | Done (Phase 2, Linux; macOS verified D-18 (§5)) |
| PANE-02 | Phase 2 | Done (Phase 2, Linux; macOS verified D-18 (§5)) |
| PANE-03 | Phase 2 | Done (Phase 2, Linux; macOS verified D-18 (§5)) |
| PANE-04 | Phase 2 | Done (Phase 2, Linux; macOS verified D-18 (§5)) |
| TAB-01 | Phase 3 | Done (Phase 3) |
| TAB-02 | Phase 3 | Done (Phase 3) |
| TAB-03 | Phase 3 | Done (Phase 3) |
| TAB-04 | Phase 3 | Done (Phase 3) |
| TAB-05 | Phase 3 | Done (Phase 3) |
| SCEN-01 | Phase 4 | Done (Phase 4, Linux; macOS deferred D-18) |
| SCEN-02 | Phase 4 | Done (Phase 4, Linux; macOS deferred D-18) |
| SCEN-03 | Phase 5 | Done (Phase 5, Linux; macOS verified D-18 (§7)) |
| SCEN-04 | Phase 5 | Done (Phase 5, Linux; macOS verified D-18 (§7)) |
| SCEN-05 | Phase 5 | Done (Phase 5, Linux; macOS verified D-18 (§7d + §4 + A-1 zsh --layout/--color)) |
| SCEN-06 | Phase 5 | Done (Phase 5, Linux; macOS verified D-18 (§7a + verify-macos §5)) |

| INST-07 | Phase 6 | Done (Phase 6; macOS on-Mac E2E verified 07-04 — real curl\|install.sh, SHA-256 gate, doctor exit 0, version match, Gatekeeper clears, on Intel) |
| INST-08 | Phase 6 | Done (Phase 6; macOS on-Mac verify deferred D-18) |
| INST-09 | Phase 6 | Done (Phase 6) |

**v1 coverage: 34/34 requirements mapped (INST-07 + INST-08 + INST-09 added 2026-06-14). Phase 0 carries validation work only (no REQUIREMENTS.md items). Phase 7 is the macOS verification gate (D-18) — no new IDs.**

---

*Roadmap created: 2026-06-07*  
*Last updated: 2026-06-22 — Phase 7 (07-05) flipped the 13 platform-sensitive D-18 requirement IDs from the deferred qualifier to the "macOS verified D-18 (§...)" form on the green harness evidence (verify-macos.sh PASS=26 FAIL=0 + agent-driven runbook + §5/§6 ui-ux PASS). SCEN-01, SCEN-02 and INST-08 remain deferred (out of the 07-05 flip scope; the arm64 end-user check is the non-gating Phase 7.1). The Coverage table agrees byte-for-byte with the REQUIREMENTS.md Traceability table per ID. Prior: 2026-06-20 — reconciled the Coverage table with delivered reality (TAB-01..05, SCEN-01/02, INST-07/08/09 flipped from Pending to Done). 2026-06-14 — added Phase 6 (Ergonomic Installer, INST-07) + Phase 7 (macOS Parity Pass, D-18); discuss-phase 6 added INST-08.*
