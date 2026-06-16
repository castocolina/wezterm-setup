---
phase: 06.1-tab-and-scene-identity-redesign
plan: 01
type: tdd
wave: 1
depends_on: []
files_modified:
  - cli/lib/color.lua
  - cli/lib/color_test.lua
autonomous: true
requirements: [D-01, D-03, D-09]
must_haves:
  truths:
    - "A single cli/lib/color.lua module owns color normalize/validate, the 10-name palette + muted-bg map, base64, and the OSC 11 / OSC 1337 builders — no second copy exists"
    - "An 8-digit #RRGGBBAA color validates and is preserved (alpha no longer stripped) per D-09"
    - "rgba()/named/#rgb/#rrggbb all normalize+validate through the one module"
  artifacts:
    - path: "cli/lib/color.lua"
      provides: "Shared color normalize/validate, palette, base64, OSC builders (D-01 consolidation)"
      exports: ["normalize_color", "validate_color", "COLOR_NAMES", "MUTED_BG", "build_osc11", "build_reset_osc11", "build_osc1337", "build_user_var_octal"]
      min_lines: 80
    - path: "cli/lib/color_test.lua"
      provides: "RED-first fixture suite for the shared color module"
      min_lines: 60
  key_links:
    - from: "cli/lib/color.lua"
      to: "(pure)"
      via: "no wezterm / no io / no os.execute"
      pattern: "^local M = \\{\\}"
---

<objective>
Create the shared `cli/lib/color.lua` module that consolidates the color logic currently
DUPLICATED verbatim across `cli/commands/pane.lua` and `cli/commands/tab.lua`
(`strip_alpha` / `normalize_color` / `validate_color`) plus the OSC builders + base64
encoder (currently only in `pane.lua`). This is the D-01 / `/reducing-entropy` foundation:
one well-designed implementation that every entry point (pane, tab, scene, recipe render)
will consume in later waves — no parallel copies.

This plan also lands the D-09 alpha behavior change at the source: `#RRGGBBAA` is ACCEPTED
and PRESERVED (stop stripping the 8th digit). `rgba()` parsing is added here only if cheap
(Claude's discretion, D-09); `#RRGGBBAA` is the must-have floor.

Purpose: Eliminate the entropy the maintainer flagged (D-01) by deleting duplicated color
code in favor of one shared module, and fix the alpha-stripping defect (D-09) in exactly one
place so it can never diverge again. `/reducing-entropy` principle applied: measure the end
state — net deletion of duplicated helpers in Wave 2 once consumers rewire.
Output: `cli/lib/color.lua` (new shared module) + `cli/lib/color_test.lua` (TDD suite).
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

# Source-of-truth files being consolidated (read to lift logic verbatim — do NOT re-derive):
@cli/commands/pane.lua
@cli/commands/tab.lua
@cli/lib/scene.lua
@cli/lib/title.lua
@cli/lib/scene_test.lua
</context>

<reducing_entropy_note>
Per D-01 the maintainer requires `/reducing-entropy` during planning. Applied mindset:
**less total code in the final codebase, measured at the end state.** `pane.lua` and `tab.lua`
hold byte-identical `strip_alpha`/`normalize_color`/`validate_color`; `pane.lua` additionally
owns `base64_encode`/`build_osc11`/`build_reset_osc11`/`build_osc1337`. This plan LIFTS those
into one module so Wave 2 can DELETE both copies and re-export from the shared module. The win
is realized as net deletion across plans 01→03→04, not in this plan alone.
</reducing_entropy_note>

<tasks>

<task type="tdd" tdd="true">
  <name>Task 1: RED — author cli/lib/color_test.lua against the not-yet-existing shared module</name>
  <read_first>
    - cli/commands/pane.lua (the canonical source of normalize_color / validate_color / strip_alpha / base64_encode / build_osc11 / build_reset_osc11 / build_osc1337 / MUTED_BG / COLOR_NAMES)
    - cli/commands/tab.lua (the duplicate normalize/validate/strip_alpha — confirm byte-identical so the consolidated behavior is a superset)
    - cli/lib/scene_test.lua (mirror this exact check/eq/teq harness; runs under plain lua5.4, no wezterm)
    - cli/commands/pane_test.lua (lines 26-30 — existing strip_alpha cases that INVERT under D-09)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md (Pattern 1 OSC shape, Pitfall 4 alpha-ignored caveat, D-09)
  </read_first>
  <behavior>
    - normalize_color("GREEN") == "green" (lowercase named pass-through)
    - normalize_color("reset") == "reset"
    - normalize_color("#1A2040CC") == "#1a2040cc" (D-09: 8-digit PRESERVED, NOT stripped to #1a2040)
    - validate_color("#1a2040cc") -> (true, "#1a2040cc") (8-digit accepted per D-09)
    - validate_color("green") -> (true, "green"); validate_color("cyan") -> (true, "cyan")
    - validate_color("#1a2") -> (true, "#1a2"); validate_color("#1a2040") -> (true, "#1a2040")
    - validate_color("bogus") -> (false, <error string listing the 10 names + hex forms incl. #rrggbbaa>)
    - validate_color("reset") -> (true, "reset")
    - COLOR_NAMES is the 10-name palette in display order (red..pink); MUTED_BG maps each name to its muted hex (verbatim from pane.lua)
    - build_osc1337("WEZTERM_TAB_COLOR", "green") == "\27]1337;SetUserVar=WEZTERM_TAB_COLOR=" .. <base64 of "green"> .. "\7"
    - build_osc11("#161c17") == "\27]11;#161c17\27\\"; build_reset_osc11() == "\27]111\7"
    - build_user_var_octal("WEZTERM_TAB_COLOR", "green") returns the octal-escaped printf-payload form of the OSC 1337 bytes (every byte as \nnn) for pane-targeted send-text writes (Pitfall 2 reuse)
    - (discretion) if rgba() is added: validate_color("rgba(30,95,46,0.5)") -> (true, <normalized>); else assert it is rejected cleanly, no traceback
  </behavior>
  <action>
    Create cli/lib/color_test.lua mirroring scene_test.lua's check/eq/teq harness exactly
    (pass/fail counters, exit non-zero on any failure). require("cli.lib.color") at the top.
    Encode every behavior bullet above as an assertion, INCLUDING the inverted alpha cases
    (the old pane_test asserted strip to 6 digits; the new shared module preserves 8 — assert
    the D-09 behavior, not the old one). For build_user_var_octal, compute the expected octal
    string from build_osc1337's bytes so the two stay coupled. Run it and confirm it FAILS
    (module absent) — this is the RED state. Commit as `test(06.1-01): RED shared color module`.
    Do NOT create cli/lib/color.lua in this task.
  </action>
  <verify>
    <automated>lua5.4 cli/lib/color_test.lua; test $? -ne 0 # MUST fail RED (module cli.lib.color absent)</automated>
  </verify>
  <acceptance_criteria>
    - cli/lib/color_test.lua exists and `require("cli.lib.color")` is its first dependency
    - Running `lua5.4 cli/lib/color_test.lua` exits NON-zero (RED — the module does not exist yet)
    - The suite contains an explicit assertion that `validate_color("#1a2040cc")` returns true with the 8-digit value preserved (D-09 regression lock)
  </acceptance_criteria>
  <done>color_test.lua authored, fails because cli/lib/color.lua does not exist yet (RED).</done>
</task>

<task type="tdd" tdd="true">
  <name>Task 2: GREEN — implement cli/lib/color.lua to pass the suite</name>
  <read_first>
    - cli/lib/color_test.lua (the contract just authored)
    - cli/commands/pane.lua (lift base64_encode, build_osc11, build_reset_osc11, build_osc1337, MUTED_BG, COLOR_NAMES, normalize_color, validate_color VERBATIM, then apply the D-09 change)
    - cli/commands/scene.lua (lines 286-289 — the existing octal printf gsub idiom that build_user_var_octal generalizes)
  </read_first>
  <behavior>
    Same behavior bullets as Task 1 — implementation must make every assertion pass GREEN.
  </behavior>
  <action>
    Create cli/lib/color.lua as a PURE module (local M = {}; return M; no require of wezterm,
    no io.*, no os.execute, no os.getenv — it must load under plain lua5.4). Lift from pane.lua:
    COLOR_NAMES (10 names, display order), MUTED_BG (the per-name muted hex table verbatim),
    base64_encode (expose as M._base64 for tests), build_osc11, build_reset_osc11, build_osc1337.
    Lift normalize_color + validate_color, then APPLY D-09: remove strip_alpha's truncation so a
    valid solid hex is now #rgb / #rrggbb / #rrggbbaa (and the 4-digit #rgba) — validate_color
    must accept #%x%x%x, #%x%x%x%x%x%x, and #%x%x%x%x%x%x%x%x; update the unknown_color_error
    string to list `#rrggbbaa` among the accepted hex forms. Add build_user_var_octal(name, value)
    that returns build_osc1337(name, value) re-encoded byte-by-byte as `\nnn` octal (the proven
    Pitfall-2 payload shape from scene.lua) so pane-targeted send-text writes reuse ONE emitter.
    (Discretion: add rgba() validation only if it is a small pure addition to validate_color;
    otherwise leave it rejected — #RRGGBBAA is the floor. Document whichever you chose in a header
    comment.) Do NOT yet edit pane.lua/tab.lua to consume this — that rewiring is Plan 03 (keeps
    file ownership clean for the parallel wave). Commit as `feat(06.1-01): shared cli/lib/color.lua`.
  </action>
  <verify>
    <automated>lua5.4 cli/lib/color_test.lua # MUST pass (exit 0)</automated>
    <automated>grep -nE 'require\("wezterm"\)|io\.|os\.execute|os\.getenv' cli/lib/color.lua | grep -vE '^\s*--' | wc -l | grep -qx 0 # purity: zero IO/wezterm refs outside comments</automated>
  </verify>
  <acceptance_criteria>
    - `lua5.4 cli/lib/color_test.lua` exits 0 (GREEN)
    - `cli/lib/color.lua contains function M.validate_color` and `function M.build_osc1337` and `function M.build_user_var_octal`
    - Purity grep (IO/wezterm refs outside comments) returns 0 — the module loads under plain lua5.4
    - The 8-digit alpha case passes (D-09): validate_color preserves `#rrggbbaa` rather than stripping it
  </acceptance_criteria>
  <done>cli/lib/color.lua passes its suite, is pure, accepts #RRGGBBAA (D-09), and exposes the shared palette/OSC/octal emitters for Wave-2 consumers.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| CLI value → pane TTY (OSC) | A user-supplied color string is encoded into an OSC 1337 escape written to a pane's terminal |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06.1-01 | Tampering | OSC 1337 value (color) | mitigate | The OSC 1337 value is base64-encoded by build_osc1337 (neutralizes control/ESC bytes) — preserved verbatim from pane.lua; no raw user bytes enter the escape stream. (RESEARCH Security Domain "OSC escape injection".) |
| T-06.1-02 | Tampering | validate_color gate | mitigate | validate-before-emit: validate_color rejects any non-palette / non-hex input BEFORE a caller emits. This module performs no I/O itself; emission is the caller's job in later plans. |
| T-06.1-SC | Tampering | npm/pip/cargo installs | accept | This phase installs ZERO external packages (RESEARCH Package Legitimacy Audit: none). No install task exists; nothing to gate. |
</threat_model>

<verification>
- `lua5.4 cli/lib/color_test.lua` passes (exit 0).
- `./tools/run-tests.sh` full suite still green (no regression — pane.lua/tab.lua untouched this plan).
- Purity grep on cli/lib/color.lua returns 0 IO/wezterm references.
</verification>

<success_criteria>
- cli/lib/color.lua is the single shared color module (palette + normalize/validate + base64 + OSC builders + octal emitter), pure, alpha-preserving (D-09).
- The TDD suite went RED (Task 1) then GREEN (Task 2).
- No consumer rewiring yet (Plan 03 deletes the duplicates and re-exports) — this plan only ADDS the shared module + test.
</success_criteria>

<output>
Create `.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-01-SUMMARY.md` when done.
</output>
