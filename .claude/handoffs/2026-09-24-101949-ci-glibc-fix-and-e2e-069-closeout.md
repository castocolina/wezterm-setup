# Handoff: Phase 06.9 (E2E Tier 3/4) — Plan 05 Task 3 blocked on a real host-level WezTerm render bug; CI glibc-floor bug found + fixed via podman viability testing

## Session Metadata
- Created: 2026-09-24 10:19:49
- Project: /var/home/bazzite/git/personal/wezterm-setup
- Branch: main
- Session duration: multi-day, spanning several context windows (session IDs changed at least 3 times across this arc — treat this handoff as the authoritative continuity anchor, not the raw transcript)

### Recent Commits (for context)
  - a42bab2 chore(gitignore): ignore gsd-tools runtime lock/cache files
  - fdb3905 docs(state): record 260923-jdt quick task in STATE.md
  - c7b79a8 fix(ci): pin release Linux build leg to ubuntu-22.04 (glibc floor)
  - e0351cb docs(06.9): record 06.9-05 SUMMARY commit hash
  - 343260a docs(06.9): author e2e-visual-review skill, score 93.3% via skill-judge
  - 6a7b4b0 docs(06.9): record 06.9-04 FIX-SUMMARY commit hash
  - dcbbf26 test(06.9): crop Tier 4 captures and skip when mux mutations do not repaint
  - fc57e13 docs(06.9): mark Plan 05 cross_ai per ONESHOT-RULES Rule 2
  - (0e39ecb and everything below it in `git log` was NOT done by this session — it was Phase 7 macOS Parity work already on `origin/main` that this session fast-forward-merged in after discovering its local checkout was 15 commits behind. Do not attribute that work to this handoff's author.)

## Handoff Chain

- **Continues from**: [2026-06-14-124916-phase5-done-phases6-7-queued.md](./2026-06-14-124916-phase5-done-phases6-7-queued.md)
  - Previous title: Phase 5 shipped + verified; Phases 6 (installer) & 7 (macOS parity) queued
  - Note: a LOT happened between that handoff and this one that this handoff does not cover in detail — Phase 6 (installer), Phase 6.8 (Linux CI gate), and all of Phase 7 (macOS Parity, now shipped, v1.0.0 tagged) landed on `origin/main` via other sessions/the user directly. This handoff picks up specifically at Phase 06.9 (E2E Tier 3 Firing + Tier 4 Visuals) and the cross-cutting CI/installer viability work that followed it.
- **Supersedes**: None

> Review the previous handoff for full Phase 5-era context if needed, but it is now quite stale relative to current `main`.

## Current State Summary

Two independent threads of work happened in this session, both centered on **local-machine-limitation discovery via careful, skeptical testing** rather than trusting green checkmarks:

**Thread 1 — Phase 06.9 (E2E Tier 3 Firing + Tier 4 Visuals) closeout, still incomplete.** Plans 01-04 are done, committed, and independently re-verified (never trusting a subagent's self-report). Plan 04 shipped with two real, confirmed bugs that were found and fixed in this session: (a) `spectacle -a` capturing the wrong window (fixed via fullscreen-capture + geometry crop), and (b) a much deeper bug — `wezterm cli split-pane` mutates the mux correctly but the GUI window **never visually repaints** the split, on this exact host. Bug (b) was root-caused as NOT being caused by Ubuntu-vs-Fedora packaging (proved via a native Fedora RPM build of `wezterm-gui`, extracted user-space, same result), NOT XWayland-specific (proved via `enable_wayland=true` native Wayland mode, same result), and NOT a transient nightly regression (still reproduces on a nightly built 2 weeks later). Plan 04's driver now honestly self-skips with a clear escalation-clause reason instead of shipping false "24 passed" results — this fix is landed and verified. Plan 05 Tasks 1-2 (author + skill-judge-validate the `e2e-visual-review` skill) are done, scoring 93.3% after the orchestrator took over from a cross-AI loop that plateaued at 83-87.5% across ~8 rounds and two exhausted time budgets. **Plan 05 Task 3 (the human-verify checkpoint that runs the finished skill against real screenshots) is still blocked** — it needs real captures, and `make e2e-visual` cannot produce any on this host because of bug (b) above. Phase 06.9 has never had a code review, verify-work pass, or `VERIFICATION.md` written — `gsd-tools` reports `verification_status: missing`, `phase_complete: false`.

**Thread 2 — cross-distro/cross-platform install & CI-asset viability audit via podman, spawned from the user's direct question about the render bug.** The user asked "is this a Bazzite/Konsole limitation, and if so what's the point of the e2e tests" — which led to a real, valuable tangent: using podman containers to test whether this project's install/update/remove flow (`tools/setup.sh`, `tools/bootstrap-wezterm.sh`, `tools/uninstall.sh`) actually works across target Linux families. Found and root-caused a REAL bug (Debian 12 stable is broken by the WezTerm-emulator bootstrap's blind "Ubuntu tarball for any non-Ubuntu distro" fallback — GLIBC mismatch). That led to an even more important discovery: **this project's OWN `wez` CLI binary**, published by `.github/workflows/release.yml`'s CI pipeline, had the exact same class of bug — built on `ubuntu-latest` (now Ubuntu 24.04, glibc 2.39) with no floor control, so the real published `v1.0.0` asset silently required GLIBC_2.38+ and failed on Debian 12 AND Ubuntu 22.04 LTS (a currently-supported mainline target). This was invisible to CI because CI only ever tests the binary on the exact machine that built it. **This CI bug has been found, fixed, verified, committed, and pushed to `origin/main`** (see Work Completed below) — this thread is essentially closed, modulo the "should we also fix the WezTerm-bootstrap's Debian-detection gap" question, which was raised but not actioned (see Deferred Items).

## Codebase Understanding

### Architecture Overview

This project ships two genuinely separate binaries/pipelines that are easy to conflate — a mistake this session made once and had to correct:

1. **The `wez` CLI** (this project's own Lua-based companion tool) — built via `luastatic` (bundles Lua 5.4 + the CLI's Lua sources into one static-ish binary; still dynamically links glibc at build time). Built and published by `.github/workflows/release.yml`'s 3-leg matrix (`ubuntu-22.04` after this session's fix / `macos-15-intel` / `macos-14`). `tools/build.sh` drives the build locally or in CI; `tools/ci-setup-toolchain.sh` provisions the Lua/luastatic toolchain on CI runners.
2. **WezTerm itself** (the upstream `wez/wezterm` terminal emulator, a completely separate open-source project) — installed onto the end user's machine by `tools/bootstrap-wezterm.sh`, which downloads a prebuilt release asset from `github.com/wez/wezterm/releases`. This script's `platform_ubuntu_base()` (in `tools/lib/platform.sh`) picks which asset variant to fetch, and currently falls back to a blind "Ubuntu 24.04 tarball" guess for ANY non-Ubuntu-detected host (Fedora, Bazzite, Debian, Arch, etc.) — this is the source of the Debian-12 WezTerm-bootstrap bug (separate from, but architecturally similar to, the `wez`-CLI CI bug this session actually fixed).

E2E test harness architecture (relevant to Thread 1): `tests/e2e/lib/gui.lua` spins a real, isolated, forced-XWayland WezTerm GUI window (`wezterm start --always-new-process --class <tag>`) loading the real product config, for Tier 3 (firing/input-injection) and Tier 4 (visual capture) tests. `tests/e2e/lib/mux.lua` drives `wezterm cli` calls against that session's embedded local mux. Both tiers have now hit genuine, confirmed host-level limitations (see "Potential Gotchas" below) and both correctly self-skip with an honest reason rather than reporting a false pass — this is a deliberate, hard-won design pattern in this codebase (the "ESCALATION CLAUSE"), not a bug to "fix" by weakening the gate.

### Critical Files

| File | Purpose | Relevance |
|------|---------|-----------|
| `tests/e2e/lib/gui.lua` | Spins real, isolated WezTerm GUI test windows | Home of `M.probe`'s input-injection canary (Plan 01/03's escalation clause) |
| `tests/e2e/tier4/visual_diff_e2e_test.lua` | Tier 4 visual capture/diff/approve driver | Home of `probe_render_sync()`, the NEW canary this session added for the render-repaint bug; also the crop-based `capture_active_window()` fix |
| `.claude/skills/e2e-visual-review/SKILL.md` + `.claude/skills/e2e-visual-review/references/dispatch.md` | Agent-performed A.4 visual-judgment skill (Plan 05 Tasks 1-2) | Authored + validated this session (93.3% skill-judge score); NOT yet exercised for real (that's Task 3) |
| `.github/workflows/release.yml` | 3-leg release CI (linux/macos-x86/macos-arm) | Linux leg's `runs-on` fixed this session: `ubuntu-latest` → `ubuntu-22.04` |
| `tools/ci-setup-toolchain.sh` | Per-runner Lua/luastatic toolchain provisioning for CI | Comments updated to match the `ubuntu-22.04` pin |
| `tools/bootstrap-wezterm.sh` + `tools/lib/platform.sh` | Sudo-free WezTerm-emulator installer | `platform_ubuntu_base()`'s blind-Ubuntu-fallback bug (Debian 12) found but NOT fixed — deferred |
| `.planning/phases/06.9-e2e-tier-3-firing-tier-4-visuals-local-permission-bound-clos/06.9-05-PLAN.md` | Plan 05's full spec | Task 3's exact checkpoint contract — read this before attempting Task 3 |
| `.planning/quick/260923-jdt-fix-release-ci-glibc-floor-pin-linux-bui/` | This session's CI-fix quick task | `PLAN.md` (untracked, by convention) + `SUMMARY.md` (committed) with full podman evidence |

### Key Patterns Discovered

- **Never trust a green CI checkmark for cross-platform binary portability.** `ubuntu-latest` silently drifts forward whenever GitHub bumps the default image — a CI job that only tests its own output on its own runner will never catch a glibc-floor regression. Any future "build a portable Linux binary in CI" work in this repo should pin an explicit, deliberately-old-enough runner label, not `-latest`.
- **podman (rootless, no FUSE, no sudo needed) is a genuinely good tool for this project's exact constraints** (sudo-free install philosophy) — used throughout this session to cross-test real published binaries against `debian:12`, `debian:11`, `ubuntu:22.04`, `ubuntu:20.04`, `fedora:42`, `archlinux:latest` containers without needing real hardware or VMs. `rpm2cpio`+`cpio` extracts an `.rpm`'s contents user-space with no root, exactly parallel to how this project already extracts `.deb`/`.tar.xz` for the WezTerm bootstrap.
- **A container shares the HOST compositor if given display access — it cannot isolate a "different compositor" variable.** This was an important realization mid-session: podman was the right tool for install/update/remove/binary-portability testing, but useless for isolating whether the render-sync bug (Thread 1) is specific to this host's KWin/Wayland session, since any container would still be drawing through the same host compositor.
- **The `opencode run --auto --model <id>` cross-AI dispatch pattern**, invoked as `timeout <N> /home/bazzite/.opencode/bin/opencode run --auto --model xai/grok-4.6 < <promptfile> > <out.log> 2> <err.log>` in the background — this exact command shape is now allow-listed in `.claude/settings.local.json` (added this session) so it no longer needs per-call approval. Use input-redirection (`<`), not `cat file | opencode`, to match the allow-listed pattern.
- **A cross-AI delegation loop can plateau and never converge** (Plan 05's skill-judge scoring got stuck 83-87.5% across ~8 rounds over two exhausted multi-thousand-second budgets). When this happens, the documented fallback (ONESHOT-RULES.md Rule 2's fallback clause) is for the orchestrator to take over directly — dispatching a genuinely clean-context sub-agent for evaluation (not self-scoring) still satisfies the "independent verification" requirement even without the cross-AI CLI.

## Work Completed

### Tasks Finished

- [x] Phase 06.9 Plan 04: fixed the wrong-window screenshot bug (crop-based capture) — commit `dcbbf26`
- [x] Phase 06.9 Plan 04: added `probe_render_sync()` escalation-clause canary for the mux-repaint bug, so Tier 4 visuals now honestly self-skip on this host instead of shipping false passes — commit `dcbbf26`
- [x] Phase 06.9 Plan 05 Tasks 1-2: authored `.claude/skills/e2e-visual-review/SKILL.md`, scored 93.3% (112/120) via skill-judge — commits `343260a`, `e0351cb`
- [x] Root-caused the render-sync bug across 3 independent axes (packaging, Wayland-vs-XWayland, nightly staleness) — all ruled out; genuine host/product-level limitation, not yet further diagnosable without a different compositor or an upstream bug report
- [x] Podman-based install/update/remove viability audit across Fedora, Debian 11/12/13, Ubuntu 20.04/22.04/24.04, Arch — found + root-caused the Debian-12 WezTerm-bootstrap GLIBC bug (NOT yet fixed in code, see Deferred Items)
- [x] Found, root-caused, and FIXED the CI release pipeline's own glibc-floor bug for the `wez` CLI binary: pinned `.github/workflows/release.yml`'s Linux leg from `ubuntu-latest` to `ubuntu-22.04` — commit `c7b79a8` (executed via `/gsd-quick`, worktree-isolated subagent, independently re-verified and merged by the orchestrator)
- [x] Caught and fixed a second real bug the pin would have silently introduced: the nightly-prune step's `matrix.runs-on == 'ubuntu-latest'` literal string match, which would have silently stopped matching and disabled nightly-release pruning — fixed in the same commit `c7b79a8`
- [x] Recorded the quick task in `STATE.md`'s Quick Tasks table — commit `fdb3905`
- [x] Cleaned up stale/generated `.planning/milestone.lock` (dead-session lock) and `.planning/state.json` (derived cache), added both to `.gitignore` — commit `a42bab2`
- [x] Discovered and fast-forward-merged 15 commits this local checkout was missing from `origin/main` (Phase 7 macOS Parity, v1.0.0 tag) — no conflict, clean fast-forward
- [x] All of the above pushed to `origin/main` (currently at `a42bab2`)

### Files Modified

| File | Changes | Rationale |
|------|---------|-----------|
| `tests/e2e/tier4/visual_diff_e2e_test.lua` | Crop-based `capture_active_window()`; new `probe_render_sync()` canary wired into `skip.require_tool` | Fix wrong-window capture + honestly detect the render-repaint bug instead of false-passing |
| `tests/e2e/README.md` | Screenshot/visual-baseline section updated to describe the escalation clause | Keep docs honest about what actually works on this host |
| `.claude/skills/e2e-visual-review/SKILL.md`, `.claude/skills/e2e-visual-review/references/dispatch.md` | New skill, ~230+61 lines | Plan 05 Tasks 1-2 deliverable |
| `.github/workflows/release.yml` | Linux leg `runs-on: ubuntu-latest` → `ubuntu-22.04`; nightly-prune step's leg-guard updated to match | The actual CI fix |
| `tools/ci-setup-toolchain.sh` | Comment updates only, referencing the new pin | Consistency, no logic change |
| `.gitignore` | Added `.planning/milestone.lock`, `.planning/state.json` | Stop tool-generated runtime files from showing as untracked noise |
| `.claude/settings.local.json` | Added scoped Bash allow-rule for the `opencode run --auto --model xai/grok-4.6` dispatch pattern | Stop needing per-call approval for cross-AI dispatch |
| `.planning/STATE.md` | Quick-task row added | Tracking convention |
| Various `.planning/phases/06.9-.../*.md` (PLAN frontmatter, SUMMARY/FIX-SUMMARY files) | `cross_ai: true` additions, FIX-SUMMARY docs | GSD process tracking |

### Decisions Made

| Decision | Options Considered | Rationale |
|----------|-------------------|-----------|
| Treat the render-repaint bug as a genuine escalation-clause finding (self-skip), not something to force a workaround for | Keep chasing a fix (resize nudges, activate-pane nudges, PTY-output nudges — all tried, all failed) vs. accept and document | User explicitly agreed after seeing the evidence: "cerremos esto" (let's close this) once packaging was ruled out. Don't re-open this without new evidence. |
| Old/EOL Linux targets (Debian 11, Ubuntu 20.04) are out of scope for the glibc-floor fix | Chase full compatibility down to CentOS-7-era glibc vs. accept `ubuntu-22.04`'s floor | Explicit user instruction: "olvidemos las versiones viejas de ubuntu y debian" — macOS + Bazzite/Fedora critical, Debian/Ubuntu nice-to-have, older releases explicitly dropped |
| Fix the `wez`-CLI CI pipeline bug now (via `/gsd-quick`), but only DOCUMENT (not fix) the separate WezTerm-bootstrap Debian-12 bug | Fix both now vs. one now, one deferred | The CI bug directly affects a currently-shipped project artifact the user asked about; the bootstrap bug is a different (also real, also worth fixing) issue that hadn't been explicitly requested for immediate action — see Deferred Items |
| Took over Plan 05's skill-judge scoring loop directly instead of retrying cross-AI a third time | Retry cross-AI again with an even bigger budget vs. orchestrator takes over | Two consecutive multi-thousand-second cross-AI budgets plateaued at the same 83-87.5% band without improving — diminishing returns; ONESHOT-RULES.md Rule 2's fallback clause explicitly permits this |

## Pending Work

## Immediate Next Steps

1. **Decide how to unblock Phase 06.9 Plan 05 Task 3.** It's a real, human-in-the-loop checkpoint (pick a vision model, review real screenshots, approve baselines) and currently has NO real screenshots to review on this host, because `make e2e-visual` self-skips (the render-repaint bug). Options to raise with the user: (a) run it for real on a different machine/compositor (e.g. the user's macOS session, once macOS Tier 4 parity is confirmed to actually render correctly there — not yet verified!), (b) investigate further on THIS host (untried: an X11-native, non-Wayland KDE session; a different DE like GNOME on the same machine; checking/filing an upstream `wez/wezterm` GitHub issue), or (c) accept Task 3 stays open indefinitely on this host and document that explicitly in the phase's eventual VERIFICATION.md.
2. **Run Phase 06.9's code review + verify-work + phase closure steps** (per `.planning/ONESHOT-RULES.md`'s Per-Phase Checklist items 5-8) — none of these have run yet for this phase. `gsd-tools query init.progress` currently reports `verification_status: missing`, `phase_complete: false` for phase `06.9`. Routes to `/gsd-execute-phase 06.9` per the last `/gsd-progress` check in this session, but that will hit the Task 3 blocker again — resolve #1 above first, or explicitly route around Task 3 if the decision is "leave it open."
3. **Decide whether to fix the deferred WezTerm-bootstrap Debian-12 bug** (`tools/lib/platform.sh`'s `platform_ubuntu_base()` blind-fallback for non-Ubuntu distros) — root-caused and a validated fix exists (use WezTerm's own native Debian/Fedora release assets instead of guessing an Ubuntu tarball) but was never implemented. Ask the user if this is in scope given they deprioritized "old" Debian/Ubuntu but Debian 12 is CURRENT stable, not old.

### Blockers/Open Questions

- [ ] Plan 05 Task 3 cannot proceed on this host — no real screenshots producible (see Immediate Next Steps #1). This is the primary open blocker for closing Phase 06.9.
- [ ] Whether macOS's `wezterm start` GUI actually renders `wezterm cli split-pane` mutations correctly is UNVERIFIED — this session never tested on real macOS hardware. If the user's macOS session hits the SAME render-repaint bug, Task 3 may be blocked everywhere, not just here, which would be a much bigger finding worth escalating upstream to the `wez/wezterm` project.
- [ ] Whether to fix the WezTerm-bootstrap's Debian-12 GLIBC bug in `tools/lib/platform.sh` (found, root-caused, fix validated, not yet implemented) — awaiting user prioritization call.

### Deferred Items

- WezTerm-bootstrap Debian-12/Debian-11 GLIBC mismatch in `platform_ubuntu_base()`'s fallback — deferred pending user decision (see Blockers above). Fix would mirror the CI fix's spirit: use WezTerm's actual native per-distro release assets (`wezterm-nightly.Debian12.tar.xz` confirmed to exist and work) instead of a blind cross-distro Ubuntu-tarball guess, and/or use the native Fedora RPM assets (also confirmed to exist and work) for Fedora-family hosts instead of the current "works by luck" Ubuntu-tarball fallback.
- Debian 11 / Ubuntu 20.04 compatibility for BOTH the `wez` CLI and WezTerm-bootstrap — explicitly out of scope per user instruction, do not re-open without the user asking again.
- Whether GitHub's `ubuntu-22.04` runner label itself has its own future deprecation timeline (like `ubuntu-20.04` did in Dec 2025) was not checked beyond confirming current validity — worth a periodic re-check, not urgent.

## Context for Resuming Agent

## Important Context

- **This project's git history moves fast and this local checkout has fallen behind `origin/main` before (by 15 commits, silently, mid-session).** ALWAYS `git fetch origin && git log --oneline HEAD..origin/main | wc -l` at the start of a new session before trusting any local file's content, especially `.planning/STATE.md`, `.planning/ROADMAP.md`, and `.github/workflows/*.yml`. A stale local checkout caused real confusion mid-session here (re-answering a question about `release.yml` incorrectly before realizing the checkout was behind).
- **Two SEPARATE binaries, two separate bug classes, do not conflate them**: the `wez` CLI (this project's own binary, CI-published, THE thing this session actually fixed) vs. the upstream WezTerm terminal emulator (a third-party binary this project's `tools/bootstrap-wezterm.sh` merely downloads, where a similar-but-DIFFERENT bug was found and NOT yet fixed). Early in this session these got conflated once and had to be corrected explicitly for the user.
- **The render-repaint bug (Thread 1) is real, reproducible, and NOT this session's invention** — it was cross-checked three separate ways (Fedora-native binary, native-Wayland mode, 2-weeks-later nightly) and every check reproduced it identically. Do not assume a future session's different WezTerm nightly, different packaging, or "just try again" will fix it without new evidence — the burden of proof has already been met that packaging/channel are NOT the cause.
- **`gsd-tools` reports phase `06.9` as `status: "executed"`, `implementation_complete: true`, but `verification_status: "missing"` and `phase_complete: false`.** It is NOT done. Running `/gsd-progress` will route to `/gsd-execute-phase 06.9` (Route V.missing) — this is correct, but will hit the Task 3 blocker.

### Assumptions Made

- Assumed `ubuntu-22.04` will remain a valid GH-hosted runner label for the foreseeable future (confirmed valid as of this session via `actions/runner-images`'s own README — re-check if a future session hits a runner-not-found error).
- Assumed the user's stated priority order (macOS + Bazzite/Fedora critical, Debian/Ubuntu nice-to-have, older releases out of scope) still holds for any FUTURE viability work, not just the CI fix already made.
- Assumed podman's rootless/no-FUSE/no-sudo setup on this exact host is representative enough of "a user's sudo-free install experience" to be a valid test proxy — it is NOT a substitute for real hardware testing on macOS, which remains unverified.

### Potential Gotchas

- **Do not re-run the render-repaint bug investigation from scratch.** It's been thoroughly disproven-as-packaging-issue three times. If picking this up again, start from "what's different about macOS" or "what's different about a non-KWin/non-Wayland session" — not "try yet another wezterm build."
- **`gh release download` and other `gh` commands must be run from inside the git repo directory** — they fail with a confusing `fatal: not a git repository` if run from `/tmp` or a scratch dir, even with an explicit `-D <output-dir>` flag. This tripped the session up once.
- **Bash's command hash cache can make `command -v <binary>` report a stale/deleted path within the same shell session** — this caused a false "still present after uninstall" result during the podman lifecycle testing. Use a fresh subshell (`bash -c 'command -v X'`) when verifying something was actually removed.
- **The `.planning/quick/*/PLAN.md` files are NEVER committed in this repo's established convention** — only `SUMMARY.md` gets tracked. Don't "fix" this by committing a PLAN.md or by gitignoring the whole `quick/` directory; it's a deliberate per-file choice already consistent across every prior quick task.
- **When dispatching cross-AI (`opencode run --auto`) for anything in this project, budget generously and expect possible non-convergence** on subjective scoring tasks (skill-judge, code review quality bars) — it plateaued hard on Plan 05. Don't be surprised if it needs orchestrator takeover again.

## Environment State

### Tools/Services Used

- `podman` 5.8.4, rootless, netavark backend — used extensively for cross-distro testing this session; no persistent containers remain (`--rm` used throughout, confirmed clean via `podman ps -a`)
- `gh` CLI — used for release/workflow-run inspection and asset download; must be run from within the repo directory
- `/home/bazzite/.opencode/bin/opencode run --auto --model xai/grok-4.6` — the cross-AI dispatch mechanism, now allow-listed in `.claude/settings.local.json`
- `gsd-tools.cjs` at `/home/bazzite/.claude/gsd-core/bin/gsd-tools.cjs` — the GSD workflow query CLI

### Active Processes

- None expected to be running. All podman containers were `--rm`-scoped and are gone. No lingering `wez-e2e-*` GUI windows or processes — verified clean via `xdotool search --class "wez-e2e"` / `pgrep -af "wez-e2e-fire"` after every test in this session.

### Environment Variables

- `WEZ_REMOTE_BOOTSTRAP=1` — gates the release-asset-download fallback path in `tools/build.sh`; required when testing the real end-user install flow (`tools/install.sh`'s actual behavior) rather than a bare dev-source-tree `tools/setup.sh` run
- `WEZ_BIN` — points E2E test invocations at a specific `wez` binary (commonly `./dist/wez`)

## Related Resources

- `.planning/ONESHOT-RULES.md` — the autonomous-run playbook governing Phase 06.9's original execution (Rule 1: never trust self-reports; Rule 2: cross-AI delegation + fallback; Rule 7/8: circuit breaker vs. convergence loop)
- `.planning/phases/06.9-e2e-tier-3-firing-tier-4-visuals-local-permission-bound-clos/06.9-05-PLAN.md` — Task 3's exact contract, read before attempting it
- `.planning/quick/260923-jdt-fix-release-ci-glibc-floor-pin-linux-bui/SUMMARY.md` — full podman evidence for the CI fix
- `.planning/phases/06.9-e2e-tier-3-firing-tier-4-visuals-local-permission-bound-clos/06.9-04-FIX-SUMMARY.md` — full evidence for the two Plan 04 bugs

---

**Security Reminder**: Before finalizing, run `validate_handoff.py` to check for accidental secret exposure.
