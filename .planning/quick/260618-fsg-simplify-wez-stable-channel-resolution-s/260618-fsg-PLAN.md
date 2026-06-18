---
phase: quick-260618-fsg
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - tools/build.sh
  - tests/cli/build_channel_test.lua
autonomous: true
requirements: [QUICK-260618-fsg]

must_haves:
  truths:
    - "One generic no-jq JSON string extractor exists (`_json_str <field>`, reads JSON on stdin, echoes the first top-level string value) and is REUSED — the copy-pasted `tr ',' '\\n' | grep -oE ... | head -n1 | grep -oE | tr -d '\"'` idiom is no longer duplicated across resolve_stable_tag + resolve_stable_date."
    - "A single `resolve_stable_latest()` does ONE `_api_fetch` of `/releases/latest` and yields BOTH the tag (line 1) and the YYYY-MM-DD date (line 2, possibly empty) from that one payload."
    - "`resolve_stable_tag()` is THIN — it delegates to resolve_stable_latest, propagates non-zero on failure, and echoes ONLY the bare tag (output contract for download_release's URL is unchanged)."
    - "The standalone `resolve_stable_date()` fetcher is ELIMINATED (no thin back-compat wrapper kept)."
    - "Exactly ONE `_api_fetch` per resolution path — the non-TTY download path = 1 fetch (resolve_stable_tag -> resolve_stable_latest); the interactive picker = 1 fetch (resolve_stable_latest once, split into tag + date). No path fetches /releases/latest twice."
    - "The interactive stable label is `newest stable (tag MIDDLEDOT date)` (exact UTF-8 U+00B7 separator) when the date is non-empty, else `newest stable (tag)`."
    - "Net result is LESS total code than today (the duplicate fetcher + duplicate idiom are gone)."
  artifacts:
    - path: "tools/build.sh"
      provides: "Generic _json_str extractor + single-fetch resolve_stable_latest + thin resolve_stable_tag delegate + single-fetch picker; resolve_stable_date deleted"
      contains: "resolve_stable_latest"
    - path: "tests/cli/build_channel_test.lua"
      provides: "Migrated + new sourced-no-run assertions: resolve_stable_latest yields tag+date from one stubbed payload; missing-date case (tag present, empty date, non-abort); failed fetch non-zero; TEXT guards on _json_str reuse, single picker fetch, bare-tag-only resolve_stable_tag, no jq"
      contains: "resolve_stable_latest"
  key_links:
    - from: "tools/build.sh resolve_stable_tag()"
      to: "resolve_stable_latest()"
      via: "capture line 1 (tag), propagate non-zero, echo bare tag only"
      pattern: "resolve_stable_latest"
    - from: "tools/build.sh resolve_channel_tag() interactive picker block"
      to: "resolve_stable_latest()"
      via: "single call, split into tag+date, build the MIDDLEDOT-augmented label"
      pattern: "resolve_stable_latest"
    - from: "tools/build.sh resolve_stable_latest() / resolve_stable_tag()"
      to: "_json_str()"
      via: "stdin pipe, field name as $1"
      pattern: "_json_str"
---

<objective>
SIMPLIFY / reduce-entropy refactor of the stable-channel resolution in
`tools/build.sh`. The no-jq JSON field-extraction idiom is copy-pasted across
`resolve_stable_tag()` (tag_name) and `resolve_stable_date()` (published_at), and
the interactive picker fetches `/releases/latest` TWICE for one logical need (once
via resolve_stable_tag, again via resolve_stable_date). This collapses both:

1. ONE generic extractor `_json_str <field>` (the shared idiom, factored out).
2. ONE `resolve_stable_latest()` that fetches `/releases/latest` ONCE and yields
   BOTH the tag (line 1) and the YYYY-MM-DD date (line 2, possibly empty).
3. `resolve_stable_tag()` becomes a THIN delegate (bare-tag-only contract intact).
4. `resolve_stable_date()` is DELETED (its job is now resolve_stable_latest's date line).
5. The picker calls `resolve_stable_latest` ONCE and builds the augmented label.

Measure of success: LESS total code AND a single network fetch per path — not churn.
Also closes the two /code-review minors: (1) the redundant double fetch (resolved by
the single-fetch design) and (2) the test gap for the "fetch succeeds but has no
parseable date" path (locked in with a new regression assertion).

Purpose: lower entropy — one operation (`_json_str`) on one data structure, one
fetch per path. No behavior change to the resolved tag, the download URL, or the
checksum gate.

Output:
- `tools/build.sh`: `_json_str` + `resolve_stable_latest` + thin `resolve_stable_tag`;
  `resolve_stable_date` removed; single-fetch picker. Net negative line delta.
- `tests/cli/build_channel_test.lua`: prior resolve_stable_date assertions MIGRATED to
  resolve_stable_latest, plus the new missing-date regression + single-fetch TEXT guards.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
</execution_context>

<context>
Project rules (./CLAUDE.md): English only (all code/comments/commits); verify-before-done
(recorded repro or `wez doctor`/test output — NO "should work"); commit discipline (ONE
cohesive commit for this whole change-set — build.sh refactor + its migrated test); D-01 —
`tools/build.sh` is bootstrap/build GLUE only, the channel selector is the locked minimal
trigger-plumbing exception (no install/version POLICY grows in bash). Pure bash glue,
sudo-free, Linux+macOS portable, no `jq`, no GNU-only flags.

@tools/build.sh
@tests/cli/build_channel_test.lua

Key facts already established from reading the source (current state, build.sh):

- `_api_fetch()` (~line 165) is the shared curl-or-wget fetch-to-stdout helper. REUSE it.
  DO NOT add a third fetcher.
- `resolve_stable_tag()` (~lines 191-204): fetches
  `${WEZ_RELEASE_API}/repos/${WEZ_RELEASE_REPO}/releases/latest` via `_api_fetch`, then
  extracts `tag_name` with the no-jq idiom (split on commas with tr, grep the quoted
  `tag_name` token, head -n1, grep the inner quoted value, tr -d the quotes). Echoes ONLY
  the bare tag; `return 1` on any failure. Its OUTPUT CONTRACT is FROZEN (it feeds
  download_release's `${WEZ_RELEASE_BASE}/${tag}/${asset}` URL at ~line 361).
- `resolve_stable_date()` (~lines 219-236): the duplicate — a SECOND `_api_fetch` of the
  SAME `/releases/latest`, the SAME idiom but for `published_at`, then
  `grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'` to isolate the leading date. THIS WHOLE
  FUNCTION IS DELETED.
- `list_nightly_tags()` (~lines 239-247): a near-variant idiom (grep the quoted
  `tag_name`:`nightly-*` token, then grep `nightly-[^"]+`). It needs ALL nightly-* values
  (a list), not the first single value. See Task 1 OPTIONAL note — leave it as-is unless
  reuse is clean.
- `resolve_channel_tag()` interactive picker (~lines 288-312): resolves
  `nightly_tag` (resolve_nightly_tag) and `stable_tag` (resolve_stable_tag) with `|| true`,
  then in the stable arm does a SECOND fetch via `resolve_stable_date` (~line 305) to build
  `newest stable (tag MIDDLEDOT date)` / tag-only fallback. THIS is the double-fetch to
  collapse: resolve via `resolve_stable_latest` ONCE, split tag+date, drop the separate
  resolve_stable_tag + resolve_stable_date calls in this branch.
- `download_release()` (~line 356) consumes ONLY `resolve_channel_tag` (no direct
  resolve_stable_* call). Its non-TTY path -> resolve_channel_tag stable arm ->
  resolve_stable_tag -> (after refactor) resolve_stable_latest = exactly ONE fetch.
- CONFIRMED via live API: `/repos/castocolina/wezterm-setup/releases/latest` returns
  `"tag_name": "v0.1.0"` and `"published_at": "2026-06-15T13:56:59Z"`.

Baseline captured for verify-before-done (run before editing): `bash -n tools/build.sh`
exits 0; `shellcheck -x tools/build.sh` is CLEAN (exit 0, no warnings). build.sh is 486
lines, build_channel_test.lua is 243 lines today.

Test-harness pattern (mirror, do NOT invent a new file): `tests/cli/build_channel_test.lua`
SOURCES build.sh (no-run via the `BASH_SOURCE`/`$0` guard) and exercises functions via two
helpers it defines:
- `bash_stdout(env, body)` — sources build.sh, runs `body`, returns trimmed stdout.
- `bash_ok(env, body)` — sources build.sh, runs `body`, returns exit-success bool.
Both run `body` in a child bash with stdin from /dev/null. The `body` string is arbitrary
bash, so it can REDEFINE `_api_fetch` AFTER the source to stub the network — e.g. a body
that defines `_api_fetch` to printf "$SAMPLE_JSON" then calls `resolve_stable_latest`, with
`SAMPLE_JSON` passed via `env`. TEXT assertions use `has(needle)` (substring on script
source) and function-body scoping via `SRC:match("name%(%)%s*{(.-)\n}")`.

NOTE — the prior resolve_stable_date test block lives at ~lines 178-239 of
build_channel_test.lua. Those assertions reference a function that this task DELETES, so
they MUST be migrated to resolve_stable_latest (NOT left dangling — they will fail to match
a deleted function otherwise).

NOTE on the separator: the picker label uses a literal UTF-8 U+00B7 MIDDLE DOT (bytes
0xC2 0xB7) between the tag and date. Wherever this plan writes "MIDDLEDOT", the code and the
test must use that exact byte sequence — copy it verbatim from the current build.sh line 308.
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Factor the JSON idiom into _json_str, add single-fetch resolve_stable_latest, thin resolve_stable_tag, delete resolve_stable_date, collapse the picker to one fetch</name>
  <files>tools/build.sh</files>
  <behavior>
    - `_json_str published_at`, fed the sample release JSON on stdin, echoes
      `2026-06-15T13:56:59Z` (the first top-level string value of that field).
      `_json_str tag_name` on the same input echoes `v0.1.0`.
    - `resolve_stable_latest`, given that JSON via a stubbed `_api_fetch`, echoes `v0.1.0`
      on line 1 and `2026-06-15` on line 2, and returns 0.
    - `resolve_stable_latest` with JSON that has a tag but NO `published_at` echoes `v0.1.0`
      on line 1 and an EMPTY line 2, and returns 0 (never aborts on a missing date).
    - `resolve_stable_latest` with an empty/failed `_api_fetch` returns non-zero.
    - `resolve_stable_tag` echoes ONLY the bare tag `v0.1.0` and returns non-zero when
      resolve_stable_latest fails. Its body contains NO `published_at`.
    - The interactive picker builds the date-augmented stable label when the date is present
      and the tag-only label when empty, via ONE resolve_stable_latest call.
    - `resolve_stable_date` no longer exists anywhere in build.sh.
  </behavior>
  <action>
    Edit tools/build.sh. Work the entropy down to ONE operation on ONE structure and ONE
    fetch per path.

    (a) ADD a generic extractor `_json_str` directly above `resolve_stable_tag()` (or beside
        `_api_fetch`, whichever reads cleaner). It takes a field name as $1, reads JSON on
        STDIN, and echoes the FIRST top-level string value of that field. It is the single
        factored-out form of the copy-pasted idiom: split on commas (tr comma to newline),
        grep the quoted field token (the ERE `"<field>"[[:space:]]*:[[:space:]]*"[^"]+"`),
        head -n1, then strip to the inner quoted value (grep the trailing quoted token, tr -d
        the quotes). The field name interpolates into the grep ERE; tag_name/published_at are
        literal lowercase-and-underscore tokens, so direct interpolation is safe — add a brief
        comment that callers pass only literal field names (no user input), so no ERE-escaping
        is needed. Keep it ~5 lines. Header-comment it in the surrounding style: a generic
        no-jq first-top-level-string extractor; the single shared idiom — DO NOT re-inline per
        field.

    (b) ADD `resolve_stable_latest()` placed where resolve_stable_tag is today (BEFORE
        resolve_stable_tag, since resolve_stable_tag will delegate to it). It does ONE
        `_api_fetch "${WEZ_RELEASE_API}/repos/${WEZ_RELEASE_REPO}/releases/latest"` into a
        `json` local (redirect stderr to /dev/null, `|| return 1`; then guard
        `[ -n "${json}" ] || return 1`). From that SINGLE payload derive:
          - the tag: pipe `printf '%s' "${json}"` into `_json_str tag_name`; guard
            `[ -n "${tag}" ] || return 1` (no tag = a failed/unparseable fetch; non-zero).
          - the date: pipe `printf '%s' "${json}"` into `_json_str published_at` to get the
            raw ISO8601, then reduce to the leading YYYY-MM-DD by piping it through
            `grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'` (pure grep — NO `date`, NO `cut -dT`, NO
            GNU-only flags; Linux+macOS portable). The date is BEST-EFFORT: a missing/empty/
            unparseable published_at leaves the date empty — do NOT return non-zero for that.
        Emit the tag on line 1 and the date on line 2 (the date line MAY be empty) via a single
        `printf '%s\n%s\n' "${tag}" "${date}"`. Contract comment: ONE fetch yields BOTH the tag
        (line 1, required) and the YYYY-MM-DD date (line 2, best-effort, possibly empty); reuses
        _api_fetch + _json_str — no third fetcher, no duplicate idiom.

    (c) REWRITE `resolve_stable_tag()` THIN: capture resolve_stable_latest into a local, propagate
        its failure (`|| return 1`), take the FIRST line as the tag (pipe through head -n1), guard
        non-empty, and echo ONLY that bare tag (`printf '%s\n' "${tag}"`). Keep/trim its header
        comment to state the FROZEN contract: bare-tag-only output (feeds download_release's URL),
        now delegating internally to resolve_stable_latest (the allowed change), non-zero on
        failure. Its body must contain NO `published_at` and NO date logic.

    (d) DELETE `resolve_stable_date()` entirely (its whole function + its header comment block,
        ~lines 206-236). No thin back-compat wrapper — removing it is the entropy win. Grep the
        whole file afterward to confirm no caller remains except the picker, which step (e)
        rewrites.

    (e) COLLAPSE the interactive picker (resolve_channel_tag, the stable arm, ~lines 296-312) to
        ONE fetch. Replace the separate `stable_tag="$(resolve_stable_tag ...)"` (~line 290) and
        `stable_date="$(resolve_stable_date ...)"` (~line 305) with a SINGLE resolve_stable_latest
        call near where nightly_tag is resolved: capture its output into a `stable_out` local with
        `|| true` (tolerate empty), then split — `stable_tag` = line 1 (`sed -n 1p` or head -n1),
        `stable_date` = line 2 (`sed -n 2p`). Use whichever splitter is already idiomatic in the
        file; `sed -n 1p`/`2p` is POSIX and fine. Then keep the existing label logic verbatim: in
        the stable arm, when `stable_date` is non-empty emit
        `labels+=("newest stable (${stable_tag} MIDDLEDOT ${stable_date})")`, else
        `labels+=("newest stable (${stable_tag})")`. Use the EXACT UTF-8 U+00B7 MIDDLE DOT byte
        sequence (copy it from the current line 308) where this plan writes MIDDLEDOT. Result: the
        picker fetches /releases/latest exactly ONCE.

    (f) OPTIONAL — `list_nightly_tags()` reuse. It needs ALL nightly-* values (a list), not the
        first single value, so `_json_str` (first-match) does NOT fit cleanly. ONLY refactor it if
        you can do so without adding complexity/risk (a tiny `_json_strs` list-variant is NOT
        warranted for one caller). DEFAULT: LEAVE list_nightly_tags AS-IS and add a one-line comment
        noting why its filter-to-nightly-* + list shape differs from the single-value _json_str.
        State in your summary that you left it unchanged.

    HARD CONSTRAINTS (assert in comments where relevant):
    - resolve_stable_tag() OUTPUT stays bare-tag-only (download URL contract). Internal delegation
      to resolve_stable_latest is the ONLY allowed change.
    - Exactly ONE `_api_fetch` per resolution path: download path = 1 fetch (resolve_stable_tag ->
      resolve_stable_latest); interactive picker = 1 fetch (resolve_stable_latest). No path fetches
      /releases/latest twice. Reuse `_api_fetch` (NO third fetcher).
    - Pure bash glue (D-01), sudo-free, Linux+macOS portable, no `jq`, no GNU-only flags.
    - NET LESS code than today — the duplicate fetcher (resolve_stable_date, ~18 lines incl.
      header) and the duplicate idiom collapse into `_json_str` (~5) + resolve_stable_latest (~12)
      + a thinner resolve_stable_tag (~6). Target intent: a NEGATIVE line delta on build.sh (state
      before=486 and after in the summary).
    - Do NOT touch ~/.config/wezterm/wezterm.lua or scenes/.
  </action>
  <verify>
    <automated>bash -n tools/build.sh; shellcheck -x tools/build.sh; test "$(grep -c 'releases/latest' tools/build.sh)" -eq 1; grep -q resolve_stable_latest tools/build.sh; grep -q _json_str tools/build.sh; if grep -q resolve_stable_date tools/build.sh; then echo FAIL-date-fetcher-still-present; exit 1; fi</automated>
  </verify>
  <done>
    `bash -n tools/build.sh` exits 0; `shellcheck -x tools/build.sh` is CLEAN (no NEW warnings vs.
    the captured baseline — baseline was exit 0). `resolve_stable_date` appears NOWHERE in build.sh.
    There is exactly ONE `releases/latest` fetch site (grep -c == 1), confirming no path
    double-fetches. `_json_str` and `resolve_stable_latest` are defined; `_json_str` is reused by
    both the tag and date extraction. `resolve_stable_tag` echoes only the bare tag and contains no
    `published_at`. `wc -l tools/build.sh` is LESS than 486 (record before/after in summary).
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Migrate the resolve_stable_date assertions to resolve_stable_latest and add the missing-date + single-fetch regression guards</name>
  <files>tests/cli/build_channel_test.lua</files>
  <behavior>
    - With `_api_fetch` stubbed to return the full sample JSON, `resolve_stable_latest` stdout is
      `v0.1.0` on line 1 and `2026-06-15` on line 2 (assert BOTH lines).
    - With `_api_fetch` stubbed to return JSON with a tag but NO published_at,
      `resolve_stable_latest` returns 0, line 1 is `v0.1.0`, line 2 is EMPTY — proving the
      missing-date path never aborts (closes /code-review Minor 2).
    - With `_api_fetch` stubbed to return nothing / return 1, `resolve_stable_latest` returns
      non-zero.
    - `resolve_stable_tag` (delegating through a stubbed resolve_stable_latest payload) echoes
      ONLY `v0.1.0`.
    - TEXT guards hold (see action).
  </behavior>
  <action>
    Edit `tests/cli/build_channel_test.lua` (the established sourced-no-run harness — do NOT create
    a new bash test file). The prior resolve_stable_date block (~lines 178-239) targets a function
    this refactor DELETES; MIGRATE it, do not leave it dangling.

    1. REPLACE the resolve_stable_date BEHAVIOR block (~lines 184-199) with resolve_stable_latest
       cases. `bash_stdout` returns trimmed stdout. Keep
       `SAMPLE = '{"tag_name": "v0.1.0", "published_at": "2026-06-15T13:56:59Z"}'`.
       - Full case: a body that redefines `_api_fetch` to printf the SAMPLE_JSON env then calls
         `resolve_stable_latest`. Assert BOTH lines — either compare the trimmed stdout to the
         joined `v0.1.0` newline `2026-06-15`, OR (cleaner with the trimming helper) run two
         `bash_stdout` calls piping the body through `sed -n 1p` (assert tag == `v0.1.0`) and
         `sed -n 2p` (assert date == `2026-06-15`). Either form is acceptable; assert BOTH.
       - Missing-date case (NEW — Minor 2): `MISSING = '{"tag_name": "v0.1.0"}'`. Assert
         `bash_ok(...) == true` (returns 0, never aborts); assert line 1 (sed -n 1p) == `v0.1.0`;
         assert line 2 (sed -n 2p) == "" (empty date). Label it the no-parseable-date regression.
       - Failed-fetch case: a body stubbing `_api_fetch` to `return 1` then calling
         `resolve_stable_latest`; assert `bash_ok(...) == false`.
    2. REPLACE the resolve_stable_date TEXT guards (~lines 201-214):
       - `check("resolve_stable_latest() helper is defined", has("resolve_stable_latest()"))`.
       - Scope its body via `SRC:match("resolve_stable_latest%(%)%s*{(.-)\n}")` and assert it
         contains `releases/latest`, contains `_api_fetch`, contains `_json_str`, and does NOT
         contain `jq `.
       - `check("the generic _json_str extractor is defined", has("_json_str"))` and assert it is
         REUSED (the resolve_stable_latest body references `_json_str` — the single shared idiom is
         factored out, not re-inlined).
       - `check("resolve_stable_date is GONE (deleted, not a back-compat wrapper)", not has("resolve_stable_date"))`.
    3. REPLACE the interactive-picker TEXT guards (~lines 216-227):
       - Scope `SRC:match("resolve_channel_tag%(%)%s*{(.-)\n}")` and assert the body references
         `resolve_stable_latest` (single-fetch source) and does NOT reference `resolve_stable_date`.
       - Keep the date-augmented label assertion (copy the EXACT UTF-8 MIDDLE-DOT byte sequence from
         build.sh so the substring lines up) and the tag-only fallback `newest stable (${stable_tag})`.
       - Single-fetch guard: assert exactly one `releases/latest` site overall — Lua `gsub` returns
         the replacement count as its 2nd value, so
         `check("exactly one /releases/latest fetch site (no double fetch)", select(2, SRC:gsub("releases/latest", "")) == 1)`.
    4. UPDATE the resolve_stable_tag contract guard (~lines 229-239): its body
       (`SRC:match("resolve_stable_tag%(%)%s*{(.-)\n}")`) must reference `resolve_stable_latest` (it
       now delegates), must still ultimately echo the bare tag (the `printf '%s\\n' "${tag}"` form),
       and must NOT contain `published_at`. It no longer extracts `tag_name` itself — drop the old
       "body contains tag_name" assertion (extraction moved into resolve_stable_latest) and assert
       delegation instead.

    Keep the harness's existing pass/fail counter + `os.exit(failed == 0 and 0 or 1)` EXACTLY.
    Match the file's `check()`/`has()` style and comment cadence. Do NOT remove the unrelated
    channel/no-TTY/checksum-gate assertions (lines 1-176) — only the resolve_stable_date section is
    migrated.
  </action>
  <verify>
    <automated>lua5.4 tests/cli/build_channel_test.lua</automated>
  </verify>
  <done>
    `lua5.4 tests/cli/build_channel_test.lua` exits 0, ALL assertions passing, including: the full
    stubbed payload yields tag `v0.1.0` + date `2026-06-15`; the missing-date payload yields tag
    present + empty date + return 0 (Minor 2 regression locked); the failed fetch is non-zero; TEXT
    guards confirm `_json_str` exists and is reused, `resolve_stable_latest` reuses `/releases/latest`
    + `_api_fetch` + `_json_str` with no `jq`, `resolve_stable_date` is GONE, the picker references
    resolve_stable_latest (not resolve_stable_date), exactly one `releases/latest` site exists, and
    `resolve_stable_tag` delegates + stays bare-tag-only (no `published_at`). No prior
    channel/no-TTY/checksum assertions were lost.
  </done>
</task>

</tasks>

<verification>
Whole-change verification (recorded, no "should work" — capture and paste actual output):

1. `bash -n tools/build.sh` exits 0.
2. `shellcheck -x tools/build.sh` clean — NO NEW warnings beyond the captured baseline (baseline =
   exit 0, clean). If unsure, diff against the pre-change run.
3. `grep -c 'releases/latest' tools/build.sh` == 1 (single fetch site — no double fetch);
   `grep -q 'resolve_stable_date' tools/build.sh` finds NOTHING (fetcher deleted);
   `grep -q '_json_str' tools/build.sh` finds the generic extractor (idiom factored out).
4. `wc -l tools/build.sh` < 486 (NET LESS code — record before=486 and after; state the delta).
5. `lua5.4 tests/cli/build_channel_test.lua` — all assertions pass (migrated resolve_stable_latest
   behavior + missing-date regression + single-fetch/contract TEXT guards + the pre-existing channel
   assertions).
6. LIVE smoke (network-dependent — record the actual output): in a child shell, source build.sh and
   call `resolve_stable_latest` against the LIVE API; confirm it still yields `v0.1.0` and a
   `2026-06-15` date. Run: `bash -c 'source tools/build.sh; resolve_stable_latest'` — paste the two
   lines emitted.
7. `./tools/run-tests.sh` — introduces NO NEW failures. KNOWN OUT-OF-SCOPE BASELINE:
   `cli/lib/recipe_test.lua` "2.9d ai.toml" fails on `main` already (commit 723af62 / logged in
   deferred-items.md). Do NOT attempt to fix it — confirm it is the ONLY failure and that it
   reproduces with this change stashed.
</verification>

<success_criteria>
- ONE generic `_json_str` extractor exists and is REUSED (no copy-pasted per-field idiom).
- ONE `resolve_stable_latest()` does a SINGLE `/releases/latest` fetch and yields tag (line 1) +
  YYYY-MM-DD date (line 2, possibly empty).
- `resolve_stable_tag()` is a THIN delegate — bare-tag-only output contract preserved (download URL
  unchanged); returns non-zero on failure.
- `resolve_stable_date()` is DELETED (no back-compat wrapper).
- Exactly ONE `_api_fetch`/`releases/latest` per path: download path = 1 fetch, interactive picker =
  1 fetch. No path double-fetches.
- Interactive picker label is the date-augmented `newest stable (tag MIDDLEDOT date)` (exact UTF-8
  U+00B7) when the date is present, `newest stable (tag)` otherwise.
- NET LESS total code than today (`wc -l tools/build.sh` < 486; state the delta).
- The /code-review Minor 2 test gap is closed: a regression asserts the fetch-succeeds-but-no-
  parseable-date path (tag present, empty date line, return 0).
- `bash -n` + `shellcheck -x` clean; `build_channel_test.lua` green; live smoke yields `v0.1.0` +
  `2026-06-15`; `./tools/run-tests.sh` adds no new failures beyond the known recipe_test baseline.
- No `~/.config/wezterm/wezterm.lua` or `scenes/` changes; no new dependency (no `jq`); single
  `_api_fetch` (no third fetcher); pure bash glue, sudo-free, Linux+macOS portable, no GNU-only flags.
</success_criteria>

<output>
On completion, the quick-task summary is recorded by the quick workflow. This whole change is a
SINGLE cohesive commit (build.sh refactor: _json_str + resolve_stable_latest + thin
resolve_stable_tag + resolve_stable_date deletion + single-fetch picker, plus its migrated
regression test) per the project commit-discipline rule.
</output>
