# wezterm-setup Phases 06.8-06.9 — Claude Code Autonomous Run Driver

**DRAFT — not yet reviewed or run.** Copy-paste driver for a single autonomous run
covering the two remaining E2E-battery phases (06.8: Linux CI Gate, 06.9: Tier 3 Firing +
Tier 4 Visuals). All operational detail — cross-AI routing, per-phase checklist, gates,
non-negotiable rules — lives in `.planning/ONESHOT-RULES.md`; this file only starts the
run and points there.

## How To Run

From the repository root, in a fresh Claude Code session:

```sh
claude --dangerously-skip-permissions
```

`--dangerously-skip-permissions` is required so the session doesn't stall on a
tool-permission prompt partway through an unattended run — the real safety gates for
this run are `.planning/ONESHOT-RULES.md`'s own Non-Negotiable Rules (rules 4, 6, and 7),
not Claude Code's generic per-call confirmation.

Paste the block below as the first message, then leave it running.

---

▼▼▼ COPY FROM HERE ▼▼▼

/gsd-autonomous --to 06.9 --converge --opencode

You are the Claude Code orchestrator for the remaining wezterm-setup v1 E2E-testing-battery
phases (06.8: E2E Linux CI Gate, 06.9: E2E Tier 3 Firing + Tier 4 Visuals).

Only implement through phase 06.9.

Read `.planning/ONESHOT-RULES.md` in full now, and again at the start of every turn,
along with `.planning/STATE.md`, `.planning/ROADMAP.md`, and `.planning/REQUIREMENTS.md`.
Follow `.planning/ONESHOT-RULES.md` exactly — it is the binding playbook, this message is
only the entry point.

Objective: run 06.8 and 06.9 to completion, unattended, stopping only for a real
destructive anomaly, an unrecoverable tool/authentication failure, or a circuit breaker
(`.planning/ONESHOT-RULES.md` Non-Negotiable Rule 7). Never trust a subagent's or
delegate's self-reported "passed" — independently re-run the real verification commands
yourself before advancing any phase (Rule 1). Never touch Phase 06.8's CI workflow scope
while executing 06.9 (Rule 4). Real OS-level input injection (Tier 3 firing) is this
project's single highest-risk surface — a misdirected `ydotool` keystroke can land on
THIS session's own terminal; never fire without the window-focus-verification protocol
in Rule 6, and treat an unverifiable focus step as a stop condition, not something to
work around. Defer everything a human needs to see to the end-of-phase UAT report
(`workflow.human_verify_mode: "end-of-phase"`) and this run's final report — the user
reviews once, after waking up, not mid-run. Do not ask the user to send a continuation
command at any point between here and Phase 06.9's close.

Treat verification as an autonomous convergence loop: any failing test, review finding,
divergent behavior, incomplete evidence, or gap report must be planned, fixed, re-tested,
and independently re-verified until clean. Do not halt merely because a previous
corrective attempt failed; halt only for a real safety/confirmation condition per
`.planning/ONESHOT-RULES.md` Non-Negotiable Rule 7.

If a `gaps_found` verification result appears at any phase, choose "Run gap closure"
yourself and continue the convergence loop described in `.planning/ONESHOT-RULES.md`
Non-Negotiable Rule 8.

▲▲▲ COPY TO HERE ▲▲▲
