---
phase: quick-260618-evx
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - tools/build.sh
  - tests/cli/build_channel_test.lua
autonomous: true
requirements: [QUICK-260618-evx]

must_haves:
  truths:
    - "The interactive `wez`-CLI channel picker shows a date next to the stable tag (e.g. `newest stable (v0.1.0 · 2026-06-15)`), giving stable date-parity with nightly."
    - "`resolve_stable_tag()` still echoes ONLY the bare tag — its download-URL contract is unchanged; the date is display-only in the picker label."
    - "No new fetch is added to the non-TTY `download_release` hot path; the extra date fetch lives only in the interactive picker branch."
    - "On any date-resolution failure the picker falls back to the existing tag-only label and NEVER aborts."
  artifacts:
    - path: "tools/build.sh"
      provides: "resolve_stable_date() best-effort helper + date-augmented stable picker label"
      contains: "resolve_stable_date"
    - path: "tests/cli/build_channel_test.lua"
      provides: "Sourced-no-run assertions: resolve_stable_date echoes YYYY-MM-DD from stubbed /releases/latest JSON; picker label includes the date"
      contains: "resolve_stable_date"
  key_links:
    - from: "tools/build.sh resolve_channel_tag() interactive block"
      to: "resolve_stable_date()"
      via: "local stable_date capture, included in the stable label when non-empty"
      pattern: "stable_date"
---

<objective>
Show the stable release date next to the stable tag in the `wez`-CLI interactive
channel picker so "stable" has date parity with "nightly".

Today the picker shows `nightly (nightly-20260618)` (date baked into the tag) but
`newest stable (v0.1.0)` with no date. This adds a best-effort
`resolve_stable_date()` helper that extracts the `published_at` date from the SAME
`/releases/latest` JSON `resolve_stable_tag()` already reads, and folds it into the
stable picker label as `newest stable (v0.1.0 · 2026-06-15)`.

Purpose: display-only UX parity in the interactive selector. No behavior change to
the download path, the resolved tag, or the checksum gate.

Output:
- `tools/build.sh`: new `resolve_stable_date()` + date-augmented stable label.
- `tests/cli/build_channel_test.lua`: sourced-no-run regression assertions.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
</execution_context>

<context>
Project rules (./CLAUDE.md): English only; verify-before-done (recorded repro, no
"should work"); commit discipline (one cohesive commit for this change-set); D-01 —
`tools/build.sh` is bootstrap/build GLUE only, the channel selector is the minimal
locked trigger-plumbing exception (no install/version POLICY grows in bash).

@tools/build.sh
@tests/cli/build_channel_test.lua
@.planning/phases/06.3-distribution-channels-inserted/06.3-CONTEXT.md

Key facts already established from reading the source:

- `resolve_stable_tag()` (build.sh ~line 191) GETs
  `${WEZ_RELEASE_API}/repos/${WEZ_RELEASE_REPO}/releases/latest` via `_api_fetch`,
  then extracts `tag_name` with the no-jq idiom:
  `printf '%s' "$json" | tr ',' '\n' | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n1 | grep -oE '"[^"]+"$' | tr -d '"'`.
  It echoes ONLY the bare tag and `return 1`s on any failure. This contract is FROZEN.
- `_api_fetch()` (~line 165) is the shared curl-or-wget fetch-to-stdout helper.
  REUSE it — do NOT add a third fetcher.
- The interactive picker block is in `resolve_channel_tag()` (~lines 256-272):
  `nightly_tag`/`stable_tag` are resolved with `|| true` (tolerate empty), then the
  stable label is built at `labels+=("newest stable (${stable_tag})")` (~line 265).
- The non-TTY `download_release` hot path resolves via the `[ ! -t 0 ]` branch and
  must NOT gain any date fetch.
- CONFIRMED via live API: `/repos/castocolina/wezterm-setup/releases/latest` returns
  `"tag_name": "v0.1.0"` and `"published_at": "2026-06-15T13:56:59Z"`.

Test-harness pattern (mirror, do NOT invent a new file unless forced):
`tests/cli/build_channel_test.lua` SOURCES `build.sh` (no-run via the
`BASH_SOURCE`/`$0` guard) and exercises functions via two helpers it already defines:
- `bash_stdout(env, body)` — sources build.sh, runs `body`, returns trimmed stdout.
- `bash_ok(env, body)` — sources build.sh, runs `body`, returns exit-success bool.
Both run the body in a child bash with `</dev/null`. The `body` string is arbitrary
bash, so it can REDEFINE `_api_fetch` AFTER the source to stub the network — e.g.
`body = '_api_fetch() { printf "%s" "$SAMPLE_JSON"; }; resolve_stable_date'` with
`SAMPLE_JSON` passed through `env`. This keeps everything inside the existing Lua
harness — no new bash test file needed, consistent with repo conventions.
The file also has TEXT-level assertions via `has(needle)` (substring on script source).
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add resolve_stable_date() and fold the date into the stable picker label</name>
  <files>tools/build.sh</files>
  <behavior>
    - resolve_stable_date(), given /releases/latest JSON containing
      `"published_at": "2026-06-15T13:56:59Z"`, echoes exactly `2026-06-15`
      (the YYYY-MM-DD prefix only) and returns 0.
    - resolve_stable_date() with an empty/failed fetch echoes nothing and returns
      non-zero (best-effort; never aborts).
    - The interactive stable picker label includes the date when resolvable:
      `newest stable (v0.1.0 · 2026-06-15)`; when the date is empty/unresolvable it
      falls back to the existing tag-only label `newest stable (v0.1.0)`.
    - resolve_stable_tag() is byte-unchanged: still echoes ONLY the bare tag.
  </behavior>
  <action>
    Add a `resolve_stable_date()` helper directly AFTER `resolve_stable_tag()` in
    tools/build.sh. It must GET the SAME endpoint resolve_stable_tag uses —
    `_api_fetch "${WEZ_RELEASE_API}/repos/${WEZ_RELEASE_REPO}/releases/latest"` (reuse
    _api_fetch, no third fetcher). Extract the `published_at` field with the existing
    no-jq idiom mirrored from resolve_stable_tag: split on commas, grep the
    `"published_at"[[:space:]]*:[[:space:]]*"[^"]+"` token, take head -n1, strip to the
    inner quoted value, then reduce to the leading YYYY-MM-DD (the substring before the
    `T`). Use `grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'` on the extracted ISO8601 value to
    isolate the date — do NOT parse with `date`/`cut -dT` brittleness; a pure grep keeps
    it Linux+macOS portable with no GNU-only flags. Best-effort contract: on a failed
    fetch, empty JSON, or no parseable date, echo NOTHING and `return 1`. It must NEVER
    abort the picker (matches resolve_stable_tag's `return 1` shape; callers use
    `|| true`). Mirror the surrounding header-comment style.

    Then in `resolve_channel_tag()`'s INTERACTIVE picker block, where the stable arm
    builds its label (`if [ -n "${stable_tag}" ]; then ... labels+=("newest stable (${stable_tag})")`):
    declare a local, resolve the date tolerantly
    (`local stable_date; stable_date="$(resolve_stable_date 2>/dev/null || true)"`),
    and choose the label — when `stable_date` is non-empty emit
    `newest stable (${stable_tag} · ${stable_date})`, otherwise the existing
    `newest stable (${stable_tag})`. Use the U+00B7 MIDDLE DOT `·` separator (matches the
    task intent example; it is a UTF-8 literal in the script string, harmless to bash).

    HARD CONSTRAINTS (call out in code comments):
    - resolve_stable_tag() return contract UNCHANGED — bare tag only (it feeds
      download_release's URL and MUST stay pure). Date is display-only, picker label only.
    - NO new fetch on the non-TTY download_release hot path — the date fetch lives ONLY
      in the interactive (`-t 0` true) picker branch. The picker already pays the
      resolve_stable_tag fetch; one extra resolve_stable_date fetch in the interactive
      branch is the accepted cost.
    - Pure bash glue, sudo-free, Linux+macOS portable, no new dependency (no jq), reuse
      _api_fetch. Do NOT touch ~/.config/wezterm/wezterm.lua or scenes/.
  </action>
  <verify>
    <automated>bash -n tools/build.sh && shellcheck -x tools/build.sh</automated>
  </verify>
  <done>
    `bash -n tools/build.sh` exits 0; `shellcheck -x tools/build.sh` reports no NEW
    warnings vs. the pre-change baseline. `resolve_stable_date` is defined and reuses
    `_api_fetch` + `/releases/latest`; the interactive stable label is date-augmented
    with a tag-only fallback; `resolve_stable_tag` body is unchanged.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Sourced-no-run regression assertions in build_channel_test.lua</name>
  <files>tests/cli/build_channel_test.lua</files>
  <behavior>
    - With `_api_fetch` stubbed (inside the sourced body) to return the sample
      `/releases/latest` JSON, `resolve_stable_date` echoes exactly `2026-06-15`.
    - The interactive stable picker label string includes the date — assert at the
      script-TEXT level that `resolve_channel_tag` builds a date-augmented stable label
      (e.g. `has("newest stable (${stable_tag} · ${stable_date})")` or the chosen exact
      label form) AND that `resolve_stable_date` is defined and called from the resolver.
    - TEXT guard: `resolve_stable_date` reuses `/releases/latest` and does NOT add `jq`.
  </behavior>
  <action>
    Extend the EXISTING Lua harness `tests/cli/build_channel_test.lua` (do NOT create a
    new bash test file — sourcing build.sh from this harness is the established repo
    pattern, and its `bash_stdout`/`bash_ok` helpers already source build.sh under the
    no-run guard). Add a small block:

    1. BEHAVIOR (stubbed fetch): build a sample JSON literal matching the live shape,
       e.g. `local SAMPLE = '{"tag_name": "v0.1.0", "published_at": "2026-06-15T13:56:59Z"}'`.
       Call `bash_stdout` with the JSON passed via env and `_api_fetch` redefined in the
       body AFTER the source, asserting the date:
       `bash_stdout("SAMPLE_JSON='" .. SAMPLE .. "'", "_api_fetch() { printf '%s' \"$SAMPLE_JSON\"; }; resolve_stable_date") == "2026-06-15"`.
       (Single-quote the env value; the JSON has no single quotes. The body redefining
       `_api_fetch` shadows the real fetcher so NO network call is made.)
    2. BEHAVIOR (best-effort empty): a body stubbing `_api_fetch` to echo nothing /
       return 1 — assert `resolve_stable_date` is non-zero (use `bash_ok(..) == false`)
       AND its stdout is empty, proving it never aborts and the picker can fall back.
    3. TEXT: `check("resolve_stable_date() helper is defined", has("resolve_stable_date()"))`;
       `check("resolve_stable_date reuses /releases/latest (no second endpoint)", ...)` by
       scoping the resolve_stable_date body via a Lua pattern match
       (`SRC:match("resolve_stable_date%(%)%s*{(.-)\n}")`) and asserting it contains
       `releases/latest`; `check("...no jq added", not has("jq "))` (already asserted
       globally — keep consistent); a TEXT assertion that the interactive resolver
       references `resolve_stable_date` and builds a date-bearing stable label.
    4. TEXT (contract guard): assert `resolve_stable_tag`'s body is still the bare-tag
       echo — its body (`SRC:match("resolve_stable_tag%(%)%s*{(.-)\n}")`) must contain
       `tag_name` and `printf '%s\\n' "${tag}"` and must NOT contain `published_at`
       (the date logic lives only in resolve_stable_date), proving the download-feeding
       contract is unchanged.

    Keep the harness's existing pass/fail counter + `os.exit(failed == 0 ...)` exactly.
    Match the file's check()/has() style. The assertion separator `·` is UTF-8 — when
    asserting the label TEXT, use the exact byte sequence emitted by Task 1 (copy the
    label form from build.sh) so `has()` substring matching lines up.
  </action>
  <verify>
    <automated>lua5.4 tests/cli/build_channel_test.lua</automated>
  </verify>
  <done>
    `lua5.4 tests/cli/build_channel_test.lua` exits 0 with all assertions passing,
    including: stubbed `resolve_stable_date` echoes `2026-06-15`; empty-fetch case is
    non-zero with empty stdout; TEXT guards confirm the helper exists, reuses
    `/releases/latest`, adds no `jq`, and that `resolve_stable_tag` stays bare-tag-only
    (no `published_at` in its body).
  </done>
</task>

</tasks>

<verification>
Whole-change verification (recorded, no "should work"):

1. `bash -n tools/build.sh` exits 0.
2. `shellcheck -x tools/build.sh` clean — no NEW warnings beyond the pre-change
   baseline (run shellcheck on the original first if unsure, diff the output).
3. `lua5.4 tests/cli/build_channel_test.lua` — all assertions pass (the new
   resolve_stable_date behavior + label + contract guards plus the pre-existing
   channel assertions).
4. `./tools/run-tests.sh` — introduces NO NEW failures. KNOWN OUT-OF-SCOPE BASELINE:
   `cli/lib/recipe_test.lua` "2.9d ai.toml" fails on `main` already (commit 723af62 /
   logged in deferred-items.md). Do NOT attempt to fix it — confirm it is the ONLY
   failure and that it reproduces with this change stashed.
</verification>

<success_criteria>
- The interactive picker stable label shows the release date when resolvable
  (`newest stable (v0.1.0 · 2026-06-15)`), falling back to `newest stable (v0.1.0)`
  on any date-resolution failure.
- `resolve_stable_tag()` is byte-unchanged (bare-tag-only contract preserved).
- No new fetch on the non-TTY `download_release` hot path.
- `bash -n` + `shellcheck -x` clean; `build_channel_test.lua` green;
  `./tools/run-tests.sh` adds no new failures beyond the known recipe_test baseline.
- No `~/.config/wezterm/wezterm.lua` or `scenes/` changes; no new dependency (no jq);
  single `_api_fetch` (no third fetcher).
</success_criteria>

<output>
On completion, the quick-task summary is recorded by the quick workflow. This change
is a single cohesive commit (build.sh helper + label + its regression test) per the
project commit-discipline rule.
</output>
