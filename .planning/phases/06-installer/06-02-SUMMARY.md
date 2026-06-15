---
phase: 06-installer
plan: 02
subsystem: installer-supply
tags: [build, publish, github-releases, sha256, asset-contract, macos-portable, wiring]
requires:
  - tools/build.sh download_release() (the dormant release-download path repointed)
  - tools/lib/platform.sh (platform_os / platform_arch — the asset-name source)
  - .planning/phases/06-installer/06-01-SUMMARY.md (Open Q2 per-asset .sha256 verdict)
provides:
  - "WEZ_RELEASE_BASE=https://github.com/castocolina/wezterm-setup/releases/download (placeholder github.com/you/ removed)"
  - "download_release() verifies per-asset <asset>.sha256 portably (sha256sum|shasum -a 256) BEFORE chmod +x"
  - "tools/publish.sh: build -> name wez-<os>-<arch> -> <asset>.sha256 -> gh release upload <tag> wez-<os>-<arch> wez-<os>-<arch>.sha256 --clobber"
  - "make build / make publish first-class targets"
  - "The byte-for-byte asset + checksum contract release.yml (Plan 03) must match"
affects:
  - .github/workflows/release.yml (Plan 03 — must emit the IDENTICAL asset name + per-asset .sha256 + same gh upload command)
  - tools/install.sh + cli/commands/update.lua (Plans 04/05 — consume the published wez-<os>-<arch> asset)
tech-stack:
  added: []
  patterns:
    - "Same-contract rule (P6-D08): asset name wez-$(platform_os)-$(platform_arch) computed identically in build.sh, publish.sh, and (Plan 03) release.yml so local + CI never drift"
    - "Portable digest: command -v sha256sum && sha256sum || shasum -a 256 (macOS has no sha256sum)"
    - "Per-asset <asset>.sha256: single line, parse with awk '{print $1}' (no grep-for-asset)"
    - "Verify BEFORE chmod +x; abort non-zero on mismatch/missing checksum (T-01-01)"
key-files:
  created:
    - tools/publish.sh
    - tests/cli/publish_test.lua
  modified:
    - tools/build.sh
    - Makefile
decisions:
  - "WEZ_RELEASE_BASE default repointed github.com/you/... -> github.com/castocolina/wezterm-setup/releases/download"
  - "WEZ_RELEASE_TAG left at v0.1.0 (Open Q3 deferred: Plan 01 SUMMARY ratified Open Q1/Q2 only, no tag) — overridable via env"
  - "publish.sh ad-hoc codesigns ONLY on macos+aarch64 (Pattern 7); other platforms skip"
  - "publish_test.lua asserts the asset-name/clobber/codesign contract on the SCRIPT TEXT (shell glue has no Lua entry point — project 'assert script TEXT' convention)"
metrics:
  duration: ~2.5 min
  completed: 2026-06-14
---

# Phase 6 Plan 02: INST-08 Supply Side (build/publish + per-asset .sha256) Summary

Wired the INST-08 SUPPLY side that the remote installer (Plan 04) and `wez update` (Plan 05)
consume: repointed `tools/build.sh`'s dormant release-download path to the real `castocolina`
URL, adopted the per-asset `<asset>.sha256` contract ratified in Plan 01 (Open Q2), made the
checksum verify portable for macOS, added a thin `tools/publish.sh` that names + checksums +
uploads `wez-<os>-<arch>` via the same `gh release upload --clobber` command CI will use, and
exposed `make build` / `make publish`. ~All wiring of existing tested glue — one new thin
shell script + one contract test, the rest minimal edits. All on the correct side of the D-01
bash/Lua boundary (no decision logic in shell or Makefile).

## The release-asset contract (the durable record Plan 03's release.yml must match byte-for-byte)

- **Release base:** `WEZ_RELEASE_BASE = https://github.com/castocolina/wezterm-setup/releases/download` (overridable; `github.com/you/` placeholder fully removed).
- **Release tag:** `WEZ_RELEASE_TAG = v0.1.0` (default; overridable via env). Left unchanged — Open Q3 (bump to first real tag) is DEFERRED because Plan 01's SUMMARY ratified Open Q1 + Open Q2 only and did NOT ratify a tag. `make publish` and CI both honor `WEZ_RELEASE_TAG` so the first real release just sets it.
- **Asset name:** `wez-$(platform_os)-$(platform_arch)` — e.g. `wez-linux-x86_64`, `wez-macos-aarch64`. Computed identically in `build.sh` `download_release()` (build.sh:104-106), `tools/publish.sh`, and (Plan 03) `release.yml`. NO hardcoded os/arch literals anywhere.
- **Per-asset checksum:** `<asset>.sha256` — a single line `'<64-hex>  <name>'`. Generate portably (`sha256sum` or `shasum -a 256`); parse the consumer side with `awk '{print $1}'` over that one line. Replaces the old combined `SHA256SUMS` grep.
- **Upload command (same-contract rule, P6-D08):** `gh release upload "${WEZ_RELEASE_TAG}" wez-<os>-<arch> wez-<os>-<arch>.sha256 --clobber` — the literal command `make publish` and CI both run.
- **Apple Silicon:** `publish.sh` ad-hoc-codesigns (`codesign --force --sign - dist/wez`) ONLY on macos+aarch64 (Pattern 7) before checksumming.
- **Verify-before-exec (T-01-01):** `download_release()` fetches `<asset>.sha256`, recomputes the digest portably, compares, and aborts non-zero on mismatch or missing checksum — all BEFORE `chmod +x`.

## Tasks

| Task | Name | Result | Commit |
| ---- | ---- | ------ | ------ |
| 1 | Repoint build.sh release base + per-asset .sha256 + portable verify | done | 710cccb |
| 2 | Add tools/publish.sh + asset-name contract test (publish_test.lua) | done | 5c8efda |
| 3 | Wire make build + make publish targets | done | ad01245 |

## Verification

- `bash -n tools/build.sh` and `bash -n tools/publish.sh` both exit 0.
- `shellcheck -x` clean on both `tools/build.sh` and `tools/publish.sh` (shellcheck present).
- `grep -c 'github.com/you/' tools/build.sh` is 0; `castocolina`, per-asset `.sha256`, and `shasum -a 256` all present; no combined `SHA256SUMS` in non-comment lines.
- Verify-before-chmod ordering preserved: `checksum verified` (build.sh:156) precedes the download_release `chmod +x` (build.sh:161).
- `lua5.4 tests/cli/publish_test.lua` → 14 passed, 0 failed (asset-name + `--clobber` + codesign + portable-checksum contract asserted on the script text).
- `./tools/run-tests.sh` → all 18 files passed (publish_test.lua discovered + green; no regressions; was 17 before).
- `make -n build` → `./tools/build.sh`; `make -n publish` → `./tools/publish.sh`; `make help` lists both; `make -n install` still dispatches to `./tools/setup.sh`.
- `make build` exercised end-to-end → produced a runnable `dist/wez` (`wez 0.1.0`) via the dev-launcher path (luastatic absent on this host). `dist/wez` is gitignored — not leaked into the commit.

## Note on `make publish` verification scope (intentional)

The first `v*` release does NOT exist yet (known interim state). Per the plan's key constraints,
`make publish` was verified for **SCRIPT CORRECTNESS ONLY** — `bash -n`, `shellcheck -x`, `make -n
publish` dry-run dispatch, and the `publish_test.lua` text-contract assertions. **No live `gh
release upload` was attempted** against a non-existent release (it would 404). The first real
publish happens once a `v*` tag + release exists; `make publish` / `WEZ_RELEASE_TAG=v… make
publish` is then the one command.

## Deviations from Plan

None — plan executed exactly as written. The only judgment call (Open Q3 tag bump) was resolved
by the plan's own instruction: leave `v0.1.0` and note it because Plan 01's SUMMARY ratified no
tag. The header doc-comment in `build.sh` describing the old `github.com/you/` placeholder was
updated alongside the code change so the comment does not contradict the repointed default (Rule
1 — keep the comment truthful; same task, same commit).

## Threat surface

No new trust boundaries beyond the plan's `<threat_model>`. The two boundaries (maintainer host
→ GitHub Releases via `gh release upload`; installer host → GitHub Releases via `download_release()`)
are exactly as registered. Mitigations applied: T-06-02-01 (per-asset `.sha256` verify before
`chmod +x`, single-line parse), T-06-02-02 (asset name from the closed platform_os/platform_arch
set — a missing asset 404s, never a silent wrong-binary fallback), T-06-02-03 (arm64-macOS ad-hoc
codesign). No language-registry installs (T-06-02-SC).

## Self-Check: PASSED

- FOUND: tools/build.sh (modified — castocolina + per-asset .sha256 + portable verify)
- FOUND: tools/publish.sh (new — asset name + sha256 + gh upload --clobber + codesign guard)
- FOUND: tests/cli/publish_test.lua (new — 14/14 green)
- FOUND: Makefile (modified — build + publish targets + help)
- FOUND: commit 710cccb (Task 1)
- FOUND: commit 5c8efda (Task 2)
- FOUND: commit ad01245 (Task 3)
