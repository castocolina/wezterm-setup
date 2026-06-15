---
phase: 06-installer
plan: 03
subsystem: infra
tags: [github-actions, ci, release-matrix, luastatic, codesign, sha256, asset-contract, supply-chain, macos-15-intel]

# Dependency graph
requires:
  - phase: 06-02
    provides: "asset-naming contract wez-<os>-<arch> + per-asset <asset>.sha256 + gh release upload --clobber (tools/publish.sh, tools/build.sh download_release())"
  - phase: 06-01
    provides: "per-asset .sha256 verdict (Open Q2) that build.sh download_release() consumes"
provides:
  - "Tag-triggered (v*) 3-leg GitHub Actions release matrix building wez natively on ubuntu-latest, macos-15-intel, macos-14"
  - "tools/ci-setup-toolchain.sh: per-runner lua5.4 + luastatic + compiler install (apt on linux, brew on macos) with version capture + loud-fail-if-absent"
  - "CI-published asset set wez-<os>-<arch> + <asset>.sha256 (same byte-for-byte contract as make publish)"
  - "Apple Silicon (macos-14) leg ad-hoc-codesigns + codesign --verify before upload"
affects:
  - "Plan 04 (tools/install.sh) + Plan 05 (wez update) — consume the published wez-<os>-<arch> assets this workflow produces"
  - "First v* tag push (Open Q3) — a maintainer action that fires this workflow for the first time"

# Tech tracking
tech-stack:
  added:
    - "GitHub Actions (.github/workflows/release.yml — first workflow in the repo)"
    - "luastatic provisioning via apt/brew per runner (ci-setup-toolchain.sh)"
  patterns:
    - "Same-contract rule extended to CI (P6-D08): asset name computed from platform.sh in release.yml, identical to build.sh + publish.sh — local + CI never drift"
    - "Asset name sourced at runtime from tools/lib/platform.sh (NOT hardcoded matrix literals) so wez-macos-* is emitted (the name download_release() requests), never wez-darwin-*"
    - "Third-party Actions pinned to an immutable ref (actions/checkout@v4.2.2), never @main (T-06-03-01)"
    - "CI toolchain install IS the legitimacy gate for [ASSUMED] luastatic (RESEARCH A3): real per-runner install + version capture + loud-fail-if-absent"

key-files:
  created:
    - .github/workflows/release.yml
    - tools/ci-setup-toolchain.sh
  modified: []

key-decisions:
  - "Upload via `gh release upload \"$GITHUB_REF_NAME\" <asset> <asset>.sha256 --clobber` (the IDENTICAL command tools/publish.sh runs) rather than softprops/action-gh-release — no third-party action to pin, and literal same-contract parity with make publish"
  - "Asset name derived from platform.sh at runtime, not from matrix os/arch literals — the canonical consumer name on macOS is wez-macos-* (platform_os returns 'macos', not 'darwin')"
  - "actions/checkout pinned to @v4.2.2 (immutable tag); hardening to a full commit SHA is a noted follow-up (registry API unreachable offline at execution time)"
  - "actionlint uninstallable in this env (no go/brew/network) — verified via the plan's documented fallback: YAML structural parse (python3) + the contract greps"

patterns-established:
  - "release.yml is pure build+publish glue (D-01): zero install/version/update decision logic in YAML; toolchain -> ci-setup-toolchain.sh, build -> build.sh"
  - "matrix os: darwin field selects runners + gates codesign; it is intentionally NOT the asset name (which comes from platform_os = macos)"

requirements-completed: [INST-08]

# Metrics
duration: ~6min
completed: 2026-06-14
---

# Phase 6 Plan 03: INST-08 CI Half (release matrix + toolchain) Summary

**Tag-triggered 3-leg GitHub Actions release matrix (ubuntu-latest, macos-15-intel, macos-14) that builds wez via luastatic, ad-hoc-codesigns the arm64 asset, and publishes wez-<os>-<arch> + <asset>.sha256 with the same `gh release upload --clobber` command make publish uses — plus a per-runner Lua toolchain installer.**

## Performance

- **Duration:** ~6 min
- **Completed:** 2026-06-14
- **Tasks:** 2
- **Files created:** 2

## Accomplishments
- `.github/workflows/release.yml` — `on: push: tags: ['v*']`, `permissions: contents: write`, a `fail-fast: false` matrix of exactly three legs (`ubuntu-latest`→linux/x86_64, `macos-15-intel`→darwin/x86_64, `macos-14`→darwin/aarch64); steps: checkout → `ci-setup-toolchain.sh` → `build.sh` → arm64-only `codesign --force --sign -` + `codesign --verify` → name+checksum → `gh release upload --clobber`.
- `tools/ci-setup-toolchain.sh` — branches on `platform_os`: apt (`lua5.4 liblua5.4-dev luarocks` + `luarocks install --local luastatic`) on linux, brew (`lua luarocks` + `luarocks install luastatic`) on macos; captures+echoes real `lua5.4 -v` + luastatic versions; exits non-zero if `luastatic`/`lua5.4` are absent post-install (no silent dev-launcher fallback).
- The CI asset contract is byte-for-byte identical to `make publish` (Plan 02): same `wez-<os>-<arch>` name (from `platform.sh`), same per-asset `.sha256`, same `gh release upload --clobber` invocation.

## Runner labels (the durable record)

| Leg | runner | os | arch | published asset |
| --- | ------ | -- | ---- | --------------- |
| linux x86_64 | `ubuntu-latest` | linux | x86_64 | `wez-linux-x86_64` (+ `.sha256`) |
| Intel macOS | `macos-15-intel` | darwin | x86_64 | `wez-macos-x86_64` (+ `.sha256`) |
| Apple Silicon | `macos-14` | darwin | aarch64 | `wez-macos-aarch64` (+ `.sha256`, ad-hoc-codesigned) |

- **`macos-15-intel`** is used for Intel — the older Intel image (the literal `macos-13` in the P6-D01 text) was removed by GitHub 2025-12-04. The workflow has **zero** `macos-13` occurrences (including in comments).
- **`macos-14`** is the arm64-only Apple Silicon image — the only leg that codesigns.

## Chosen upload mechanism + pin

- **Upload:** `gh release upload "$GITHUB_REF_NAME" "$WEZ_ASSET" "$WEZ_ASSET.sha256" --clobber` with `env: GH_TOKEN: ${{ github.token }}`. Chosen over `softprops/action-gh-release` because it is the **literal same command** `tools/publish.sh` runs (same-contract rule, P6-D08) and introduces **no third-party action to pin/audit**.
- **Third-party action pinned:** `actions/checkout@v4.2.2` (immutable release tag, never `@main` — T-06-03-01). Hardening to a full commit SHA is a recommended follow-up (the registry API was unreachable offline at execution time, so a verified SHA could not be resolved; a tag pin satisfies the stated mitigation).

## Asset-name contract note (matches Plan 02 byte-for-byte)

`tools/build.sh` `download_release()` and `tools/publish.sh` both compute `asset="wez-$(platform_os)-$(platform_arch)"`, and `platform_os` returns **`macos`** on Darwin (not `darwin`). So the canonical consumer asks for `wez-macos-x86_64` / `wez-macos-aarch64`. The workflow therefore **sources `tools/lib/platform.sh` in the name+checksum step and computes the asset name the same way** — it does NOT interpolate `wez-${{ matrix.os }}-${{ matrix.arch }}` (which would publish `wez-darwin-*` that no consumer ever requests). The matrix `os: darwin` field only selects runners and gates the arm64 codesign step. This keeps local + CI byte-identical (P6-D08). See Deviations.

## Verification scope (NOT a live CI run)

This workflow is **not triggered yet** — no `v*` tag has been pushed. It was verified for **correctness**, not by a live run:
- `bash -n tools/ci-setup-toolchain.sh` → clean; `shellcheck -x tools/ci-setup-toolchain.sh` → clean.
- `release.yml`: **actionlint is uninstallable in this environment** (no `go`, no `brew`, no network). Per the plan's documented fallback, verification used a **YAML structural parse (python3 `yaml.safe_load`)** + the contract greps:
  - YAML parses; `on` = `{push: {tags: [v*]}}`; `permissions` = `{contents: write}`; exactly 3 matrix legs with the `(linux,x86_64,ubuntu-latest)`, `(darwin,x86_64,macos-15-intel)`, `(darwin,aarch64,macos-14)` tuples; 6 ordered steps.
  - `grep -q 'macos-15-intel'` ✓; `grep -c 'macos-13'` = **0** ✓; `tools/build.sh` ✓; `tools/ci-setup-toolchain.sh` ✓; `codesign` ✓; `contents: write` ✓; `gh release upload` + `--clobber` ✓; codesign guarded by `matrix.arch == 'aarch64'` ✓; `actions/checkout@v4.2.2` (not `@main`) ✓.
- **The first `v*` tag (RESEARCH Open Q3) is a follow-up maintainer action** that fires this workflow for the first time; that first real run is the live integration check.

## Task Commits

1. **Task 1: tools/ci-setup-toolchain.sh** — `492f231` (feat)
2. **Task 2: .github/workflows/release.yml** — `7bc2f1c` (feat)

## Files Created/Modified
- `tools/ci-setup-toolchain.sh` — per-runner Lua toolchain install (apt/brew on `platform_os`), version capture, loud-fail-if-luastatic-absent.
- `.github/workflows/release.yml` — tag-triggered 3-leg build+publish matrix; first GitHub Actions workflow in the repo.

## Decisions Made
- `gh release upload --clobber` over `softprops/action-gh-release` (literal same-contract parity, no third-party action to pin).
- Asset name from `platform.sh` at runtime, not matrix literals → emits `wez-macos-*` (consumer name), never `wez-darwin-*`.
- `actions/checkout@v4.2.2` tag pin (SHA hardening noted as follow-up; API offline).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Asset name derived from platform.sh, not from `wez-${{ matrix.os }}-${{ matrix.arch }}` literals**
- **Found during:** Task 2 (release.yml name+checksum step)
- **Issue:** The plan's example name+checksum step used `asset="wez-${{ matrix.os }}-${{ matrix.arch }}"` with `matrix.os: darwin`. That publishes `wez-darwin-x86_64` / `wez-darwin-aarch64`. But the consumer — `tools/build.sh` `download_release()` and `tools/publish.sh` — computes `wez-$(platform_os)-$(platform_arch)`, and `platform_os` returns `macos` on Darwin. So a Mac running the installer / `wez update` would request `wez-macos-*` and **404** against the `wez-darwin-*` assets the literal plan text would have published — a direct same-contract (P6-D08) break.
- **Fix:** The name+checksum step sources `tools/lib/platform.sh` and computes `asset="wez-$(platform_os)-$(platform_arch)"` — byte-identical to publish.sh/build.sh. The matrix `os: darwin` field is retained only to select runners and gate the arm64 codesign `if:`.
- **Files modified:** `.github/workflows/release.yml`
- **Verification:** Confirmed against `tools/publish.sh:50-52` and `tools/build.sh:105-107` (both `wez-$(platform_os)-$(platform_arch)`); Plan 02 SUMMARY's contract section names `wez-macos-aarch64` as a canonical example.
- **Committed in:** `7bc2f1c` (Task 2 commit)

**2. [Rule 3 - Blocking] Removed the literal string `macos-13` from comments to satisfy the `! grep -q 'macos-13'` gate**
- **Found during:** Task 2 verification
- **Issue:** Explanatory comments referenced the removed image by its literal name (`# NOT macos-13`), so the plan's blunt `! grep -q 'macos-13'` acceptance gate failed (2 comment matches) even though `macos-13` was never a runner value.
- **Fix:** Reworded the comments to "the older Intel image (removed 2025-12-04)" — preserving the explanatory intent while driving the `macos-13` count to 0.
- **Files modified:** `.github/workflows/release.yml`
- **Verification:** `grep -c 'macos-13' .github/workflows/release.yml` → 0; plan verify gate → PASS.
- **Committed in:** `7bc2f1c` (Task 2 commit)

**3. [Rule 1 - Bug] Dropped unused `REPO_ROOT` from ci-setup-toolchain.sh**
- **Found during:** Task 1 verification (shellcheck)
- **Issue:** The setup.sh-style header set `REPO_ROOT`, but this script never `cd`s to it → shellcheck SC2034 (unused).
- **Fix:** Removed the `REPO_ROOT` line; kept `SCRIPT_DIR` (used to source `lib/platform.sh`).
- **Files modified:** `tools/ci-setup-toolchain.sh`
- **Verification:** `shellcheck -x tools/ci-setup-toolchain.sh` → clean.
- **Committed in:** `492f231` (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (2 bug, 1 blocking).
**Impact on plan:** Deviation #1 is the load-bearing one — it preserves the P6-D08 same-contract guarantee the plan's literal example would have broken on macOS. #2 and #3 are mechanical (satisfy a blunt grep gate; satisfy shellcheck). No scope creep; both required artifacts delivered.

## Issues Encountered
- **actionlint unavailable + uninstallable** (no `go`, no `brew`, no network). Resolved via the plan's documented fallback: YAML structural parse (python3) + the contract greps. The first real `v*` tag push will exercise the workflow on GitHub's actual runners.
- **GitHub registry API unreachable offline** → could not resolve a verified commit SHA for `actions/checkout`. Pinned to the immutable tag `@v4.2.2` (satisfies T-06-03-01's "tag or SHA, never @main"); SHA hardening noted as a follow-up.

## Threat surface

All mitigations from the plan's `<threat_model>` are applied, no new trust boundaries:
- **T-06-03-01** (compromised third-party Action): `actions/checkout@v4.2.2` pinned (not `@main`); no other third-party action used (chose `gh release upload` over `action-gh-release`).
- **T-06-03-02** (wrong/failed-build asset): `ci-setup-toolchain.sh` fails the leg if `luastatic` is absent (no silent dev-launcher fallback); arm64 leg runs `codesign --verify` before upload.
- **T-06-03-03** (over-broad token): `permissions: { contents: write }` only.
- **T-06-03-04** (unsigned arm64 won't run): ad-hoc `codesign --force --sign -` on the `macos-14` leg; Gatekeeper/quarantine runtime is Phase 7.
- **T-06-03-SC** (luastatic LuaRocks install): real per-runner install + version capture is the legitimacy gate; no npm/pip/cargo installs; no `[SLOP]`/`[SUS]` packages.
- **No command-injection surface:** the workflow interpolates no event payload (issue/PR/comment titles or bodies); the only `${{ }}` expansions are `matrix.*` (statically defined) and `github.token` (passed via `env:`, not inlined into a run command). `$GITHUB_REF_NAME` is the runner-provided tag, used quoted.

## Next Phase Readiness
- Supply side (Plan 02 build/publish + Plan 03 CI) is complete: a `v*` tag now produces all three `wez-<os>-<arch>` assets.
- **Ready for Plan 04** (`tools/install.sh` remote bootstrap) and **Plan 05** (`wez update`) — both consume these published assets.
- **Open Q3 (first `v*` tag)** remains a maintainer action; until a tag is pushed, `download_release()` stays dormant (no assets exist yet), exactly as Plan 02 recorded.
- **macOS legs** are built+signed here; their on-Mac runtime verification (Gatekeeper/quarantine) is the Phase 7 / D-18 gap (per macos-parity backlog).

## Self-Check: PASSED

- FOUND: tools/ci-setup-toolchain.sh (new — apt/brew toolchain + version capture + loud-fail)
- FOUND: .github/workflows/release.yml (new — 3-leg matrix; macos-15-intel; zero macos-13)
- FOUND: .planning/phases/06-installer/06-03-SUMMARY.md
- FOUND: commit 492f231 (Task 1)
- FOUND: commit 7bc2f1c (Task 2)

---
*Phase: 06-installer*
*Completed: 2026-06-14*
