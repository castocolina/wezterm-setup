# Plan 00-02 Summary — CWD Inheritance Mechanism

**Status:** Complete (Linux); macOS verification deferred.
**Date:** 2026-06-07
**Outcome:** CWD mechanism locked → **OSC 7 (primary) + WezTerm OS-level read (backstop)**.

## What was decided

Pane-split / new-tab cwd inheritance is **WezTerm default behavior**. Standardize on **OSC 7**
(shell-emitted `file://HOST/path`) as the portable, immediate mechanism, with WezTerm's OS-level
cwd read (`/proc` on Linux, libproc on macOS) as the backstop. Full record:
[`.planning/decisions/cwd-mechanism.md`](../../decisions/cwd-mechanism.md).

## How (evidence-driven, reproducible)

`.tmp/h03-cwd-mechanism/run.sh` against an isolated headless mux proved inheritance in two cases:
- **OSC 7 shell** (`bash -l`): split inherited `file://pop-os/tmp/cwdtest-AAA/` (host present = OSC 7).
- **No-OSC7 shell** (`env -i bash --norc --noprofile`): split still inherited the real cwd
  `/tmp/cwdtest-BBB` — WezTerm read the source process cwd at spawn time (`file:///` = OS read).

The `cwd` URI host distinguishes the source: `file://<host>/` = OSC 7; `file:///` = OS read.

## Deliverable
- `.planning/decisions/cwd-mechanism.md` — committed decision record.

## Phase 1 implication
- `cwd.lua` needs no custom split logic; ship OSC 7 emission in shell integration for **both** zsh
  and bash so cwd tracking is accurate regardless of distro rc quirks.

## Deferred
- **macOS:** re-run `run.sh` on the Mac pass (libproc + OSC 7) before FOUND-01 ships (D-04/D-05).

## ROADMAP Success Criterion 2
✅ Satisfied (Linux portion): mechanism proven with a standalone experiment script; macOS recorded
as a deferred verification checkpoint per the user's macOS-later decision.
