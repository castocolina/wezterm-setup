---
phase: 7
slug: macos-parity
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-20
updated: 2026-06-20
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Phase 7 is a macOS parity/verification gate driven on a real Intel Mac — the
> primary "tests" are the existing harness suite plus the non-interactive macOS
> gate and runbook, with focused Wave-0/1 unit tests for the new pure logic.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test harness (`tools/run-tests.sh`, now bash-3.2-safe) + Lua `*_test.lua` under `lua5.4` + non-interactive macOS gate (`tools/verify-macos.sh`) |
| **Config file** | none — harness is self-contained; Wave 0 (Plan 01) installs the macOS compile toolchain (`lua@5.4`/luastatic) via the sudo-free `tools/setup-dev.sh` / `make setup` target |
| **Quick run command** | `bash tools/run-tests.sh` (after `make setup` exposes `lua5.4`) |
| **Full suite command** | `bash tools/verify-macos.sh` (auto gate) then drive `docs/macos-verification.md` |
| **Estimated runtime** | ~60–180 seconds (harness); gate adds build + completion + scene-launch checks |

---

## Sampling Rate

- **After every task commit:** Run `bash tools/run-tests.sh`
- **After every plan wave:** Run `bash tools/verify-macos.sh`
- **Before `/gsd-verify-work`:** Auto gate green + runbook deviations table filled + `agent-ui-ux-designer` notes captured (D-03 evidence bar — all Intel-runnable)
- **Max feedback latency:** ~180 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| P01-T1 | 07-01 | 0 | DIAG-05/SCEN-03..06 | T-07-02 | harness runs on stock bash 3.2; no unguarded sha256sum | smoke | `/bin/bash tools/run-tests.sh` | ✅ (run-tests.sh) | ⬜ pending |
| P01-T2 | 07-01 | 0 | DIAG-05/SCEN-03..06 | T-07-02/03/SC | sudo-free toolchain; no bare `lua` (5.5); lua5.4 on PATH | unit + end-state | `lua5.4 tests/cli/setup_dev_test.lua` ; `make setup && make build` | ❌ W0 creates setup_dev_test.lua | ⬜ pending |
| P02-T1 | 07-02 | 1 | INST-06 | T-07-06 | official-host HTTPS asset URL only | unit (RED) | `lua5.4 tests/cli/bootstrap_macos_test.lua` | ❌ W1 creates bootstrap_macos_test.lua | ⬜ pending |
| P02-T2 | 07-02 | 1 | INST-06 | T-07-04/05/07/08 | integrity-gate-before-extract; ~/Applications; no sudo/quarantine-strip | unit (GREEN) + smoke | `lua5.4 tests/cli/bootstrap_macos_test.lua` ; `bash tools/run-tests.sh` | ✅ (after P02-T1) | ⬜ pending |
| P03-T1 | 07-03 | 1 | INST-07 | T-07-09/10/SC | lua@5.4 keg PATH; ad-hoc codesign both arches; no spctl gate | smoke (bash -n + suite) | `bash -n tools/ci-setup-toolchain.sh && bash -n tools/build.sh && bash tools/run-tests.sh` | ✅ (scripts exist) | ⬜ pending |
| P03-T2 | 07-03 | 1 | INST-07 | T-07-11/12 | 3-leg matrix; no macos-13; arm64 smoke; dispatch dry-run | unit (TEXT) + actionlint | `actionlint .github/workflows/release.yml ; lua5.4 tests/cli/ci_macos_toolchain_test.lua` | ❌ W1 creates ci_macos_toolchain_test.lua | ⬜ pending |
| P04-T1 | 07-04 | 2 | INST-07 | T-07-13/15 | unattended CI wait; both signed macOS assets + .sha256 | live CI | `gh run watch <id> --exit-status` | ✅ (release.yml after W1) | ⬜ pending |
| P04-T2 | 07-04 | 2 | INST-07/INST-06 | T-07-13/14/16 | checksum-verified-before-chmod; D-07 verify-then-decide; doctor exit 0 | live E2E | `wez doctor` (exit 0) ; quarantine probe | ✅ (install path after W1) | ⬜ pending |
| P04-T3 | 07-04 | 2 | INST-07 | T-07-17 | first v* tag gated behind human checkpoint | human-check | maintainer confirm (pushed+green / deferred) | n/a (checkpoint) | ⬜ pending |
| P05-T1 | 07-05 | 3 | INST-01/FOUND-01/DIAG-05/PANE-01..04/SCEN-03..06 | T-07-18/19 | auto gate FAIL=0; runbook driven; ui-ux notes | gate + runbook | `bash tools/verify-macos.sh` (FAIL=0, exit 0) | ✅ (verify-macos.sh) | ⬜ pending |
| P05-T2 | 07-05 | 3 | (all D-18 IDs) | T-07-19 | each Done flip cites a runbook section; tables agree per ID | doc-consistency | `for id in INST-01 INST-06 INST-07 FOUND-01 DIAG-05 PANE-01..04 SCEN-03..06; do grep -F "$id" REQUIREMENTS.md ROADMAP.md \| grep -c 'deferred D-18'; done` (per-ID gate, each =0) | ✅ (REQUIREMENTS/ROADMAP) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky. Sampling continuity: no 3 consecutive tasks lack an automated/live verify — every task above carries an automated command, a Wave-0 dependency that creates its test, or (P04-T3 only) a human-check checkpoint immediately preceded + followed by automated tasks.*

---

## Wave 0 Requirements

- [ ] Sudo-free macOS compile toolchain setup target (`tools/setup-dev.sh` / `make setup` — `lua@5.4` keg-wired, luastatic) — autonomy item #1 (Plan 01 Task 2)
- [ ] `tools/run-tests.sh` bash-3.2-safe (`mapfile` replaced) so the harness runs on stock macOS (Plan 01 Task 1)
- [ ] `tests/cli/setup_dev_test.lua` created (Plan 01 Task 2) — the automated gate for the setup target
- [ ] `tools/verify-macos.sh` runnable green on this Intel Mac (depends on the toolchain above; exercised in Plan 05)

> Wave-1 test scaffolds (created within their RED tasks, not Wave 0, because they unit-test
> NEW pure logic shipped in the same plan): `tests/cli/bootstrap_macos_test.lua` (Plan 02 Task 1),
> `tests/cli/ci_macos_toolchain_test.lua` (Plan 03 Task 2).

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual identity parity (tab-bar accents, pane bg, emoji cell-width, colors/glyphs) | PANE/TAB/SCEN visual sections | Visual judgment not auto-assertable | Drive runbook visual sections (§5/§6); capture `agent-ui-ux-designer` notes per D-03 (Plan 05 Task 1) |
| CWD inheritance (OSC 7) on macOS shells | FOUND-01 | Needs a live WezTerm session | Runbook §3 — split pane / new tab inherits the active pane cwd; recorded repro (Plan 05 Task 1) |
| Gatekeeper first-launch + quarantine on this Intel Mac | INST-06/07 | Needs the live macOS install | Plan 04 Task 2 — E2E install + `xattr -p com.apple.quarantine` probe (D-07) |
| First public `v*` tag push | INST-07 | Real irreversible-ish public release | Plan 04 Task 3 — blocking-human checkpoint (Open Q1) |
| arm64 first-launch on Apple Silicon hardware | INST-06/07 (arm64) | No Silicon hardware this session | OUT OF SCOPE — deferred to non-gating Phase 7.1; arm64 evidence this phase = CI `codesign --verify` + the macos-14-runner in-build smoke (Plan 03/04) |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (P04-T3 is the lone human-check checkpoint, flanked by automated tasks)
- [x] Sampling continuity: no 3 consecutive tasks without automated/live verify
- [x] Wave 0 covers all MISSING references (toolchain + bash-3.2 harness + setup_dev_test.lua)
- [x] No watch-mode flags
- [x] Feedback latency < 180s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** planned (2026-06-20)
