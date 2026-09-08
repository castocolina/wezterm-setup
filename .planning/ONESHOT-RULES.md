# ONESHOT PLAYBOOK — wezterm-setup Claude Code Autonomous Run

**DRAFT — not yet reviewed or run.** General, phase-agnostic execution rules for any
autonomous `/gsd-autonomous` run in this repository (adapted from the equivalent
`tools-installer` playbook's structure, not its content). Phase-specific scope (which
phases, which decisions are locked) lives in each phase's own `{N}-CONTEXT.md` and in
`.planning/ONESHOT-AUTONOMOUS.md`'s entry-prompt — this file states the rules that apply
regardless of which phase is currently running. Do not treat any specific number, path,
or finding below as final until reviewed. Read this in full at the start of the run and
again at the start of every turn.

## Starting Point

Determine the working phase at invocation time, not from a hardcoded number: read
`.planning/ROADMAP.md` and `.planning/STATE.md` and use the earliest phase that is not
`phase_complete`. `gsd-autonomous`'s own resume gates already reconcile a
partially-finished phase — do not hand-run a phase's closeout; let the Per-Phase
Checklist below apply to whichever phase is earliest-incomplete, up to whatever stop
point the entry prompt names.

## Per-Phase Checklist

For every phase this run touches, confirm all of these before advancing — do not assume
any ran just because the previous one did:

1. **Discuss** — `{N}-CONTEXT.md` exists and reflects the phase. If it already exists
   (`has_context: true`), do not re-run discuss-phase and do not second-guess its locked
   decisions.
2. **Plan** — `PLAN.md` file(s) exist for every wave, and carry `cross_ai: true` in
   frontmatter when cross-AI delegation is intended for that plan (Rule 2).
3. **Plan-review convergence** — if `workflow.plan_review_convergence: true` is set,
   run planning through `--converge` with the configured reviewer lane
   (`review.default_reviewers` / `review.models.<cli>` in `.planning/config.json`). 0
   unresolved HIGH concerns before execution.
4. **Execute** — every wave's `SUMMARY.md` exists, tree is clean, `make test` green.
   Record whether cross-AI delegation fired (`workflow.cross_ai_execution`) or fell back
   to a local `gsd-executor` — either is acceptable in this project, but note which
   happened.
5. **Code review** — `REVIEW.md` shows clean or all findings fixed.
6. **Verify-work** — `VERIFICATION.md` shows `passed`, backed by REAL command output
   (Rule 1). Never accept a delegate's or subagent's unverified claim.
7. **Real-machine-effect review** — if the phase's own `{N}-CONTEXT.md` scopes in any
   of: a CI/GitHub Actions workflow, real OS-level input injection, or a real screenshot
   /GUI check, apply the matching rule below (Rule 3 for CI, Rule 6 for input injection)
   before considering that item done. If the phase touches none of these, skip.
8. Only close a phase and advance once every applicable item above is evidenced.

(This project currently has no `.codegraph/` index and no prior `gsd-audit-uat` usage on
record — skip both rather than inventing steps that don't apply here. Re-check this if
either changes.)

## Non-Negotiable Rules

1. **Never trust a self-reported "passed."** This project already shipped a bug because
   a debug subagent reported "5/5 clean runs, guardrail accepted" and that report was
   wrong — the fix was only proven broken when a human independently re-ran the exact
   same regression test and watched it fail
   (`.planning/debug/knowledge-base.md` § `scene-launch-motd-race`). `docs/agent-iteration.md`
   R2 codifies this generally: *"Should work", "compiles", "looks right" are not
   evidence. The output of the verifying command, with its exit code, is."* This applies
   to every phase, not just the one where it was first learned — whichever agent or
   delegate ran execution, the orchestrator itself re-runs the real verification commands
   (`make test`, `make e2e`, and any phase-specific target) afterward before advancing.

2. **Cross-AI delegation contract — plans declare it, and each role has a defined
   fallback.** `.planning/config.json` carries TWO independent cross-AI routes — plan-review
   convergence and execution delegation. Which provider/model is PRIMARY for either role,
   and how it resolves (local router, direct provider, whatever), is a
   `.planning/config.json` / `~/.config/opencode/opencode.jsonc` configuration detail —
   this playbook does not duplicate or hardcode it; read the config, don't restate it here.
   - Every generated `PLAN.md` whose execution should delegate to cross-AI must carry
     `cross_ai: true` in its frontmatter — that field is what actually makes
     `execute-phase.md` delegate to `workflow.cross_ai_command` instead of a local
     `gsd-executor`. Add it if a planner omits it; do not advance a plan past planning
     without it when cross-AI delegation is intended for that plan.
   - **Cross-AI EXECUTION fallback:** if the configured execution route fails for a given
     plan (unreachable, errors, times out), fall back to `opencode run --model
     xai/grok-4.6` before treating it as a Rule 7 circuit breaker. Record which path
     actually ran.
   - **Cross-AI plan-review-convergence fallback:** if the configured reviewer route
     fails, fall back to `opencode` with model `openai/gpt-5.6-sol` at high reasoning
     effort before treating it as a Rule 7 circuit breaker. Record which path actually
     ran.
   - Never substitute one role's model for the other's — execution and plan-review are
     different jobs, and a fallback for one is not a fallback for the other.

3. **If a phase wires CI, it is not done until a real run is observed green.** A
   workflow file that merely "looks correct" is exactly the kind of unverified claim
   Rule 1 forbids. If observing a live push/PR-triggered run isn't feasible from this
   session, record it as a `human_verification` item — do not assume success.

4. **Respect phase boundaries — never modify another phase's already-locked scope from
   within the current one.** Before editing a shared file (a CI workflow, a shared config,
   a cross-cutting module), check whether an earlier phase's `{N}-CONTEXT.md` already
   locked decisions about it. Reopening a closed phase's scope from inside a later phase
   is scope creep — defer it and note it, don't just do it because it's convenient.

5. **This project's real-machine-mutation policy is decided per phase, not blanket-
   forbidden — read the current phase's `{N}-CONTEXT.md` before assuming either way.**
   Some phases in this project's roadmap have explicitly decided that a `make` target
   SHOULD install real packages or start real daemons on the real machine (dev-environment
   provisioning is a legitimate, intentional side effect here) — do not block on that if a
   phase's locked decisions call for it. What is NEVER acceptable regardless of phase:
   - Touching the user's real running WezTerm GUI session, real `wezterm.lua`, or real
     shell-rc files outside an isolated scratch config. Existing e2e tiers already
     establish this isolation pattern (fresh scratch `HOME`/`XDG_RUNTIME_DIR`/
     `XDG_CONFIG_HOME`/`WEZTERM_CONFIG_FILE` per test case) — any new test that spawns a
     real WezTerm process must follow the same pattern.
   - Exercising `wez uninstall` or the installer's sentinel-block logic against this
     actual dev machine's real config "to prove it live" — that already has its own
     dedicated scratch-dir coverage; do not duplicate it against the real config.

6. **Input-injection safety protocol — applies to ANY phase that adds real OS-level
   input injection, not just one specific phase.** Confirmed live on this machine
   (Bazzite, KDE Plasma, Wayland): `ydotoold` was not running when checked, and `ydotool`
   itself has **no window-targeting concept** — every key/click event goes to whatever
   window currently has OS input focus, system-wide (unlike `xdotool key --window <id>`
   on X11 — which doesn't apply on this Wayland machine anyway — or the `cliclick`
   precedent from `06.5-04-PLAN.md`, which also lacks window-scoping but at least runs on
   a different OS). A misdirected event under this mechanism could land on THIS Claude
   Code session's own terminal and be interpreted as a command — that is the literal
   failure mode of a system-wide virtual-input tool with no scoping, not a hypothetical.
   **Whenever any phase drives real OS input:**
   - Spawn the target under an isolated scratch config (Rule 5).
   - Explicitly activate/focus that window and VERIFY the focus took effect (read back the
     focused window's title/class and confirm it matches the freshly spawned instance)
     immediately before every injected event, and re-verify after — never fire blind.
   - If focus cannot be verified with confidence on the active compositor/OS, that is a
     phase-blocking question for that phase's own planning to resolve — raise it there,
     do not silently ship a test that "usually" targets the right window.
   - Never run this class of test unattended on a shared interactive desktop session
     without the verify-before-every-event step above.

7. **Circuit breaker — halt, do not guess past these:**
   - A cross-AI route (reviewer or executor) is unreachable AND its Rule 2 fallback also
     fails — do not silently proceed with zero reviewers/executors, and do not invent a
     third model on the fly.
   - Rule 6's focus-verification protocol cannot be built with confidence for the active
     compositor/OS — record as `human_verification`, do not fire blind.
   - A permission-granting step (sudo password, group-membership re-login, OS permission
     dialog) requires interaction this session's account cannot complete
     non-interactively — record as `human_verification`, do not fake success.
   - Any tool/auth failure repeats with zero progress after a genuine retry.

8. **Treat verification as a convergence loop, not a single check.** Any failing test,
   review finding, divergent behavior, or gap report must be planned, fixed, re-tested,
   and independently re-verified until clean. Do not halt merely because a previous
   corrective attempt failed — halt only for a Rule 7 condition or a demonstrated
   repeated zero-progress tool failure. If a `gaps_found` verification result appears,
   choose "Run gap closure" and continue this loop yourself.

9. **Stay bash-3.2-safe in every script this run touches or produces.** This project's
   existing convention (`tools/*.sh`) targets macOS's ancient shipped bash as the floor —
   do not introduce GNU-bash-only constructs (associative arrays, `${var^^}`, etc.) in any
   new script regardless of which phase produces it. Shell-portability questions specific
   to zsh (macOS's interactive default) belong to whichever phase actually discusses macOS
   parity — do not attempt to verify or adapt for zsh in a run that hasn't reached that
   phase's own discuss-phase session.

10. **This run is an explicit, scoped exception to `.claude/agent-rules.md`'s "No
    auto-commit... wait for an explicit go-ahead" rule.** The user's request for an
    autonomous run is the explicit authorization for unattended commit/push, for the exact
    scope named in `.planning/ONESHOT-AUTONOMOUS.md`'s entry prompt — `commit_docs: true`
    already governs GSD's own per-step commits. This exception does not carry forward to
    any work outside that named scope.

11. **Every new registry/OS-detection code path ships with test coverage in the same
    commit.** Mirrors existing project convention (e.g. `tests/e2e/platform.lua` as the
    single source of Mac↔Linux deltas): a new compositor-detection branch, a new
    screenshot-tool selector, or a new self-skip gate must land with its own test, not as
    untested glue.

## Cross-AI Execution — Confirm Reachability Before Relying On It

Do not assume a configured cross-AI route is reachable just because it's present in
`.planning/config.json` — a config entry records intent, not a live-tested connection.
The run's FIRST cross-AI call for a given role is that role's actual confirmation. If the
PRIMARY route fails, apply that role's Rule 2 fallback (grok-4.6 for execution,
gpt-5.6-sol/high for plan-review-convergence) before treating it as Rule 7's circuit
breaker — do not retry the same failing route indefinitely, and do not invent a model
outside the two defined fallbacks without surfacing that first.

## Phase/Milestone Close

At the end of whatever scope this run targets (or at any Rule 7 halt), consolidate
everything a human needs to see into a single end-of-run report — real command
output/exit codes (Rule 1), any CI-run evidence (Rule 3), any input-injection
focus-verification evidence (Rule 6), and any `human_verification` items recorded along
the way — so the one review pass after this run has everything in one place, never a
mid-run stop to ask for it.
