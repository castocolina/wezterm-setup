---
phase: 06.1-tab-and-scene-identity-redesign
plan: 06
type: tdd
wave: 3
depends_on: []
files_modified:
  - cli/commands/doctor.lua
  - tests/cli/doctor_test.lua
  - docs/migration-tab-color-decouple.md
autonomous: true
requirements: [D-10, D-11]
must_haves:
  truths:
    - "`wez doctor` has a FIFTH core gate that detects a user-defined format-tab-title handler OR duplicate keybindings shadowing the managed block in the user's wezterm.lua, and FAILS (non-zero exit) when found (D-11)"
    - "The shadow-detection decision is a pure text grep over the wezterm.lua content OUTSIDE the managed sentinel block — it never executes the user's wezterm.lua (T-06-02 preserved)"
    - "A healthy install (no shadowing handler) still exits 0; the four existing core gates are unchanged"
    - "A migration doc tells the user exactly what to remove from their prototype wezterm.lua (best-effort detect + instruct, D-10)"
  artifacts:
    - path: "cli/commands/doctor.lua"
      provides: "Fifth core gate: shadow-detection of format-tab-title handler / duplicate keybindings (D-11)"
      contains: "format-tab-title"
    - path: "docs/migration-tab-color-decouple.md"
      provides: "Best-effort migration instructions for the legacy encoding + shadowing handler (D-10)"
      min_lines: 20
  key_links:
    - from: "cli/commands/doctor.lua"
      to: "M.run core gates array"
      via: "gate_no_shadowing added to core (gates exit code)"
      pattern: "core = \\{"
---

<objective>
Surface the bug class that motivated this phase. The prototype `wezterm.lua` defined its OWN
inline `wezterm.on("format-tab-title", ...)` handler (and duplicate keybindings) that SHADOW the
managed block — the root cause of the `cyan:` literal / no-color / no-cwd symptoms. Per D-11 add
a FIFTH CORE gate to `wez doctor` (alongside binary-on-PATH / sentinel / config-dofiles / backup)
that detects a user-defined `format-tab-title` registration or duplicate-shadowing keybindings
OUTSIDE the managed sentinel block and FAILS loudly (non-zero exit) so this bug never hides again.

The decision is a PURE text grep over the wezterm.lua content (doctor never executes the user's
wezterm.lua — T-06-02 holds; it only reads + greps text). Per D-10 (best-effort detect + instruct,
this is a solo daily-driver setup, not a mass product) the gate's failure detail tells the user
exactly what to remove, and a migration doc captures the same guidance — a fragile auto-rewrite is
NOT required (an opt-in `--fix` is allowed if cheap, Claude's discretion, but the bar is
detect + instruct + the installer's existing backup).

Purpose: make the shadowing-handler / duplicate-keybinding failure mode a loud, gating doctor
check plus clear migration instructions. Output: extended doctor.lua + its test + a migration doc.
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

# The doctor module + its gate pattern (extend, mirror gate_sentinel_well_formed):
@cli/commands/doctor.lua
@tests/cli/doctor_test.lua
@cli/commands/install_state.lua
</context>

<reducing_entropy_note>
D-01 / `/reducing-entropy`: reuse the install_state PARSE contract to locate the managed sentinel
block (the same LOCKED markers GATE 2 already uses) so the shadow gate shares ONE block-boundary
parser — do not write a second sentinel scanner. The new gate is a small pure decision added to the
existing gate_* family; mirror gate_sentinel_well_formed's shape exactly.
</reducing_entropy_note>

<tasks>

<task type="tdd" tdd="true">
  <name>Task 1: RED/GREEN — add the shadow-detection core gate to doctor.lua (D-11)</name>
  <read_first>
    - cli/commands/doctor.lua (gate() helper, gate_sentinel_well_formed (mirror it), the `core` array in M.run, config_path(), aggregate())
    - tests/cli/doctor_test.lua (the fixture/injection harness — gates take TEXT so the decision is pure)
    - cli/commands/install_state.lua (parse() returns the managed-block boundaries from the LOCKED markers — reuse to know what is "inside" vs "outside" the managed block)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md ("Doctor shadow-detection core gate (D-11)" code example; Pitfall 1 the shadowing handler; Security Domain "Doctor reading the user's wezterm.lua")
  </read_first>
  <behavior>
    - M.gate_no_shadowing(text) -> PASS when the wezterm.lua text has NO `wezterm.on("format-tab-title"` / `wezterm.on('format-tab-title'` registration OUTSIDE the managed sentinel block
    - FAIL (with an actionable detail: "remove the inline format-tab-title handler from your wezterm.lua — wezterm-setup's managed block renders the tab bar") when such a registration exists outside the managed block
    - FAIL also when a duplicate-shadowing keybinding registration is found outside the managed block (best-effort heuristic — e.g. a user `config.keys` / `wezterm.on('format-tab-title')`); keep the heuristic conservative to avoid false positives (a managed-block-internal match is NOT a failure)
    - the gate is PURE on the text (no os.execute, no loadfile of the user's wezterm.lua — T-06-02 preserved); run() reads the file and passes the text in, like gate_sentinel_well_formed
    - M.run adds the gate to the `core` array so it gates the exit code (D-11); a healthy install (no shadowing) still exits 0; the 4 existing gates unchanged
  </behavior>
  <action>
    Update doctor_test.lua FIRST (RED): add gate_no_shadowing cases — (a) clean text -> PASS,
    (b) text with an inline `wezterm.on("format-tab-title", ...)` OUTSIDE the managed markers -> FAIL,
    (c) the SAME registration INSIDE the managed block -> PASS (managed handler is expected),
    (d) aggregate() with the shadow gate failing -> non-zero code. Run RED. Then add
    M.gate_no_shadowing(text) to doctor.lua mirroring gate_sentinel_well_formed: use
    install_state.parse(text) to find the managed-block range, then search the text OUTSIDE that range
    for a format-tab-title registration (and the conservative duplicate-keybinding heuristic). Return a
    gate() with an actionable detail on FAIL. Add it to the `core` array in M.run (read the config text
    once, pass to both gate_sentinel_well_formed and gate_no_shadowing). Run GREEN. Commit RED then GREEN:
    `test(06.1-06): RED doctor shadow-detection` / `feat(06.1-06): doctor shadow-detection core gate (D-11)`.
  </action>
  <verify>
    <automated>lua5.4 tests/cli/doctor_test.lua # GREEN</automated>
    <automated>grep -q 'format-tab-title' cli/commands/doctor.lua # the gate exists</automated>
    <automated>grep -vE '^\s*--' cli/commands/doctor.lua | grep -c 'loadfile.*wezterm%.lua\|dofile' | grep -qx 0 # never executes the user's wezterm.lua (T-06-02)</automated>
  </verify>
  <acceptance_criteria>
    - `lua5.4 tests/cli/doctor_test.lua` exits 0 with the four shadow-detection cases
    - `cli/commands/doctor.lua contains function M.gate_no_shadowing` and it is added to the `core` array (gates exit code, D-11)
    - The gate is a pure text decision — no loadfile/dofile of the user's wezterm.lua (T-06-02 preserved)
    - A clean install passes all five core gates (exit 0); a shadowing handler outside the managed block fails (non-zero)
  </acceptance_criteria>
  <done>`wez doctor` gains a fifth core gate detecting a shadowing format-tab-title handler / duplicate keybindings, gating the exit code, decided purely on text — tests green.</done>
</task>

<task type="auto">
  <name>Task 2: write the migration doc (best-effort detect + instruct, D-10)</name>
  <read_first>
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-CONTEXT.md (D-04 parse-and-warn migration, D-10 best-effort detect+instruct, the "clean reinstall is an acceptable reset" stance)
    - .planning/phases/06.1-tab-and-scene-identity-redesign/06.1-RESEARCH.md (Runtime State Inventory — what still holds the old string after every repo file is updated; the three remaining items)
    - cli/commands/doctor.lua (Task 1's gate detail text — the doc must say the same thing the gate says)
  </read_first>
  <action>
    Create docs/migration-tab-color-decouple.md (English). Cover: (1) what changed — tab color moved
    from the `"<color>:<title>"` set-tab-title prefix to the WEZTERM_TAB_COLOR user var (D-02/D-03/D-04);
    (2) the symptom — a literal `cyan:` in the tab title / no accent / no cwd — caused by an inline
    `wezterm.on("format-tab-title", ...)` handler (or duplicate keybindings) in the user's wezterm.lua
    SHADOWING the managed block (Pitfall 1); (3) the fix — `wez doctor` now FAILS with the exact lines to
    remove; remove the inline handler + duplicate keybindings, keeping genuine personal settings; the
    installer already wrote a timestamped backup (INST-02). (4) the reset option — a clean reinstall (or
    a future `wez uninstall`, noted as deferred) is always acceptable (D-10). (5) live tabs reset on the
    next recolor / WezTerm restart (Runtime State Inventory). Keep it concise and actionable — this is a
    solo daily-driver setup, not a product migration guide. Commit:
    `docs(06.1-06): tab-color decouple migration guide (D-10)`.
  </action>
  <verify>
    <automated>test -f docs/migration-tab-color-decouple.md && grep -q 'WEZTERM_TAB_COLOR' docs/migration-tab-color-decouple.md && grep -q 'format-tab-title' docs/migration-tab-color-decouple.md</automated>
  </verify>
  <acceptance_criteria>
    - `docs/migration-tab-color-decouple.md` exists, is English, mentions WEZTERM_TAB_COLOR and the shadowing format-tab-title handler
    - The doc's "what to remove" instruction matches the doctor gate's failure detail (single source of guidance)
    - It states the clean-reinstall reset option (D-10) and the live-tab reset behavior
  </acceptance_criteria>
  <done>A concise, actionable migration doc captures the detect + instruct guidance, matching the doctor gate detail (D-10).</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| user's wezterm.lua text → doctor grep | doctor READS the user's config file as text to decide the gate |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06.1-14 | Info disclosure / Elevation | doctor reading wezterm.lua | mitigate | doctor only READS + greps text; it does NOT loadfile/dofile/execute the user's wezterm.lua (T-06-02, preserved + grep-gated). No user side effects run. (RESEARCH Security Domain "Doctor reading the user's wezterm.lua".) |
| T-06.1-15 | DoS (false positive) | shadow-detection heuristic | accept | The duplicate-keybinding heuristic is conservative (managed-block-internal matches excluded) to avoid false failures; a rare false positive is recoverable (the gate prints exactly what it matched) and is acceptable for a solo setup (D-10). |
| T-06.1-SC | Tampering | npm/pip/cargo installs | accept | Zero external packages this phase (RESEARCH Package Legitimacy Audit). |
</threat_model>

<verification>
- `lua5.4 tests/cli/doctor_test.lua` passes.
- `./tools/run-tests.sh` full suite green.
- grep confirms the gate exists and is text-only (no loadfile of wezterm.lua).
- migration doc present + accurate.
- Live `wez doctor` against a planted shadowing handler verified in Plan 07 (recorded repro / integration guard).
</verification>

<success_criteria>
- `wez doctor` fails loudly on a shadowing format-tab-title handler / duplicate keybindings (D-11), as a CORE gate.
- The gate is pure text (T-06-02 preserved); the four existing gates unchanged; healthy install still exits 0.
- A migration doc captures the detect + instruct guidance (D-10).
</success_criteria>

<output>
Create `.planning/phases/06.1-tab-and-scene-identity-redesign/06.1-06-SUMMARY.md` when done.
</output>
