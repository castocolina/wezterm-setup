---
phase: quick-260623-gbk
plan: 01
type: tdd
wave: 1
depends_on: []
files_modified:
  - tools/build.sh
  - tests/cli/build_dev_launcher_test.lua
autonomous: true
requirements: [INST-08]

must_haves:
  truths:
    - "On macOS with keg-only lua@5.4 (lua5.4 NOT on PATH), `./tools/build.sh` succeeds: the generated dev launcher execs a resolved Lua 5.4 interpreter and `./dist/wez version` exits 0 (was 127)."
    - "The generated dev launcher no longer contains a bare `exec lua5.4 ...` line; it execs an interpreter path resolved at build time."
    - "When no Lua 5.4 interpreter can be found at all, the build fails loudly with a clear, actionable error (never silently generates a launcher that will 127 at runtime)."
  artifacts:
    - path: "tools/build.sh"
      provides: "Robust Lua 5.4 interpreter resolution baked into build_dev_launcher()"
      contains: "resolve_dev_lua"
    - path: "tests/cli/build_dev_launcher_test.lua"
      provides: "RED-first regression: generated launcher execs a resolved interpreter, not bare lua5.4; resolver fails loud when 5.4 absent"
  key_links:
    - from: "tools/build.sh build_dev_launcher()"
      to: "resolved Lua 5.4 interpreter path"
      via: "interpreter resolved (PATH lua5.4 -> brew --prefix lua@5.4/bin/lua5.4 -> a `lua` reporting 5.4) and baked into the generated exec line at build time"
      pattern: "exec \"\\$\\{?DEV_LUA"
---

<objective>
Fix the macOS dev-launcher build failure. `tools/build.sh build_dev_launcher()` generates a launcher whose final line is a hardcoded `exec lua5.4 "${REPO_ROOT}/${ENTRY}" "$@"`. On macOS, Homebrew's `lua@5.4` is keg-only, so `lua5.4` is NOT on the default PATH → the generated `dist/wez` dies with `exec: lua5.4: not found` (exit 127), the build's own `wez version` smoke test then correctly aborts, and `make install` fails.

The fix resolves a Lua 5.4 interpreter robustly at BUILD time and bakes the RESOLVED path into the generated launcher's `exec` line (consistent with how `REPO_ROOT` is already baked). Resolution order: (1) `lua5.4` on PATH, (2) `$(brew --prefix lua@5.4)/bin/lua5.4` (the keg-only macOS path already used for the static build at lines ~204-206), (3) a `lua` on PATH that reports version 5.4. If none is found, fail loudly with an actionable error. Sudo-free, no new dependencies, bash-3.2-safe (macOS default bash).

Purpose: unblock `make install` on macOS for the dev (luastatic-absent) build path; close the gap where the dev launcher ignored the keg-resolution idiom the static path already uses.
Output: a Lua 5.4 resolution helper in build.sh wired into `build_dev_launcher()`, plus a RED-first regression test.

Out of scope (observation only — do NOT change): `have_luastatic()` (line ~92) and the luastatic static-build path's keg resolution (lines ~202-209) are correct as-is and must not be refactored. This fix is confined to the dev-launcher interpreter resolution.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
</execution_context>

<context>
@./CLAUDE.md
@.planning/STATE.md
@tools/build.sh
@tests/cli/setup_dev_test.lua
@tests/cli/ci_macos_toolchain_test.lua
@tests/cli/build_channel_test.lua
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: RED — regression test asserting the generated dev launcher execs a RESOLVED interpreter, not bare lua5.4</name>
  <files>tests/cli/build_dev_launcher_test.lua</files>
  <behavior>
    Mirror the existing Lua TEXT+sourced-behavior test style (read script text via io.open; source build.sh under bash via the BASH_SOURCE/$0 guard and invoke a function against a temp dir). Add a NEW test file `tests/cli/build_dev_launcher_test.lua` with the helper preamble (this_dir/repo_root resolution, `check(label, ok, detail)`, `read_file`, `has`) copied from `build_channel_test.lua`.

    Assertions (all MUST FAIL against current build.sh — the RED state):

    - TEXT regression guard: the build.sh source contains NO bare `exec lua5.4 ` line in `build_dev_launcher()`. Use the grep-comment-filter idiom from setup_dev_test.lua (`grep -E 'exec lua5\.4 ' build.sh | grep -vc '^[[:space:]]*#'` must be 0) so header prose mentioning `lua5.4` does not self-invalidate the gate. Currently FAILS (line ~526 has the bare exec).
    - TEXT presence: build.sh defines a dedicated resolver (assert `has("resolve_dev_lua")`). Currently FAILS (does not exist yet).
    - BEHAVIOR (the load-bearing assertion): source build.sh under bash and call `build_dev_launcher` with `OUT` pointed at a temp file and `ENTRY`/`REPO_ROOT` set, with a fake `lua5.4` shim on PATH (a temp dir prepended to PATH containing an executable `lua5.4` that prints `Lua 5.4`), then read the generated launcher and assert: (a) it does NOT contain a bare `exec lua5.4 ` token (it execs an absolute/resolved path or a `${DEV_LUA}`-style baked variable, NOT the bare command name); (b) the resolved interpreter token in the exec line is the shim's absolute path. Use an os.execute bash wrapper that `source`s build.sh then runs `build_dev_launcher` (the BASH_SOURCE/$0 guard prevents main() from running on source). Currently FAILS (heredoc emits bare `exec lua5.4`).
    - BEHAVIOR (fail-loud): with PATH scrubbed of any `lua5.4`/`lua` and `brew` absent/returning nothing, calling the resolver (or `build_dev_launcher`) exits NON-ZERO and the error text references a missing Lua 5.4 interpreter. Currently FAILS (no resolver, no fail-loud).

    RED label note: this task ONLY adds the failing test. Do NOT touch build.sh in this task. Running `LUA_BIN=lua5.4 ./tools/run-tests.sh` (or the file directly) MUST report failures for the assertions above — that failing run IS the RED gate.
  </behavior>
  <action>
    Create `tests/cli/build_dev_launcher_test.lua` following the exact style of `tests/cli/build_channel_test.lua` and `tests/cli/setup_dev_test.lua` (TEXT assertions via `has()`, comment-filtered grep counts via `io.popen`, and a `bash_ok`/`os.execute` sourced-behavior harness as in setup_dev_test.lua lines 126-146). Name the resolver the test expects `resolve_dev_lua` so Task 2 implements to that contract. For the sourced-behavior cases, write a small bash wrapper to a tmp file that: sets `OUT` to a tmp path, `ENTRY="cli/wez.lua"`, prepends a tmp `bin/` holding an executable `lua5.4` shim (`printf '#!/usr/bin/env bash\necho "Lua 5.4"\n'` + chmod +x) onto PATH, `source`s `tools/build.sh`, then runs `build_dev_launcher`; read the produced `OUT` text and assert on the `exec` line. For the fail-loud case, run the wrapper with `PATH=/nonexistent` (no lua5.4/lua/brew) and assert non-zero exit. Add the standard `passed/failed` footer and `os.exit(failed == 0 and 0 or 1)`. Do NOT modify build.sh in this task.
  </action>
  <verify>
    Run on macOS (default `lua` is 5.5, so put the keg 5.4 on PATH for the harness): `LUA_BIN=lua5.4 PATH="$(brew --prefix lua@5.4)/bin:$PATH" lua5.4 tests/cli/build_dev_launcher_test.lua` — MUST exit NON-ZERO with the new assertions reported as FAIL (this is the expected RED). Confirm the failures are the four listed assertions, not harness/syntax errors.
  </verify>
  <done>The new test file exists, runs cleanly (no Lua syntax/harness errors), and FAILS on the bare-`exec lua5.4`, `resolve_dev_lua`-presence, resolved-exec-line, and fail-loud assertions — establishing the RED baseline before any build.sh change.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: GREEN — resolve a Lua 5.4 interpreter and bake it into the generated dev launcher</name>
  <files>tools/build.sh</files>
  <behavior>
    After this task the Task-1 test goes GREEN: the generated launcher execs a resolved interpreter path (not bare `lua5.4`), and the resolver fails loud when no Lua 5.4 is present.

    Resolution contract (`resolve_dev_lua`, printing the resolved interpreter path to stdout, returning non-zero + a clear stderr message when none found), in priority order:
    1. `command -v lua5.4` on PATH → use it (its absolute path via `command -v`).
    2. On macOS (or whenever `brew` is available): `keg="$(brew --prefix lua@5.4 2>/dev/null)"`; if `"${keg}/bin/lua5.4"` exists and is executable, use it. (Same keg idiom as the static path, lines ~202-209.)
    3. A `lua` on PATH that reports 5.4: `command -v lua` and `lua -v 2>&1` matching `Lua 5.4` → use that `lua` path. (Guards against the bare Homebrew `lua` 5.5 — only accept when it actually reports 5.4.)
    4. None found → emit `log`/stderr ERROR ("no Lua 5.4 interpreter found (need `lua5.4` on PATH, a Homebrew `lua@5.4` keg, or a `lua` reporting 5.4) — run tools/setup-dev.sh") and `return 1` so `build_dev_launcher` aborts before generating an inert launcher.

    `build_dev_launcher` then resolves once into a local (e.g. `DEV_LUA="$(resolve_dev_lua)" || exit 1`) and BAKES the resolved path into the generated heredoc's exec line — i.e. emit `exec "<resolved-path>" "${REPO_ROOT}/${ENTRY}" "$@"` with the resolved value expanded at build time (like `REPO_ROOT` already is), NOT the literal token `lua5.4`. Keep the `"$@"` and `${REPO_ROOT}/${ENTRY}` runtime-escaped in the heredoc exactly as today.

    Constraints: bash-3.2-safe (no `${var,,}`, no associative arrays — macOS default bash is 3.2); sudo-free; no new external deps (only `command -v`, `brew --prefix`, `lua -v`). Do NOT alter `have_luastatic()` or the luastatic static path.
  </behavior>
  <action>
    Add a `resolve_dev_lua()` function to `tools/build.sh` (place it near `build_dev_launcher`, after the toolchain-detection section). Implement the 4-arm priority resolution above using `command -v`, `brew --prefix lua@5.4`, and a `lua -v` 5.4 grep — bash-3.2-safe, sudo-free. In `build_dev_launcher()`, replace the bare `exec lua5.4 "\${REPO_ROOT}/${ENTRY}" "\$@"` heredoc line: first resolve `DEV_LUA="$(resolve_dev_lua)" || exit 1`, then emit the exec line with `${DEV_LUA}` expanded at build time (e.g. `exec "${DEV_LUA}" "\${REPO_ROOT}/${ENTRY}" "\$@"` inside the heredoc — note `${DEV_LUA}` is build-time-expanded, while `\${REPO_ROOT}` and `\$@` stay runtime-escaped as today). Update the launcher's header comment (currently "it execs lua5.4 against the in-repo Lua sources") to reflect that it execs the resolved Lua 5.4 interpreter. Do not change the smoke-test block or any other path.
  </action>
  <verify>
    1. Test GREEN: `LUA_BIN=lua5.4 PATH="$(brew --prefix lua@5.4)/bin:$PATH" lua5.4 tests/cli/build_dev_launcher_test.lua` exits 0.
    2. Full suite: `PATH="$(brew --prefix lua@5.4)/bin:$PATH" ./tools/run-tests.sh` exits 0 (no regressions).
    3. MANUAL REPRO (the original failure): with `lua5.4` NOT on the bare PATH (keg-only macOS state) but luastatic ABSENT so the dev-launcher path runs, build and smoke-test the launcher — `./tools/build.sh` should complete its own `'dist/wez version' OK` log line, then `./dist/wez version` exits 0 (was exit 127 `exec: lua5.4: not found`). Inspect `dist/wez`: its `exec` line names a resolved absolute interpreter path, not bare `lua5.4`.
  </verify>
  <done>`resolve_dev_lua` resolves via PATH lua5.4 → keg lua@5.4 → a 5.4-reporting `lua`, and fails loud otherwise; `build_dev_launcher` bakes the resolved path into the generated launcher; Task-1 test and the full suite are GREEN; the manual repro shows `./dist/wez version` exits 0 on the keg-only macOS state.</done>
</task>

</tasks>

<verification>
- `tests/cli/build_dev_launcher_test.lua` is RED before Task 2 and GREEN after.
- `./tools/run-tests.sh` (with the keg bin on PATH) passes with no regressions to existing build/toolchain tests.
- Manual repro: dev-launcher `./dist/wez version` exits 0 on macOS with keg-only `lua@5.4` (no `lua5.4` on the bare PATH); the generated launcher's `exec` line names a resolved interpreter, not bare `lua5.4`.
- `have_luastatic()` and the luastatic static path are unchanged (out of scope).
</verification>

<success_criteria>
- The generated dev launcher execs a build-time-resolved Lua 5.4 interpreter (PATH `lua5.4`, else `$(brew --prefix lua@5.4)/bin/lua5.4`, else a `lua` reporting 5.4); never a bare `lua5.4` command name.
- On macOS keg-only state, `./tools/build.sh` (dev path) passes its `wez version` smoke test and `./dist/wez version` exits 0 (regression from exit 127 closed).
- When no Lua 5.4 interpreter exists, the build aborts loudly with an actionable message instead of generating an inert launcher.
- Fix is bash-3.2-safe, sudo-free, adds no new dependencies, and is confined to the dev-launcher resolution.
- TDD discipline honored: RED test commit precedes the GREEN fix commit.
</success_criteria>

<output>
Create `.planning/quick/260623-gbk-macos-dev-launcher-lua-resolve/260623-gbk-SUMMARY.md` when done.
</output>
