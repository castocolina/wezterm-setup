---
phase: 06-installer
plan: 06
subsystem: installer
tags: [bootstrap, wezterm-update, nightly-default, install-kind-predicate, p6-d09, sc8]
requires:
  - tools/bootstrap-wezterm.sh (detect_and_reuse / select_release / install_linux / version helpers)
  - tools/lib/wezterm-release.sh (_wezterm_fetch + WEZTERM_RELEASE_* host seams + WEZTERM_PINNED_RELEASE)
  - tools/lib/platform.sh (platform_os / platform_ubuntu_base)
  - .planning/phases/06-installer/06-01-SUMMARY.md (Open-Q1 latest-nightly want verdict)
provides:
  - "WEZTERM_TARGET=nightly default seam (pinned/explicit-tag opt-in) consumed by select_release + the update path"
  - "latest_nightly_datestamp() / resolve_want_datestamp() — the latest-nightly want resolver with graceful-degrade-to-no-op"
  - "wezterm_install_is_user_path(path?) — reusable install-kind predicate (true iff under ${BIN_DIR}) for Plan 05"
  - "update-in-place branch in detect_and_reuse() gated on the predicate, reusing install_linux() (SC#8)"
affects:
  - cli/commands/update.lua (Plan 05 — reuses wezterm_install_is_user_path as the user-vs-system gate)
  - tools/setup.sh STEP 2 (the single update flow both the one-liner (Plan 04) and `wez update` (Plan 05) hit)
tech-stack:
  added: []
  patterns:
    - "Install TARGET (WEZTERM_TARGET) is distinct from the reuse FLOOR (WEZTERM_MIN_RELEASE): floor gates usability, target gates freshness"
    - "Latest-nightly 'newer?' signal degrades to EMPTY want -> no-op (never a forced swap) on any fetch/parse failure (T-06-06-01)"
    - "Update-in-place REUSES install_linux() STEP-3 (verify_tarxz + assert_safe_members + fresh per-release dir + ln -sfn) — no second fetch path (T-06-06-02/04)"
    - "Install-kind safety is a checkable predicate (wezterm_install_is_user_path), not a log line — user-path gates every swap (T-06-06-03)"
key-files:
  created:
    - tests/cli/bootstrap_update_test.lua
  modified:
    - tools/bootstrap-wezterm.sh
decisions:
  - "WEZTERM_TARGET defaults to `nightly` incl. the non-interactive pipe path (P6-D09); pinned/explicit-tag is the reproducibility opt-in"
  - "latest_nightly_datestamp() queries releases/tags/nightly per-asset updated_at (OS-base-matched) -> YYYYMMDD; empty on failure -> no-op (Open-Q1 verbatim)"
  - "A system install (e.g. /usr/bin/wezterm) is NEVER fetched-over or sudo'd; behind-want -> leave intact + place a user-path copy that wins on PATH"
  - "Open-Q3 first-release-tag ownership reaffirmed: WezTerm assets come from upstream wez/wezterm (always has nightly); only the project's own first wez v* tag remains a maintainer action"
metrics:
  duration: ~10 min
  completed: 2026-06-14
---

# Phase 6 Plan 06: WezTerm Version Policy (nightly default + update-in-place + install-kind predicate) Summary

Closed the three plan-checker BLOCKERS that the prior Phase 6 plan set left open in
`tools/bootstrap-wezterm.sh`, delivering the P6-D09 WezTerm version policy that BOTH the one-liner
(Plan 04 → `setup.sh` STEP 2) and `wez update` (Plan 05) depend on. All changes are surgical
additions to the existing detection-first glue (D-01); the update path REUSES the proven STEP-3
fetch — no second download path was introduced.

## What shipped

### Blocker 2 — nightly default target (P6-D09)
- Added the `WEZTERM_TARGET="${WEZTERM_TARGET:-nightly}"` seam, documented as the install TARGET
  distinct from the `WEZTERM_MIN_RELEASE` reuse FLOOR. The floor still gates whether a found
  install is usable at all; the target gates whether it is fresh enough.
- `select_release()` now honors `WEZTERM_TARGET` on the **no-TTY** path: `nightly` (default) prints
  `nightly`; `pinned` prints `WEZTERM_PINNED_RELEASE`; an explicit dated tag prints that tag. The
  interactive TTY menu (nightly + last-5 dated via `wezterm_release_list`) is unchanged.

### Blocker 3 — real install-kind predicate (the P6-D09 safety gate)
- `wezterm_install_is_user_path([path])` — returns 0 (true) iff the resolved `wezterm` path is under
  `${BIN_DIR}` (the project user-path), non-zero (false) for any other path (e.g. `/usr/bin/wezterm`,
  the verified apt `wezterm-nightly` system case). A real `return`-valued predicate (not the old
  log-only check), unit-testable by sourcing the script. **Signature Plan 05 consumes:** takes a
  wezterm path as `$1` (resolves the active one via `command -v wezterm` when omitted).

### Blocker 1 — update-in-place branch (ROADMAP SC#8 / P6-D09)
- Added `latest_nightly_datestamp()` implementing 06-01-SUMMARY's ratified Open-Q1 query verbatim:
  `GET ${WEZTERM_RELEASE_API}/repos/${WEZTERM_RELEASE_REPO}/releases/tags/nightly` via the existing
  `_wezterm_fetch` (official `wez/wezterm` HTTPS only — no new fetcher), select the OS-base-matched
  asset, take the leading 8 digits of THAT asset's **per-asset `updated_at`** (never the stale
  release-level `published_at`/`created_at`). On any fetch/parse failure it prints nothing.
- `resolve_want_datestamp()` returns the latest-nightly datestamp when `WEZTERM_TARGET=nightly`, else
  the pinned/explicit-tag datestamp.
- `detect_and_reuse()` now compares `have` against the resolved `want` (after first gating on the
  fixed floor):
  - `have < floor` → fresh fetch (return 1), regardless of target.
  - empty want (degraded fetch) OR `have >= want` → reuse untouched (no-op) — a garbage/missing
    "newer?" signal NEVER forces a swap.
  - `have < want` AND **user-path** → UPDATE IN PLACE by calling `install_linux "$(select_release)"`
    (reuses verify→assert→fresh-dir→`ln -sfn`); return 0.
  - `have < want` AND **system install** → left intact, no sudo; logs the offer and returns 1 so
    `main()` places a fresh user-path copy under `${BIN_DIR}` (install_linux writes user-path only).

### Test (new)
- `tests/cli/bootstrap_update_test.lua` (25 assertions) — mirrors the `seed_scenes_test.lua`
  `check()`-harness. TEXT asserts: the `WEZTERM_TARGET` nightly default, the three new functions, the
  predicate's `${BIN_DIR}` compare, the want query (official host + per-asset `updated_at`), the
  update-in-place branch gated on the predicate + reusing `install_linux` with NO second fetch block,
  and `select_release`'s `WEZTERM_TARGET` wiring. BEHAVIOR asserts (sourced no-run mode, via the
  `$0`/`BASH_SOURCE` guard): `wezterm_install_is_user_path "${BIN_DIR}/wezterm"` exits 0 (user-path)
  while `/usr/bin/wezterm` and an empty path exit non-zero (system); `resolve_want_datestamp` with
  `WEZTERM_TARGET=pinned` yields the pinned 8-digit date; `select_release` under no-TTY prints
  `nightly` (default) / the pinned release (pinned) — all with NO live WezTerm download.

## Tasks

| Task | Name | Commit |
| ---- | ---- | ------ |
| 1 | WEZTERM_TARGET nightly default + want resolver + user-path predicate (Blockers 2+3) | `1e24c3b` |
| 2 | update-in-place branch in detect_and_reuse + select_release wiring (Blocker 1 / SC#8) | `474badf` |

## Deviations from Plan

**1. [Rule 1 — Bug] Test assertion `grep -c 'sudo '` intent vs. literal**
- **Found during:** Task 1 verification.
- **Issue:** The plan's literal `[ "$(grep -c 'sudo ' …)" -eq 0 ]` check was never satisfiable —
  HEAD already carried one pre-existing comment line (`no FUSE, no sudo — D-05`) containing the
  `sudo ` substring. The real constraint is "no sudo **introduced** / no sudo **invoked**".
- **Fix:** The Lua test asserts no NON-COMMENT line invokes `sudo` (the accurate intent). Confirmed
  `grep -c 'sudo '` is unchanged (1 → 1, comment-only) and non-comment `sudo` invocations = 0. No new
  sudo introduced; D-05's pre-existing comment was left untouched.
- **Files modified:** `tests/cli/bootstrap_update_test.lua`
- **Commit:** `1e24c3b`

## Open-Q3 first-release-tag ownership (inherited)

WezTerm's update path here is unaffected by the project's own first `wez` `v*` release tag — WezTerm
assets come from upstream `wez/wezterm`, which always publishes a `nightly` tag. The gap is solely
the project's first `wez` BINARY release tag (a maintainer action AFTER Plan 03's CI lands); until
then the one-liner uses the dev source-launcher fallback (Plan 04 checkpoint step 2a). This decision
is reaffirmed so Plans 04/05 inherit it.

## Verification

- `bash -n tools/bootstrap-wezterm.sh` — clean.
- `shellcheck -S warning tools/bootstrap-wezterm.sh` — clean (only pre-existing SC1091 info on the
  sourced libs, suppressed at warning level).
- `WEZTERM_TARGET:-nightly`, `wezterm_install_is_user_path`, `latest_nightly_datestamp`,
  `resolve_want_datestamp` all defined; no non-comment `sudo` invocation introduced.
- `lua5.4 tests/cli/bootstrap_update_test.lua` — 25 passed, 0 failed.
- `./tools/run-tests.sh` — all 19 files pass (exit 0); no regressions.

## Self-Check: PASSED

- FOUND: `tools/bootstrap-wezterm.sh` (modified — WEZTERM_TARGET, resolvers, predicate, update branch)
- FOUND: `tests/cli/bootstrap_update_test.lua`
- FOUND: commit `1e24c3b` (Task 1)
- FOUND: commit `474badf` (Task 2)
