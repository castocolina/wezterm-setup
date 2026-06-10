---
phase: 01-foundation
plan: 02
subsystem: installer-bootstrap
tags: [bash, wezterm, bootstrap, tarball, sudo-free, github-releases, install]
requires:
  - "Phase 0 D-04/D-05 emulator-install decision (sudo-free .tar.xz to ~/.local, NOT AppImage)"
  - "Plan 01 tools/lib/platform.sh (shared OS/arch/Ubuntu-base detector)"
  - "wezterm-cli-surface audit (pinned known-good release 20260604-145453)"
provides:
  - "tools/bootstrap-wezterm.sh: detect+reuse-if-adequate, else fetch/extract/symlink sudo-free (INST-06)"
  - "tools/lib/wezterm-release.sh: GitHub releases listing (nightly + last 5 dated) + asset-URL builder, pinned-default degradation"
  - "Pinned minimum-version reuse gate + non-TTY pinned default (D-07/D-08)"
  - "Integrity + path-traversal extraction gates (T-02-01/T-02-02)"
affects:
  - "Plan 04 installer: the bootstrap guarantees a usable wezterm before config sentinel injection"
  - "Deferred Mac pass: macOS .app -> ~/Applications branch is present-but-deferred (D-06/D-18)"
tech-stack:
  added: []
  patterns:
    - "Detection-first non-destructive bootstrap: reuse an adequate install untouched, never modify a system install"
    - "Pre-extract integrity gates (xz magic + size sanity) and member validation (no absolute / '..') before tar -xJf"
    - "Sourceable bootstrap: main() runs only when executed, individual steps exposed when sourced for fetch-path testing"
    - "Graceful API degradation to a pinned reproducible default (T-02-04 accept)"
key-files:
  created:
    - tools/bootstrap-wezterm.sh
    - tools/lib/wezterm-release.sh
    - docs/repro/h-inst06-bootstrap.md
  modified: []
decisions:
  - "Bootstrap installs the emulator sudo-free via generic .Ubuntu<base>.tar.xz -> ~/.local/opt/wezterm/<tag>/, symlink ~/.local/bin/wezterm; never AppImage/FUSE/sudo (D-04/D-05)"
  - "Detection-first reuse: an existing wezterm at or above the pinned minimum 20260604-145453 is reused untouched; system installs are never modified (D-07)"
  - "Version model = one rolling nightly + last 5 dated releases (TTY selector); non-TTY uses pinned 20260604-145453 for reproducibility (D-08)"
  - "Date-stamp (leading YYYYMMDD) is the monotonic version comparator for the minimum-version gate"
  - "macOS .app branch is design-only / deferred to the Mac pass (D-06/D-18)"
requirements-completed: [INST-06]
metrics:
  duration: ~6 min
  completed: 2026-06-09
  tasks: 2
  files: 3
---

# Phase 1 Plan 02: Sudo-free WezTerm Emulator Bootstrap (INST-06) Summary

Detection-first, sudo-free WezTerm emulator bootstrap that reuses an adequate existing install untouched and otherwise downloads the generic `.Ubuntu<base>.tar.xz` into `~/.local` and symlinks the binary onto PATH — no AppImage, no FUSE, no sudo (D-04..D-08).

## What Was Built

- **`tools/lib/wezterm-release.sh`** (Task 1, committed `5af3301`) — sourceable helper exposing `wezterm_release_list` (rolling `nightly` + last 5 dated GitHub releases, degrading to the pinned `20260604-145453` default when the API is unreachable/rate-limited/unparseable, T-02-04), `wezterm_release_asset_url <tag> <base>` (builds the official-host HTTPS `.Ubuntu<base>.tar.xz` URL, T-02-05), and `wezterm_release_archive_binary_path` (the probe-01-confirmed in-archive path `wezterm/usr/bin/wezterm`). The releases-JSON parser tolerates control-char-laced release bodies (probe 02 gotcha) via a temp-file python parse with a `tag_name`-only regex fallback.
- **`tools/bootstrap-wezterm.sh`** (Task 2, committed `b2db8e6`) — sources `platform.sh` + `wezterm-release.sh` and runs the four-step flow: (1) **DETECT/REUSE** — parse `wezterm --version`, compare the leading-8-digit date stamp against the pinned minimum, and reuse an adequate install untouched (never modifying a system install, D-07); (2) **SELECT** — TTY presents the release list and reads a numeric pick, non-TTY selects the pinned `20260604-145453` (D-08); (3) **FETCH/EXTRACT/SYMLINK** — download, integrity-check (xz magic + size sanity, T-02-01), refuse absolute/`..` members (T-02-02), extract into a fresh `~/.local/opt/wezterm/<tag>/` with `--no-absolute-names`, symlink the binary into `~/.local/bin`, and verify it runs; (4) **macOS** — a clearly-labelled design-only `.app` -> `~/Applications` branch deferred to the Mac pass (D-06/D-18).
- **`docs/repro/h-inst06-bootstrap.md`** — promoted R2 repro: manual steps plus the observed Linux evidence (the reuse path firing on this host) and the probe-backed coverage note for the fetch path.

## How It Works

`main()` runs only when the script is EXECUTED; sourcing exposes the individual steps so the fetch path can be exercised without the reuse short-circuit. On a host that already has an adequate WezTerm, `detect_and_reuse` returns 0 and the script exits without any download. Otherwise the OS detection routes to `install_linux` (verified) or the deferred `install_macos`, the selector resolves a release tag, and the Linux installer fetches/verifies/extracts/symlinks the binary, gating every untrusted byte before extraction per the threat register.

## Verification

Run on this Linux host (which has a system WezTerm `20260604-145453-eeb80972` at exactly the pinned minimum), the non-interactive bootstrap detected and reused it untouched and exited 0:

```
$ bash tools/bootstrap-wezterm.sh < /dev/null
[bootstrap] existing WezTerm 'wezterm 20260604-145453-eeb80972' meets minimum 20260604-145453 — reusing it untouched (D-07)
[bootstrap] note: reused install is outside /home/user-zero/.local/bin (likely a system/managed install); leaving it intact
exit=0
$ wezterm --version
wezterm 20260604-145453-eeb80972
```

- Forbidden-reference gate: `rg -v '^\s*#' tools/bootstrap-wezterm.sh | rg -ci 'sudo|appimage|fuse'` -> `0`.
- `rg -c '20260604-145453' tools/bootstrap-wezterm.sh` -> `1`; `rg -c Applications` -> `3` (macOS branch present).
- Sourcing exposes `detect_and_reuse`, `select_release`, `install_linux`, `verify_tarxz` as functions without running `main`.
- `shellcheck -x tools/bootstrap-wezterm.sh` -> clean (no findings).
- Probe 01 (`holds`): in-archive binary at the fixed path `wezterm/usr/bin/wezterm`, no traversal members. Probe 02: releases-API shape + asset pattern, with pinned-default degradation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused `REPO_ROOT` variable in bootstrap**
- **Found during:** Task 2 verification (`shellcheck -x`)
- **Issue:** `REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"` was dead code (SC2034); only `SCRIPT_DIR` is used to source the libs.
- **Fix:** Deleted the unused assignment so shellcheck is clean.
- **Files modified:** `tools/bootstrap-wezterm.sh`
- **Commit:** `b2db8e6`

## Notes on Resumption

This plan was resumed mid-execution: Task 1 (`tools/lib/wezterm-release.sh` + the two R6 probes) was already complete and committed (`5af3301`) and was left intact. Task 2's `tools/bootstrap-wezterm.sh` existed as an untracked, nearly-complete draft; it was reconciled against the Task 2 spec, shellcheck-cleaned, verified against the live host, completed with the missing `docs/repro/h-inst06-bootstrap.md` artifact, and committed atomically (`b2db8e6`). The R6 probe files live under the gitignored `.tmp/probes/phase-1/` per the hypothesis playbook (scratch, deleted post-promotion) and are intentionally not committed.

## Deferred / Not Verified On Linux

- The fresh-install fetch/extract/symlink path is probe-backed and shellcheck-clean but not exercised on this reuse host — to be re-verified on a host without an adequate WezTerm.
- The macOS `.app` -> `~/Applications` branch is design-only, deferred to the batched Mac pass (D-06/D-18).

## Self-Check: PASSED

All created files exist on disk (`tools/bootstrap-wezterm.sh`, `tools/lib/wezterm-release.sh`, `docs/repro/h-inst06-bootstrap.md`, `01-02-SUMMARY.md`) and both task commits are reachable in git history (`5af3301`, `b2db8e6`).
