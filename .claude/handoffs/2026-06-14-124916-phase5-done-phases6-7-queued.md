# Handoff: Phase 5 shipped + verified; Phases 6 (installer) & 7 (macOS parity) queued

## Session Metadata
- Created: 2026-06-14 12:49:16
- Project: /home/user-zero/git/personal/wezterm-setup
- Branch: master
- Session duration: long (multi-phase: planned + executed + verified Phase 5, then reviews, macOS prep, A-1 fix, roadmap edit)

### Recent Commits (for context)
  - 7f5551d docs(roadmap): add Phase 6 (Ergonomic Installer) + Phase 7 (macOS Parity, D-18)
  - 9307829 fix(completion): wire scene new --layout/--color value completion (A-1)
  - 69a1870 docs: consolidate post-phase-5 follow-ups + macOS auto-verifier
  - 5e3f73d fix(05): apply UX review polish to scene launch error copy
  - 7a2d76c docs(05): mark Phase 5 complete in checklist + coverage (SCEN-03/04 Done)

## Handoff Chain

- **Continues from**: None (fresh start)
- **Supersedes**: None

> This is the first handoff for this task.

## Current State Summary

wezterm-setup is a WezTerm config distribution + companion `wez` CLI (pure Lua 5.4, built to a single binary via luastatic, zero external deps). **Phase 5 (Named Scenes) is complete and goal-verified on Linux** — `wez scene launch <name>`, copy-if-absent seeding, dynamic completion all shipped. All 31 original v1 requirements are Linux-done; full test suite is **17/17 green**. This session also: ran a 3-way review (code + E2E + UI/UX) on Phase 5, applied UX fixes, built the macOS verification tooling, fixed the A-1 completion bug, and **added two new roadmap phases**. Work left off cleanly right after committing the roadmap changes — nothing is mid-edit. The next concrete action is `/gsd-plan-phase 6`.

## Codebase Understanding

## Architecture Overview

- **Two runtimes:** (1) pure-Lua config layer inside WezTerm (`config/wezterm-setup/`), zero deps; (2) companion `wez` CLI (`cli/`), built by `tools/build.sh` to `dist/wez` via luastatic — falls back to a dev source-launcher when luastatic is absent.
- **Pure-core / IO-shell split** is the governing pattern: pure logic in `cli/lib/*.lua` (no `io`/`os.execute`/`wezterm`), I/O + shell-outs in `cli/commands/*.lua`. Verified by grep-based purity tests.
- **D-16 single-source completion:** the hidden `wez __complete <context>` hook (`cli/commands/complete.lua`) is the ONE dynamic-value extension point; `cli/commands/completions.lua` GENERATES the zsh/bash scripts by walking `cli/spec.lua`. Adding a subcommand to spec.lua makes it appear in completion with no script edit.
- **D-01 decision-free installer:** logic lives in Lua commands; `tools/setup.sh` is glue.
- **Tests:** `tools/run-tests.sh` discovers `*_test.lua` under `tests/`, `cli/`, `config/`; runs each under `lua5.4` (`LUA_BIN=lua` override for Homebrew). Tests assert script TEXT + `bash -n`/`zsh -n`, not live completion.

## Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `.planning/ROADMAP.md` | Phases 0–7; Phase 6/7 just added | Start here for what's next |
| `.planning/MACOS-PARITY-AND-FOLLOWUPS.md` | Single tracker: all post-Phase-5 work (macOS + backlog) | Source of truth for pending items |
| `docs/macos-verification.md` | Step-by-step macOS runbook (agent-drivable) | Phase 7 driver |
| `tools/verify-macos.sh` | Non-destructive auto-verifier (24 PASS on Linux) | Phase 7 gate; run first on Mac |
| `cli/commands/completions.lua` | Generates zsh/bash completion scripts | Touched by A-1 fix |
| `cli/commands/complete.lua` | `__complete` contexts (incl. new `scene-colors`) | Touched by A-1 fix |
| `cli/lib/scene.lua` | Scene core; now exposes `M.LAYOUTS` + `M.COLOR_NAMES` | Single-source palettes |
| `cli/commands/scene.lua` | `scene new`/`scene launch` (M.run_new reuse seam) | Phase 5 core |
| `tools/setup.sh` | Install glue (STEP 4 cp -R, STEP 4b seed-scenes) | Phase 6 builds on this |
| `tools/bootstrap-wezterm.sh` | WezTerm bootstrap; `install_macos()` is a STUB | Phase 6/7 gap to close |

### Key Patterns Discovered

- **macOS parity is decision D-18** — deliberately deferred to a batched pass; now promoted to **Phase 7**.
- **Commit discipline** (CLAUDE.md): prefer fewer cohesive commits; amend closely-related follow-ups. Route file edits through GSD workflows. Verify-before-done (real repro / suite output, never "should work").
- **The user communicates in Spanish**; reply in Spanish.
- **GSD `state.update`/`state.record-session` no-op** on this repo's free-form STATE.md (no structured session fields) — edit STATE.md directly when needed. `phase.add` generates verbose phase names + long dir slugs — clean them up after (done this session: `06-installer`, `07-macos-parity`).

## Work Completed

### Tasks Finished

- [x] Planned Phase 5 (`/gsd-plan-phase 5`) — 4 plans, 3 waves, plan-checker PASSED
- [x] Executed Phase 5 (`/gsd-execute-phase 5`) — incl. a human-approved supply-chain checkpoint (vendored tinytoml SHA-verified) and a session-limit resume mid-05-03
- [x] Phase verification — goal achieved; 2 UX defects found + fixed (I-1 double `error:`, I-3 "reinstall"→`wez seed-scenes`)
- [x] 3-way review (code reviewer + self-driven E2E + agent-ui-ux-designer) — all passed; backlog captured
- [x] Built macOS tooling: `docs/macos-verification.md` runbook + `tools/verify-macos.sh` (24 PASS Linux self-test, shellcheck-clean)
- [x] Fixed A-1: `wez scene new --layout/--color <Tab>` value completion (was unwired); bash runtime-proven
- [x] Added Phase 6 (Ergonomic Installer, new req INST-07) + Phase 7 (macOS Parity, D-18) to roadmap; cleaned phase.add output

## Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| (all committed — see git log) | Phase 5 impl, UX fixes, A-1 fix, macOS docs/script, roadmap | Working tree is CLEAN |

## Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| A-1 `--layout` bug: capture vs fix-now | TODO vs fix | User first chose capture; later chose fix (`/gsd-phase` session) → fixed in 9307829 |
| macOS parity as a real phase | tracker-only vs phase | User wanted it visible in roadmap → Phase 7 |
| Two phases, installer first | 1 combined / reverse order / installer-as-task | Installer built Linux-first; macOS pass then covers it too |
| INST-07 added (coverage 31→32) | reuse INST-06 vs new ID | The one-line remote bootstrap is genuinely new scope |
| `bg`/`opacity` | bug vs not-a-feature | Confirmed: `bg` == `wez pane color`; no `bg`/`opacity` ships — new req if wanted |

## Pending Work

## Immediate Next Steps

1. **`/gsd-plan-phase 6`** — plan the Ergonomic Installer (Linux-first). Will need discuss/spec + a threat model for the `curl|bash` pipe-to-bash entry point.
2. **`/gsd-plan-phase 7`** (or after 6 ships) — plan the macOS Parity Pass; it consumes `verify-macos.sh` + `docs/macos-verification.md`.
3. **Run Phase 7 on a real Mac** — `bash tools/verify-macos.sh` then drive the runbook with `agent-ui-ux-designer` for visual/UX steps.
4. After Phase 7 passes: `/gsd-complete-milestone` (NOT before — macOS is a hard v1 requirement, D-18).

### Blockers/Open Questions

- [ ] Phase 7 requires a physical/real macOS machine — cannot be done from this Linux environment.
- [ ] zsh runtime of the A-1 `--layout` completion is `zsh -n`-clean + text-correct but NOT headlessly runtime-verified (bash IS proven) — confirm in zsh on the macOS runbook §6.

### Deferred Items

- `--pane`/`--title` value completion (no closed candidate set) — minor, tracker §A-1.
- UX backlog (tracker §A-2): `wez scene list`, did-you-mean, unify `error:` vs `wez <cmd>:` prefixes, dead `scene` dispatcher branch, README recipe-edge-case caveats.

## Context for Resuming Agent

## Important Context

**Phase 5 is DONE and verified — do not re-do it.** The active frontier is Phases 6 & 7, freshly added to the roadmap (commit 7f5551d) with empty dirs (`.planning/phases/06-installer/`, `07-macos-parity/`). The single source of truth for ALL pending work is `.planning/MACOS-PARITY-AND-FOLLOWUPS.md` — read it before planning Phase 7. The macOS runbook + `verify-macos.sh` already exist and are the Phase-7 driver. Everything is committed; working tree clean; suite 17/17. The user wanted the roadmap right FIRST, then "después hablamos de descargar en macOS y probar lo pendiente" — so Phase 6 planning is the natural next move, Phase 7 waits for a Mac.

## Assumptions Made

- The user will run Phase 7 on their own Mac (this session's env is Linux).
- Phase 6 (installer) should be Linux-first like every prior phase, then verified on macOS in Phase 7.

## Potential Gotchas

- `phase.add` produces verbose names + long dir slugs — always clean up (rename dirs, set concise ROADMAP headers).
- GSD `state.record-session`/`state.update` silently no-op on this repo's free-form STATE.md — edit directly.
- The build uses a **dev source-launcher** here (luastatic absent locally); `dist/wez` runs identical Lua but is not the shipping artifact.
- `bash tools/verify-macos.sh` is non-destructive (scratch dirs) and runs on Linux too — use it as a smoke test before the Mac.

### Environment State

### Tools/Services Used

- GSD workflow system (gsd-tools.cjs at `/home/user-zero/.claude/gsd-core/bin/gsd-tools.cjs`; path cached in `/tmp/gsd_tools_path.txt`)
- `lua5.4`, `wezterm` on PATH; `luastatic` ABSENT (dev launcher fallback); `shellcheck`, `zsh`, `bash` available
- CodeGraph MCP + Engram MCP configured (Engram was unavailable in subagents this session)

### Active Processes

- None. No servers/watchers running.

### Environment Variables

- `WEZTERM_SETUP_DIR` — overrides the managed config dir (used by tests/verify with scratch dirs)
- `WEZ_SEED_SRC_DIR` — points the seeder at the repo's `scenes/` (setup.sh sets it)
- `LUA_BIN` — set to `lua` on Homebrew macOS where `lua5.4` isn't the binary name

## Related Resources

- `.planning/ROADMAP.md` — Phases 0–7, coverage 32/32
- `.planning/MACOS-PARITY-AND-FOLLOWUPS.md` — pending-work tracker (§A functional, §B clarifications, §C macOS by capability)
- `docs/macos-verification.md` — macOS runbook
- `tools/verify-macos.sh` — auto-verifier
- `.planning/REQUIREMENTS.md` — INST-07 added
- `CLAUDE.md` — project rules (commit discipline, hypothesis-before-impl, verify-before-done)

---

**Security Reminder**: Before finalizing, run `validate_handoff.py` to check for accidental secret exposure.
