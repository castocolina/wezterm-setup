---
phase: 07-macos-parity
plan: 02
subsystem: infra
tags: [macos, bootstrap, wezterm, zip, ditto, install, security]

# Dependency graph
requires:
  - phase: 07-macos-parity (07-01)
    provides: macOS toolchain provisioning available for the Mac pass
  - phase: 06-installer
    provides: nightly-default + resolve_want_datestamp + select_release version contract; shared fetch_to fetcher; verify_tarxz/assert_safe_members integrity-gate pattern
provides:
  - "wezterm_macos_asset_url(tag): official-host HTTPS macOS .zip URL helper (mirror of wezterm_release_asset_url)"
  - "Real, sudo-free install_macos(): fetch -> pre-extract integrity gate -> ditto extract -> place WezTerm.app under ~/Applications, with run-the-binary evidence"
  - "tests/cli/bootstrap_macos_test.lua: pure url/path + source-no-run security gate for the macOS bootstrap branch"
affects: [07-macos-parity (verify-macos / runbook flips), 07-04 (quarantine verify-then-decide), INST-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pre-extract integrity gate for .zip: size floor + PK magic 504b0304 + member-safety BEFORE ditto (never extract-then-check)"
    - "unzip -Z1 (names-only) for member-safety listing so the unzip -l header cannot false-positive the absolute-member check"
    - "macOS install mirrors install_linux structure (mktemp+RETURN-trap, shared fetch_to, rm -rf+place, run-the-binary evidence) with OS/asset specifics swapped"

key-files:
  created:
    - tests/cli/bootstrap_macos_test.lua
  modified:
    - tools/lib/wezterm-release.sh
    - tools/bootstrap-wezterm.sh

key-decisions:
  - "macOS asset name is uniformly WezTerm-macos-<tag>.zip for both nightly and dated tags (API-confirmed 2026-06-22 — closes Open Q2/A3)"
  - "The nightly .zip wraps WezTerm.app in a top-level dated dir; locate the bundle via find -maxdepth 3, not at the scratch root"
  - "Member-safety uses unzip -Z1 to avoid the unzip -l 'Archive: <abspath>' header false-positive"

patterns-established:
  - "Pre-extract .zip integrity + member-safety gate (PK magic + size + traversal reject) before ditto"
  - "Reuse the shared fetch_to fetcher for the macOS download — never add a third downloader"

requirements-completed: [INST-06]

# Metrics
duration: 35min
completed: 2026-06-22
---

# Phase 7 Plan 02: Real macOS install_macos() .app Placement Summary

**Sudo-free install_macos() that fetches the official WezTerm nightly macOS .zip, integrity-gates it (PK magic + size + member-safety) before a ditto extract, and places WezTerm.app under ~/Applications — plus a new wezterm_macos_asset_url helper, all live-verified on the Intel Mac.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-06-22 (TDD RED first)
- **Completed:** 2026-06-22
- **Tasks:** 2 (both TDD)
- **Files modified:** 3 (2 modified, 1 created)

## Accomplishments
- `wezterm_macos_asset_url(tag)` added to `tools/lib/wezterm-release.sh` — official-host HTTPS only, missing-arg `:?` guard, emits `WezTerm-macos-<tag>.zip` (API-confirmed name + date in a code comment, closing Open Q2/A3).
- Real `install_macos()` replaces the design-only stub: shared `fetch_to` download, pre-extract integrity gate (empty/size floor + PK magic `504b0304` + `unzip -Z1` member-safety), `ditto -x -k` extract (unzip fallback), `rm -rf` + `cp -R` placement under `${HOME}/Applications`, run-the-binary `--version` evidence. No sudo/hdiutil/DMG; no `com.apple.quarantine` strip (D-07).
- New `tests/cli/bootstrap_macos_test.lua` (26 assertions, all green) covering the pure url/path helper behavior + source-no-run TEXT/security gates (integrity-precedes-extract, no `/Applications`, no sudo/hdiutil, no xattr).
- **Live-verified on this Intel Mac:** fetched the nightly `.zip`, placed `~/Applications/WezTerm.app`, and the inner binary ran (`wezterm 20260622-120102-6ff54928`).

## Task Commits

Each task was committed atomically (TDD):

1. **Task 1: wezterm_macos_asset_url + RED macOS unit gate** - `bc882bd` (test)
2. **Task 2: real install_macos() .app placement + pre-extract gate** - `a68eb58` (feat — GREEN, includes the two live-found auto-fixes)

_Task 1 RED = helper url/path assertions PASS, install_macos assertions FAIL (stub). Task 2 GREEN = all 26 pass._

## Files Created/Modified
- `tools/lib/wezterm-release.sh` - Added `wezterm_macos_asset_url(tag)` helper (official-host HTTPS macOS `.zip` URL, API-confirmed name).
- `tools/bootstrap-wezterm.sh` - Replaced the design-only `install_macos()` stub with real, sudo-free `.app` placement + pre-extract integrity/member-safety gate; updated the file-header step-4 comment.
- `tests/cli/bootstrap_macos_test.lua` - New auto-discovered unit test for the macOS bootstrap branch (pure url/path + source-no-run security TEXT gates).
- `.planning/phases/07-macos-parity/deferred-items.md` - Logged out-of-scope pre-existing Lua 5.5 suite failures + the `lua5.4`-pinned harness (D-08, separate plan).

## Decisions Made
- macOS asset name is uniformly `WezTerm-macos-<tag>.zip` for nightly AND dated tags (verified via `gh api repos/wez/wezterm/releases` on 2026-06-22) — closes Open Q2/A3.
- Locate `WezTerm.app` via `find -maxdepth 3` because the nightly `.zip` wraps the bundle inside a top-level `WezTerm-macos-<tag>/` dir (not at the zip root).
- Member-safety uses `unzip -Z1` (names-only) rather than `unzip -l` to avoid the `Archive: <abspath>` header false-positive.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] WezTerm.app not at the scratch root (bundle is wrapped)**
- **Found during:** Task 2 GREEN — live `install_macos nightly` on the Intel Mac.
- **Issue:** The PATTERNS skeleton assumed `${unzipped}/WezTerm.app`, but the official nightly `.zip` wraps the bundle as `WezTerm-macos-<tag>/WezTerm.app/...`, so the bundle was never found/placed.
- **Fix:** Locate the bundle with `find "${unzipped}" -maxdepth 3 -type d -name 'WezTerm.app'` and `cp -R` that path.
- **Files modified:** tools/bootstrap-wezterm.sh
- **Verification:** Live run placed `~/Applications/WezTerm.app` and the inner binary printed `wezterm 20260622-120102-6ff54928`.
- **Committed in:** `a68eb58` (Task 2 commit)

**2. [Rule 1 - Bug] Member-safety false-positive from the `unzip -l` header**
- **Found during:** Task 2 GREEN — first live run aborted with "archive contains absolute or '..' members".
- **Issue:** `unzip -l ... | awk '{print $NF}'` captured the `Archive:  /var/folders/.../w.zip` header line; its absolute path matched the `^/` traversal guard, blocking every install.
- **Fix:** Switched to `unzip -Z1` (zipinfo names-only) which emits only bare member names with no header/footer.
- **Files modified:** tools/bootstrap-wezterm.sh
- **Verification:** Live run passed the gate and extracted; the test's "member-safety precedes extraction" assertion stays green.
- **Committed in:** `a68eb58` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs, both surfaced by live verification on real hardware).
**Impact on plan:** Both fixes were required for a working install on real WezTerm assets; no scope creep — the integrity gate, sudo-free invariant, and D-07 (no quarantine strip) are all preserved.

## Issues Encountered
- A linter reverted the `install_macos` body + header edit on disk mid-task (the file briefly returned to the stub). Re-applied the real body via Edit, confirmed via `bash -n`, the 26-assertion test, and a fresh live run. The good version was also preserved in a transient stash, which was dropped after reconciling on-disk state.
- `tools/run-tests.sh` pins `lua5.4`, absent on this Homebrew-Lua-5.5 Mac; ran the suite via the sanctioned `LUA_BIN=lua` override. 8 unrelated CLI/config tests fail under Lua 5.5 (`<const>` reassignment is now a hard error) — pre-existing, not caused by 07-02 (my two bootstrap tests PASS). Logged to deferred-items.md per the SCOPE BOUNDARY rule.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- INST-06 macOS gap closed: `install_macos()` is real, sudo-free, integrity-gated, and live-proven on Intel hardware.
- Plan 07-04 owns the verify-then-decide quarantine/Gatekeeper step (D-07) — `install_macos` deliberately leaves `com.apple.quarantine` untouched, so the empirical first-launch check is unobstructed.
- The harness `lua5.4` pin (D-08) and the Lua 5.5 test-compat failures are logged for their own follow-up; they do not block this plan.

## TDD Gate Compliance
- RED gate: `bc882bd` (test) — helper url/path assertions green, install_macos assertions red.
- GREEN gate: `a68eb58` (feat) — all 26 assertions pass; full suite (under `LUA_BIN=lua`) shows both bootstrap tests green.
- No separate REFACTOR commit (the two live-found fixes were folded into the GREEN commit as correctness bugs).

## Self-Check: PASSED

- Files: all 4 present (`wezterm-release.sh`, `bootstrap-wezterm.sh`, `bootstrap_macos_test.lua`, `07-02-SUMMARY.md`).
- Commits: `bc882bd` (RED), `a68eb58` (GREEN) both in history.

---
*Phase: 07-macos-parity*
*Completed: 2026-06-22*
