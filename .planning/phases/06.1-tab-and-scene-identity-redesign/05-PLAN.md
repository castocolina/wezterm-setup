---
phase: 06.1-tab-and-scene-identity-redesign
plan: 05
type: tdd
wave: 3
depends_on: [01]
files_modified:
  - config/wezterm-setup/format-tab-title.lua
  - config/wezterm-setup/format-tab-title_test.lua
  - config/wezterm-setup/keybindings.lua
  - config/wezterm-setup/init.lua
  - tests/config/keybindings_test.lua
  - tests/config/apply_test.lua
autonomous: true
requirements: [D-02, D-04, D-09, D-12]
must_haves:
  truths:
    - "The tab bar reads the active pane's WEZTERM_TAB_COLOR for the accent; the `<color>:<title>` prefix is dropped from the steady-state render (parse-and-warn migration only) (D-02/D-04)"
    - "resolve_profile accepts a #RRGGBBAA accent (8-digit) without falling back to the default profile (D-09)"
    - "Alt+Shift+R = RotatePanes Clockwise and Alt+Shift+E = RotatePanes CounterClockwise are bound, with matching init.lua resolve_action arms and DisableDefaultAssignment entries; the Alt+Shift+Z zoom toggle is kept (D-12)"
    - "Ctrl+Shift+F search and Ctrl+R CopyMode CycleMatchType are documented as embraced defaults (item 8)"
  artifacts:
    - path: "config/wezterm-setup/format-tab-title.lua"
      provides: "Active-pane color render + #RRGGBBAA accent + prefix demoted to migration (D-02/D-04/D-09)"
      contains: "active_pane"
    - path: "config/wezterm-setup/keybindings.lua"
      provides: "RotatePanes Alt+Shift+R / Alt+Shift+E bindings + DisableDefaultAssignment (D-12)"
      contains: "RotatePanes"
    - path: "config/wezterm-setup/init.lua"
      provides: "resolve_action arms for RotatePanes (lockstep with keybindings, no config-load error)"
      contains: "RotatePanes"
  key_links:
    - from: "config/wezterm-setup/format-tab-title.lua"
      to: "tab.active_pane.user_vars.WEZTERM_TAB_COLOR"
      via: "active-pane read (D-02 active-pane-wins)"
      pattern: "active_pane"
    - from: "config/wezterm-setup/keybindings.lua"
      to: "config/wezterm-setup/init.lua resolve_action"
      via: "declarative RotatePanes spec resolved to wezterm.action.RotatePanes"
      pattern: "RotatePanes"
---

<objective>
Update the in-VM config layer (a SEPARATE Lua bundle from the CLI) to match the decoupled
model. The `format-tab-title.lua` renderer reads the ACTIVE pane's `WEZTERM_TAB_COLOR` for the
accent (D-02 active-pane-wins — already the dominant code path) and DROPS the `<color>:<title>`
prefix from the steady-state render, keeping it only as a graceful migration path so a legacy
live title still renders without warning-on-every-paint (Open Q3). `resolve_profile` accepts a
`#RRGGBBAA` accent so an IDE-inserted alpha never falls back to the default profile (D-09;
Pitfall 4 caveat: alpha only renders with window transparency — documented, not promised).

This plan also adds the Arrange keybindings: `Alt+Shift+R` = RotatePanes Clockwise and
`Alt+Shift+E` = RotatePanes CounterClockwise (D-12), with the matching `init.lua resolve_action`
arms added in LOCKSTEP (Pitfall 3 — an unresolved spec crashes config load) plus
`DisableDefaultAssignment` entries for any replaced defaults. The existing `Alt+Shift+Z` zoom
toggle is kept. `Ctrl+Shift+F` search + `Ctrl+R` CopyMode CycleMatchType are documented as
embraced WezTerm defaults (item 8 — they already fire; no binding needed).

Purpose: make the render layer agree with the CLI's new color carrier, accept alpha, and ship
the Arrange presets + embraced search overlay. Output: updated config-layer Lua + tests.
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

# Plan 01 (palette/alpha shape, for parity with the CLI side):
@.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-01-SUMMARY.md

# Config-layer files being edited (separate Lua bundle — NOT bundled by luastatic):
@config/wezterm-setup/format-tab-title.lua
@config/wezterm-setup/format-tab-title_test.lua
@config/wezterm-setup/keybindings.lua
@config/wezterm-setup/init.lua
@tests/config/keybindings_test.lua
@tests/config/apply_test.lua
</context>

<reducing_entropy_note>
The config layer is a SEPARATE bundle (luastatic bundles only cli/, never config/), so it
cannot `require("cli.lib.color")` at runtime. Per RESEARCH the config-side color_profiles is the
intentional render-side single source (the CLI-side palette validates; the config-side paints).
Do NOT duplicate the CLI palette here beyond what render needs. The deletion win in this plan is
removing the prefix parse from the steady-state render path (D-04), shrinking the handler.
</reducing_entropy_note>

<tasks>

<task type="tdd" tdd="true">
  <name>Task 1: RED/GREEN — format-tab-title.lua: active-pane color, #RRGGBBAA accent, prefix demoted to migration (D-02/D-04/D-09)</name>
  <read_first>
    - config/wezterm-setup/format-tab-title.lua (resolve_profile, parse_tab_title, the handler's accent precedence `pane WEZTERM_TAB_COLOR > tab-prefix color > default`)
    - config/wezterm-setup/format-tab-title_test.lua (prefix cases 17-23 + precedence — these become migration-only or change)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md (Pattern 2 active-pane read is already the code; Pitfall 4 alpha-ignored caveat)
  </read_first>
  <behavior>
    - resolve_profile("#1a2040cc") -> { bg = "#1a2040cc", fg = <default fg> } (8-digit accent accepted, NOT default-fallback) (D-09)
    - resolve_profile("green") -> the green profile (unchanged); resolve_profile(nil/"") -> default
    - the handler accent precedence becomes: active pane WEZTERM_TAB_COLOR > default — the tab-prefix color is NO LONGER consulted in the steady state (D-02/D-04)
    - a legacy stored title "cyan:api" still renders gracefully: title text = "api" (prefix stripped for DISPLAY) but the accent comes from the user var, not the prefix; no per-paint warning (Open Q3)
    - format_label / build_runs unchanged
  </behavior>
  <action>
    Update format-tab-title_test.lua FIRST (RED): add resolve_profile("#1a2040cc") -> 8-digit accent
    accepted (extend the hex match to allow %x%x%x%x%x%x%x%x); change the handler-precedence assertions
    so the accent derives from the active pane's WEZTERM_TAB_COLOR only (drop the prefix-color fallback);
    keep a migration case proving a legacy "cyan:api" stored title still DISPLAYS "api" without crashing.
    Run RED. Then edit format-tab-title.lua: extend resolve_profile's hex branch to accept #rrggbbaa
    (8-digit) in addition to #rgb/#rrggbb; in the handler, set accent_color = active pane WEZTERM_TAB_COLOR
    (drop `or tabColor`); keep parse_tab_title ONLY to strip a legacy prefix for the DISPLAYED title text
    (migration), with a comment marking it migration-only per D-04. Run GREEN. Commit RED then GREEN:
    `test(06.1-05): RED active-pane color + alpha` / `feat(06.1-05): render active-pane WEZTERM_TAB_COLOR + #RRGGBBAA, drop prefix (D-02/D-04/D-09)`.
  </action>
  <verify>
    <automated>lua5.4 config/wezterm-setup/format-tab-title_test.lua # GREEN</automated>
    <automated>grep -q 'active_pane' config/wezterm-setup/format-tab-title.lua</automated>
  </verify>
  <acceptance_criteria>
    - `lua5.4 config/wezterm-setup/format-tab-title_test.lua` exits 0
    - resolve_profile accepts a `#RRGGBBAA` accent (8-digit) — asserted, not default-fallback (D-09)
    - The steady-state accent reads the active pane's WEZTERM_TAB_COLOR; the prefix-color fallback is removed (D-02/D-04)
    - A legacy `"cyan:api"` stored title still renders display text "api" without error (migration grace)
  </acceptance_criteria>
  <done>The renderer derives the accent from the active pane's WEZTERM_TAB_COLOR, accepts #RRGGBBAA, and treats the legacy prefix as migration-only — tests green.</done>
</task>

<task type="tdd" tdd="true">
  <name>Task 2: RED/GREEN — RotatePanes keybindings + resolve_action arms (lockstep) + DisableDefaultAssignment; document search overlay (D-12, item 8)</name>
  <read_first>
    - config/wezterm-setup/keybindings.lua (M.keys table, the mapped() helper, the Alt+Shift family H/V/X/Z, M.disabled_defaults)
    - config/wezterm-setup/init.lua (resolve_action closed switch — it error()s on an unknown spec.type, so a new RotatePanes entry MUST get a matching arm in the SAME change, Pitfall 3)
    - tests/config/keybindings_test.lua + tests/config/apply_test.lua (how key entries + resolve_action are asserted)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md (Pattern 4 RotatePanes 'Clockwise'/'CounterClockwise'; Search + CopyMode CycleMatchType are already defaults; Pitfall 3)
  </read_first>
  <behavior>
    - keybindings.lua M.keys gains: { key = mapped("r"), mods = "ALT|SHIFT", action = { type = "RotatePanes", arg = "Clockwise" } } and the same for mapped("e") with arg = "CounterClockwise"
    - init.lua resolve_action gains an arm: t == "RotatePanes" -> act.RotatePanes(spec.arg) (so config load does not error — Pitfall 3)
    - M.disabled_defaults gains entries for any WezTerm default that Alt+Shift+R / Alt+Shift+E replace (truthful `wez keys`, D-12); the Alt+Shift+Z zoom toggle entry is RETAINED
    - the keybindings_test asserts both new key entries exist with the correct mods/arg; apply_test asserts resolve_action maps RotatePanes to a wezterm action under the test stub (or keeps the spec when wezterm absent)
    - a header comment in keybindings.lua documents Ctrl+Shift+F (Search) and Ctrl+R (CopyMode CycleMatchType) as embraced defaults — no binding added (item 8)
  </behavior>
  <action>
    Update keybindings_test.lua + apply_test.lua FIRST (RED): assert the two RotatePanes entries
    (Alt+Shift+R Clockwise, Alt+Shift+E CounterClockwise) and that resolve_action handles type
    "RotatePanes". Run RED. Then add the two entries to keybindings.lua M.keys (using the existing
    mapped() helper, following the Alt+Shift family style), add the RotatePanes arm to init.lua
    resolve_action (act.RotatePanes(spec.arg)) in lockstep, add DisableDefaultAssignment entries to
    M.disabled_defaults for the replaced defaults, and add the search-overlay documentation comment
    (item 8 — Ctrl+Shift+F + Ctrl+R already fire; relax the prior "no less-style search" rule in the
    comment). Keep Alt+Shift+Z. Run GREEN. Commit RED then GREEN:
    `test(06.1-05): RED RotatePanes keys` / `feat(06.1-05): Arrange RotatePanes keys + resolve_action + search docs (D-12)`.
  </action>
  <verify>
    <automated>lua5.4 tests/config/keybindings_test.lua # GREEN</automated>
    <automated>lua5.4 tests/config/apply_test.lua # GREEN</automated>
    <automated>grep -q 'RotatePanes' config/wezterm-setup/keybindings.lua && grep -q 'RotatePanes' config/wezterm-setup/init.lua # lockstep (Pitfall 3)</automated>
  </verify>
  <acceptance_criteria>
    - `lua5.4 tests/config/keybindings_test.lua` and `lua5.4 tests/config/apply_test.lua` both exit 0
    - `config/wezterm-setup/keybindings.lua contains RotatePanes` AND `config/wezterm-setup/init.lua contains RotatePanes` (lockstep — no config-load error per Pitfall 3)
    - Alt+Shift+R (Clockwise) and Alt+Shift+E (CounterClockwise) entries present; Alt+Shift+Z retained
    - DisableDefaultAssignment entries added for replaced defaults; search overlay documented (Ctrl+Shift+F + Ctrl+R)
  </acceptance_criteria>
  <done>RotatePanes Arrange keys bound with lockstep resolve_action + disabled-defaults; search overlay embraced + documented — tests green.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| user_var value → tab-bar render | The renderer reads a pane-set user var and paints it; values originate from the CLI's validated OSC emit |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06.1-12 | Tampering | resolve_profile accent value | mitigate | resolve_profile only maps a name to a {bg,fg} pair or accepts a hex MATCH (%x pattern) — a non-matching value falls back to the default profile, so a malformed user var cannot inject arbitrary render data (it is a color string fed to WezTerm's own color parser). |
| T-06.1-13 | DoS | unknown key spec → config load | mitigate | resolve_action gets the RotatePanes arm in the SAME change (Pitfall 3) so config never hits the `error()` branch on load; keybindings_test + apply_test guard the lockstep. |
| T-06.1-SC | Tampering | npm/pip/cargo installs | accept | Zero external packages this phase (RESEARCH Package Legitimacy Audit). |
</threat_model>

<verification>
- `lua5.4 config/wezterm-setup/format-tab-title_test.lua`, `tests/config/keybindings_test.lua`, `tests/config/apply_test.lua` all pass.
- `./tools/run-tests.sh` full suite green.
- grep confirms RotatePanes in BOTH keybindings.lua and init.lua (lockstep).
- Live render + RotatePanes verification owned by Plan 07 (recorded repro — GPU render is not headlessly assertable).
</verification>

<success_criteria>
- Renderer uses active-pane WEZTERM_TAB_COLOR, accepts #RRGGBBAA, drops the prefix from steady state (D-02/D-04/D-09).
- Arrange keys (RotatePanes Alt+Shift+R/E) bound with lockstep resolve_action + disabled defaults (D-12).
- Search overlay embraced + documented (item 8).
- Config loads without error; tests green.
</success_criteria>

<output>
Create `.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-05-SUMMARY.md` when done.
</output>
