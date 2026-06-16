---
phase: 06.1-tab-and-scene-identity-redesign
plan: 02
type: tdd
wave: 1
depends_on: []
files_modified:
  - cli/lib/cwd.lua
  - cli/lib/cwd_test.lua
autonomous: true
requirements: [D-01, D-07, D-08]
must_haves:
  truths:
    - "A single cli/lib/cwd.lua resolves the locked cwd grammar (literal | ~ | $ENV | relative where . = launch dir and .. = dirname(launch dir)) to an absolute path, purely, with NO shell $(...) evaluation"
    - "A cwd value containing $(...) or backticks is REJECTED before emit (validate-before-emit), never passed to a shell"
    - "An omitted cwd defaults to the launch dir (D-07)"
  artifacts:
    - path: "cli/lib/cwd.lua"
      provides: "Pure cwd-grammar resolver shared by --cwd CLI flags and the .toml cwd field (D-01/D-07/D-08)"
      exports: ["resolve", "validate"]
      min_lines: 50
    - path: "cli/lib/cwd_test.lua"
      provides: "RED-first fixture suite for cwd grammar + the $(...) rejection"
      min_lines: 50
  key_links:
    - from: "cli/lib/cwd.lua"
      to: "(pure)"
      via: "no io / no os.execute / no shell eval"
      pattern: "function M.resolve"
---

<objective>
Create the shared `cli/lib/cwd.lua` — the ONE pure resolver for the locked cwd grammar
(D-07/D-08), used by both the `--cwd` CLI segment and the `.toml` `cwd` field in Wave 2/3.
The grammar (locked in CONTEXT.md, NO new research): a cwd value is one of
`literal absolute` | `~`-prefixed | `$ENV`-expanded | relative, where `.` = the launch dir
and `..` = `dirname(launch dir)`. Shell command substitution (`$(...)` / backticks) is
FORBIDDEN — the resolver expands purely in Lua and REJECTS those forms (validate-before-emit).

The resolved absolute path is what later plans hand to `wezterm cli spawn --cwd <path>` so a
pane opens DIRECTLY in the target directory with NO visible `cd <path>` line (D-08 clean pane).

Purpose: D-01 single-implementation for cwd resolution so scene launch, scene new, and any
`--cwd` flag share identical edge handling and the same security posture (no shell eval).
Output: `cli/lib/cwd.lua` + `cli/lib/cwd_test.lua`.
</objective>

<execution_context>
@$HOME/.claude/gsd-core/workflows/execute-plan.md
@$HOME/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-CONTEXT.md
@.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md

# Harness + purity template to mirror:
@cli/lib/scene_test.lua
@cli/lib/scene.lua
</context>

<tasks>

<task type="tdd" tdd="true">
  <name>Task 1: RED — author cli/lib/cwd_test.lua for the grammar + the security rejection</name>
  <read_first>
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md ("Resolve cwd grammar to a spawn --cwd (D-07/D-08, pure)" code example + Security Domain "cwd grammar shell evaluation" row)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-CONTEXT.md (D-07 default-to-launch-dir, D-08 clean-pane requirement, the locked grammar text)
    - cli/lib/scene_test.lua (mirror the check/eq harness; runs under plain lua5.4)
    - cli/lib/scene.lua (the pure-by-contract header + purity grep this module must satisfy)
  </read_first>
  <behavior>
    Given launch_dir = "/home/u/proj" and a HOME / env fixture passed in (resolver takes the
    launch dir + an env-getter as arguments so it stays pure/testable — NO os.getenv inside):
    - resolve(nil, launch_dir, env) == "/home/u/proj"            (D-07 omitted -> launch dir)
    - resolve(".", launch_dir, env) == "/home/u/proj"            (. = launch dir)
    - resolve("..", launch_dir, env) == "/home/u"                (.. = dirname(launch dir))
    - resolve("~", launch_dir, env={HOME="/home/u"}) == "/home/u"
    - resolve("~/x", launch_dir, env={HOME="/home/u"}) == "/home/u/x"
    - resolve("$WORK/svc", launch_dir, env={WORK="/srv"}) == "/srv/svc"
    - resolve("/abs/path", launch_dir, env) == "/abs/path"       (literal absolute as-is)
    - resolve("sub/dir", launch_dir, env) == "/home/u/proj/sub/dir"  (relative joined to launch dir)
    - validate("$(rm -rf /)", env) -> (false, <error: command substitution not allowed>)
    - validate("`whoami`", env) -> (false, <error>)
    - validate("$UNSET/x", env={}) -> (false, <error: $UNSET is not set>)  (validate-before-emit on unset env)
    - validate("~/ok", env={HOME="/home/u"}) -> (true)
  </behavior>
  <action>
    Create cli/lib/cwd_test.lua mirroring scene_test.lua's check/eq harness, require("cli.lib.cwd").
    Encode every bullet. The resolver signature takes (value, launch_dir, env) so the test injects a
    fixture env table — keeping the module pure (NO os.getenv / io / os.execute). Assert BOTH the
    happy grammar paths AND the rejection paths ($(...), backticks, unset $ENV). Run it; confirm it
    FAILS RED (module absent). Commit as `test(06.1-02): RED shared cwd resolver`.
  </action>
  <verify>
    <automated>lua5.4 cli/lib/cwd_test.lua; test $? -ne 0 # MUST fail RED (cli.lib.cwd absent)</automated>
  </verify>
  <acceptance_criteria>
    - cli/lib/cwd_test.lua exists; first dependency is `require("cli.lib.cwd")`
    - `lua5.4 cli/lib/cwd_test.lua` exits NON-zero (RED)
    - Contains an explicit assertion that `validate("$(...)")` is rejected (the security lock from RESEARCH Security Domain)
  </acceptance_criteria>
  <done>cwd_test.lua authored, fails because cli/lib/cwd.lua does not exist yet (RED).</done>
</task>

<task type="tdd" tdd="true">
  <name>Task 2: GREEN — implement the pure cli/lib/cwd.lua resolver</name>
  <read_first>
    - cli/lib/cwd_test.lua (the contract just authored)
    - cli/lib/scene.lua (pure-by-contract style + the dirname-style string matching used elsewhere, e.g. doctor's `match("^(.*)/[^/]+$")`)
  </read_first>
  <behavior>
    Same bullets as Task 1; implementation makes them GREEN.
  </behavior>
  <action>
    Create cli/lib/cwd.lua as a PURE module (local M = {}; return M; no os.getenv / io / os.execute /
    wezterm). M.validate(value, env) runs validate-before-emit: reject any value containing `$(` or a
    backtick (command substitution not allowed); reject `$NAME` where env[NAME] is unset; otherwise
    return true. M.resolve(value, launch_dir, env) expands per the locked grammar: nil/empty -> launch_dir
    (D-07); "." -> launch_dir; ".." -> dirname(launch_dir) via a `match("^(.*)/")` style split; leading
    "~" -> env.HOME (+ remainder); `$NAME` prefix -> env[NAME] (+ remainder); leading "/" -> as-is;
    otherwise relative -> launch_dir .. "/" .. value. The env-getter is a passed-in table so the module
    never touches os.getenv (the IO-shell in plans 04 will pass a real env snapshot). Keep it minimal —
    the smallest code that satisfies the grammar (reducing-entropy: do not add path-normalization the
    spec does not require). Commit as `feat(06.1-02): shared cli/lib/cwd.lua resolver`.
  </action>
  <verify>
    <automated>lua5.4 cli/lib/cwd_test.lua # MUST pass (exit 0)</automated>
    <automated>grep -nE 'os\.getenv|os\.execute|io\.|require\("wezterm"\)' cli/lib/cwd.lua | grep -vE '^\s*--' | wc -l | grep -qx 0 # purity</automated>
  </verify>
  <acceptance_criteria>
    - `lua5.4 cli/lib/cwd_test.lua` exits 0 (GREEN)
    - `cli/lib/cwd.lua contains function M.resolve` and `function M.validate`
    - Purity grep returns 0 (no os.getenv/io/os.execute/wezterm) — pure under plain lua5.4
    - `validate("$(rm -rf /)", {})` returns false (shell-eval rejection enforced)
  </acceptance_criteria>
  <done>cli/lib/cwd.lua passes its suite, is pure, expands the locked grammar, and rejects $(...) / backticks / unset $ENV before emit.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| cwd value → `wezterm cli spawn --cwd` arg | A user-supplied directory string becomes a spawn argument (later plans) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06.1-03 | Elevation | cwd grammar resolver | mitigate | The locked grammar FORBIDS `$(...)`/backticks; M.validate rejects them and the resolver expands purely in Lua (no shell eval), per RESEARCH Security Domain "cwd grammar shell evaluation". Unset `$ENV` is rejected (validate-before-emit), never silently empty. |
| T-06.1-04 | Tampering | spawn --cwd argument | mitigate | This module only produces the resolved STRING; the IO-shell (Plan 04) MUST shquote it before os.execute. Noted here so the contract is explicit; quoting is enforced + tested in Plan 04. |
| T-06.1-SC | Tampering | npm/pip/cargo installs | accept | Zero external packages this phase (RESEARCH Package Legitimacy Audit). No install task. |
</threat_model>

<verification>
- `lua5.4 cli/lib/cwd_test.lua` passes (exit 0).
- Purity grep returns 0.
- `./tools/run-tests.sh` full suite green (new file only; no consumer wiring yet).
</verification>

<success_criteria>
- cli/lib/cwd.lua is the single shared cwd resolver, pure, grammar-complete, and rejects shell eval.
- TDD RED (Task 1) → GREEN (Task 2).
- No consumer wiring yet (plans 04 consume it).
</success_criteria>

<output>
Create `.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-02-SUMMARY.md` when done.
</output>
