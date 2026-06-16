---
phase: 06.1-tab-and-scene-identity-redesign
plan: 04
type: tdd
wave: 3
depends_on: [01, 02, 03]
files_modified:
  - cli/lib/scene.lua
  - cli/lib/scene_test.lua
  - cli/lib/recipe.lua
  - cli/lib/recipe_test.lua
  - cli/commands/scene.lua
  - cli/spec.lua
  - tests/cli/spec_test.lua
autonomous: true
requirements: [D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08]
must_haves:
  truths:
    - "A --pane segment / [[pane]] entry accepts cwd, focus, and size in addition to cmd/color/title (D-05/D-06/D-07)"
    - "More than one focus=true pane is a validate-before-emit error (D-05)"
    - "A pane's size is an integer percent 1..100 that overrides the equal-share split for its step (D-06)"
    - "Scene panes spawn with `wezterm cli spawn/split-pane --cwd <resolved>` so the pane opens directly in the target dir with NO visible `cd` line (D-08 clean pane)"
    - "Scene tab-level color is emitted as WEZTERM_TAB_COLOR via OSC (no `<color>:<title>` encoding) — scene.lua no longer depends on tablib.parse_stored/merge_title (D-02/D-03/D-04)"
    - "The recipe schema accepts top-level tab keys (title/color/cwd) + [[pane]]/[[panes]] aliases + per-pane cwd/focus/size, with deprecated top-level aliases kept for migration (D-04)"
    - "cwd/focus/size segment keys are registered in cli/spec.lua so completion + `wez keys` surface them (D-16)"
  artifacts:
    - path: "cli/lib/scene.lua"
      provides: "parse_pane_spec with cwd/focus/size; focus>1 validation; size->percent mapping (D-05/D-06/D-07)"
      contains: "focus"
    - path: "cli/lib/recipe.lua"
      provides: "Schema with per-pane cwd/focus/size + top-level cwd + [[pane]] alias + migration aliases (D-04)"
      contains: "cwd"
    - path: "cli/commands/scene.lua"
      provides: "Spawn with --cwd (clean pane D-08); tab color via OSC (D-02/D-03); apply size percent + focus pane (D-05/D-06)"
      contains: "--cwd"
  key_links:
    - from: "cli/commands/scene.lua"
      to: "wezterm cli spawn --cwd"
      via: "cli/lib/cwd.resolve + shquote at spawn time"
      pattern: "--cwd"
    - from: "cli/commands/scene.lua"
      to: "WEZTERM_TAB_COLOR user var"
      via: "color.build_user_var_octal via send-text printf (pane-targeted)"
      pattern: "WEZTERM_TAB_COLOR"
    - from: "cli/lib/recipe.lua"
      to: "cli/lib/scene.lua validators"
      via: "reused validate_layout/validate_color (single source)"
      pattern: "scene\\.validate_"
---

<objective>
Extend the scene/recipe model with the attributes daily use needs — `cwd`, `focus`, `size`
(D-05/D-06/D-07) — and apply cwd at SPAWN time so panes open directly in the target directory
with no visible `cd` line (D-08 clean pane, "el pane debería quedar limpio"). Simultaneously
finish the tab-color decouple on the scene side: scene tab-level color is emitted as
`WEZTERM_TAB_COLOR` via OSC (reusing the Plan 01 shared emitters), and scene.lua DROPS its
dependency on `tablib.parse_stored`/`merge_title` (D-02/D-03/D-04). The recipe schema gains
top-level tab keys + `[[pane]]` alias + per-pane `cwd`/`focus`/`size`, keeping the deprecated
top-level `color`/`title` + `[[panes]]` as migration aliases (D-04). New segment keys are
registered in `cli/spec.lua` for completion + `wez keys` (D-16).

This plan consumes the shared `cli/lib/color.lua` (Plan 01) and `cli/lib/cwd.lua` (Plan 02) so
the new spawn path uses ONE color emitter and ONE cwd resolver — no parallel copies (D-01).

Purpose: deliver the rich-recipe capability (cwd/focus/size, clean panes) and complete the
encoding-free tab color on the scene path. Output: extended scene/recipe libs + scene command +
spec registration.
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
@.planning/phases/04-ad-hoc-scenes/04-CONTEXT.md
@.planning/phases/05-named-scenes/05-CONTEXT.md

# Shared modules consumed (built in Wave 1/2 — read their SUMMARYs + sources):
@.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-01-SUMMARY.md
@.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-02-SUMMARY.md
@.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-03-SUMMARY.md
@cli/lib/color.lua
@cli/lib/cwd.lua

# Modules being extended:
@cli/lib/scene.lua
@cli/lib/scene_test.lua
@cli/lib/recipe.lua
@cli/lib/recipe_test.lua
@cli/commands/scene.lua
@cli/spec.lua
</context>

<reducing_entropy_note>
D-01: the new cwd/color emit must REUSE cli/lib/cwd.resolve and cli/lib/color.build_*; the
existing scene.lua octal-printf idiom (lines ~286-289) is generalized by color.build_user_var_octal
(Plan 01) — call that instead of re-deriving the gsub. Removing scene.lua's tablib.parse_stored/
merge_title dependency DELETES the last consumer of the encoding, enabling that code to be retired.
</reducing_entropy_note>

<tasks>

<task type="tdd" tdd="true">
  <name>Task 1: RED/GREEN — pure scene.lua: parse_pane_spec gains cwd/focus/size; focus>1 error; size->percent (D-05/D-06/D-07)</name>
  <read_first>
    - cli/lib/scene.lua (parse_pane_spec, split_kv_segments, plan_splits, validate_* — extend, do not rewrite)
    - cli/lib/scene_test.lua (the check/eq/teq harness + existing parse_pane_spec/plan_splits cases)
    - cli/lib/cwd.lua (validate — parse_pane_spec should carry cwd raw; cwd validation/resolution happens in the IO-shell Task 3 with the launch dir + env)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-CONTEXT.md (D-05 focus boolean + >1 error; D-06 size 1..100; D-07 cwd default)
  </read_first>
  <behavior>
    - parse_pane_spec("cmd=top, color=teal, cwd=~/x, focus=true, size=30") -> {cmd="top", color="teal", cwd="~/x", focus=true, size=30, shell=false}
    - parse_pane_spec("shell") -> {shell=true, ...} unchanged
    - parse_pane_spec bare command unchanged
    - unknown key still errors (now the allowed set is cmd/color/title/cwd/focus/size)
    - focus parses "true"->true, absent->nil/false; size parses "30"->30 (integer), rejects "0"/"101"/"abc" as a validate-before-emit error
    - a new M.validate_focus(parsed_list) -> (true) | (false, "error: more than one pane marked focus=true") when >1 focus=true (D-05)
    - a new M.size_percent(parsed, default_pct) -> parsed.size when set (1..100) else default_pct (D-06 override of the equal-share step)
  </behavior>
  <action>
    Extend split_kv_segments consumers: in parse_pane_spec add cwd/focus/size to the accepted key set;
    coerce focus to boolean, size to an integer in 1..100 (reject out-of-range as the UI-SPEC-style
    "error: invalid --pane value '<spec>' — size must be an integer 1..100"). Add M.validate_focus
    (scans the parsed list, errors on >1 focus=true). Add M.size_percent helper. Keep the module PURE
    (no cwd resolution here — only carry the raw cwd string; resolution needs the launch dir + env which
    live in the IO-shell). Author the test cases FIRST (RED) in scene_test.lua, then implement (GREEN).
    Commit RED then GREEN: `test(06.1-04): RED scene cwd/focus/size` / `feat(06.1-04): scene parse cwd/focus/size + focus>1 + size%`.
  </action>
  <verify>
    <automated>lua5.4 cli/lib/scene_test.lua # GREEN</automated>
    <automated>grep -nE 'require\("wezterm"\)|io\.popen|os\.execute' cli/lib/scene.lua | grep -vE '^\s*--' | wc -l | grep -qx 0 # still pure</automated>
  </verify>
  <acceptance_criteria>
    - `lua5.4 cli/lib/scene_test.lua` exits 0 with cwd/focus/size + focus>1 + size-range cases
    - `cli/lib/scene.lua contains function M.validate_focus`
    - parse_pane_spec accepts cwd/focus/size and rejects size out of 1..100
    - scene.lua remains pure (purity grep returns 0)
  </acceptance_criteria>
  <done>scene.lua purely parses cwd/focus/size, enforces single-focus, and maps size to a split percent — tests green.</done>
</task>

<task type="tdd" tdd="true">
  <name>Task 2: RED/GREEN — recipe.lua schema: per-pane cwd/focus/size, top-level cwd, [[pane]] alias, migration aliases (D-04/D-07)</name>
  <read_first>
    - cli/lib/recipe.lua (pane_table_to_spec, recipe_to_args, load_and_map — extend the spec mapping)
    - cli/lib/recipe_test.lua (existing schema round-trip cases)
    - cli/lib/scene.lua (the now-extended parse_pane_spec that recipe specs round-trip through)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md (Pitfall 5 comma caveat — adding fields inherits the comma-in-command limitation; the refreshed seeds in Plan 07 must stay comma-safe)
  </read_first>
  <behavior>
    - a [[pane]] (alias of [[panes]]) entry with command/cmd + color + title + cwd + focus + size maps to a --pane spec string carrying cwd=/focus=/size= (in addition to cmd=/color=/title=)
    - top-level recipe cwd is carried into args (tab-level default cwd, D-07) — recipe_to_args returns args.cwd
    - deprecated top-level color/title still accepted as aliases (migration, D-04); [[panes]] still accepted (existing seeds)
    - bare-command fast path preserved when only command is present (comma-safe seeds)
    - load_and_map still validates layout/color via the reused scene validators (single source) and pcall-wraps tinytoml (no traceback)
  </behavior>
  <action>
    Extend pane_table_to_spec to append cwd=/focus=/size= segments when present (after cmd=, before/among
    color=/title= — order-independent for parse_pane_spec). Extend recipe_to_args to read recipe.pane as an
    alias for recipe.panes and carry recipe.cwd into args.cwd. Keep load_and_map's pcall + reused validators.
    Author RED cases first in recipe_test.lua (new-field round-trip, [[pane]] alias, top-level cwd, migration
    alias), then implement GREEN. NOTE the Pitfall-5 comma caveat in the header (a comma inside a multi-field
    command still mis-splits; the Plan 07 seeds avoid it). Commit RED then GREEN:
    `test(06.1-04): RED recipe schema` / `feat(06.1-04): recipe cwd/focus/size + [[pane]] alias + migration (D-04/D-07)`.
  </action>
  <verify>
    <automated>lua5.4 cli/lib/recipe_test.lua # GREEN</automated>
    <automated>grep -nE 'io\.|os\.execute|os\.getenv|require\("wezterm"\)' cli/lib/recipe.lua | grep -vE '^\s*--' | wc -l | grep -qx 0 # still pure</automated>
  </verify>
  <acceptance_criteria>
    - `lua5.4 cli/lib/recipe_test.lua` exits 0 with new-field + alias + migration cases
    - `cli/lib/recipe.lua contains cwd` (per-pane + top-level mapping)
    - [[pane]] and [[panes]] both round-trip; deprecated top-level color/title still accepted (D-04)
    - recipe.lua remains pure
  </acceptance_criteria>
  <done>recipe schema carries cwd/focus/size + top-level cwd, accepts [[pane]]/[[panes]] + migration aliases, reuses the scene validators — tests green.</done>
</task>

<task type="tdd" tdd="true">
  <name>Task 3: GREEN — scene.lua IO-shell: spawn --cwd clean pane, OSC tab color, size%/focus apply; spec.lua registration (D-01/D-02/D-03/D-06/D-08/D-16)</name>
  <read_first>
    - cli/commands/scene.lua (run_new Phase A spawn / Phase B style+cmd / tab-level styling / focus; the run_capture_pane_id + DIR_FLAG + shquote helpers)
    - cli/lib/color.lua (build_user_var_octal for the pane-targeted WEZTERM_TAB_COLOR emit; build_osc11/build_osc1337 for per-pane styling — already reused)
    - cli/lib/cwd.lua (resolve + validate — the IO-shell passes the launch dir = the CLI process $PWD and a real env snapshot)
    - cli/spec.lua (lines ~164-195 scene registration; the --pane option help string lists the segment keys)
    - tests/cli/spec_test.lua (how spec registration is asserted)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md (Open Q1: launch dir = CLI process $PWD; Pattern 3 spawn/split --cwd/--percent; Pitfall 2 send-text printf; "Map recipe size percent onto the split step")
  </read_first>
  <behavior>
    - Phase A spawn/split now passes `--cwd <resolved>` for each pane: the first pane's spawn uses the
      tab-level/launch cwd; each split uses its pane's resolved cwd (default = launch dir, D-07). The
      pane opens IN that dir — NO `cd` line is sent (D-08). cwd resolved via cli/lib/cwd.resolve(value,
      launch_dir, env) where launch_dir = os.getenv("PWD") (CLI process cwd, Open Q1) and env is a
      snapshot; validate-before-emit rejects $(...)/unset $ENV with ZERO mux calls.
    - size: a pane with size=N overrides the equal-share --percent for ITS split step (scene.size_percent)
    - focus: after build, activate-pane on the focus=true pane if present (D-05); else keep the main pane (pane 1) default; >1 focus already rejected in validate-before-emit
    - tab-level color: emitted as WEZTERM_TAB_COLOR via OSC to the scene's tab pane(s) using
      color.build_user_var_octal through the existing send-text printf path — NOT via set-tab-title prefix.
      scene.lua NO LONGER requires tablib.parse_stored/merge_title (dependency removed, D-04). Tab-level
      title (if given) still set via pure-text set-tab-title.
    - every cwd value is shquote'd before reaching os.execute (security)
  </behavior>
  <action>
    Edit cli/commands/scene.lua: `local color = require("cli.lib.color")`, `local cwdlib = require("cli.lib.cwd")`.
    In Step 0 validate-before-emit, add cwd validation (cwdlib.validate per pane + tab-level) and
    scenelib.validate_focus over the parsed list; bail with the exact error + ZERO mux calls on failure.
    In Phase A, resolve each pane's cwd (default launch dir) and append `--cwd <shquote(resolved)>` to the
    spawn and split-pane command strings; apply size% by using scenelib.size_percent(parsed, step.percent)
    for the split's --percent. In the tab-level styling block, REPLACE the tablib.parse_stored/merge_title
    read-modify-write with: if args.color, emit color.build_user_var_octal("WEZTERM_TAB_COLOR", normalized)
    to the tab's first pane via the existing send-text printf payload; if args.title, set pure text via
    set-tab-title --tab-id. Remove `local tablib = require(...)` if it becomes unused. In Step 4 focus,
    activate-pane on the focus=true pane id if one was parsed, else pane_ids[1]. Then register cwd/focus/size
    in cli/spec.lua: update the scene_new --pane help string to list the new segment keys, and add a
    `--cwd` tab-level option to scene new (mirrors --color/--title) so completion/`wez keys` surface it
    (D-16); update spec_test.lua assertions accordingly. Commit GREEN:
    `feat(06.1-04): scene clean-pane --cwd + OSC tab color + size/focus + spec (D-02/D-06/D-08)`.
  </action>
  <verify>
    <automated>lua5.4 tests/cli/spec_test.lua # spec registration green</automated>
    <automated>grep -q -- '--cwd' cli/commands/scene.lua # spawn uses --cwd (clean pane)</automated>
    <automated>grep -q 'WEZTERM_TAB_COLOR' cli/commands/scene.lua # tab color via OSC, not encoding</automated>
    <automated>grep -vE '^\s*--' cli/commands/scene.lua | grep -c 'parse_stored\|merge_title' | grep -qx 0 # encoding dependency removed (non-comment)</automated>
    <automated>./tools/run-tests.sh # full suite green (scene_launch_test, recipe_test, scene_test, spec_test)</automated>
  </verify>
  <acceptance_criteria>
    - `cli/commands/scene.lua contains --cwd` and `WEZTERM_TAB_COLOR`
    - No non-comment `parse_stored`/`merge_title` reference remains in scene.lua (encoding dependency removed, D-04)
    - `lua5.4 tests/cli/spec_test.lua` passes with cwd/focus/size segment + `--cwd` flag registered (D-16)
    - `./tools/run-tests.sh` exits 0 (full suite, no regression)
    - Live spawn `--cwd` round-trip is verified in Plan 07's integration test (cross-plan); this plan's gate is the unit + spec suite
  </acceptance_criteria>
  <done>Scene panes spawn clean in their target cwd (D-08), size%/focus apply (D-05/D-06), tab color rides WEZTERM_TAB_COLOR via OSC (D-02/D-03/D-04), new keys registered in spec (D-16), full suite green.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Recipe/CLI value → os.execute (spawn/split/send-text) | cwd/command/color/title values from a TOML file or --pane flag reach the shell + pane TTY |
| Recipe name → io.open path | (Handled in Plan 05's launch path; recipe.lua guard_name unchanged here) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06.1-08 | Elevation | --cwd value → spawn | mitigate | cwdlib.validate rejects $(...)/backticks/unset $ENV before emit; the resolved path is shquote'd before os.execute (RESEARCH Security Domain "cwd grammar shell evaluation" + "Shell command injection"). |
| T-06.1-09 | Tampering | per-pane command → send-text | mitigate | Startup command sent as a DISTINCT trailing line, never concatenated into an escape (T-04-02, preserved); send-text payload shquote'd. |
| T-06.1-10 | Tampering | WEZTERM_TAB_COLOR OSC (scene tab) | mitigate | Emitted via color.build_user_var_octal (base64 value, octal-escaped printf payload) — control bytes neutralized (RESEARCH "OSC escape injection", Pitfall 2). |
| T-06.1-11 | DoS/Info | malformed recipe TOML | mitigate | recipe.load_and_map pcall-wraps tinytoml, translates to "could not parse TOML at line N" — no traceback (T-05-02, preserved). |
| T-06.1-SC | Tampering | npm/pip/cargo installs | accept | Zero external packages this phase (RESEARCH Package Legitimacy Audit). |
</threat_model>

<verification>
- `lua5.4 cli/lib/scene_test.lua`, `lua5.4 cli/lib/recipe_test.lua`, `lua5.4 tests/cli/spec_test.lua` all pass.
- `./tools/run-tests.sh` full suite green.
- grep confirms `--cwd` + `WEZTERM_TAB_COLOR` present and `parse_stored`/`merge_title` removed from scene.lua.
- Live clean-pane + cwd round-trip verification is owned by Plan 07 (integration test + recorded repro).
</verification>

<success_criteria>
- cwd/focus/size delivered end to end (parse → recipe → spawn) with clean-pane --cwd (D-08).
- Scene tab color decoupled to OSC WEZTERM_TAB_COLOR (D-02/D-03/D-04); encoding dependency removed.
- New surface registered in spec for completion/`wez keys` (D-16).
- Shared color + cwd modules reused (D-01) — no parallel copies.
</success_criteria>

<output>
Create `.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-04-SUMMARY.md` when done.
</output>
