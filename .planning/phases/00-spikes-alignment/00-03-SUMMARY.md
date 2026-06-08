# Plan 00-03 Summary — `wezterm cli` Surface Audit

**Status:** Complete (Linux); macOS column deferred.
**Date:** 2026-06-07
**Outcome:** Durable catalogue of the full `wezterm cli` surface recorded.

## What was produced

A committed reference catalogue of **all 19 `wezterm cli` subcommands** (WezTerm `20260604-145453`)
with purpose, key flags, Linux availability, and a pending macOS column:
[`.planning/decisions/wezterm-cli-surface.md`](../../decisions/wezterm-cli-surface.md).

## How
Captured `wezterm cli --help` + every subcommand's `--help` against an isolated headless mux
(no GUI, no sudo). Raw capture in `.tmp/probes/phase-0/05-wezterm-cli-help-surface.md` (gitignored).

## Known gaps documented (with workarounds)
- **`set-user-var` is NOT a CLI subcommand** → use the **OSC 1337 `SetUserVar` escape** for pane
  user vars (e.g. `WEZTERM_TAB_COLOR`). Confirmed absent from the surface.
- **No "set tab color" command** → encode color in the tab-title prefix (`"color:title"`) via
  `set-tab-title` (see `tab-title-format.md`).
- **cwd inheritance** is WezTerm-default on split/spawn; `--cwd` is an override.

## Deferred
- **macOS column:** re-run the audit on the Mac pass (libproc-backed mux) before Phase 1 closes (D-04/D-05).

## ROADMAP Success Criterion 3
✅ Satisfied: full surface audited; gaps (missing subcommands) documented with workarounds.
