---
phase: 06.1-tab-and-scene-identity-redesign
plan: 07
type: execute
wave: 4
depends_on: [04, 05, 06]
files_modified:
  - scenes/ai.toml
  - scenes/dev.toml
  - tests/integration/scene_cwd_integration_test.lua
  - tests/integration/install_config_load_integration_test.lua
  - docs/repro/h-06.1-tab-color-decouple.md
autonomous: false
requirements: [D-01, D-02, D-08, D-11, D-12, D-13, D-14, D-15]
user_setup: []
must_haves:
  truths:
    - "scenes/dev.toml is tall:mirrored, green tab color, 3 panes (editor green / working shell teal / git pane yellow) and round-trips through the loader to the same result as the equivalent scene new (D-13, SCEN-04)"
    - "scenes/ai.toml is tall, purple tab color, 2 panes (AI CLI purple + working shell teal), inheriting the launch dir (D-14)"
    - "The refreshed seeds are comma-safe (Pitfall 5) and validate through recipe.load_and_map"
    - "An integration test spawns scene panes with --cwd and reads back the pane cwd via `wezterm cli list --format json`, asserting the clean-pane cwd (D-08) when a live WezTerm is present"
    - "A recorded manual repro proves the decoupled tab color (no `cyan:` literal, active-pane-wins), clean-pane cwd (no visible `cd`), RotatePanes keys, #RRGGBBAA render-with-transparency, and refreshed scenes (launch ≡ new) against a live WezTerm session"
  artifacts:
    - path: "scenes/dev.toml"
      provides: "Refreshed dev seed: tall:mirrored, green, 3 styled panes (D-13)"
      contains: "tall:mirrored"
    - path: "scenes/ai.toml"
      provides: "Refreshed ai seed: tall, purple, 2 styled panes (D-14)"
      contains: "purple"
    - path: "tests/integration/scene_cwd_integration_test.lua"
      provides: "Live spawn --cwd round-trip e2e (D-08)"
      min_lines: 30
    - path: "docs/repro/h-06.1-tab-color-decouple.md"
      provides: "Recorded live-WezTerm repro for every 6.1 behavior change"
      min_lines: 40
  key_links:
    - from: "scenes/dev.toml"
      to: "recipe.load_and_map -> scene.run_new"
      via: "launch ≡ new structural equivalence (SCEN-04)"
      pattern: "\\[\\[pane"
    - from: "tests/integration/scene_cwd_integration_test.lua"
      to: "wezterm cli list --format json"
      via: "read-back pane cwd after spawn --cwd"
      pattern: "cli list"
---

<objective>
Refresh the `ai` and `dev` seed scenes to use the new rich schema (per-pane + tab colors, real
commands, cwd inheritance — D-13/D-14) like the proven `docker` scene, delivered copy-if-absent by
the existing seeder so a user's edited recipe is never overwritten (D-15). Then build the e2e
verification layer the operator explicitly asked for: (a) a `wezterm cli spawn --cwd` integration
test that reads back the pane cwd to prove the clean-pane behavior (D-08), an integration guard for
the shadow-detection + decoupled render in the existing install/config integration test, and (b) a
RECORDED manual repro against a LIVE WezTerm session covering every behavior change in the phase
(tab color decouple / active-pane-wins, clean-pane cwd with no visible `cd`, RotatePanes keys,
#RRGGBBAA render-with-transparency caveat, refreshed scenes round-tripping launch ≡ new).

This plan has a `checkpoint:human-verify` because GPU tab-bar RENDER and key-driven pane rotation
are not headlessly assertable — per CLAUDE.md "verify before declaring done", the maintainer
confirms the live behavior after the automated gates pass.

Purpose: ship the refreshed seeds and PROVE the whole redesign against a real running WezTerm.
Output: refreshed seed recipes + integration tests + a recorded repro doc.
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

# Prior-wave SUMMARYs (the schema + render + doctor this plan exercises):
@.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-04-SUMMARY.md
@.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-05-SUMMARY.md
@.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-06-SUMMARY.md

# The reference "new style" seed + the seeder contract + the e2e test template:
@scenes/docker.toml
@scenes/ai.toml
@scenes/dev.toml
@cli/commands/seed_scenes.lua
@cli/lib/recipe.lua
@tests/integration/install_config_load_integration_test.lua
@docs/agent-iteration.md
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: refresh scenes/dev.toml + scenes/ai.toml to the new schema (D-13/D-14/D-15)</name>
  <files>scenes/dev.toml, scenes/ai.toml</files>
  <read_first>
    - scenes/docker.toml (the proven new-style reference: layout + tab color + per-pane command/color)
    - scenes/dev.toml + scenes/ai.toml (the current 2-plain-shell-panes versions to replace)
    - cli/lib/recipe.lua (the extended schema — [[pane]]/[[panes]], command/cmd, color, cwd; the bare-command fast path + Pitfall 5 comma caveat)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-CONTEXT.md (D-13 dev: tall:mirrored, green, editor/shell/git panes green/teal/yellow; D-14 ai: tall, purple, AI CLI + shell purple/teal; D-15 copy-if-absent unchanged)
  </read_first>
  <behavior>
    - dev.toml: layout = "tall:mirrored", color = "green", 3 [[panes]]: editor pane (command runs $EDITOR or a portable editor, color green), working shell (command = "shell", color teal), git pane (command = a git status / lazygit-style command available cross-platform, color yellow). cwd omitted -> inherits launch dir (D-07).
    - ai.toml: layout = "tall", color = "purple", 2 [[panes]]: AI CLI pane (command = "claude", color purple), working shell (command = "shell", color teal). cwd inherits launch dir.
    - both round-trip through recipe.load_and_map to a valid args table (no parse/validate error) and are comma-safe (no comma inside a multi-field command — Pitfall 5)
  </behavior>
  <action>
    Rewrite scenes/dev.toml and scenes/ai.toml mirroring scenes/docker.toml's structure with the
    D-13/D-14 content. Use the editor/git commands per Claude's discretion for cross-platform
    availability (e.g. `$EDITOR` fallback, `git status` or a lazygit-style invocation) — keep each
    command comma-free so the multi-field color round-trip is safe (Pitfall 5). Keep the existing
    explanatory header comments (edit freely / copy-if-absent / NEVER overwrite). Add a TDD-style
    round-trip assertion to the recipe test surface (or a small fixture) proving both refreshed seeds
    load_and_map cleanly — author the assertion before finalizing the TOML so the schema is proven, not
    assumed. Commit: `feat(06.1-07): refresh ai + dev seed scenes (D-13/D-14)`.
  </action>
  <verify>
    <automated>grep -q 'tall:mirrored' scenes/dev.toml && grep -q '"green"' scenes/dev.toml && grep -q '"purple"' scenes/ai.toml</automated>
    <automated>lua5.4 -e 'package.path="cli/?.lua;cli/lib/?.lua;"..package.path; local r=require("cli.lib.recipe"); for _,f in ipairs({"scenes/dev.toml","scenes/ai.toml"}) do local fh=io.open(f,"rb"); local raw=fh:read("*a"); fh:close(); local m,e=r.load_and_map(raw); assert(m, f.." -> "..tostring(e)) end; print("OK")'</automated>
  </verify>
  <acceptance_criteria>
    - `scenes/dev.toml contains tall:mirrored` + green tab color + 3 panes; `scenes/ai.toml contains purple` + tall + 2 panes
    - Both seeds round-trip through `recipe.load_and_map` with NO error (asserted by the lua5.4 one-liner exiting 0)
    - Commands are comma-free (Pitfall 5 comma-safety)
    - The seeder is unchanged (copy-if-absent, D-15) — only the in-repo seed CONTENT changed
  </acceptance_criteria>
  <done>ai + dev seeds refreshed to the new rich schema, round-trip cleanly, comma-safe, delivered copy-if-absent (D-13/D-14/D-15).</done>
</task>

<task type="auto">
  <name>Task 2: integration tests — live spawn --cwd round-trip (D-08) + shadow/render guard</name>
  <files>tests/integration/scene_cwd_integration_test.lua, tests/integration/install_config_load_integration_test.lua</files>
  <read_first>
    - tests/integration/install_config_load_integration_test.lua (the existing e2e pattern: stage the config tree, load the managed block under a WezTerm-like package.path, assert no error — add a guard here)
    - cli/commands/scene.lua (run_new spawn --cwd path; read_topology via `wezterm cli list --format json`)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md (Validation Architecture: WEZTERM_INTEGRATION=1 runs tests/integration/*_integration_test.lua; Environment Availability — live wezterm present; Open Q1 launch dir)
    - tools/run-tests.sh (how integration tests are discovered + the WEZTERM_INTEGRATION gate)
  </read_first>
  <action>
    Create tests/integration/scene_cwd_integration_test.lua: guarded by WEZTERM_INTEGRATION=1 (skip
    cleanly + exit 0 when unset or when `wezterm cli list` is unreachable, mirroring the existing
    integration test's skip pattern). When live: spawn a scene (or a single split) with a known --cwd
    via the scene path, read back `wezterm cli list --format json`, and assert the spawned pane's cwd
    matches the resolved target — proving the clean-pane spawn-with-cwd (D-08). Also extend
    install_config_load_integration_test.lua with a guard that loads the refreshed format-tab-title
    handler and asserts the managed block still loads cleanly (no error) under the WezTerm-like
    package.path (catches a render-layer regression from Plan 05). Keep both pure-skip when headless so
    CI stays green. Commit: `test(06.1-07): live spawn --cwd integration + config-load guard`.
  </action>
  <verify>
    <automated>lua5.4 tests/integration/scene_cwd_integration_test.lua # exits 0 (skips cleanly when WEZTERM_INTEGRATION unset)</automated>
    <automated>WEZTERM_INTEGRATION=1 ./tools/run-tests.sh # full + integration suite green against the live wezterm</automated>
  </verify>
  <acceptance_criteria>
    - `tests/integration/scene_cwd_integration_test.lua` exists and skips cleanly (exit 0) when WEZTERM_INTEGRATION is unset
    - Under `WEZTERM_INTEGRATION=1` with a live WezTerm, it spawns with `--cwd` and asserts the read-back pane cwd matches the target (D-08)
    - `WEZTERM_INTEGRATION=1 ./tools/run-tests.sh` exits 0 (full + integration green)
    - The install/config integration test guards that the refreshed render layer loads cleanly
  </acceptance_criteria>
  <done>An integration test proves clean-pane spawn --cwd against the live WezTerm, with a render-layer load guard; both skip cleanly when headless.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: live-WezTerm repro of every 6.1 behavior change (CLAUDE.md verify-before-done)</name>
  <files>docs/repro/h-06.1-tab-color-decouple.md</files>
  <action>
    Rebuild the CLI (`make build`) and reinstall the managed config (or `wez update`) so the live
    session runs the new code, then drive the live repro below and RECORD every result (pass/fail +
    observed output) in docs/repro/h-06.1-tab-color-decouple.md per the hypothesis playbook
    (docs/agent-iteration.md). Do NOT mark the phase done on "should work" — the recorded repro IS the
    acceptance evidence. Commit: `docs(06.1-07): recorded live repro of the tab/scene redesign`.
  </action>
  <what-built>
    The full Phase 6.1 redesign is implemented and the automated gates pass:
    - Tab color decoupled to WEZTERM_TAB_COLOR via OSC; tab title is pure text (Plans 03/04).
    - format-tab-title reads the active pane's color, accepts #RRGGBBAA, no prefix (Plan 05).
    - Scene panes spawn with --cwd (clean pane) + size/focus; ai/dev seeds refreshed (Plans 04/07).
    - RotatePanes Alt+Shift+R / Alt+Shift+E bound; search overlay documented (Plan 05).
    - `wez doctor` shadow-detection core gate added (Plan 06).
    The CLI has been rebuilt (`make build`) and the managed config reinstalled (or `wez update`) so
    the live session runs the new code.
  </what-built>
  <how-to-verify>
    Against a LIVE WezTerm session (per CLAUDE.md verify-before-done; record results in
    docs/repro/h-06.1-tab-color-decouple.md):
    1. Tab color decouple + active-pane-wins (D-02): run `wez tab color cyan`. The tab shows the CYAN
       accent with NO literal `cyan:` text in the title. Set two panes in one tab to different colors
       (`wez pane color green` in one, `wez pane color purple` in another); confirm the tab accent
       follows the FOCUSED pane as you switch.
    2. Clean-pane cwd (D-08): `wez scene launch dev` from a repo dir. Each pane opens IN the repo dir
       with NO visible `cd <path>` line in the scrollback; the git pane shows the repo's status.
    3. RotatePanes (D-12): in a multi-pane tab press Alt+Shift+R (clockwise) and Alt+Shift+E
       (counter-clockwise); confirm panes rotate; Alt+Shift+Z still toggles zoom.
    4. Search overlay (item 8): Ctrl+Shift+F opens search; Ctrl+R cycles case-sensitive /
       case-insensitive / regex.
    5. Alpha (D-09): `wez pane color '#1a204080'` does NOT error (the 8-digit value is accepted);
       confirm it renders solid unless window transparency is enabled (the documented caveat).
    6. Refreshed scenes (D-13/D-14, SCEN-04): `wez scene launch dev` ≡ the equivalent `wez scene new`
       (same layout/colors/panes); `wez scene launch ai` shows the purple AI + teal shell panes.
    7. Shadow detection (D-11): temporarily add an inline `wezterm.on("format-tab-title", ...)` to your
       wezterm.lua; confirm `wez doctor` FAILS naming it; remove it; confirm `wez doctor` passes (exit 0).
  </how-to-verify>
  <verify>
    <human-check>All seven live checks pass and are recorded with observed output in docs/repro/h-06.1-tab-color-decouple.md (maintainer types "approved").</human-check>
  </verify>
  <resume-signal>Type "approved" once the live repro passes, or describe what failed.</resume-signal>
  <acceptance_criteria>
    - docs/repro/h-06.1-tab-color-decouple.md exists with a recorded result for each of the 7 checks
    - No `cyan:` literal appears in the tab title (check 1); no visible `cd` line in scene panes (check 2)
    - `wez doctor` fails on a planted shadowing handler and passes once removed (check 7)
    - The maintainer approves the live behavior ("approved")
  </acceptance_criteria>
  <done>Every 6.1 behavior change is verified against a live WezTerm and recorded; the maintainer approves.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| seed recipe command/color → spawn/send-text | Seed .toml values flow through the same validated scene spawn path |
| live mux JSON → integration test | `wezterm cli list --format json` output is parsed in the test (read-only) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06.1-16 | Tampering | seed recipe values | mitigate | Seeds flow through recipe.load_and_map (pcall, reused validators) and the validated scene spawn path (shquote, distinct command line) — no new emit path; the seeds are repo-controlled content. |
| T-06.1-17 | Info | integration test reading mux JSON | accept | The test only reads `wezterm cli list` output to assert cwd; no secrets, local single-user. |
| T-06.1-SC | Tampering | npm/pip/cargo installs | accept | Zero external packages this phase (RESEARCH Package Legitimacy Audit). |
</threat_model>

<verification>
- `lua5.4 tests/integration/scene_cwd_integration_test.lua` exits 0 (skips when headless).
- `./tools/run-tests.sh` and `WEZTERM_INTEGRATION=1 ./tools/run-tests.sh` both green.
- Both refreshed seeds load_and_map cleanly.
- The human-verify checkpoint records a passing live repro for all seven behaviors in docs/repro/h-06.1-tab-color-decouple.md.
</verification>

<success_criteria>
- ai + dev seeds refreshed to the rich schema, copy-if-absent (D-13/D-14/D-15).
- Clean-pane spawn --cwd proven by an integration test (D-08).
- Every 6.1 behavior change verified against a live WezTerm and recorded (CLAUDE.md verify-before-done).
</success_criteria>

<output>
Create `.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-07-SUMMARY.md` when done.
</output>
