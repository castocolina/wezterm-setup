---
phase: 01-foundation
plan: 07
subsystem: cli-completions
tags: [completions, cli, shell, zsh, bash, diag-05, d-16]
requires:
  - "cli/spec.lua (the single-source argparse tree — Plan 01)"
  - "tools/setup.sh installer + wez binary on PATH (Plan 04)"
  - "tools/build.sh bundle (Plan 01)"
provides:
  - "`wez completions <zsh|bash>` — spec-driven completion-script generator (D-16)"
  - "`wez __complete <context>` — hidden dynamic-value hook for future contexts"
  - "install-time completion registration in tools/setup.sh (marker-guarded, sudo-free)"
affects:
  - "tools/setup.sh (added STEP 5b registration)"
  - "cli/wez.lua (added __complete -> complete module alias)"
tech-stack:
  added: []
  patterns:
    - "Generators read the live argparse parser (_commands/_options) so coverage grows with the spec — no per-phase generator edits (D-16)"
    - "Dynamic completion routes through a hidden `wez __complete <context>` hook; future contexts plug in without regenerating static scripts"
    - "Install-time rc edits are idempotent + marker-guarded; distinct markers coexist (osc7 + completions)"
key-files:
  created:
    - "cli/commands/completions.lua"
    - "cli/commands/complete.lua"
    - "tests/cli/completions_test.lua"
    - "docs/repro/h-diag-completions.md"
  modified:
    - "tools/setup.sh"
    - "cli/wez.lua"
decisions:
  - "Walk the argparse parser's _commands/_options to enumerate subcommands + long flags; drop the auto -h/--help and hidden __complete from visible candidates (D-16)"
  - "Dispatcher aliases the spec name `__complete` to the clean module leaf `complete` (cli/commands/complete.lua) — closed map, no raw user input on the require path (T-01-02 holds)"
  - "Generated scripts shell out to `wez __complete subcommands` for dynamic candidates so later phases extend completion by teaching __complete new contexts"
  - "Completions written to user-owned dirs (~/.local/share/zsh/site-functions/_wez, ~/.local/share/bash-completion/completions/wez); rc registration guarded by `# wezterm-setup:completions`, sudo-free (T-07-01/03)"
metrics:
  duration: "~1 session"
  completed: "2026-06-09"
  tasks: 2
  files: 6
---

# Phase 1 Plan 07: Shell Completions Summary

Spec-driven zsh/bash completion generation from `cli/spec.lua` (D-16) with a hidden `wez __complete` dynamic-value hook, registered into user-owned completion dirs by the installer (sudo-free, idempotent, marker-guarded) — `wez <Tab>` completes subcommands and `wez keys --<Tab>` completes `--json` in both shells.

## What Was Built

### Task 1 — generator + dynamic hook (`d7930e8`, TDD)
- **`cli/commands/completions.lua`** — `run(args)` walks the argparse parser built by `cli/spec.lua` (its `_commands` + each command's `_options._aliases`), enumerates every visible subcommand and its long flags, and emits a shell-appropriate completion script (`#compdef wez` zsh function / `complete -F _wez` bash function). The walk is the single spec-driven step: adding a subcommand to `spec.lua` makes it appear in regenerated output with no edit here. For testability `run` accepts an optional injected `parser`/`names`; production walks the real spec.
- **`cli/commands/complete.lua`** — `run(args)` implements the hidden `wez __complete <context>` hook. A closed context dispatch (`subcommands` for Phase 1) prints newline-separated plain tokens drawn from the spec; unknown contexts emit nothing and still exit 0 (a Tab-time hook must never become an error surface). Plain tokens only — no shell metacharacters (T-07-02).
- **`cli/wez.lua`** — added a small fixed alias map so the spec name `__complete` resolves to the clean module leaf `complete.lua` (the `-`→`_` transform leaves `__complete` unchanged, so it would otherwise miss the file). Closed map over the already-allow-listed name; T-01-02 still holds.
- **`tests/cli/completions_test.lua`** — 47 assertions, all spec-driven (the expected subcommand set is derived from the real spec minus hidden names, never hardcoded). Asserts non-empty zsh/bash scripts covering every visible subcommand + `--json`, the `__complete` shell-out, hidden `__complete` excluded from visible candidates, and a "spec grew" proof (a parser with an extra command surfaces it without generator edits).

### Task 2 — install-time registration + repro (`aea68ef`)
- **`tools/setup.sh` STEP 5b** — generates both scripts via explicit `wez completions zsh` / `wez completions bash`, writes them to user-owned dirs (`~/.local/share/zsh/site-functions/_wez`, `~/.local/share/bash-completion/completions/wez`) atomically (temp→rename), and appends an idempotent rc line guarded by `# wezterm-setup:completions`. Distinct from and coexisting with Plan 04's `# wezterm-setup:osc7`. Sudo-free.
- **`docs/repro/h-diag-completions.md`** — R2 evidence: `bash -n`/`zsh -n` validity, observed `wez <Tab>` subcommand candidates (live bash `compgen` + zsh `_wez` candidate block), `wez keys --<Tab>` → `--json` in both shells, the `wez __complete subcommands` output, and idempotent/coexistence proof.

## Verification

- `lua5.4 tests/cli/completions_test.lua` → 47 passed, 0 failed.
- Full suite `tools/run-tests.sh` → 8/8 files passed (no regression from the `wez.lua` alias change).
- `./dist/wez completions zsh | rg -c 'doctor|keys'` = 2; bash = 2.
- `./dist/wez __complete subcommands` lists all six visible subcommands through the binary.
- Generated scripts pass `bash -n` and `zsh -n`.
- **bash (live)**: `_wez` via `compgen` offers all subcommands at position 1 and `--json` after `keys`.
- **zsh**: `compinit` loads `_wez` without error; its delimited subcommand block = `version doctor keys install-state uninstall-state completions`, and the `keys` branch offers `--json`.
- **Installer dogfood** against a scratch HOME: scripts written; re-install idempotent (completions marker count stays 1); `# wezterm-setup:osc7` line preserved alongside `# wezterm-setup:completions`.
- `shellcheck -x tools/setup.sh` clean.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Dispatcher could not reach the `__complete` module**
- **Found during:** Task 1 verification (`./dist/wez __complete` reported "not implemented").
- **Issue:** The dispatcher maps a subcommand name to its module via `name:gsub("%-","_")`. For `__complete` (no hyphens) that yields `cli.commands.__complete`, but the plan's module is `cli/commands/complete.lua` — so the registered hidden command had no reachable module.
- **Fix:** Added a closed `MODULE_ALIASES` map in `cli/wez.lua` aliasing `__complete` → `complete`. The alias is applied to the already-allow-listed name only; no raw user input reaches the require path (T-01-02 preserved). `cli/spec.lua` was NOT modified (D-16).
- **Files modified:** `cli/wez.lua`
- **Commit:** `d7930e8`

## Known Stubs

None. The `__complete` Phase 1 context set is intentionally minimal (`subcommands`) by design (D-16) — it is the established extension point for future phases (colors, scene names), not a stub. Documented in `cli/commands/complete.lua` and the repro.

## Notes for Verifier

- The plan's Task 2 verify line `test "$(rg -v '^\s*#' tools/setup.sh | rg -ci sudo)" -eq 0` counts ONE pre-existing line: the STEP 2 `log "bootstrapping WezTerm (sudo-free)…"` message (Plan 04). That is a log string, not a privileged invocation, and predates this plan. The lines THIS plan added contain no `sudo` (acceptance criterion: "no `sudo` in the added lines" — satisfied). The completion registration writes only to user-owned paths (T-07-03).
- Live interactive zsh Tab capture via `zpty` is flaky in a non-tty sandbox; zsh evidence was captured deterministically by loading the generated `_wez` under `compinit` (no error) and reading its candidate blocks, plus `zsh -n` syntactic validation. bash evidence is a live `compgen` run.

## Self-Check: PASSED
