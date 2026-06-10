---
phase: 01-foundation
plan: 05
subsystem: cli
tags: [lua, wezterm, keybindings, show-keys, classification, json, dkjson, diagnostics]

# Dependency graph
requires:
  - phase: 01-foundation (Plan 01)
    provides: cli/spec.lua keys subcommand + --json flag, cli/wez.lua lazy dispatch, vendored dkjson
  - phase: 01-foundation (Plan 03)
    provides: config/wezterm-setup/keybindings.lua (key table + disabled-defaults as DATA)
provides:
  - "`wez keys`: live 3-way keybinding classification (setup/default/user) + conflict/who-wins, grouped by category, with --json"
  - "cli/lib/showkeys.lua: a defensive parser for `wezterm show-keys --lua` (excludes copy_mode/search_mode)"
affects: [01-06 (doctor), 01-07 (completions), FOUND-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Untrusted external process output parsed line-by-line, never load()/eval'd (T-05-01)"
    - "Pure classify()/build_json() helpers separated from live run() so the autonomous gate is fixture-driven (no WezTerm session)"
    - "Cross-source binding identity = normalized (key, mods): strip `mapped:` prefix, canonicalize/sort mods, drop NONE"

key-files:
  created:
    - cli/lib/showkeys.lua
    - cli/commands/keys.lua
    - tests/cli/keys_test.lua
    - docs/repro/h-diag-keys.md
  modified: []

key-decisions:
  - "Effective table = top-level `keys = {}` from `wezterm show-keys --lua`; `key_tables` (copy_mode/search_mode) excluded by the `key_tables = {` boundary (D-13)"
  - "Baseline captured via `wezterm -n show-keys --lua` (`-n` skips the user config); parsed by the identical scanner (D-14)"
  - "Conflict detection is driven by overridden-absence of OUR bindings from the effective table; declarative action tables are not string-compared (presence governs), avoiding false action-mismatch conflicts"
  - "keybindings.lua read from the installed path $HOME/.config/wezterm/wezterm-setup/keybindings.lua at runtime (luastatic bundle has no LUA_PATH)"

patterns-established:
  - "Probe-before-parse (R6): captured the real show-keys --lua shape + baseline before writing the parser"
  - "Autonomous gate (fixture tests) vs integration/manual gate (live ./dist/wez keys) explicitly separated per D-18"

requirements-completed: [DIAG-02, DIAG-03, DIAG-04]

# Metrics
duration: 4min
completed: 2026-06-09
---

# Phase 1 Plan 05: `wez keys` Summary

**`wez keys` classifies the live `wezterm show-keys --lua` effective table against the no-config baseline and our `keybindings.lua` into setup/default/user with conflict/who-wins flags, grouped by category, with jq-valid `--json` output (DIAG-02/03/04).**

## Performance

- **Duration:** 4 min
- **Started:** 2026-06-09T18:07:12Z
- **Completed:** 2026-06-09T18:11:32Z
- **Tasks:** 2 (both TDD)
- **Files created:** 4 (1 gitignored probe)

## Accomplishments

- Built `cli/lib/showkeys.lua`: a defensive, line-oriented parser that turns the textual `wezterm show-keys --lua` module into normalized `{key, mods, action}` records, excluding `copy_mode`/`search_mode` (D-13) and never evaluating the untrusted action text (T-05-01).
- Built `cli/commands/keys.lua`: a pure `classify()` implementing the full D-14 math (setup = ours ∩ baseline ∩ effective; default = baseline ∩ effective, not ours; user = effective only; conflict = ours absent from effective), category grouping (Tabs/Panes/Navigation/Font/Other), a human grouped table, and jq-valid `--json` via vendored dkjson — implementing the Plan-01-registered subcommand WITHOUT editing `cli/spec.lua`.
- 21/21 fixture-driven assertions in `tests/cli/keys_test.lua` pass (autonomous gate, no live session); the full `tools/run-tests.sh` suite stays green (4/4 files).
- Live-verified on Linux: `./dist/wez keys` groups bindings under 3 category headers; `./dist/wez keys --json | jq .` exits 0 with `{ bindings, conflicts }` shape; promoted to `docs/repro/h-diag-keys.md` (R2).

## Task Commits

Each task was committed atomically (TDD: test → feat):

1. **RED — failing tests for parser + classifier** - `ba51ffc` (test)
2. **Task 1: show-keys --lua parser library** - `aa1cad4` (feat)
3. **Task 2: keys command — classify, group, table + --json** - `ad07225` (feat)

_Note: this plan is `type: tdd`-style per task; the RED gate (`test`) precedes both GREEN (`feat`) gates. No refactor commit was needed._

## Files Created/Modified

- `cli/lib/showkeys.lua` — parses `wezterm show-keys --lua` text → `{key, mods, action}` records; `parse()` for the effective table, `parse_baseline()` (same scanner) for the no-config baseline; excludes `copy_mode`/`search_mode`; skips+counts malformed lines.
- `cli/commands/keys.lua` — `wez keys`: pure `classify(effective, baseline, ours)` (D-14) + `build_json(entries, conflicts)` + live `run(args)`; reads installed `keybindings.lua` at runtime; groups by category; `--json` via dkjson.
- `tests/cli/keys_test.lua` — fixture-driven assertions: parser record count + copy_mode/search_mode exclusion + key/mods/action extraction + all four D-14 classification cases + `--json` dkjson round-trip.
- `docs/repro/h-diag-keys.md` — promoted R2 repro: observed grouped table + jq-valid `--json` evidence on Linux.
- `.tmp/probes/phase-1/05-show-keys-lua.md` — R6 probe (gitignored): real show-keys `--lua` shape + documented `wezterm -n` baseline capture; verdict HOLDS.

## Deviations from Plan

None — plan executed as written. The probe revealed (and the implementation accounts for) that on a host where the config is not yet installed, the effective table equals the baseline, so every live binding classifies as `default`/`user` and `[setup]` labels appear only after Plan 04 installs the config. This is the truthful, expected result (DIAG-03), documented in both the probe and the repro, not a deviation.

## Verification

- **Automated (autonomous gate):** `lua5.4 tests/cli/keys_test.lua` → `21 passed, 0 failed` (keys_test_exit=0). `tools/run-tests.sh` → all 4 files pass. `rg -ci verdict .tmp/probes/phase-1/05-show-keys-lua.md` → 1; `rg -c 'copy_mode|search_mode' cli/lib/showkeys.lua` → 4.
- **Manual / integration (Linux, D-18):** `bash tools/build.sh` (dev-launcher path; no luastatic on host) then `./dist/wez keys --json | jq .` → exits 0 (json_valid_ok); `./dist/wez keys | rg -c 'Tabs|Panes|Navigation'` → 3. Label distribution on the un-installed host: 132 `[default]` + 4 `[user]`, 0 conflicts (expected). `cli/spec.lua` confirmed untouched (`git diff` empty).

## Known Stubs

None. `wez keys` is fully wired to the live `wezterm show-keys --lua` output and the installed `keybindings.lua`; the `[setup]` label simply requires the config to be installed (Plan 04) to appear, which is correct behavior, not a stub.

## Notes for Downstream

- FOUND-04 (the `wez keys` half of Phase 1 success criterion #4) is satisfied on Linux; the `[setup]`-label divergence is fully exercised once Plan 04 installs the config and a session reloads.
- `cli/commands/doctor.lua` (Plan 06) can reuse `cli/lib/showkeys.lua` and `cli/commands/keys.classify` to surface keybinding health without duplicating the parser.
- macOS re-verification of the live `wez keys` output is deferred to the batched Mac pass before Phase 1 closes (D-04/D-05/D-18).

## Self-Check: PASSED

All created files exist on disk (`cli/lib/showkeys.lua`, `cli/commands/keys.lua`, `tests/cli/keys_test.lua`, `docs/repro/h-diag-keys.md`, this SUMMARY). All task commits found in git history (`ba51ffc`, `aa1cad4`, `ad07225`).
