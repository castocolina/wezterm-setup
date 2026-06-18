---
quick_id: 260618-dlc
type: execute
description: Set WezTerm scrollback_lines to 50000 in the config layer
files_modified:
  - config/wezterm-setup/init.lua
  - tests/config/apply_test.lua
autonomous: true
must_haves:
  truths:
    - "WezTerm's scrollback buffer is raised from the 3500 default to 50000 lines via the config layer"
    - "The value lives in a single labeled, discoverable module-level constant so future changes are a one-line edit"
    - "M.apply() AUGMENTS config (sets config.scrollback_lines) without replacing the table (D-17)"
    - "The installed copy at ~/.config/wezterm/wezterm-setup/ carries the change so it takes effect live"
  artifacts:
    - "config/wezterm-setup/init.lua: local SCROLLBACK_LINES = 50000 + config.scrollback_lines = SCROLLBACK_LINES"
  key_links:
    - "config/wezterm-setup/init.lua"
    - "tests/config/apply_test.lua"
    - "~/.config/wezterm/wezterm-setup/init.lua (synced copy)"
---

# Quick Task 260618-dlc: WezTerm scrollback_lines → 50000

<objective>
Raise the WezTerm scrollback buffer from the 3500 default to 50000 lines, exposed as a
discoverable one-line knob in the config layer, and sync it to the installed copy so it
takes effect live. The user lost the first prompt off the top after a single Claude turn.
</objective>

<context>
- Config layer is pure Lua (zero deps). `config/wezterm-setup/init.lua` exposes `M.apply(config)`
  which MUTATES the passed WezTerm config table (AUGMENT only — D-17, never replace).
- No general/terminal-options step exists yet; `scrollback_lines` is the first such option.
- Memory/project gotcha: config-layer edits must be cp-synced to `~/.config/wezterm/wezterm-setup/`
  (the copy WezTerm actually loads) to take effect live.
- The sibling apply test is `tests/config/apply_test.lua` (loads init.lua under a wezterm stub).
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add SCROLLBACK_LINES knob + set config.scrollback_lines in apply()</name>
  <files>config/wezterm-setup/init.lua, tests/config/apply_test.lua</files>
  <read_first>
    - config/wezterm-setup/init.lua (module-level locals near the top; the M.apply(config) body, esp. its numbered steps and the "augment, never replace" contract)
    - tests/config/apply_test.lua (harness shape + existing apply assertions to mirror)
  </read_first>
  <action>
    In config/wezterm-setup/init.lua: add a labeled module-level constant near the top with the
    other locals — `local SCROLLBACK_LINES = 50000` — preceded by a one-line comment marking it
    as the future-change knob (e.g. "-- Scrollback buffer depth (lines). Change here to adjust;
    WezTerm default is 3500."). Then inside M.apply(config), add a new clearly-commented step
    (general/terminal options) that sets `config.scrollback_lines = SCROLLBACK_LINES`. AUGMENT
    only — do not reassign or replace `config`. Keep the existing `return config` (same object).
    In tests/config/apply_test.lua: add an assertion that after apply() runs on a fresh config
    table, `config.scrollback_lines == 50000`.
  </action>
  <verify>
    <automated>lua5.4 tests/config/apply_test.lua</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c 'local SCROLLBACK_LINES = 50000' config/wezterm-setup/init.lua` == 1
    - `grep -c 'config.scrollback_lines = SCROLLBACK_LINES' config/wezterm-setup/init.lua` == 1
    - `tests/config/apply_test.lua` asserts `config.scrollback_lines == 50000` and exits 0
    - `./tools/run-tests.sh` introduces no NEW failures (the pre-existing cli/lib/recipe_test.lua
      "2.9d ai.toml" baseline from commit 723af62 is out of scope and expected)
  </acceptance_criteria>
  <done>init.lua exposes the SCROLLBACK_LINES knob and apply() sets config.scrollback_lines = 50000; apply test green.</done>
</task>

<task type="auto">
  <name>Task 2: Sync config layer to the installed copy (~/.config) so it takes effect live</name>
  <files>(no repo files — syncs to ~/.config/wezterm/wezterm-setup/)</files>
  <read_first>
    - tools/setup.sh / tools/install.sh (how the config layer is copied to ~/.config — mirror that copy mechanism rather than inventing one)
  </read_first>
  <action>
    Sync the updated config layer to the installed copy at ~/.config/wezterm/wezterm-setup/ using
    the SAME copy mechanism the installer uses (prefer re-running the installer's config-sync path
    or `make install` if it is non-destructive; otherwise a direct `cp` of the changed
    config/wezterm-setup/ files). Do NOT touch the user's top-level ~/.config/wezterm/wezterm.lua.
  </action>
  <verify>
    <automated>grep -c 'SCROLLBACK_LINES = 50000' ~/.config/wezterm/wezterm-setup/init.lua</automated>
  </verify>
  <acceptance_criteria>
    - `grep 'scrollback_lines' ~/.config/wezterm/wezterm-setup/init.lua` shows the new code (SCROLLBACK_LINES wired)
    - `grep -c 'SCROLLBACK_LINES = 50000' ~/.config/wezterm/wezterm-setup/init.lua` == 1
  </acceptance_criteria>
  <done>The installed copy at ~/.config/wezterm/wezterm-setup/init.lua carries scrollback_lines=50000; WezTerm hot-reloads on next config touch.</done>
</task>

</tasks>

<verification>
- `lua5.4 tests/config/apply_test.lua` passes with the new scrollback assertion.
- `./tools/run-tests.sh` shows no new failures vs the known recipe_test baseline.
- `grep -c 'SCROLLBACK_LINES = 50000' ~/.config/wezterm/wezterm-setup/init.lua` == 1.
</verification>

<success_criteria>
- scrollback_lines = 50000 set via a labeled one-line knob in config/wezterm-setup/init.lua (AUGMENT, D-17).
- apply test asserts it; suite introduces no new failures.
- Installed ~/.config copy carries the change (live).
</success_criteria>

<artifacts_this_phase_produces>
- `config/wezterm-setup/init.lua`: new `local SCROLLBACK_LINES = 50000` constant + `config.scrollback_lines = SCROLLBACK_LINES` in `M.apply()`.
- `tests/config/apply_test.lua`: new assertion `config.scrollback_lines == 50000`.
</artifacts_this_phase_produces>

<output>
Create `.planning/quick/260618-dlc-set-wezterm-scrollback-lines-to-50000-in/260618-dlc-SUMMARY.md` when done.
</output>
