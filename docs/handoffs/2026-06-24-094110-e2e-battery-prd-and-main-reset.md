# Handoff: E2E Testing Battery PRD + main reset to v1.0.0

## Session Metadata
- Created: 2026-06-24 09:41:10
- Project: /Users/ramon/git/personal/wezterm-setup
- Branch (at handoff): archive/phase-7-macos @ 69e0e20
- Session duration: long (multi-phase: 07.1 execution → live debugging → strategic reset → PRD)

### Recent Commits (for context)
- `a79367d` (main) docs(prd): add E2E testing battery PRD; reset main to v1.0.0 baseline
- `69e0e20` (archive/phase-7-macos, gsd/phase-07.1) fix(07.1-scene-reuse): emit reused pane styling to wez stdout
- `77d18cf` (v1.0.0 tag) docs(07-04): record Task 3 green-gate decision — push v1.0.0

## Handoff Chain
- **Continues from**: None (fresh start for the e2e effort)
- **Supersedes**: the prior 07.1 "complete/shipped" handoff (that work is now parked on `archive/phase-7-macos`)

## Current State Summary

Phase 07.1 (macOS post-v1 follow-ups) was executed, then live-testing on the real WezTerm mux
surfaced a cascade of regressions (scene escape-char leak + hang, dead new-tab keybinding, `wez keys`
broken, build/install failures). Several fixes oscillated (the scene fix was rewritten 4×). The user
concluded the post-v1 delta (~125 commits, +4,674/−700 runtime) was too unstable to keep building on
and chose a **clean reset**: archive the delta, reset `main` to the shipped `v1.0.0`, and rebuild the
macOS behavior **test-first** under a new **E2E testing battery**. We authored that PRD
(`docs/prds/e2e-testing-battery-v1.0-prd.md`, scored 100/100), committed it to `main`, executed the
migration (backup branch + fast-forward reset + push), and left this checkout on the mac archive branch.
**Next work is the e2e battery, Linux-first, off `main`.**

## Codebase Understanding

### Architecture Overview
- **Config layer:** pure Lua under `config/wezterm-setup/` (zero deps), loaded by WezTerm via a managed
  `require('wezterm-setup').apply(config)` block injected into `~/.config/wezterm/wezterm.lua`.
- **Companion CLI `wez`:** Lua under `cli/` (`cli/commands/*`, `cli/lib/*`), shipped as a luastatic
  static binary OR (local dev) a `dist/wez` launcher that execs the repo sources directly.
- **Install/build pipeline:** `tools/setup.sh` (places config, install-state), `tools/bootstrap-wezterm.sh`
  (`install_macos`/`install_linux`), `tools/build.sh` (luastatic or dev launcher), `tools/uninstall.sh`,
  `Makefile` targets, `tools/run-tests.sh` (Lua test discovery + `WEZTERM_INTEGRATION` gate).
- **Scenes:** `cli/commands/scene.lua` (I/O orchestration) + `cli/lib/scene.lua` (pure: split plan,
  `decide_materialization` reuse-vs-new-tab). Recipes in `scenes/{ai,dev,docker}.toml`.

### Critical Files
| File | Purpose | Relevance |
|------|---------|-----------|
| `docs/prds/e2e-testing-battery-v1.0-prd.md` | The PRD (on `main`) | THE artifact to execute next |
| `cli/commands/scene.lua` | scene spawn/style orchestration | reuse-pane styling is the fragile spot |
| `cli/lib/scene.lua` | `decide_materialization` (reuse if tab has 1 pane, else new-tab) | explains "some scenes fine, others not" = launch context |
| `config/wezterm-setup/keybindings.lua` | curated key table (`mapped:` keys, `disabled_defaults`) | SpawnTab/clear not registering — open bug |
| `config/wezterm-setup/format-tab-title.lua` | tab-title render/truncation | column-aware fix lives in archive |
| `tools/bootstrap-wezterm.sh` | `install_macos` symlinks | siblings fix (wezterm-gui) is verified-good |
| `tools/setup.sh` / `tools/uninstall.sh` | install/uninstall glue | install-cycle fixes verified-good |
| `cli/lib/color.lua` | OSC-1337/OSC-11 + octal printf builders | how user-vars are emitted |

### Key Patterns Discovered
- **Deployment chain matters:** repo edits do NOT affect the user until `make install` copies
  `config/wezterm-setup/` → `~/.config/wezterm/` AND WezTerm **reloads** config. The dev launcher
  (`dist/wez`) DOES pick up `cli/` changes live (it execs repo source).
- **OSC delivery:** user-vars reach the terminal as PROGRAM OUTPUT, not shell input. `wez pane color`
  writes OSC to its own stdout. Scenes (spawned panes) emit via a spawn **prelude**
  (`sh -c 'printf <octal>; exec $SHELL -l'`); the **reused** pane must write OSC to `wez`'s own stdout
  (NOT `send-text`, which races the running `wez`).
- **Project rules:** English-only; TDD; bash-3.2-safe (macOS bash 3.2 vs Linux 5); sudo-free; zero
  runtime deps; `mapped("k")` = `"mapped:k"` (fire-on-produced-char); `M.super_mod = "SUPER"` (Cmd on
  mac, Super on Linux).

## Work Completed

### Tasks Finished
- [x] Executed Phase 07.1 (3 plans) + verification; persisted UAT
- [x] Fixed (quick tasks, verified): dev-launcher Lua 5.4 resolution; idempotent uninstall
- [x] Live-debugged on the real mux: reproduced scene leak/hang, dead `wez keys`, install Error 3
- [x] Fixed + verified: keys-siblings symlink; install-cycle (non-interactive reinstall + dist/wez uninstall fallback)
- [x] Localized (NOT fully fixed): scene reuse-pane styling; SpawnTab/clear keybinding non-registration; tab-title truncation
- [x] Authored e2e battery PRD (100/100); committed to `main`
- [x] Migration: created `archive/phase-7-macos`, reset `main` → v1.0.0 + PRD, pushed both

### Files Modified (this session — now split across branches)
| File | Changes | Where |
|------|---------|-------|
| `docs/prds/e2e-testing-battery-v1.0-prd.md` | NEW PRD | **main** (`a79367d`) |
| scene.lua / keybindings.lua / format-tab-title.lua / bootstrap / setup / uninstall / build | 07.1 fixes (mixed quality) | **archive/phase-7-macos** (`69e0e20`) |

### Decisions Made
| Decision | Options | Rationale |
|----------|---------|-----------|
| Reset `main` to v1.0.0 | A) v1.0.0  B) pre-Phase-7 | A: keeps working build/CI/bootstrap, drops unverified churn |
| E2E runner | Lua / bats / hybrid | Lua asserts (zero deps, cross-platform) + bash-3.2-safe orchestration |
| v1 scope | T1-2 / T1-3 / all 4 | All 4 tiers in v1 |
| Done-bar | deterministic must-pass / all ≥80% / 80% overall | T1+T2+T3-reg MUST-PASS (gate CI); T3-firing + T4 best-effort/local |
| CI | GH Actions / local / both | Both, phased (local `make e2e` first, then Linux CI gate) |
| T4 method | AI-vision / snapshot / hybrid | Hybrid (AI-vision semantic + snapshot chrome) |
| Knobs | N=10 / N=5 / defer | N=5 rerun flake guard; Haiku-class vision model |

## Pending Work

## Immediate Next Steps
1. On the **Linux** machine: `git pull` `main` (at `a79367d`) — it has the PRD and the clean v1.0.0 baseline.
2. **Phase 1 (PRD):** scaffold `tests/e2e/` + `tools/run-e2e.sh` (bash-3.2-safe) + `make e2e`/`make e2e-setup`
   + a platform-expectations module + self-skip gates; implement **Tier 1** (all subcommands, deterministic).
3. **Cherry-pick the 4 verified fixes** from `archive/phase-7-macos` onto `main` (after their tests are
   green under the new battery): `39aa3b6`+`59f803e` (dev-launcher Lua), `7e72bf5`+`dec5d59` (install-cycle),
   `9d117cd`+`2798d6f` (uninstall idempotent), `4c765e1`+`959dac0` (keys-siblings symlink).
4. Then Phase 2 (scenes + T3-registration), Phase 3 (Linux CI gate), Phase 4 (firing + visuals, local).

### Blockers/Open Questions
- [ ] **SpawnTab + clear keybindings do NOT register** in the effective `show-keys` table (fresh config
      load), while other hybrids do. Localized to keys `t`/`k` (the only ones in `disabled_defaults`).
      Hypothesis: `disabled_defaults` disables the working default while the `mapped:t/k` replacement
      fails to register. UNRESOLVED — rebuild under T3-registration.
- [ ] **Scene reuse-pane** behavior unverified on a real single-pane-tab launch (the fix writes OSC to
      `wez` stdout; mechanism proven via `wez pane color`, byte-verified, but not GUI-confirmed).
- [ ] Linux regression risk: the archived changes touched cross-platform code; never verified on Linux.

### Deferred Items
- Exact "80%" is enumerated in PRD Appendix A but coverage tracking is built as tests land.
- macOS GUI in headless CI — out of scope (macOS GUI runs locally only).

## Context for Resuming Agent

## Important Context
- **`main` is the clean starting line** (v1.0.0 + PRD). Do NOT reintroduce the suspect scene/keys/tab
  changes by merging the archive branch wholesale — REBUILD them test-first per the PRD. Only cherry-pick
  the 4 explicitly-verified fixes.
- **The reset push was a fast-forward** (origin/main was an ancestor of v1.0.0) — nothing was lost, and
  everything is also on `archive/phase-7-macos`.
- **Why earlier "verified" claims failed:** testing hit the wrong layer (unit data / string-greps), not
  the running GUI. The PRD exists specifically to close that gap. When you claim "verified," it must mean
  observed on a running system (mux get-text / show-keys / injected keys / screenshot), not unit-green.

### Assumptions Made
- The user works `main`/Linux on a Linux box and may keep the mac branch checked out here (offered a
  `git worktree` for simultaneous checkouts — not yet set up).
- v1.0.0's build/CI/bootstrap scaffolding is sound (the release was cut from it).

### Potential Gotchas
- `wezterm cli` can HANG if a prior `wez scene` deadlocked the mux (stuck processes). Kill stuck
  `cli/wez.lua scene` + `wezterm cli` PIDs to recover; the integration test will then pass/skip instead
  of hanging.
- macOS: `lua5.4` is keg-only — prepend `$(brew --prefix lua@5.4)/bin` to PATH for tests.
- CLI cannot read RENDERED tab text or inject GUI key chords — those need screenshots / OS input tools
  (cliclick/osascript on mac, xdotool/ydotool on Linux) + macOS Accessibility/Screen-Recording perms.
- Scene "reuse vs new-tab" is decided by `decide_materialization`: tab with exactly 1 pane → reuse;
  ≥2 panes → new-tab. This (not the recipe) explains differing behavior.

## Environment State

### Tools/Services Used
- git (branches: `main` a79367d pushed; `archive/phase-7-macos` 69e0e20 pushed+current; `gsd/phase-07.1...`
  also 69e0e20; `gsd/phase-07-macos-parity` bd045c4). Remote: github.com:castocolina/wezterm-setup.
- WezTerm mux (`wezterm cli`), Homebrew lua@5.4 + luastatic, `make`/`run-tests.sh`.

### Active Processes
- None intentionally left running. (Watch for stale `wezterm cli`/`wez scene` if the mux hangs.)

### Environment Variables
- `WEZTERM_SETUP_DIR` (scene/scratch tests), `WEZTERM_PANE` (reuse-mode detection), `WEZTERM_INTEGRATION`
  (integration test gate), `WEZ_BIN_DIR`, `PATH` (must include keg lua on mac). No secrets.

## Related Resources
- `docs/prds/e2e-testing-battery-v1.0-prd.md` (on `main`) — the plan to execute
- `archive/phase-7-macos` branch — the parked delta + the 4 reusable fix commits
- `.planning/STATE.md`, `.planning/phases/07.1-macos-post-v1-follow-ups/` (on archive branch)

---

**Security Reminder**: No secrets included; only env var NAMES.
