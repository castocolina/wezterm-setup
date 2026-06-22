---
phase: 07-macos-parity
plan: 04
subsystem: unattended-e2e-supply-consume
tags: [macos, ci, gh-run-watch, e2e, install, codesign, quarantine, d-09, d-10, d-11, release, v1]

# Dependency graph
requires:
  - phase: 07-macos-parity (07-02)
    provides: real sudo-free install_macos() .app placement (consumed by the E2E)
  - phase: 07-macos-parity (07-03)
    provides: 3-leg release matrix + build-time ad-hoc codesign + workflow_dispatch dry-run path + actionlint-clean release.yml
  - phase: 06-installer
    provides: per-asset .sha256 verify-before-chmod gate; nightly channel resolution; install.sh /dev/tty handoff
provides:
  - "D-11 branch-aware build version stamp: tools/build.sh stamps <channel-tag>+<branchname> into cli/spec.lua at build time (release.yml passes WEZ_BUILD_VERSION + WEZ_BUILD_BRANCH)"
  - "Fresh-install support: wez install-state CREATES ~/.config/wezterm/wezterm.lua on a clean machine (config_builder base + single managed block, no backup); wez doctor backup gate passes on a fresh creation"
  - "macos-15-intel CI toolchain fix: luarocks install --local (the /usr/local prefix is not user-writable on the Intel runner)"
  - "Recorded unattended E2E evidence (dispatch dry-run + real install + D-07 quarantine decision + green-gated v1.0.0) in docs/macos-verification.md"
  - "First stable release v1.0.0 (green-gated auto-push, D-10)"
affects: [INST-07, INST-06, INST-01, DIAG-01, v1-close-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Build-time version stamp: in-place sed of cli/spec.lua M.VERSION before the luastatic bundle + explicit mktemp save/restore after (NO RETURN trap — a subshell return fires it early)"
    - "D-09 unattended CI loop: gh workflow run --ref <living-branch> -> gh run watch --exit-status -> gh run view --log-failed -> fix -> re-dispatch (bounded; human stop only on a recurring failure)"
    - "D-10 green-gate: cut+push the first stable v* tag IFF dispatch-dry-run-green AND real-E2E-green; the runbook records both signals (audit-enforced)"
    - "D-07 verify-then-decide: probe com.apple.quarantine empirically; leave install.sh unchanged when curl downloads carry none (the default outcome)"

key-files:
  created:
    - .planning/phases/07-macos-parity/07-04-SUMMARY.md
  modified:
    - tools/build.sh
    - .github/workflows/release.yml
    - tools/ci-setup-toolchain.sh
    - cli/commands/install_state.lua
    - cli/commands/doctor.lua
    - tests/cli/install_state_test.lua
    - tests/cli/doctor_test.lua
    - docs/macos-verification.md

key-decisions:
  - "D-11 version stamp lives in the embedded wez version (cli/spec.lua M.VERSION), NOT the GitHub release tag (the tag stays bare nightly-YYYYMMDD; '+' is not tag-name-safe). '/' in the branch maps to '-' for SemVer build-metadata safety."
  - "D-07: install.sh is left UNCHANGED — the curl-download E2E set NO com.apple.quarantine on either wez or WezTerm.app and Gatekeeper did not block (Pitfall 5 / A4 confirmed live). The default no-code-change outcome."
  - "D-10: v1.0.0 (not v0.1.0 reuse) is the first real stable tag; it sorts above the pre-existing v0.1.0 under sort -V so the green-gate cross-check applies to it."
  - "Fresh-install backup-gate exception: a clean-machine install creates wezterm.lua with no prior content to back up, so doctor's core 'timestamped backup exists' gate passes on a fresh creation (marker-detected) — otherwise every first install would fail doctor."

requirements-completed: [INST-07, INST-06]

# Metrics
duration: 80min
completed: 2026-06-22
tasks: 3
files: 8
---

# Phase 7 Plan 04: Fully Unattended End-to-End Supply→Consume Loop Summary

**Drove the entire push→wait→install→verify loop unattended on this Intel Mac: dispatched the release workflow on the living branch with a D-11 `+<branchname>` version stamp, auto-fixed two red dispatch runs (D-09 loop) to green, ran the real `curl|install.sh` of THIS branch's artifact (integrity gate passed, `wez doctor` exit 0, version match), confirmed D-07 quarantine is absent (install.sh left unchanged), and green-gated the first stable `v1.0.0` auto-push (D-10) with its stable run green — no human checkpoint.**

## Performance

- **Duration:** ~80 min
- **Tasks:** 3 (all autonomous)
- **Files modified:** 8 (1 created)
- **CI runs:** 4 dispatch/stable runs (2 red→auto-fixed, 2 green) consuming real CI minutes; 1 irreversible public stable release (`v1.0.0`).

## Accomplishments

### Task 1 — Dispatch dry-run on the living branch (D-09/D-11)
- Wired the **D-11 branch-aware version stamp**: `tools/build.sh` resolves `<channel-tag>+<branchname>` on a non-main branch and stamps `cli/spec.lua` `M.VERSION` before the luastatic bundle; `release.yml` passes `WEZ_BUILD_VERSION=$TAG` + `WEZ_BUILD_BRANCH=github.ref_name`. The embedded `wez version` then reports `nightly-20260622+gsd-phase-07-macos-parity` while the GitHub release tag stays bare `nightly-20260622`.
- Dispatched on the living branch (`gh workflow run release.yml --ref gsd/phase-07-macos-parity`) and waited non-interactively (`gh run watch --exit-status`).
- **D-09 autonomous auto-fix loop:** attempt 1 (run `27970794764`) went red on all 3 legs; `gh run view --log-failed` surfaced two distinct bugs, both fixed (`d85fa27`); attempt 2 (run `27970971643`) was green. After the Task-2 fixes a third dispatch (run `27971403588`, HEAD `eddef2e`) re-confirmed green — the authoritative dry-run signal.
- Both macOS arches + `.sha256` published to the `nightly-20260622` prerelease; arm64 macos-14 in-build smoke recorded (`codesign --verify` valid + `./dist/wez version` match). actionlint NOT re-run (Plan 03 owns it).

### Task 2 — Real E2E install + D-07 quarantine verify-then-decide
- Ran the real `tools/install.sh` (pinned to this branch, channel nightly, headless) on this Intel Mac from a truly clean state. Full chain green:
  - **Integrity gate (T-07-13):** `checksum verified for wez-macos-x86_64` BEFORE `chmod +x`.
  - **D-11 match:** `wez version` → `wez nightly-20260622+gsd-phase-07-macos-parity` (THIS branch's artifact).
  - **INST-06:** `install_macos` placed `~/Applications/WezTerm.app` sudo-free.
  - **`wez doctor` exit 0** (all 5 core gates pass); **single managed block** (INST-01); Gatekeeper clears (`wezterm --version` exit 0, config loads clean).
- **D-07 decision:** `xattr -p com.apple.quarantine` on both `wez` and `WezTerm.app` → **no quarantine** (curl download). **install.sh left UNCHANGED** (the default outcome), sudo-free; the manual `xattr -d` fallback note is kept.

### Task 3 — Green-gated autonomous v1.0.0 auto-push (D-10)
- Asserted the binding green-gate: BOTH the dispatch dry-run (`27971403588` exit 0) AND the E2E install (doctor exit 0, version match) were green, both recorded in the runbook (audit-enforced, no GATE-VIOLATION).
- Auto-pushed `git tag v1.0.0 && git push origin v1.0.0` — no human checkpoint. The `v*` ref resolved `CHANNEL=stable`; the **stable run `27971643099` was green** (`gh run watch --exit-status` exit 0).
- **v1.0.0 published** (`prerelease=false`) with all 6 assets; `/releases/latest` now resolves to `v1.0.0`.

## Task Commits

1. **Task 1 D-11 wiring** — `9a1f59b` (feat)
2. **D-09 auto-fix (red→green)** — `d85fa27` (fix: spec.lua restore + Intel luarocks --local)
3. **Task 1 evidence** — `840e48b` (docs)
4. **Task 2 fresh-install fixes** — `eddef2e` (fix: install-state create + doctor backup gate, +12 tests)
5. **Task 2 E2E evidence + D-07** — `f7efdd8` (docs)
6. **Task 3 green-gate decision** — `77d18cf` (docs)
7. **Task 3 stable-run finalization** — `126286b` (docs)
- **Tag:** `v1.0.0` pushed to origin (stable run `27971643099` green).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] D-11 spec.lua restore consumed early by the luastatic subshell**
- **Found during:** Task 1, dispatch attempt 1 (run `27970794764`, ubuntu + macos-14 legs).
- **Issue:** the version stamp's `RETURN` trap fired on the luastatic `( )` subshell's return, consuming the backup early; the function's own restore then failed `mv: cannot stat '…/cli/spec.lua.bak.<pid>'`.
- **Fix:** replaced the RETURN-trap restore with an explicit `mktemp` save + restore immediately after the bundle.
- **Files:** tools/build.sh — **Commit:** `d85fa27`

**2. [Rule 3 - Blocking] macos-15-intel luarocks /usr/local permission denied**
- **Found during:** Task 1, dispatch attempt 1 (Intel toolchain install).
- **Issue:** `luarocks install luastatic` could not write the `/usr/local` Homebrew/luarocks tree on the Intel runner (`install requires exclusive write access to /usr/local … Permission denied`, exit 4).
- **Fix:** `luarocks install --local luastatic` (~/.luarocks) + `$GITHUB_PATH`, mirroring install_linux and uniform across both arches.
- **Files:** tools/ci-setup-toolchain.sh — **Commit:** `d85fa27`

**3. [Rule 2 - Missing critical functionality] Fresh install failed on a clean machine**
- **Found during:** Task 2, the real E2E install (no prior `~/.config/wezterm/wezterm.lua`).
- **Issue:** `wez install-state` aborted `cannot read … No such file or directory` (exit 1) — the managed-block injection assumed a pre-existing `wezterm.lua`. `wez doctor` then failed its core "timestamped backup exists" gate (a fresh creation takes no backup). The clean-machine first run is the PRIMARY INST-06/INST-07 path.
- **Fix:** install-state treats ENOENT as the absent state — seeds a minimal `config_builder()` base, injects exactly one managed block (Shape A), and `atomic_write`s to CREATE the file (no backup); a genuine read error on an existing file still aborts. doctor's backup gate passes on a fresh creation (marker-detected). +8 install_state and +4 doctor tests (70/70, 29/29 green).
- **Files:** cli/commands/install_state.lua, cli/commands/doctor.lua, tests/cli/install_state_test.lua, tests/cli/doctor_test.lua — **Commit:** `eddef2e`
- **Re-verified:** rebuilt into the nightly asset via the green re-dispatch `27971403588` and re-run end-to-end (doctor exit 0).

**Total deviations:** 3 auto-fixed (1 Rule 1, 1 Rule 3, 1 Rule 2), all surfaced by the live unattended loop and required for a working clean-machine install. No scope creep; D-07 (no quarantine strip) and the sudo-free invariant preserved.

## D-07 Quarantine Decision (verify-then-decide)
- Probe result: **no `com.apple.quarantine`** on either `~/.local/bin/wez` or `~/Applications/WezTerm.app` (curl/wget downloads carry none — RESEARCH Pitfall 5 / A4).
- **install.sh left unchanged** (no `xattr -dr` strip), sudo-free. The runbook keeps the manual `xattr -d` / right-click-open fallback note for browser-download cases.

## Threat surface
No new threat surface beyond the plan's `<threat_model>`. Mitigations confirmed live: T-07-13 (SHA-256 verified-before-chmod, observed), T-07-14 (no unnecessary quarantine strip — D-07 default), T-07-15 (arm64 ad-hoc codesign clears the smoke), T-07-16 (install.sh main() last line unchanged), T-07-17 (first v* tag green-gated, no premature release on a red signal).

## Self-Check: PASSED

- Files created: `07-04-SUMMARY.md` present.
- Commits present in history: `9a1f59b`, `d85fa27`, `840e48b`, `eddef2e`, `f7efdd8`, `77d18cf`, `126286b` (verified below).
- Tag `v1.0.0` present on origin (`refs/tags/v1.0.0`); stable run `27971643099` green.
- Runbook records BOTH green signals (no GATE-VIOLATION).

---
*Phase: 07-macos-parity*
*Completed: 2026-06-22*
