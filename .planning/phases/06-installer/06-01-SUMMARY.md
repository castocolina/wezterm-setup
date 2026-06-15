---
phase: 06-installer
plan: 01
subsystem: installer-spikes
tags: [spike, probe, sha256, github-releases, nightly-datestamp, hypothesis-first]
requires:
  - tools/lib/wezterm-release.sh (_wezterm_fetch curl-or-wget shape)
  - tools/bootstrap-wezterm.sh (wezterm_version_datestamp / wezterm_datestamp_ge)
  - tools/build.sh (download_release SHA256SUMS contract being changed)
provides:
  - "Open Q1 verdict: per-asset updated_at -> YYYYMMDD is the want source for `wez update`"
  - "Open Q2 verdict: per-asset <asset>.sha256 round-trips across sha256sum/shasum, fails on tamper"
affects:
  - tools/build.sh download_release() (Plan 02 contract change)
  - tools/publish.sh (Plan 02 emits per-asset .sha256)
  - cli/commands/update.lua decide_update (Plan 05 want-datestamp comparator)
tech-stack:
  added: []
  patterns:
    - "GitHub releases nightly: per-asset updated_at is fresh; release published_at/created_at are STALE (rolling-tag artifact)"
    - "Portable sha256: command -v sha256sum && sha256sum || shasum -a 256 (identical digest+ordering)"
key-files:
  created:
    - .tmp/h61-nightly-datestamp/repro.md (gitignored)
    - .tmp/h62-perasset-sha256/repro.md (gitignored)
  modified: []
decisions:
  - "Open Q1: want-datestamp = first 8 digits of the OS-base-matched asset's updated_at from releases/tags/nightly; empty fetch -> ge() false -> never force a swap"
  - "Open Q2: per-asset <asset>.sha256 (single line, awk '{print $1}'); replaces combined SHA256SUMS grep; portable recompute for macOS"
metrics:
  duration: ~2.5 min
  completed: 2026-06-14
---

# Phase 6 Plan 01: Spike-First Probes (Open Q1 + Open Q2) Summary

Two `.tmp/` hypothesis probes de-risk the RESEARCH open questions before Plans 02 and 05
build on them: the cheapest "latest nightly datestamp" query (Open Q1) and the per-asset
`<asset>.sha256` generate+verify contract (Open Q2). Both probes ran against REAL upstream
(`wez/wezterm` GitHub) and real system tools, each landing a parseable `verdict:` line.
Probe-only — no `cli/` or `tools/` source was touched.

## Verdicts (the durable record Plans 02/05 cite)

### Open Q1 — latest-nightly-datestamp query: `verdict: holds-with-caveat`

- **Chosen `want` source:** `GET api.github.com/repos/wez/wezterm/releases/tags/nightly`
  (via `_wezterm_fetch`), select the asset matching the install's OS base
  (`wezterm-nightly.Ubuntu<base>.tar.xz` / `WezTerm-macos-nightly.zip`), take the first 8
  digits of THAT asset's `updated_at` -> `YYYYMMDD`. Real capture: Ubuntu24.04 asset
  `updated_at=2026-06-14T04:57:06Z` -> `20260614`.
- **Cross-checked** against a HEAD `last-modified` on the asset URL (`Sun, 14 Jun 2026
  04:57:06 GMT` -> `20260614`) — byte-identical to the API value. API query chosen as
  cheapest/most-stable (single request; no 301->302 signed-URL JWT redirect chain; no
  `date -d` parse dependency).
- **Composes** with the existing `wezterm_datestamp_ge "$want" "$have"` verbatim:
  `want=20260614 >= have=20260604` -> "offer update".
- **Caveat (why not plain holds):** MUST use the **per-asset `updated_at`**, NEVER the
  release-level `published_at`/`created_at` — those are frozen at the rolling tag's
  2017/2019 creation and would falsely report "never newer". And the asset MUST be selected
  by OS base (Ubuntu20.04 lags 24.04 by months; 16.04 is abandoned).
- **Graceful degradation (T-06-01-01):** a failed/garbage fetch yields empty `want`;
  `wezterm_datestamp_ge` guards each arg with `[ -n ... ]` so it returns false -> "assume
  current / never force a swap". Verified with a 404-tag fetch (rc=22, 0 bytes).

### Open Q2 — per-asset `.sha256` contract: `verdict: holds`

- Per-asset `<asset>.sha256` generates as **exactly one line** (`'<64-hex>  <name>'`).
- The SAME bytes produce an **IDENTICAL 64-hex digest** under `sha256sum` and
  `shasum -a 256` (`b44b86fa...db174ffa`), same field ordering -> `awk '{print $1}'` works
  for either (Pitfall 4 portability holds).
- **Cross-host `-c` verify in both directions** returns rc=0 (sha256sum verifies a
  shasum-generated file and vice-versa).
- **Tamper fails:** appending one byte changes the digest; `sha256sum -c` returns rc=1
  ("did NOT match") BEFORE any `chmod +x` — the abort-on-mismatch guard (T-01-01 /
  T-06-01-02) survives the contract change.
- **Parse change for Plan 02:** `sums_url` -> `${...}/${asset}.sha256`; replace the
  `grep -E "  ${asset}\$..."` at build.sh:138 with `awk '{print $1}'` over the single line;
  make recompute portable via `command -v sha256sum && sha256sum || shasum -a 256`.

## Tasks

| Task | Name | Result | Artifact (gitignored) |
| ---- | ---- | ------ | --------------------- |
| 1 | Probe latest-nightly-datestamp query (Open Q1) | holds-with-caveat | `.tmp/h61-nightly-datestamp/repro.md` |
| 2 | Probe per-asset `.sha256` generate+verify (Open Q2) | holds | `.tmp/h62-perasset-sha256/repro.md` |
| 3 | checkpoint:human-verify (gate=blocking) | STOPPED — awaiting ratification | — |

## Deviations from Plan

None — plan executed exactly as written. Both probes were probe-only; `git status --porcelain
cli tools` is clean and `git diff --stat tools/build.sh` is empty.

## Note on artifacts (intentional, by design)

Both `repro.md` files live under `.tmp/` which is **gitignored** (hypothesis-first rule R5,
`docs/agent-iteration.md`). They are NOT committed — they remain as real files on the main
working tree for the human checkpoint (Task 3) to read. This SUMMARY is the durable,
committed record of their verdicts. The probe dirs are deleted on manual promotion per R5.

## Self-Check: PASSED

- FOUND: `.tmp/h61-nightly-datestamp/repro.md` (verdict: holds-with-caveat)
- FOUND: `.tmp/h62-perasset-sha256/repro.md` (verdict: holds)
- FOUND: `.planning/phases/06-installer/06-01-SUMMARY.md`
- `git diff --stat tools/build.sh` empty; `git status --porcelain cli tools` clean (probe-only invariant held)
