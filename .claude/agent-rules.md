# Agent Rules — wezterm-setup

## Universal rules

- **English everywhere** — code, comments, commits, PR text, agent responses.
- **No auto-commit.** Surface `git status` and `git diff --stat`; wait for an explicit
  go-ahead ("commit", "do it", "proceed") before any commit/push/amend/force-push.
- **Re-read before edit.** The user may edit files between turns; never trust in-memory
  contents. Re-read before evaluating or modifying.
- **Skill outputs land on disk.** Brainstorms, designs, plans, analyses are written to
  files (under `.planning/` or `docs/`). If it isn't on disk, it doesn't exist.
- **Spec-first.** The active GSD plan is authoritative. The agent that produces a design
  or plan is *not* the same agent that executes it.
- **Hypothesis before implementation.** Every shipped behavior begins as an experiment
  script in `.tmp/`. Promote only after a manual repro is green on Linux
  and macOS.
- **Verify before declaring done.** Any "ready" claim is backed by `wez doctor` output
  or a recorded manual repro. No "should work" — only "verified by `<command>` → `<output>`".
- **Questions are not orders.** Answer questions; do not auto-change code.
- If existing code conflicts with the requirements or active GSD plan, refactor the code.
  The spec is not silently rewritten to match drifted code.

## Pluggable rules

Stack-specific conventions live in `.claude/conventions.md` — this file is created once
the CLI language is settled after Phase 0. Replace it wholesale when the language decision
is made. Keep the filename; the agent always reads it.
