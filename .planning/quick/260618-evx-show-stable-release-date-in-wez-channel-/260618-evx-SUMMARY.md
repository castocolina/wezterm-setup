---
quick_id: 260618-evx
slug: show-stable-release-date-in-wez-channel
phase: quick-260618-evx
plan: 01
type: execute
status: complete
completed: "2026-06-18"
commit: 501fca2
files_modified:
  - tools/build.sh
  - tests/cli/build_channel_test.lua
requirements: [QUICK-260618-evx]
---

# Quick 260618-evx: Show Stable Release Date in `wez` Channel Picker Summary

One-liner: The interactive `wez`-CLI channel picker now shows the stable
release date next to the tag (`newest stable (v0.1.0 · 2026-06-15)`) via a
best-effort `resolve_stable_date()` that reuses the existing `/releases/latest`
fetch — display-only, with a tag-only fallback and zero impact on the download
path.

## What Changed

### `tools/build.sh`

1. **New `resolve_stable_date()` helper** (placed directly after
   `resolve_stable_tag()`):
   - GETs the SAME endpoint `resolve_stable_tag()` reads —
     `_api_fetch "${WEZ_RELEASE_API}/repos/${WEZ_RELEASE_REPO}/releases/latest"`
     (reuses `_api_fetch`, no third fetcher).
   - Extracts `published_at` with the existing no-jq idiom (split on commas,
     grep the `"published_at"…` token, head -n1, strip to the inner quoted
     value) then isolates the leading `YYYY-MM-DD` with a pure
     `grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'` — no `date`/`cut -dT`, so it stays
     Linux+macOS portable with no GNU-only flags.
   - Best-effort contract: on a failed fetch / empty JSON / no parseable date it
     echoes NOTHING and `return 1` (mirrors `resolve_stable_tag`'s shape;
     callers use `|| true`). NEVER aborts the picker.

2. **Date-augmented stable picker label** in `resolve_channel_tag()`'s
   interactive block: a local `stable_date` is resolved tolerantly
   (`resolve_stable_date 2>/dev/null || true`); when non-empty the label becomes
   `newest stable (${stable_tag} · ${stable_date})` (U+00B7 MIDDLE DOT separator,
   UTF-8 literal), otherwise it falls back to the existing
   `newest stable (${stable_tag})`.

**Hard constraints honored:**
- `resolve_stable_tag()` body is byte-unchanged (bare-tag-only download contract
  preserved; no `published_at` in it).
- No new fetch on the non-TTY `download_release` hot path — the date fetch lives
  ONLY in the interactive (`-t 0`) picker branch.
- Pure bash glue, sudo-free, no new dependency (no jq), single `_api_fetch`.
- No `~/.config/wezterm/wezterm.lua` or `scenes/` changes.

### `tests/cli/build_channel_test.lua`

+14 sourced-no-run regression assertions (37 total, all green):
- BEHAVIOR: stubbed `_api_fetch` returning the live-shaped sample JSON →
  `resolve_stable_date` echoes exactly `2026-06-15`.
- BEHAVIOR: failed fetch → non-zero exit AND empty stdout (best-effort, never
  aborts).
- TEXT: helper defined; reuses `/releases/latest` + `_api_fetch`; no jq; extracts
  `published_at`.
- TEXT: interactive resolver references `resolve_stable_date` and builds the
  date-bearing label, with the tag-only fallback surviving.
- TEXT contract guard: `resolve_stable_tag` body still extracts `tag_name`,
  still echoes the bare tag, and has NO `published_at`.

## Verification (recorded, no "should work")

### `bash -n tools/build.sh`
```
bash-n exit=0
```

### `shellcheck -x tools/build.sh`
```
shellcheck exit=0
```
Clean — no NEW warnings vs. the pre-change baseline (baseline was also exit 0,
no output).

### `lua5.4 tests/cli/build_channel_test.lua`
```
37 passed, 0 failed
exit=0
```
(All 23 pre-existing channel assertions + the 14 new `resolve_stable_date`
behavior/label/contract assertions.)

### `./tools/run-tests.sh`
```
run-tests: 1 file(s) failed
RUNTESTS_EXIT=1
```
The ONLY failure is the known out-of-scope baseline:
```
FAIL: 2.9d ai.toml maps to the D-03/D-05/D-14 args (...)
recipe_test: 64 passed, 1 failed
FAIL  cli/lib/recipe_test.lua
```
This is the pre-existing `cli/lib/recipe_test.lua` "2.9d ai.toml" failure from
commit 723af62 (logged in `deferred-items.md`), in a file NOT touched by this
change. Confirmed independent: with my two files stashed,
`lua5.4 tests/cli/lib/recipe_test.lua` still exits 1. NOT fixed (scope boundary).
The `bash -n` + `shellcheck -x` gate over `tools/build.sh` passes inside the
suite (`PASS  bash -n tools/build.sh` / `PASS  shellcheck -x tools/build.sh`), and
`build_channel_test.lua` is green within the suite run.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Commit

| Hash | Message |
|------|---------|
| `501fca2` | feat(quick-260618-evx): show stable release date in wez channel picker |

Single atomic code commit (both `tools/build.sh` + `tests/cli/build_channel_test.lua`)
per project commit-discipline. Docs artifacts (this SUMMARY, STATE, PLAN) are NOT
in this commit — the orchestrator commits docs afterward. Pre-existing unrelated
`scenes/ai.toml` working-tree modification was left untouched.

## Self-Check: PASSED

- FOUND: tools/build.sh (modified, `resolve_stable_date` present)
- FOUND: tests/cli/build_channel_test.lua (modified, +14 assertions)
- FOUND: commit 501fca2 in git log
