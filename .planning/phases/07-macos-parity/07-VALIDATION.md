---
phase: 7
slug: macos-parity
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-20
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Phase 7 is a macOS parity/verification gate driven on a real Intel Mac — the
> primary "tests" are the existing harness suite plus the non-interactive macOS
> gate and runbook. The planner refines the per-task map below.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test harness (`tools/run-tests.sh`) + non-interactive macOS gate (`tools/verify-macos.sh`) |
| **Config file** | none — harness is self-contained; Wave 0 installs the macOS compile toolchain (`lua@5.4`/luastatic) via a sudo-free setup target |
| **Quick run command** | `bash tools/run-tests.sh` |
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
| TBD | TBD | TBD | INST-01/06/07, FOUND-01, DIAG-05, PANE-01..04, SCEN-03..06 (D-18) | TBD | macOS behavior matches Linux | gate | `bash tools/verify-macos.sh` | ❌ W0 | ⬜ pending |

*Planner fills this map: one row per task, mapping each D-18 requirement flip to its Intel-runnable command. Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Sudo-free macOS compile toolchain setup target (`lua@5.4` keg-wired, luastatic) — autonomy item #1
- [ ] `tools/run-tests.sh` bash-3.2-safe (`mapfile` replaced) so the harness runs on stock macOS
- [ ] `tools/verify-macos.sh` runnable green on this Intel Mac

*If none: "Existing infrastructure covers all phase requirements." — NOT the case here; Wave 0 installs the toolchain.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual identity parity (tab-bar accents, pane bg, emoji cell-width, colors/glyphs) | PANE/TAB/SCEN visual sections | Visual judgment not auto-assertable | Drive runbook visual sections; capture `agent-ui-ux-designer` notes per D-03 |
| arm64 first-launch on Apple Silicon hardware | INST-06/07 (arm64) | No Silicon hardware this session | Deferred to non-gating Phase 7.1; arm64 evidence this phase = CI `codesign --verify` + arm64-runner smoke |

*Planner may add rows. The arm64 hardware launch is explicitly out of scope (Phase 7.1).*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (toolchain + bash-3.2 harness)
- [ ] No watch-mode flags
- [ ] Feedback latency < 180s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
