---
phase: 07-macos-parity
plan: 03
subsystem: ci-cd-supply-side
tags: [macos, ci, codesign, release-matrix, lua, toolchain]
requires:
  - "07-01 (Wave-0 toolchain: keg-only lua@5.4 + build.sh macOS keg cflags/liblua fallback)"
  - "07-02 (Wave-1 install_macos .app placement)"
provides:
  - "fixed macOS CI toolchain provisioning (keg-only lua@5.4 on $GITHUB_PATH)"
  - "build-time ad-hoc codesign of both macOS arches with codesign --verify evidence"
  - "3-leg release matrix (ubuntu-latest / macos-15-intel / macos-14) with arm64 in-build smoke"
  - "workflow_dispatch dry-run path that builds+codesigns+uploads the macOS legs without a v* tag"
affects:
  - "Plan 07-04 (consumes the dispatch dry-run via gh run watch; relies on the actionlint pass run here)"
tech-stack:
  added:
    - "actionlint 1.7.12 (static GitHub Actions linter — installed on the verify host)"
  patterns:
    - "build-time ad-hoc codesign inside a platform_os=macos guard (widened from publish.sh arm64-only to both arches)"
    - "strategy.matrix restored over three runner labels; single-leg-guarded prune; arm64-only smoke"
key-files:
  created:
    - "tests/cli/ci_macos_toolchain_test.lua (TEXT gate over the matrix + Task 1 cross-file regression guard)"
  modified:
    - "tools/ci-setup-toolchain.sh (install_macos: lua@5.4 keg + $GITHUB_PATH)"
    - "tools/build.sh (build_with_luastatic: macOS-guarded codesign + verify)"
    - ".github/workflows/release.yml (3-leg matrix, arm64 smoke, single-leg prune, dispatch dry-run docs)"
    - ".planning/phases/07-macos-parity/deferred-items.md (reconfirm pre-existing Lua-5.5 failures)"
decisions:
  - "Sign BOTH macOS arches uniformly (D-06) — x86_64 signing is harmless; arm64 is the one the kernel SIGKILLs unsigned. Same-contract rule with publish.sh, widened from arm64-only."
  - "Never gate the build on Gatekeeper assessment — ad-hoc signatures are always rejected (Pitfall 4); codesign --verify success is the real evidence."
  - "macos-13 literal appears NOWHERE in release.yml (not even in comments) so the grep -c 'macos-13' == 0 gate holds; comments say 'the retired Intel image' instead."
  - "actionlint runs HERE in 07-03 (the static-lint owner); 07-04 does the LIVE dispatch run and does NOT re-lint (no double-lint, no gap — F9)."
metrics:
  duration: "~30min"
  tasks: 2
  files: 5
  completed: "2026-06-22"
---

# Phase 7 Plan 03: macOS CI Release Matrix + Codesign Summary

Restored the full macOS supply side — both darwin-x86_64 and darwin-aarch64 are now
provisioned (keg-only `lua@5.4`), build-time ad-hoc-codesigned (both arches, with a
`codesign --verify` evidence line), and published from a 3-leg `strategy.matrix` over
`ubuntu-latest`/`macos-15-intel`/`macos-14`, with an arm64-only in-build smoke and a
`workflow_dispatch` dry-run that exercises the macOS legs without cutting a `v*` tag.

## What shipped

### Task 1 — `fix(07-03)` `a97adb4`: lua@5.4 keg PATH + build-time codesign

- **`tools/ci-setup-toolchain.sh` `install_macos()`** — replaced the latent-bug
  `brew install lua luarocks` (Homebrew `lua` is now 5.5 — Pitfall 1) with
  `brew install lua@5.4 luarocks`. Resolved `PREFIX="$(brew --prefix lua@5.4)"`,
  prepended `${PREFIX}/bin` to `PATH` (keg-only is not auto-on-PATH — Pitfall 2),
  and `printf … >> "$GITHUB_PATH"` so the subsequent build step finds `lua5.4`.
  Left `assert_and_capture()` untouched (it already fails loud if `lua5.4`/`luastatic`
  are absent). Documented the keg link-flag fix in a comment (build.sh already
  resolves it via the 07-01 keg fallback).
- **`tools/build.sh` `build_with_luastatic()`** — after `chmod +x "${OUT}"`, added an
  `if [ "$(platform_os)" = "macos" ]; then … fi` block that runs
  `codesign --force --sign - "${OUT}"` AND `codesign --verify --verbose "${OUT}"`
  INSIDE the guard, signing BOTH arches uniformly (D-06). A comment states the build
  intentionally does NOT gate on Gatekeeper assessment (always rejects ad-hoc —
  Pitfall 4).

### Task 2 — `feat(07-03)` `025220a`: 3-leg matrix + arm64 smoke + dispatch dry-run + TEXT gate

- **`.github/workflows/release.yml`** — re-introduced `strategy.matrix`
  (`fail-fast: false`) over `ubuntu-latest`/`macos-15-intel`/`macos-14`;
  `runs-on: ${{ matrix.runner }}`; `name: build (${{ matrix.runner }})`. The retired
  Intel label appears NOWHERE (Pitfall 7). Every existing step (checkout, Resolve-channel
  D-07, Skip-if-unchanged, ci-setup-toolchain, build.sh, Name+checksum, Ensure-release,
  Upload) runs per-leg unchanged. Added an arm64-only in-build smoke gated
  `if: matrix.runner == 'macos-14'` running `codesign --verify --verbose dist/wez` +
  `./dist/wez version`. Guarded the Prune step to a single leg
  (`matrix.runner == 'ubuntu-latest'`) so three legs do not race the same delete.
  Documented `workflow_dispatch` as the unattended macOS-leg dry-run proof path.
- **`tests/cli/ci_macos_toolchain_test.lua`** (new) — TEXT gate asserting release.yml
  has the matrix + all three runner labels, NO `macos-13`, the arm64 smoke
  (`matrix.runner == 'macos-14'` + `codesign --verify` + `dist/wez version`), and the
  `workflow_dispatch` trigger; plus a cross-file regression guard that
  ci-setup-toolchain.sh pins `lua@5.4` (not bare `lua`) on `$GITHUB_PATH` and build.sh
  has the `codesign --force --sign -` block. 19/19 green.

## Verification

- **Task 1:** `bash -n` clean on both scripts; `shellcheck -x` clean (in the suite)
  and `shellcheck -S error` direct. Acceptance greps all pass: no bare
  `brew install lua ` (non-comment), `lua@5.4` count 6 (>=2), `GITHUB_PATH` count 4
  (>=1), `codesign --force --sign -` count 1 (>=1), `codesign --verify` count 3 (>=1),
  no non-comment `spctl`. The awk SCOPE assertion (guard-open before codesign before
  guard-close) exits 0 — the codesign sits INSIDE the `platform_os=macos` guard.
- **Task 2:** acceptance greps pass — `macos-15-intel` 3 (>=1), `macos-14` 6 (>=1),
  `strategy:|matrix:` 2 (>=2), `macos-13` **0**, `matrix.runner == 'macos-14'` 1 (>=1),
  `workflow_dispatch` 5 (>=1). **`actionlint` 1.7.12 ran clean (exit 0) on release.yml**
  — run HERE in 07-03 (the static-lint owner; 07-04 does the live `gh run watch` and
  does NOT re-lint). The TEXT gate is 19/19 and is now discovered + green inside
  `run-tests.sh`.
- **TDD flow:** the TEXT gate was authored first and ran RED (6 matrix/smoke
  assertions failing on the pre-matrix release.yml, the Task-1 cross-file guards
  already green), then GREEN after the release.yml edits (19/19).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `actionlint` was not installed on the verify host**
- **Found during:** Task 2 verification.
- **Issue:** The plan designates 07-03 as the actionlint static-lint owner ("run
  actionlint if available; record that it ran clean"), but `actionlint` was absent on
  this Mac, which would have left the designated lint gate unverified and forced a gap
  that 07-04 explicitly does not cover.
- **Fix:** Installed `actionlint` 1.7.12 via Homebrew (a well-known, legitimate,
  bottled formula — not a slopsquat risk; this is a verify-tool install, not a runtime
  dependency added to the project). Ran it clean (exit 0) on release.yml.
- **Files modified:** none (tooling only).
- **Commit:** evidence recorded in `025220a`'s message.

**2. [Rule 1 - Bug] `macos-13` / `spctl` literals in comments tripped the zero-count gates**
- **Found during:** Task 1/2 verification.
- **Issue:** First drafts mentioned `macos-13` and `spctl --assess` in explanatory
  comments. The acceptance criteria are literal `grep -c` over the whole file
  (`macos-13` must be 0) and a `grep -nE 'spctl' | grep -v '^#'` whose `-n` prefix
  defeats the comment filter — so even a comment mention fails the gate.
- **Fix:** Reworded the comments to "the retired Intel image" and "Gatekeeper
  assessment" — preserving intent while removing the literal tokens.
- **Files modified:** `.github/workflows/release.yml`, `tools/build.sh`.
- **Commit:** folded into `025220a` and `a97adb4` respectively.

## Deferred Issues (out-of-scope, NOT fixed)

The 8 pre-existing Lua-5.5 test failures (`<const>` reassignment is a hard error in
Lua 5.5) reproduce on this Mac (no `lua5.4`; suite ran under `LUA_BIN=lua`). They are
in files completely unrelated to 07-03 (`complete`, `scene`, `recipe`, `completions`,
`keys`, `scene_launch`, `seed_scenes`) and reproduce with the 07-03 diff stashed.
Reconfirmed and logged in `deferred-items.md` under a new `## 07-03` section. 07-03's
shell scripts are gated by `bash -n` + `shellcheck -x` (all PASS) + the new TEXT gate —
the correct verification path for shell/YAML glue.

## Threat surface

No new threat surface beyond the plan's `<threat_model>`. The mitigations the register
assigns to these files are present: T-07-09 (lua@5.4 pin + keg PATH + fail-loud gate +
cross-file TEXT guard), T-07-10 (build-time ad-hoc codesign both arches + `codesign
--verify`), T-07-11 (no manual channel input field — `github.ref`-only resolution;
dispatch → nightly prerelease), T-07-12 (`permissions: contents: write` retained).

## Notes for Plan 07-04

- The `workflow_dispatch` dry-run is the unattended macOS-leg proof path: a dispatch is
  a non-tag ref → `CHANNEL=nightly` → builds + codesigns + uploads all three legs to a
  `nightly-YYYYMMDD` prerelease (excluded from /releases/latest) WITHOUT a `v*` tag.
- **actionlint already ran clean here (07-03).** 07-04 Task 1 should do the LIVE
  `gh run watch` dispatch run only — do NOT re-run actionlint (no double-lint, no gap).
- This plan delivers a CORRECTNESS-verified workflow (actionlint + greps + TEXT gate);
  the live CI execution is 07-04's job. Do NOT push or dispatch from 07-03.

## Self-Check: PASSED

All 5 key files exist on disk; both task commits (`a97adb4`, `025220a`) are present in
git history.
