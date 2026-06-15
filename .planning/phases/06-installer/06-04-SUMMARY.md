---
phase: 06-installer
plan: 04
subsystem: installer
tags: [install, curl-bash, codeload, dev-tty, pipe-safe, trust-model, readme, bash-n, shellcheck]

# Dependency graph
requires:
  - phase: 06-installer (Plan 02)
    provides: "download_release() repointed to castocolina + per-asset .sha256 verify-before-chmod; the wez-<os>-<arch> asset contract setup.sh STEP 3 consumes"
  - phase: 06-installer (Plan 06)
    provides: "bootstrap-wezterm.sh nightly-default + update-in-place (the WezTerm refresh half of the hand-off)"
provides:
  - "tools/install.sh — the pipe-safe remote one-liner (curl|bash / wget|bash / bash <(curl …)) front door"
  - "install.sh hand-off contract: WEZ_REMOTE_BOOTSTRAP=1 \"$tmp/tools/setup.sh\" \"$@\" < /dev/tty"
  - "WEZ_REF pin seam (tag/commit) + WEZ_ASSUME_HEADLESS deterministic test seam + WEZ_BOOTSTRAP_CMD test seam"
  - "the shared-launcher entry point Plan 05's `wez update` re-invokes (single update path, P6-D11)"
  - "a bash -n (+ advisory shellcheck -x) shell-syntax gate over tools/*.sh in run-tests.sh"
  - "README install section with the real castocolina one-liners + P6-D05 trust model + post-install steps"
affects: ["06-installer Plan 05 (wez update re-invokes the shared launcher)", "first v* release tag (Open Q3)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pipe-safe bootstrap (Pattern 1): whole body in main(), `main \"$@\"` the literal last line — a truncated curl|bash stream never executes a half-command"
    - "Temp checkout + trap EXIT cleanup (Pattern 3): mktemp -d guarded by `trap 'rm -rf \"$tmp\"' EXIT` — nothing left behind on success/error/signal"
    - "Codeload tarball fetch (Pattern 5): curl|wget piped into `tar -xzf - --strip-components=1` — no git dependency, GitHub wrapper dir stripped"
    - "/dev/tty revive (Pattern 2 / P6-D04): hand-off runs `< /dev/tty` so the D-03 re-install + D-08 version prompts stay interactive under the pipe"
    - "bash -n syntax gate folded into the existing run-tests.sh pass/fail exit accounting (closes the PATTERNS.md no-shell-syntax-gate gap)"

key-files:
  created:
    - tools/install.sh
    - tests/cli/install_sh_test.lua
  modified:
    - tools/run-tests.sh
    - README.md

key-decisions:
  - "install.sh is pure D-01 glue — NO version/update/target/asset-selection logic (06-06 owns the WezTerm refresh; setup.sh/build.sh/the Lua binary own the rest)"
  - "WEZ_ASSUME_HEADLESS=1 seam forces the headless hand-off branch independent of /dev/tty, so the D-03 abort is deterministically testable without a controlling terminal (Warning 7), distinct from `</dev/null`"
  - "Added a WEZ_BOOTSTRAP_CMD test seam (default: the unpacked setup.sh) so the hand-off target is overridable for tests without a full network fetch"
  - "Deterministic headless-abort assertion drives the SMALLEST entry reaching the SAME D-03 abort (local-checkout `wez install-state` headless against a scratch managed block) — the plan's sanctioned hermetic fallback; install.sh's network fetch is covered by the human dogfood"
  - "README authored to the crafting-effective-readmes OSS template structure (primary path → variants → requirements/post-install → trust model)"

patterns-established:
  - "Shell-syntax gate in run-tests.sh: bash -n over tracked tools/*.sh, advisory shellcheck -x when present, failures fold into the suite exit accounting"

requirements-completed: [INST-07]

# Metrics
duration: ~12min
completed: 2026-06-14
---

# Phase 6 Plan 04: INST-07 Remote One-Liner Installer Summary

**Pipe-safe `tools/install.sh` (main()-last-line codeload-tarball bootstrap that hands off to setup.sh with /dev/tty revived) + the rewritten README install section with real castocolina one-liners and a P6-D05 trust model, plus a bash -n gate and a deterministic headless-abort assertion.**

> STATUS: auto tasks (1 + 2) COMPLETE and committed. Task 3 is a **blocking human-verify checkpoint** (live curl|bash dogfood) — execution STOPPED there; details below for the orchestrator/human.

## Performance

- **Duration:** ~12 min (auto tasks)
- **Started:** 2026-06-14
- **Completed:** 2026-06-14 (auto tasks; Task 3 checkpoint pending)
- **Tasks:** 2 of 3 (Task 3 is the human checkpoint)
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments

- `tools/install.sh` — the user-facing remote one-liner. Pure D-01 glue: whole body in `main()`, `main "$@"` the literal last line (truncated `curl|bash` never executes a partial command); `mktemp -d` + `trap 'rm -rf "$tmp"' EXIT`; codeload `tar.gz` fetch piped into `tar -xzf - --strip-components=1` (no git); hand-off `WEZ_REMOTE_BOOTSTRAP=1 "$tmp/tools/setup.sh" "$@" < /dev/tty` (headless fallback passes `"$@"` through). `WEZ_REF` pin seam, `WEZ_ASSUME_HEADLESS` deterministic test seam, `WEZ_BOOTSTRAP_CMD` test seam.
- README install section rewritten via the `crafting-effective-readmes` OSS template: primary `curl|bash`, `wget -qO-|bash`, and `bash <(curl …)` forms; Requirements; "What it does"; post-install steps; and an explicit Trust model (inspect-before-run, `WEZ_REF` pin-to-tag/commit, SHA-256-before-chmod + HTTPS≠authenticity). The broken `…/tools/setup.sh | sh` and `you/` placeholder are gone.
- `tools/run-tests.sh` now runs a `bash -n` syntax gate (+ advisory `shellcheck -x`) over all tracked `tools/*.sh` before the Lua suite, failures folded into the suite exit code.
- `tests/cli/install_sh_test.lua` — text contract on install.sh + README, AND a deterministic headless-abort assertion proving the D-03 non-zero (exit 3) abort without a human.

## The install.sh hand-off contract (durable record for Plan 05 `wez update`)

- **Hand-off line:** `WEZ_REMOTE_BOOTSTRAP=1 "$tmp/tools/setup.sh" "$@" < /dev/tty` (interactive); headless fallback drops the `< /dev/tty` redirect and passes flags via `"$@"`. setup.sh's exit code is surfaced as install.sh's own (so the D-03 abort propagates non-zero).
- **Pin seam:** `WEZ_REF=<tag|sha>` (default `main`) → `https://codeload.github.com/castocolina/wezterm-setup/tar.gz/refs/heads/${ref}`. README documents the `refs/tags/<tag>` / `<sha>` URL forms.
- **Test seams:** `WEZ_ASSUME_HEADLESS=1` forces the headless branch regardless of `/dev/tty`; `WEZ_BOOTSTRAP_CMD` overrides the hand-off target (default: the unpacked setup.sh). Both documented as test-only; real headless detection remains the absence of a readable `/dev/tty`.
- **Shared launcher (P6-D11):** this is the single entry point Plan 05's `wez update` re-invokes — one update path, no duplicate download logic in Lua.
- **WezTerm refresh:** flows through 06-06's nightly-default + update-in-place path (setup.sh STEP 2 → bootstrap-wezterm.sh). install.sh adds NO version/update/target/asset logic.

## Task Commits

Each auto task was committed atomically:

1. **Task 1: install.sh + bash -n gate** — `2f0780c` (feat)
2. **Task 2: README rewrite + install_sh_test.lua** — `ba8c5ad` (docs)

**Plan metadata:** committed separately after this SUMMARY.

## Files Created/Modified

- `tools/install.sh` (created) — pipe-safe remote bootstrap: codeload tarball fetch → setup.sh hand-off with /dev/tty revived.
- `tools/run-tests.sh` (modified) — added the `bash -n` (+ advisory `shellcheck -x`) gate over `tools/*.sh`.
- `tests/cli/install_sh_test.lua` (created) — install.sh + README text contract + deterministic headless-abort assertion.
- `README.md` (modified) — rewritten `## Install` section (real one-liners + trust model + post-install).

## Verification (auto tasks — all green)

- `bash -n tools/install.sh` exits 0; `tail -n1 tools/install.sh` is `main "$@"` (exactly one invocation); greps for `/dev/tty`, `mktemp`, `trap 'rm -rf`, `codeload`, `--strip-components=1`, `WEZ_REMOTE_BOOTSTRAP=1`, `WEZ_REF`, `WEZ_ASSUME_HEADLESS` all pass.
- No-decision-logic check: `download_release|wezterm_datestamp|select_release|WEZTERM_TARGET|latest_nightly` absent from install.sh (D-01 confirmed).
- `shellcheck -x tools/install.sh` clean.
- `lua5.4 tests/cli/install_sh_test.lua` → 24 passed, 0 failed (incl. the deterministic headless-abort: existing managed block + `WEZ_ASSUME_HEADLESS=1` + no flag → exit 3; and `--force` → exit 0).
- README: castocolina curl + wget + `bash <(curl …)` one-liners present; `WEZ_REF`, Trust model, SHA-256 note, post-install steps present; `tools/setup.sh | sh` and `github.com/you/` / `raw.githubusercontent.com/you/` all absent (count 0).
- `./tools/run-tests.sh` → exit 0 (bash -n gate over 9 tools/*.sh all green + shellcheck advisory all green; install_sh_test.lua discovered + green; no regressions).

## Decisions Made

See `key-decisions` in the frontmatter. Headline: install.sh stays pure glue; the `WEZ_ASSUME_HEADLESS`/`WEZ_BOOTSTRAP_CMD` seams exist only to make the headless abort deterministically + hermetically testable.

## Deviations from Plan

None — plan executed as written. One additive seam (`WEZ_BOOTSTRAP_CMD`) beyond the plan's named seams (`WEZ_REF`, `WEZ_ASSUME_HEADLESS`) was added to make the hand-off target overridable for tests; it is documented in install.sh as test-only and defaults to the real unpacked setup.sh, so it changes no production behavior.

## Known interim state (first-release-tag ownership — Open Q3)

No `v*` release exists yet, so a live `curl|bash` against raw GitHub cannot download a real `wez` binary (`download_release()` would 404). The Task 3 human checkpoint therefore uses the **local-checkout dogfood** (run install.sh against the local repo / a scratch HOME), NOT a live network release. A maintainer cuts the first `v*` tag AFTER Plan 03's CI lands; until then the local-checkout / source-launcher fallback is the documented path. The gap is explicitly owned, not silent.

## Issues Encountered

None.

## Next Phase Readiness

- Auto tasks shipped and green. The shared launcher contract is ready for Plan 05's `wez update` to re-invoke (P6-D11).
- **BLOCKER: Task 3 is a blocking human-verify checkpoint** — the live `curl|bash` one-liner cannot be safely integration-tested in CI; it needs a human dogfood (local-checkout against a scratch HOME). See the checkpoint detail returned to the orchestrator.

## Task 3 — Pending blocking human-verify checkpoint

**Type:** human-verify (gate="blocking"). Execution STOPPED here — not auto-approved.

**What to verify (local-checkout dogfood — no live network release required):**

1. Inspect `tools/install.sh` end-to-end: whole body inside `main()`, `main "$@"` the literal last line, temp dir cleaned via `trap … EXIT`, hand-off redirects stdin from `/dev/tty` when present.
2. Dogfood against a **scratch HOME** (NOT your real config), e.g.:
   ```sh
   scratch="$(mktemp -d)"
   HOME="$scratch" \
   WEZ_BIN_DIR="$scratch/.local/bin" \
   WEZTERM_CONFIG_DIR="$scratch/.config/wezterm" \
   WEZ_BOOTSTRAP_CMD="$(git rev-parse --show-toplevel)/tools/setup.sh" \
     bash "$(git rev-parse --show-toplevel)/tools/install.sh"
   ```
   (`WEZ_BOOTSTRAP_CMD` points the hand-off at the LOCAL setup.sh so no network fetch / published `wez` asset is needed — exercises the fetch-skip + hand-off path. Drop it to also exercise the live codeload fetch once a `v*` tag + assets exist.) Confirm it bootstraps/reuses WezTerm WITHOUT touching the system `/usr/bin/wezterm`, targets `nightly` by default, places assets, and ends with `wez doctor` exit 0.
3. Confirm nothing is left behind: the `mktemp` temp checkout is gone after the run.
4. Headless path two ways: (a) the deterministic suite assertion (`WEZ_ASSUME_HEADLESS=1`) is green in `./tools/run-tests.sh` — already confirmed; AND (b) a live headless run against an existing managed block aborts non-zero with the explicit-flag guidance (D-03), and `--force` re-yields one managed block.
5. Read the README install section: one-liners copy-pasteable, trust model clear, post-install steps accurate.

**Resume signal:** Type "approved" once the dogfood passes `wez doctor`, leaves no temp dir, never touches the system WezTerm, the deterministic headless-abort assertion is green, and the README one-liners are verified — or describe what to fix.

## Self-Check: PASSED

- FOUND: tools/install.sh (created — pipe-safe codeload bootstrap)
- FOUND: tools/run-tests.sh (modified — bash -n gate)
- FOUND: tests/cli/install_sh_test.lua (created — 24/24 green)
- FOUND: README.md (modified — rewritten install section)
- FOUND: .planning/phases/06-installer/06-04-SUMMARY.md
- FOUND: commit 2f0780c (Task 1)
- FOUND: commit ba8c5ad (Task 2)

---
*Phase: 06-installer*
*Completed: 2026-06-14 (auto tasks; Task 3 human checkpoint pending)*
