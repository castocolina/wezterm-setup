---
phase: 01-foundation
plan: 06
subsystem: cli-install-lifecycle
tags: [doctor, uninstall, diagnostics, sentinel, lua]
requires:
  - "01-01: cli/spec.lua subcommand registry + wez.lua hyphen→underscore dispatch"
  - "01-04: cli/commands/install_state.lua PARSE/atomic_write/newest_backup contract + LOCKED sentinel markers"
provides:
  - "wez doctor: four core integrity gates gate the exit code (DIAG-01, D-15)"
  - "wez uninstall-state: granular removal honoring --keep-config/--keep-backup/--keep-cli (INST-04/05)"
  - "tools/uninstall.sh: sudo-free decision-free glue wired to the Makefile KEEP_* env (D-01)"
affects:
  - "Makefile uninstall target (KEEP_* env already wired in Plan 01-04 scaffold)"
  - "Phase 1 success criteria #2 (granular uninstall) and #4 (wez doctor half)"
tech-stack:
  added: []
  patterns:
    - "Pure decision core + injectable seams: aggregate()/gate_* and plan_removal()/excise_block() are filesystem-free, fixture-testable; run() wires them to the real env"
    - "Doctor reuses the install_state PARSE contract for the sentinel gate (single sentinel-parsing implementation, no variants)"
    - "Block excision via write-temp-then-os.rename (reused install_state.atomic_write) so a failed write leaves the original intact"
key-files:
  created:
    - "cli/commands/doctor.lua"
    - "cli/commands/uninstall_state.lua"
    - "tools/uninstall.sh"
    - "tests/cli/doctor_test.lua"
    - "tests/cli/uninstall_state_test.lua"
    - "docs/repro/h-diag-doctor.md"
  modified: []
decisions:
  - "Followed the PLAN's authoritative FOUR-core-gate spec for doctor's exit code (binary-on-PATH, sentinel well-formed, config dofiles cleanly, backup exists); completions-installed is ADVISORY (printed, never gates exit) — resolving the CONTEXT D-15 prose that loosely listed completions among the gates"
  - "uninstall: only the wezterm-setup/ subtree is removed, never its user-owned parent ~/.config/wezterm (T-06-03 guard checks the basename before rm -rf)"
metrics:
  duration: "~12 min"
  completed: "2026-06-09"
  tasks: 2
  files: 6
---

# Phase 1 Plan 6: `wez doctor` + granular uninstall Summary

`wez doctor` exit code gated by four CORE install-integrity checks (advisory probes printed but never flip exit 0, D-15) plus a granular `wez uninstall-state` that removes the managed block/config/CLI/backups independently via three keep-flags, fronted by sudo-free `tools/uninstall.sh` glue.

## What Was Built

### Task 1 — `wez doctor` (DIAG-01, D-15) — commit `a06febe`

`cli/commands/doctor.lua` exposes `run(args)` returning a numeric exit code. The exit code is gated by EXACTLY FOUR CORE integrity gates, each a pure builder returning `{ ok, label, detail }`:

1. **binary on PATH** — `command -v wez`
2. **sentinel block well-formed** — reuses `install_state.parse()` (the LOCKED markers, no variants)
3. **config dofiles cleanly** — `loadfile` + protected `pcall` of the managed `wezterm-setup/init.lua` (T-06-02: never executes the user's `wezterm.lua` side effects)
4. **timestamped backup exists** — reuses `install_state.newest_backup()`

`aggregate(core, advisory)` returns `code == 0` iff every core gate passed; `code ~= 0` otherwise. **Advisory probes** (completions-installed, live `wezterm cli list` reachability) are printed but **never** influence the code. All gate builders take injectable inputs (`opts.found`, config text, `opts.loader`, `opts.backup`) so the aggregation logic is fixture-testable with no real filesystem/PATH/live session.

### Task 2 — granular uninstall (INST-04/05, D-01) — commit `3dcf337`

`cli/commands/uninstall_state.lua` exposes `run(args, seams)`:
- `plan_removal(flags)` (PURE) maps `--keep-config/--keep-cli/--keep-backup` to a `{block, config, cli, backups}` removal plan — everything removed by default, each keep-flag suppressing exactly its component. The sentinel block has no keep-flag (its removal IS the uninstall).
- `excise_block(text)` (PURE) removes EXACTLY the sentinel-bounded managed range (markers inclusive + the close line's trailing newline), leaving surrounding user lines **byte-identical** (INST-04 no-trace, T-06-01). No-op when no block is present.
- Filesystem effects: block removed via `install_state.atomic_write` (write-temp-then-rename); only the `wezterm-setup/` subtree removed (basename-guarded, never the parent — T-06-03); `wez` binary removed; all `wezterm.lua.bak.*` removed. All user paths, sudo-free (T-06-04).

`tools/uninstall.sh` is decision-free glue (D-01): reads `KEEP_CONFIG`/`KEEP_CLI`/`KEEP_BACKUP`, maps truthy values to `--keep-*` flags, delegates to `wez uninstall-state`, surfaces its exit code. No `rm`, no removal branching. `shellcheck -x` clean.

## Verification Evidence

- **Unit (autonomous):** `lua5.4 tests/cli/doctor_test.lua` → 15 passed; `lua5.4 tests/cli/uninstall_state_test.lua` → 37 passed. Full suite `./tools/run-tests.sh` → all 7 files pass.
- **Doctor live (R2, `docs/repro/h-diag-doctor.md`):** built `dist/wez`; on a scratch HEALTHY install `wez doctor` exits **0** even though the advisory completions probe FAILs (proving advisory never flips exit 0); after excising the sentinel block, `wez doctor` exits **1** naming the failed gate.
- **Uninstall live dogfood:** full uninstall through `tools/uninstall.sh` against a scratch install removed block+config+cli+backups, exit 0, and `wezterm.lua` user lines were **byte-identical** to the pre-install original after block excision.
- **Glue contract:** `tools/uninstall.sh` references `KEEP_*` (7 hits), delegates to `uninstall-state` (5 hits), contains zero `sudo`.
- **D-16 honored:** `cli/spec.lua` is unmodified by this plan (last touched in 01-01).

## Deviations from Plan

### Auto-fixed / clarified

**1. [Rule 3 — clarification] Doctor gate count: PLAN's FOUR-gate spec is authoritative**
- **Found during:** Task 1 reading.
- **Issue:** The CONTEXT D-15 prose (`01-CONTEXT.md:76-79`) loosely lists "completions installed" among the exit-code gates, while the PLAN frontmatter `must_haves`, `<behavior>`, and `<acceptance_criteria>` are explicit and repeated: EXACTLY FOUR core gates, with completions-installed ADVISORY (printed, never affecting exit 0).
- **Resolution:** Followed the PLAN (the contract being executed). Implemented four exit-code gates; completions-installed is an advisory probe. The doctor unit test explicitly asserts `completions-not-installed with all core gates passing still returns 0`, and the R2 repro demonstrates it on a real run.
- **Files:** `cli/commands/doctor.lua`, `tests/cli/doctor_test.lua`, `docs/repro/h-diag-doctor.md`.
- **Commit:** `a06febe`.

No bugs, no missing-critical-functionality, no architectural changes were required.

## Known Stubs

None. Both commands are fully wired to real filesystem/PATH/session via injectable seams; tests drive both the pure logic and real scratch-FS effects.

## Threat Flags

None. This plan adds only first-party Lua + a sudo-free glue shell script; no new network endpoints, no package-manager installs (T-06-SC accept). All threat-register mitigations (T-06-01 byte-identical excision + atomic write, T-06-02 protected pcall, T-06-03 subtree-only removal, T-06-04 zero sudo) are implemented and test/grep-enforced.

## Self-Check: PASSED
- FOUND: cli/commands/doctor.lua
- FOUND: cli/commands/uninstall_state.lua
- FOUND: tools/uninstall.sh
- FOUND: tests/cli/doctor_test.lua
- FOUND: tests/cli/uninstall_state_test.lua
- FOUND: docs/repro/h-diag-doctor.md
- FOUND commit: a06febe (Task 1)
- FOUND commit: 3dcf337 (Task 2)
