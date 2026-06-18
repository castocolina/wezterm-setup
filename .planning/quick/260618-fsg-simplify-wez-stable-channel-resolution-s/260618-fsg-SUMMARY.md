---
quick: 260618-fsg
slug: simplify-wez-stable-channel-resolution
subsystem: tools/build.sh (release-channel resolver)
tags: [refactor, build, channel-resolution, no-jq, entropy-reduction]
key-files:
  modified:
    - tools/build.sh
    - tests/cli/build_channel_test.lua
commit: 0c78694
completed: 2026-06-18
---

# Quick 260618-fsg: Simplify wez stable-channel resolution Summary

Collapsed the stable-channel resolution in `tools/build.sh` to a single network
fetch per path and a single shared JSON extractor — eliminating the copy-pasted
no-jq idiom and the redundant double fetch, ending with net LESS code (486 → 479).

## What changed

### tools/build.sh (486 → 479 lines, delta **-7**)

- **`_json_str <field>` (NEW, generic extractor):** reads JSON on stdin, takes a
  literal field name, echoes the first top-level string value of that field. The
  single factored-out form of the idiom that was copy-pasted across the old
  `resolve_stable_tag` (tag_name) and `resolve_stable_date` (published_at).
- **`resolve_stable_latest()` (NEW, single fetch):** does ONE `_api_fetch` of the
  latest-release API and yields BOTH the tag (line 1, required → non-zero if
  absent) and the YYYY-MM-DD date (line 2, best-effort, possibly empty) from that
  one payload. Reuses `_api_fetch` + `_json_str` — no third fetcher, no duplicate
  idiom. A missing/unparseable `published_at` leaves the date empty and NEVER
  aborts (`grep ... || true` under `set -e`/pipefail).
- **`resolve_stable_tag()` (THIN delegate):** now `resolve_stable_latest | head -n1`,
  guarded non-empty, echoes ONLY the bare tag. Frozen output contract intact (it
  feeds `download_release`'s `${WEZ_RELEASE_BASE}/${tag}/${asset}` URL); no
  `published_at`, no date logic.
- **`resolve_stable_date()` (DELETED):** the duplicate fetcher is gone — no
  back-compat wrapper.
- **Interactive picker (single fetch):** the stable arm now makes ONE
  `resolve_stable_latest` call, split into `stable_tag` (`sed -n 1p`) +
  `stable_date` (`sed -n 2p`). The date-augmented label
  `newest stable (${stable_tag} · ${stable_date})` (exact U+00B7 byte sequence
  0xC2 0xB7, copied verbatim) is emitted when the date is present, the tag-only
  label otherwise. The old separate `resolve_stable_date` fetch is gone.
- **`list_nightly_tags()`:** left AS-IS (one-line comment added explaining why it
  cannot cleanly reuse `_json_str` — it needs ALL `nightly-*` values as a list,
  not the first single top-level string).
- **Single-fetch guard upkeep:** reworded comments + the `stable` no-TTY `log`
  string to refer to "the latest-release API" instead of the literal
  `releases/latest` substring, so the literal appears EXACTLY ONCE (the single
  fetch site in `resolve_stable_latest`). Also reworded the `_json_str` header
  from "no-jq JSON" to "no external JSON tool" so the `jq ` substring guard holds.

### tests/cli/build_channel_test.lua

- Migrated the `resolve_stable_date` block to `resolve_stable_latest`: full-payload
  case asserts BOTH lines (tag `v0.1.0`, date `2026-06-15`).
- NEW missing-date regression (closes /code-review Minor 2): a tag-but-no-
  `published_at` payload returns 0, line 1 is the tag, line 2 is empty.
- Failed-fetch case: stubbed `_api_fetch` returning 1 → non-zero.
- TEXT guards: `_json_str` defined + reused inside `resolve_stable_latest`;
  `resolve_stable_latest` reuses the latest-release endpoint + `_api_fetch` +
  `_json_str` with no jq; `resolve_stable_date` is GONE; the picker references
  `resolve_stable_latest` and NOT `resolve_stable_date`; exactly one
  `releases/latest` site (`select(2, SRC:gsub("releases/latest", "")) == 1`);
  `resolve_stable_tag` delegates + stays bare-tag-only (no `published_at`).
- Pre-existing channel/no-TTY/checksum-gate assertions untouched.

## Verification (recorded, actual output)

```
$ bash -n tools/build.sh
OK exit 0

$ shellcheck -x tools/build.sh
CLEAN exit 0

$ grep -c 'releases/latest' tools/build.sh
1

$ grep -c 'resolve_stable_date' tools/build.sh
0

$ grep -q '_json_str' tools/build.sh && grep -q 'resolve_stable_latest' tools/build.sh
both FOUND

$ wc -l tools/build.sh
479    (was 486 — delta -7)

$ lua5.4 tests/cli/build_channel_test.lua
44 passed, 0 failed   (exit 0)

$ bash -c 'source tools/build.sh; resolve_stable_latest'
v0.1.0
2026-06-15
exit=0

$ ./tools/run-tests.sh
run-tests: 1 file(s) failed  (ONLY cli/lib/recipe_test.lua "2.9d ai.toml" —
  recipe_test: 64 passed, 1 failed)
```

The single `run-tests.sh` failure is the known out-of-scope baseline
`cli/lib/recipe_test.lua` "2.9d ai.toml". Confirmed it reproduces with my two
files stashed (`git stash push tools/build.sh tests/cli/build_channel_test.lua`
→ `recipe_test: 64 passed, 1 failed`), i.e. it is pre-existing and NOT caused by
this change. Not fixed (scope boundary).

## Deviations from Plan

**[Rule 3 - Blocking] Reworded pre-existing `releases/latest` comment/log mentions.**
- **Found during:** Task 1 verification — `grep -c 'releases/latest'` returned 7,
  but the single-fetch guard requires exactly 1.
- **Fix:** Reworded 5 pre-existing comment lines + 1 `log` string (top-of-file
  usage block, channel comment, resolver header, no-TTY stable log) to say "the
  latest-release API" instead of the literal `releases/latest` substring. The one
  remaining literal is the actual fetch URL in `resolve_stable_latest`.
- **Why:** required for the `grep -c == 1` and Lua `gsub == 1` single-fetch guards
  to be accurate; explicitly anticipated by the task constraints.

**[Rule 1 - Bug] Missing-date path aborted under `set -e`.**
- **Found during:** Task 2 (test RED) — the missing-date case returned non-zero
  with empty output.
- **Issue:** the date `grep -oE` found no match → exit 1; under `set -e`/pipefail
  the failing command substitution made `resolve_stable_latest` return before
  `printf`, violating the "never abort on a missing date" contract.
- **Fix:** appended `|| true` to the date pipeline so a no-match leaves the date
  empty without aborting.

**[Rule 1 - Bug] `jq ` substring leaked into a comment.**
- **Found during:** Task 2 — the pre-existing "does NOT add a jq dependency" TEXT
  guard failed because the new `_json_str` header read "no-jq JSON" (contains the
  literal `jq ` = jq + space).
- **Fix:** reworded the header to "no external JSON tool".

No architectural changes. No `~/.config/wezterm/wezterm.lua` or `scenes/` source
edits. No new dependency (no `jq`). Single `_api_fetch` (no third fetcher). Pure
bash glue, sudo-free, Linux+macOS portable, no GNU-only flags.

## Self-Check: PASSED

- FOUND: tools/build.sh (modified, 479 lines)
- FOUND: tests/cli/build_channel_test.lua (modified, 44 assertions green)
- FOUND: commit 0c78694
