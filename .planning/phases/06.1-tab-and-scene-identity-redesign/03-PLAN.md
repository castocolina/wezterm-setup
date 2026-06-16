---
phase: 06.1-tab-and-scene-identity-redesign
plan: 03
type: tdd
wave: 2
depends_on: [01]
files_modified:
  - cli/commands/tab.lua
  - cli/commands/tab_test.lua
  - cli/commands/pane.lua
  - cli/commands/pane_test.lua
autonomous: true
requirements: [D-01, D-02, D-03, D-04, D-09]
must_haves:
  truths:
    - "`wez tab color <name>` emits WEZTERM_TAB_COLOR via OSC 1337 to the tab's pane(s) — it no longer writes a `<color>:<title>` prefix into the tab title (D-02/D-03)"
    - "`wez tab title <text>` sets pure tab title text via set-tab-title with NO color prefix (D-04 decouple)"
    - "tab.lua and pane.lua both consume cli/lib/color.lua — the duplicated strip_alpha/normalize_color/validate_color and the OSC builders are DELETED, not copied (D-01)"
    - "An 8-digit #RRGGBBAA passed to `wez tab color`/`wez pane color` validates and is preserved (D-09)"
    - "parse_stored/merge_title survive ONLY as a migration parse-and-warn helper, removed from the steady-state write path (D-04)"
  artifacts:
    - path: "cli/commands/tab.lua"
      provides: "Tab color via OSC WEZTERM_TAB_COLOR + pure-text title; consumes cli/lib/color (D-01/D-02/D-03/D-04)"
      contains: "require(\"cli.lib.color\")"
    - path: "cli/commands/pane.lua"
      provides: "Pane color rewired to cli/lib/color (duplicate color logic deleted, D-01/D-09)"
      contains: "require(\"cli.lib.color\")"
  key_links:
    - from: "cli/commands/tab.lua"
      to: "WEZTERM_TAB_COLOR user var"
      via: "OSC 1337 SetUserVar emit (color.build_osc1337 / build_user_var_octal)"
      pattern: "WEZTERM_TAB_COLOR"
    - from: "cli/commands/tab.lua"
      to: "cli/lib/color.lua"
      via: "shared module require"
      pattern: "require\\(\"cli\\.lib\\.color\"\\)"
---

<objective>
Decouple tab COLOR from tab TITLE in the standalone `wez tab` surface — the headline cleanup
of the phase. Today `wez tab color green` does a read-modify-write of the tab's stored title
into the `"green:title"` prefix encoding; the renderer parses that back. Per D-02/D-03/D-04
this plan switches `wez tab color` to emit `WEZTERM_TAB_COLOR` via OSC 1337 SetUserVar (the
SAME channel panes already use), and `wez tab title` to write PURE title text via
`set-tab-title`. The `<color>:<title>` encoding is dropped from the steady state;
`parse_stored`/`merge_title` are kept ONLY as a one-time migration parse-and-warn (D-04).

Simultaneously this plan executes the D-01 / `/reducing-entropy` consolidation for these two
modules: `tab.lua` and `pane.lua` rewire to consume `cli/lib/color.lua` (built in Plan 01),
and their DUPLICATED `strip_alpha`/`normalize_color`/`validate_color` + the OSC builders are
DELETED. Net result: less total code, one color implementation, alpha preserved (D-09) in one
place.

Purpose: kill the encoding that caused the `cyan:` literal-prefix bug, unify tab + pane on the
two-user-var model, and collapse the duplicated color logic into the shared module.
Output: rewired `cli/commands/tab.lua` + `cli/commands/pane.lua` (and their tests).
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
@.planning/decisions/tab-title-format.md
@.planning/decisions/wezterm-cli-surface.md

# The shared module this plan consumes (built in Plan 01 — read its SUMMARY + the module):
@.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-01-SUMMARY.md
@cli/lib/color.lua

# The modules being rewired:
@cli/commands/tab.lua
@cli/commands/tab_test.lua
@cli/commands/pane.lua
@cli/commands/pane_test.lua
</context>

<reducing_entropy_note>
D-01 / `/reducing-entropy`: this plan is where the duplication actually gets DELETED. Before:
strip_alpha/normalize_color/validate_color exist 2x (pane.lua + tab.lua) and the OSC builders +
base64 exist in pane.lua. After: both modules `require("cli.lib.color")` and re-export or call
through; the local copies are removed. Measure the end state — net line deletion vs. Plan 01's
addition. Do NOT keep a "compat shim" copy; consumers call the shared module directly.
</reducing_entropy_note>

<tasks>

<task type="tdd" tdd="true">
  <name>Task 1: RED/GREEN — rewire pane.lua to cli/lib/color.lua, delete its duplicate color logic, accept #RRGGBBAA (D-01/D-09)</name>
  <read_first>
    - cli/lib/color.lua (the shared exports: COLOR_NAMES, MUTED_BG, normalize_color, validate_color, build_osc11, build_reset_osc11, build_osc1337, build_user_var_octal)
    - cli/commands/pane.lua (the duplicate strip_alpha/normalize_color/validate_color + base64/OSC builders to DELETE; M.run_color/M.run_title call sites; M.OPACITY_SUPPORTED + the alpha warning)
    - cli/commands/pane_test.lua (lines 26-30 strip_alpha cases INVERT under D-09; build_osc1337/MUTED_BG cases stay)
  </read_first>
  <behavior>
    - validate_color("#1a2040cc") -> (true, "#1a2040cc") via the shared module (8-digit PRESERVED, D-09)
    - `wez pane color green` still emits OSC 11 (MUTED_BG.green) + OSC 1337 WEZTERM_TAB_COLOR=green
    - `wez pane color reset` still emits reset-OSC11 + empty WEZTERM_TAB_COLOR
    - pane.lua exposes the same public surface (M.COLOR_NAMES, M.MUTED_BG, M.build_osc11, M.build_osc1337, M.run_color, M.run_title, M.ICONS, M.resolve_title) by re-exporting from cli/lib/color (+ cli/lib/title) — no local re-definition
    - the opacity-warning path: since alpha is no longer stripped (D-09), reconcile the --opacity message; the named palette + solid render stays the default (Pitfall 4 — alpha renders only with window transparency; do NOT silently drop the 8th digit)
  </behavior>
  <action>
    First UPDATE pane_test.lua: invert the strip_alpha cases (the shared module preserves #rrggbbaa,
    so assert validate_color("#1a2040cc") -> (true,"#1a2040cc") and remove/replace the old "strip to 6"
    assertions); keep build_osc1337/MUTED_BG/run_color emission assertions. Run it RED. Then edit
    pane.lua: `local color = require("cli.lib.color")`; DELETE the local COLOR_NAMES, MUTED_BG,
    strip_alpha, normalize_color, validate_color, base64_encode, build_osc11, build_reset_osc11,
    build_osc1337, and re-export them from `color` (M.COLOR_NAMES = color.COLOR_NAMES, etc.) so the
    public surface is unchanged for current callers. Rewire run_color to call color.validate_color and
    color.build_osc11/build_osc1337. Adjust the --opacity reconciliation per D-09 (accept #rrggbbaa,
    keep the cross-platform transparency caveat note; do not strip). Commit RED then GREEN:
    `test(06.1-03): RED pane.lua on shared color` / `refactor(06.1-03): pane.lua consumes cli/lib/color`.
  </action>
  <verify>
    <automated>lua5.4 cli/commands/pane_test.lua # GREEN after rewire</automated>
    <automated>grep -cE 'function M\.(strip_alpha|normalize_color|validate_color|build_osc11|build_osc1337)' cli/commands/pane.lua | grep -qx 0 # duplicates DELETED (now re-exported assignments, not function defs)</automated>
    <automated>grep -q 'require("cli.lib.color")' cli/commands/pane.lua</automated>
  </verify>
  <acceptance_criteria>
    - `lua5.4 cli/commands/pane_test.lua` exits 0 with the inverted (alpha-preserving) cases
    - `cli/commands/pane.lua contains require("cli.lib.color")`
    - pane.lua defines ZERO local `function M.strip_alpha/normalize_color/validate_color/build_osc11/build_osc1337` (they are re-exports/assignments from the shared module) — verified by the grep returning 0 function definitions
    - `wez pane color #1a2040cc` validates (D-09) — assert via the test, not manual
  </acceptance_criteria>
  <done>pane.lua consumes cli/lib/color, its duplicate color logic is deleted, #RRGGBBAA is accepted, public surface unchanged, tests green.</done>
</task>

<task type="tdd" tdd="true">
  <name>Task 2: RED/GREEN — `wez tab color` emits WEZTERM_TAB_COLOR via OSC; `wez tab title` writes pure text; encoding demoted to migration-only (D-02/D-03/D-04)</name>
  <read_first>
    - cli/lib/color.lua (build_osc1337 / build_user_var_octal / validate_color)
    - cli/commands/tab.lua (current parse_stored/merge_title/read_current_tab/write_tab_title/run_color/run_title — the read-modify-write encoding to dismantle; shquote helper)
    - cli/commands/tab_test.lua (current parse_stored/merge_title cases — most become migration-only or are removed)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md (Pattern 1 OSC 1337; the io.write vs send-text decision — `wez tab color` runs INSIDE the target pane so it can io.write directly to the active pane TTY, like `wez pane color`; Open Question 3 migration-warn surface)
    - .planning/decisions/wezterm-cli-surface.md (set-tab-title for pure title; no set-user-var subcommand)
  </read_first>
  <behavior>
    - `wez tab color green`: emits color.build_osc1337("WEZTERM_TAB_COLOR", "green") to the active pane TTY (io.write, same as `wez pane color`'s accent emit) — does NOT call set-tab-title, does NOT write a "green:" prefix
    - `wez tab color reset`: emits WEZTERM_TAB_COLOR="" (clears the accent)
    - `wez tab color #1a2040cc`: validates (D-09) and emits the 8-digit value
    - `wez tab color blue --title api`: emits WEZTERM_TAB_COLOR=blue (OSC) AND set-tab-title 'api' (pure text via the shared title resolver) — two distinct writes, no encoding
    - `wez tab title api`: set-tab-title 'api' (pure text, no color prefix); `wez tab title reset` -> set-tab-title '' (empty)
    - migration: a parse-and-warn helper still recognizes a legacy "<color>:<title>" stored title and warns ONCE on the CLI side when read, then writes the clean form — but the steady-state write path never produces the prefix
    - invalid color still bails validate-before-emit (exit 2) with ZERO writes
  </behavior>
  <action>
    Update tab_test.lua FIRST (RED): drop the merge_title "<color>:<title>" assertions from the
    steady state; assert run_color emits a WEZTERM_TAB_COLOR OSC (not a set-tab-title prefix) — test by
    capturing io.write output or by asserting on the emitted escape via a seam; assert run_title writes
    pure text; keep ONE migration test that parse_stored still splits a legacy prefix (for the warn path).
    Run RED. Then edit tab.lua: `local color = require("cli.lib.color")` and `local title = require("cli.lib.title")`;
    DELETE the duplicate strip_alpha/normalize_color/validate_color (use color.*); rework run_color to
    validate via color.validate_color then io.write(color.build_osc1337("WEZTERM_TAB_COLOR", normalized))
    for the accent, and if --title is present additionally write_tab_title(title.resolve_title_str(args.title)).
    Rework run_title to write pure resolved text via set-tab-title (no merge). Keep parse_stored ONLY as a
    migration helper (rename intent in a comment to "legacy migration parse-and-warn, D-04") and DELETE
    merge_title from the steady-state path (keep a minimal legacy-detect that warns once, per Open Q3).
    Reuse the existing shquote + write_tab_title for the pure-text title write. Commit RED then GREEN:
    `test(06.1-03): RED tab color OSC decouple` / `feat(06.1-03): decouple tab color (OSC) from title (D-02/D-03/D-04)`.
  </action>
  <verify>
    <automated>lua5.4 cli/commands/tab_test.lua # GREEN</automated>
    <automated>grep -q 'WEZTERM_TAB_COLOR' cli/commands/tab.lua # tab now emits the user var</automated>
    <automated>grep -vE '^\s*--' cli/commands/tab.lua | grep -c 'merge_title' | grep -qx 0 # merge_title removed from steady-state CODE (comments allowed)</automated>
    <automated>grep -q 'require("cli.lib.color")' cli/commands/tab.lua</automated>
  </verify>
  <acceptance_criteria>
    - `lua5.4 cli/commands/tab_test.lua` exits 0 with the decoupled assertions
    - `cli/commands/tab.lua contains WEZTERM_TAB_COLOR` (OSC emit) and `require("cli.lib.color")`
    - No non-comment `merge_title` call remains in tab.lua steady state (grep returns 0) — the encoding is dropped from the write path (D-04)
    - The combined `wez tab color blue --title api` path performs TWO writes (OSC color + pure-text set-tab-title), asserted in the test
  </acceptance_criteria>
  <done>`wez tab color` emits WEZTERM_TAB_COLOR via OSC, `wez tab title` writes pure text, the `<color>:<title>` encoding is migration-only, tab.lua consumes the shared color module, tests green.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| CLI color/title value → pane TTY (OSC) / set-tab-title arg | User-supplied color emitted as base64 OSC; title passed as a set-tab-title shell argument |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06.1-05 | Tampering | WEZTERM_TAB_COLOR OSC emit | mitigate | Value base64-encoded by color.build_osc1337 (control/ESC bytes neutralized) — RESEARCH "OSC escape injection". |
| T-06.1-06 | Tampering | set-tab-title title arg | mitigate | The pure-text title is shquote'd (single-quote escaper, already in tab.lua) before os.execute — RESEARCH "Shell command injection". Title resolved through the shared title resolver (no new code path). |
| T-06.1-07 | Tampering | validate-before-emit | mitigate | Invalid color bails (exit 2) with ZERO writes — preserves the no-half-applied-state invariant (CLAUDE.md). |
| T-06.1-SC | Tampering | npm/pip/cargo installs | accept | Zero external packages this phase (RESEARCH Package Legitimacy Audit). |
</threat_model>

<verification>
- `lua5.4 cli/commands/pane_test.lua` and `lua5.4 cli/commands/tab_test.lua` both pass.
- `./tools/run-tests.sh` full suite green (note: scene.lua still references tablib.parse_stored/merge_title — Plan 04 rewires it; confirm scene tests still pass because parse_stored survives as a migration helper. If a scene test breaks because merge_title is gone, that is expected ownership of Plan 04 — coordinate: keep merge_title callable from scene.lua until Plan 04 lands, OR ensure Plan 04 is the SAME wave-2 sibling. See note below.).
- grep confirms WEZTERM_TAB_COLOR emit in tab.lua and require("cli.lib.color") in both modules.
- Live repro (deferred to Plan 07 e2e): `wez tab color cyan` shows the accent with NO `cyan:` literal in the tab title.
</verification>

<cross_plan_note>
scene.lua (Plan 04) currently calls tablib.parse_stored/merge_title for its tab-level styling. To
keep Wave 2 parallel-safe, this plan KEEPS parse_stored AND merge_title as callable functions
(merge_title demoted to migration-only, not deleted from the module — only removed from tab.lua's
OWN steady-state write path). Plan 04 then removes scene.lua's dependency on them entirely. The
grep gate above checks merge_title is gone from tab.lua's run_color/run_title paths (non-comment),
not that the function symbol is deleted. This avoids breaking scene tests before Plan 04 runs.
</cross_plan_note>

<success_criteria>
- `wez tab color` emits WEZTERM_TAB_COLOR via OSC; `wez tab title` writes pure text (D-02/D-03/D-04).
- tab.lua + pane.lua consume cli/lib/color; duplicated color logic deleted (D-01).
- #RRGGBBAA accepted everywhere (D-09).
- All affected unit tests green; full suite green.
</success_criteria>

<output>
Create `.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-03-SUMMARY.md` when done.
</output>
