---
phase: 06-installer
plan: 05
subsystem: installer
tags: [cli, wez-update, self-update, semver-comparator, datestamp-comparator, p6-d09, p6-d11, d-01, d-16, inst-09]
requires:
  - phase: 06-installer
    provides: "06-06 wezterm_install_is_user_path() predicate + resolve_want_datestamp() / latest-nightly want (the install-kind gate + WezTerm freshness want)"
  - phase: 06-installer
    provides: "06-04 tools/install.sh shared launcher (the SAME entry point the curl|bash one-liner uses; WEZ_REF pin seam) + the eb8a691 temp-cleanup/tty fix"
  - phase: 06-installer
    provides: "06-02 published wez-<os>-<arch> release contract + WEZ_RELEASE_TAG (the latest-release-tag source for the semver comparator)"
  - phase: 06-installer
    provides: "06-01 ratified Open-Q1 latest-nightly datestamp query (consumed via 06-06's resolver) + graceful-degrade-on-fetch-failure"
provides:
  - "`wez update` subcommand (INST-09): a single trusted self-update front door that re-invokes the shared launcher — no retyping the remote URL, no divergent second update path"
  - "M.decide_wez_update(have, latest, kind) — PURE semver/tag comparator for the wez BINARY half (numeric per-field, leading-v tolerant), returning update|current|system-skip"
  - "M.decide_wezterm_update(have, want, kind) — PURE 8-digit YYYYMMDD comparator for the WezTerm EMULATOR half (same `>=` semantics as wezterm_datestamp_ge), returning update|current|system-skip"
  - "`update` registered in cli/spec.lua's 3 places (CATEGORIES + SUBCOMMANDS + build_parser) so `wez update` tab-completes via the spec-walk with no completions.lua edit (D-16)"
affects:
  - "Phase 6 wrap-up / handoff (INST-09 closed; the wez-binary self-update half waits only on the first v* release tag, Open Q3)"
  - "tools/setup.sh STEP 2/3 (the single update flow both the one-liner and `wez update` hit)"
tech-stack:
  added: []
  patterns:
    - "Warning 4 split: two DISTINCT freshness comparators (semver for the wez binary vs YYYYMMDD datestamp for the WezTerm emulator) — never conflated, each its own pure function + fixtures"
    - "D-01/P6-D11 thin-command boundary: the ONLY Lua logic is the version-comparison decision; ALL fetch/unpack/self-replace is delegated to the shared launcher (single entry point), never re-implemented in Lua"
    - "Install-kind safety is resolved by CALLING 06-06's reusable wezterm_install_is_user_path() predicate (sourced + invoked), not by re-mirroring a log line — system installs return system-skip (checked FIRST) and are never touched"
    - "Graceful degradation as a no-op default: an empty/garbage want-datestamp -> 'current' (never a forced swap); an empty latest release tag -> 'current' (clean no-op for the wez half, Open Q3)"
key-files:
  created:
    - cli/commands/update.lua
    - tests/cli/update_test.lua
  modified:
    - cli/spec.lua
    - tests/cli/spec_test.lua
decisions:
  - "Two distinct comparators (decide_wez_update semver / decide_wezterm_update datestamp), each PURE and fixture-tested — the wez binary uses semver, the WezTerm emulator uses the 8-digit datestamp; neither is reused for the other half (Warning 4)"
  - "system-skip is checked FIRST in BOTH comparators (before any version/datestamp compare) so a system install is never modified regardless of freshness (P6-D09); install kind comes from 06-06's predicate, not a re-mirror of detect_and_reuse:83"
  - "run() delegates the actual update to tools/install.sh — the SAME launcher the one-liner uses (P6-D11) — re-implementing NO download/verify/place/self-replace; the temp-same-dir + atomic mv -f swap lives in the launcher glue (Pattern 4), not in Lua"
  - "Open-Q3 first-release-tag ownership: until a v* wez tag is cut, latest_wez_release_tag() returns empty -> the wez half reports a clean no-op ('no published wez release yet') while the WezTerm half keeps working (upstream always has nightly)"
  - "spec 3-place registration mirrors seed-scenes (no flags — all decisions in update.lua, D-01) so completion auto-covers `update` with zero completions.lua/complete.lua edits (D-16)"
metrics:
  duration: ~12 min
  completed: 2026-06-15
---

# Phase 6 Plan 05: `wez update` Self-Update Front Door (INST-09) Summary

Shipped `wez update` — the single trusted self-update front door that checks for and applies updates
without retyping the remote URL. It re-invokes the **SAME** shared launcher (`tools/install.sh`, Plan 04)
the `curl|bash` one-liner uses (P6-D11 single entry point, no divergent second path). Per the D-01 boundary
the command is a THIN Lua wrapper: the only logic in Lua is the version-comparison **decision**, split
(Warning 4) into two DISTINCT pure comparators — `decide_wez_update` (semver, the wez binary) and
`decide_wezterm_update` (8-digit YYYYMMDD datestamp, the WezTerm emulator). All fetch / unpack /
binary-self-replace is delegated to the launcher glue, never re-implemented in Lua.

## What shipped

- **`cli/commands/update.lua`** (NEW, ~300 lines) — the thin command:
  - **`M.decide_wez_update(have_version, latest_version, install_kind)`** — the wez BINARY half. A SEMVER/tag
    compare of `M.VERSION` (e.g. `0.1.0`) against the latest published `wez` release tag (e.g. `v0.2.0`),
    using a NUMERIC per-field compare (so `0.10.0 > 0.9.0`, which a lexical compare gets wrong) with a
    leading-`v` tolerance. `system` → `system-skip` (checked FIRST); empty/nil latest → `current` (no
    published release yet, Open Q3); `have >= latest` → `current`; strictly-newer latest → `update`. PURE.
  - **`M.decide_wezterm_update(have_datestamp, want_datestamp, install_kind)`** — the WezTerm EMULATOR half.
    The 8-digit `YYYYMMDD` numeric `>=` compare (the SAME semantics as `bootstrap-wezterm.sh`'s
    `wezterm_datestamp_ge`); the `want` is resolved by 06-06. `system` → `system-skip` (FIRST); empty/garbage
    want → `current` (graceful degradation — a failed latest-nightly fetch NEVER forces a swap,
    T-06-05-04 / T-06-06-01); empty/unparseable have → `update` (treated as below); `have >= want` →
    `current`; strictly-newer want → `update`. PURE.
  - **`M.run(args)`** — resolves the install kind by CALLING 06-06's `wezterm_install_is_user_path()`
    predicate (sources `tools/bootstrap-wezterm.sh` and invokes the real function — NOT a re-mirror of
    `detect_and_reuse:83`), reads the wez semver + WezTerm datestamp inputs, applies BOTH comparators, then:
    a system install → a clear "leaving it untouched (no sudo, P6-D09)" message and a non-destructive exit;
    both `current` → a clear combined no-op; either `update` (user-path) → DELEGATE to `tools/install.sh`
    (the shared launcher) and surface its exit code. No download/verify/place/self-replace in Lua; every
    shell path goes through `install_state.shquote` (CR-02).
- **`cli/spec.lua`** (MODIFIED) — `update` registered in the THREE places `seed-scenes` is (D-16):
  `CATEGORIES["update"] = "install"`, the `SUBCOMMANDS` allow-list, and `build_parser()`
  (`parser:command("update", …)`, no flags). The completion generator's spec-walk picks it up automatically.
- **`tests/cli/update_test.lua`** (NEW) — fixture tests of BOTH comparators, each with its own fixtures
  (Warning 4): `decide_wez_update` (newer→update, equal/older→current, numeric-not-lexical, leading-v,
  system→system-skip, no-release→current) and `decide_wezterm_update` (newer→update, have≥want→current,
  empty-have→update, degraded-want→current, system→system-skip), plus the module interface + the spec
  3-place registration assertions.
- **`tests/cli/spec_test.lua`** (MODIFIED) — `update` (and the previously-missing `seed-scenes`) added to
  `required_subcommands` so the registration + category contract covers it.

## Shared-launcher delegation (P6-D11)

`run()` shells out to `tools/install.sh` — the SAME entry point the `curl|bash` one-liner runs (resolved via
the `WEZ_LAUNCHER` test seam / `WEZ_REPO_DIR`, defaulting to `<repo>/tools/install.sh`). The launcher
(`setup.sh` STEP 2 runs 06-06's WezTerm update-in-place; STEP 3 refreshes the `wez` binary) performs the
fetch/place AND the self-replace swap (temp-same-dir + atomic `mv -f`, Pattern 4 — in the glue, never
`rm`-then-write / ETXTBSY). `update.lua` re-implements NO `download_release`/`codeload`/`gh release` path
(grep confirmed FALSE) and contains no `sudo` (count 0).

## System-install guard (P6-D09)

The install kind is resolved by sourcing `tools/bootstrap-wezterm.sh` and CALLING its reusable
`wezterm_install_is_user_path()` predicate against the active `wezterm` path. A binary outside `~/.local/bin`
(the verified real case: apt `wezterm-nightly` in `/usr/bin`, root-owned) → `system-skip` in BOTH comparators
(checked FIRST), so it is never sudo'd/overwritten — `run()` messages and exits cleanly.

## Open-Q3 first-release-tag ownership

`decide_wez_update` compares `M.VERSION` against the latest published `wez` release tag, which does not exist
until the first `v*` tag is cut (Open Q3, a maintainer action shared with 06-02/06-04). Until then
`latest_wez_release_tag()` (honoring `WEZ_RELEASE_TAG`) is empty → the wez half reports a clean no-op
("no published wez release yet"), while the WezTerm half still works (upstream `wez/wezterm` always has
`nightly`). The gap is explicitly owned, not silent.

## KNOWN INTERIM

No `v*` wez release exists yet, so `wez update` cannot fetch a real `wez` binary live. Per the plan, the
tests are PURE-decision / contract only (the two comparators + the spec/completion registration) — they
never trigger a real download or swap. Once the first `v*` tag + release lands, the wez-binary half fetches
through the same shared launcher; no code change is required (it reads `WEZ_RELEASE_TAG`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing test coverage] `seed-scenes` was absent from `spec_test.lua`'s `required_subcommands`**
- **Found during:** Task 2 (extending the registration assertion set)
- **Issue:** The interface-first contract in `spec_test.lua` listed every Phase-1 subcommand EXCEPT
  `seed-scenes` (registered back in Plan 05's seed-scenes work but never added to the required set). Adding
  only `update` would have left that gap.
- **Fix:** Added BOTH `seed-scenes` and `update` to `required_subcommands` so the registration + category
  assertions cover the full install-category surface.
- **Files modified:** `tests/cli/spec_test.lua`
- **Commit:** 89b137c

**2. [Rule 1 - Acceptance-gate false positive] doc comment tripped the `grep -c 'sudo ' == 0` guard**
- **Found during:** Task 1 verify
- **Issue:** A header comment contained the literal token `sudo ` (with a trailing space) while describing
  the no-sudo guarantee, which made the `! grep -Eq '…|sudo '` acceptance check fail even though there is no
  `sudo` invocation anywhere.
- **Fix:** Reworded the comment to "Never elevates privileges (no privilege escalation anywhere in this
  module)"; `grep -c 'sudo '` is now 0.
- **Files modified:** `cli/commands/update.lua`
- **Commit:** d738040 (folded into the GREEN implementation commit)

## Verification

- `lua5.4 tests/cli/update_test.lua` → 0 (27 assertions: both comparators' fixtures + interface + spec
  registration).
- `lua5.4 tests/cli/spec_test.lua` → 0; `lua5.4 tests/cli/completions_test.lua` → 0 (the generated zsh+bash
  scripts reference `update`; D-16 coverage with no completions.lua/complete.lua edit — `git diff --stat`
  on both is empty).
- Task 1 grep gate: `decide_wez_update`, `decide_wezterm_update`, `wezterm_install_is_user_path`,
  `install_state.shquote`, `install.sh` all present; `download_release|sudo ` absent; `sudo` count 0;
  no `download_release|codeload|gh release` second path.
- `./tools/run-tests.sh` → all 21 files pass (incl. the Plan 04 `bash -n` shell-syntax gate).
- `wez update` parses + dispatches to `cli/commands/update.lua` without a raw traceback.

## Self-Check: PASSED

- FOUND: cli/commands/update.lua
- FOUND: tests/cli/update_test.lua
- FOUND (modified): cli/spec.lua, tests/cli/spec_test.lua
- FOUND commit 7de903e (test RED), d738040 (feat GREEN update.lua), 89b137c (feat spec registration)
