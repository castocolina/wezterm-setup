---
phase: 01-foundation
plan: 04
subsystem: installer
tags: [installer, sentinel, backup, atomic-write, osc7, cli-dispatch]
requires: [01-01, 01-02, 01-03]
provides:
  - "wez install-state command (PARSE/BACKUP/INJECT/DECIDE) — cli/commands/install_state.lua"
  - "locked sentinel markers: -- >>> wezterm-setup managed block >>> / -- <<< wezterm-setup managed block <<<"
  - "tools/setup.sh — decision-free glue installer (Makefile install target dispatches here)"
  - "hyphenated-subcommand dispatch in cli/wez.lua (install-state -> install_state)"
affects:
  - "Plan 06 (doctor / uninstall-state) reuses the locked sentinel markers + parse contract"
  - "Plan 06 uninstall-state benefits from the same hyphen->underscore dispatch mapping"
tech-stack:
  added: []
  patterns:
    - "write-temp-then-atomic-rename for any user-config mutation (os.rename, T-04-01)"
    - "timestamped backup before any write (wezterm.lua.bak.<UTC>)"
    - "pure decide(state, has_tty, flags) dispatcher; run() wires to FS + TTY"
    - "rc-file edits guarded by a literal marker for idempotence"
key-files:
  created:
    - cli/commands/install_state.lua
    - tests/cli/install_state_test.lua
    - tools/setup.sh
    - .tmp/probes/phase-1/04-sentinel-injection.md (gitignored scratch)
  modified:
    - cli/wez.lua
    - tests/cli/spec_test.lua
decisions:
  - "Sentinel markers LOCKED: '-- >>> wezterm-setup managed block >>>' / '-- <<< wezterm-setup managed block <<<' (R6 probe 04, canonical contract for downstream plans)"
  - "INJECT writes temp then os.rename over target so an interrupted write leaves the original intact (T-04-01)"
  - "wez.lua dispatcher maps hyphenated allow-listed subcommand names to underscored module files (install-state -> install_state); fixes a Task-1 integration bug surfaced by the Task-2 dogfood"
metrics:
  duration_min: 6
  completed: "2026-06-09"
  tasks: 2
  files: 6
---

# Phase 1 Plan 04: Non-destructive Installer Summary

One-liner: the `wez install-state` Lua command owns sentinel parse + timestamped backup
+ single-block atomic inject + override/restore/skip decision (no-TTY aborts non-zero,
D-03), and `tools/setup.sh` is decision-free glue that bootstraps WezTerm, builds/places
`wez`, copies the managed config tree, registers OSC 7 idempotently, and delegates the
install-state decision to the Lua binary (D-01).

## What Was Built

### Task 1 — `cli/commands/install_state.lua` (TDD) — commit `7b71b0d`
- **PARSE** `parse(text)` → `{ state = "absent"|"present", block }` via the two locked
  sentinel markers (in order); extracts a present block inclusive of both markers.
- **BACKUP** `backup(target)` copies `wezterm.lua` → `wezterm.lua.bak.<UTC-timestamp>`
  before any write (INST-02). `newest_backup(target)` selects the lexicographically-latest
  (== chronological) backup deterministically (T-04-05).
- **INJECT** `inject(target)` writes the backup, then inserts EXACTLY ONE managed block
  wiring `require('wezterm-setup').apply(config)` positioned before the user's final
  `return` (Shape A reuses the returned identifier; Shape B wraps the returned expression
  in a local). Write goes to a temp file then `os.rename` over the target —
  `atomic_write()` — so an interrupted write never corrupts the user's config (T-04-01).
- **DECIDE** pure `decide(state, has_tty, flags)` → `(action, exit_code, msg)`:
  absent → install/0; present+`--skip` → skip/0; `--force` → override/0; `--restore` →
  restore/0; present+TTY → prompt; present+NO-TTY → abort/3 naming `--force/--restore/--skip`
  (D-03 / T-04-02, never silent overwrite). `run(args)` wires this to the real FS + TTY.
- 28 fixture/temp-fs assertions green; `cli/spec.lua` untouched (D-16).
- R6 probe `.tmp/probes/phase-1/04-sentinel-injection.md` (six fields + verdict `holds`)
  records the real Shape-A `config_builder()` + `return config` shape, the injection
  position, and the locked marker strings.

### Task 2 — `tools/setup.sh` glue installer — commit `46cc24a`
- Sequence: source `platform.sh` → `bootstrap-wezterm.sh` → `build.sh` + install `dist/wez`
  to `~/.local/bin` → copy `config/wezterm-setup/` → `~/.config/wezterm/wezterm-setup/` →
  register OSC 7 into `.bashrc`/`.zshrc` (guarded by literal `# wezterm-setup:osc7`,
  idempotent — T-04-03) → `wez install-state "$@"`, surfacing its exit code (D-03).
- Zero decision logic (D-01): grep confirms the override/restore/skip keywords live in the
  Lua module, not in setup.sh branching. Zero `sudo` (T-04-04). Cross-platform via
  `platform.sh`, no `/proc` (D-18). shellcheck `-x` clean.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Hyphenated subcommand names did not dispatch to underscored modules**
- **Found during:** Task 2 dogfood (clean install reached `wez install-state` and got
  `wez: command 'install-state' is not implemented yet`, exit 3).
- **Issue:** `cli/wez.lua` built the module name as `"cli.commands." .. name`, so the
  allow-listed `install-state` mapped to `cli/commands/install-state.lua` (hyphen). The
  plan mandates the module file be `install_state.lua` (underscore) and forbids editing
  `cli/spec.lua`, so the fix had to live in the dispatcher. Single-word commands
  (`version`/`keys`/`doctor`) never hit this; `install-state` and the future
  `uninstall-state` (Plan 06) both do.
- **Fix:** map the already-allow-listed name `-` → `_` before building the require path
  (`name:gsub("%-", "_")`). T-01-02 still holds — only the closed allow-listed name is
  transformed, no raw user input reaches the require path. Added a regression assertion in
  `tests/cli/spec_test.lua`.
- **Files modified:** `cli/wez.lua`, `tests/cli/spec_test.lua`
- **Commit:** `46cc24a`

## Verification

- `lua5.4 tests/cli/install_state_test.lua` → 28/28 green (parse absent/present, single-block
  inject, timestamped backup, no-TTY abort non-zero, write-temp-then-rename, newest-backup).
- Full suite `./tools/run-tests.sh` → all 5 files pass (31/31 spec assertions including the
  hyphen-dispatch regression).
- Plan verify lines: `rg -ci verdict <probe>`=2; `rg -c 'sentinel|apply' install_state.lua`=9;
  `rg -c 'install-state|install_state' setup.sh`=8; no-sudo-OK; `rg -c 'bootstrap-wezterm|build.sh'`=4.
- **Dogfood against a scratch HOME with a COPY of the real `wezterm.lua` (112 lines):**
  - Clean install (non-TTY): one managed block, `wezterm.lua.bak.<ts>` byte-identical to the
    original, `~/.config/wezterm/wezterm-setup/init.lua` placed, OSC 7 registered once,
    `config.window_decorations` and other user lines intact — exit 0.
  - Re-install (non-TTY): abort exit 3, message names `--force/--restore/--skip`, still
    exactly one block (no silent overwrite), OSC 7 not duplicated.
  - `--skip`: no-op exit 0. `--force`: override yields exactly one block, exit 0.

Verified on Linux (D-18); macOS deferred to the batched Mac pass.

## Success Criteria

- Phase 1 success criterion #1 satisfied: clean install = one managed block + timestamped
  backup + nothing else touched; re-run aborts non-zero (no TTY) / prompts (TTY) — never
  silent overwrite.
- D-01 boundary honored: setup.sh holds zero decision logic; `wez install-state` owns it all.
- D-17 augment model wired: the injected block calls `require('wezterm-setup').apply(config)`.

## Notes for Downstream Plans

- The two sentinel markers are a LOCKED contract — Plan 06 (doctor / uninstall-state) must
  reuse `install_state.OPEN_MARKER` / `install_state.CLOSE_MARKER` and the `parse()` shape.
- The hyphen→underscore dispatch mapping now also unblocks `uninstall-state` (Plan 06).
- `install_state.lua` honors `WEZTERM_CONFIG_FILE` for non-default config locations (used by
  the dogfood + future integration tests).

## Self-Check: PASSED

All created files exist on disk (install_state.lua, install_state_test.lua, setup.sh,
SUMMARY.md, probe 04). Both task commits verified in git history (`7b71b0d`, `46cc24a`).
