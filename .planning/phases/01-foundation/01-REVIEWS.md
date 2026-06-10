# Phase 01-foundation — Review Feedback (for `--reviews` replan)

**Source:** clean-context spec review (`/review-spec` → `reviewing-specs`, GSD · plan archetype), iter 1.
**Date:** 2026-06-08
**Scope:** the 7 plan files `01-01-PLAN.md` … `01-07-PLAN.md`.
**Grounded against:** `/home/user-zero/git/cco/wezterm-setup` (Makefile, README, decisions/, REQUIREMENTS, ROADMAP, docs/agent-iteration.md — all factual premises confirmed).

Each item below states a **Required outcome**. Apply every CRITICAL and HIGH. The planner owns
how the change lands in plan structure (frontmatter, waves, task actions, acceptance criteria),
but the outcomes are binding.

---

## LOCKED operator decision (apply during replan)

**HIGH #1 resolution — completions gate is ADVISORY.** `wez doctor`'s "completions installed"
check MUST be an advisory/warning line that does **NOT** affect the exit code. A missing
completions registration must never turn a healthy install's `wez doctor` into a non-zero exit.
This is consistent with CONTEXT D-15 ("live-session probes are advisory only, never affect exit 0").
Consequence: Plan 06 and Plan 07 stay decoupled — do NOT add a 06→07 dependency. Plan 06's doctor
**core** gates remain: binary-on-PATH, sentinel well-formed, config dofiles cleanly, backup exists.
"Completions installed" drops from the core/exit-code set into the advisory set.

---

## CRITICAL

### C1 — `cli/spec.lua` ownership contradiction (Plan 01 vs Plans 06 & 07)
Plan 01 registers the COMPLETE Phase 1 subcommand surface (`version, doctor, keys, install-state,
uninstall-state, completions, __complete`) as a frozen single-source contract — its own truth says
"so no later plan edits spec.lua (D-16)" and its rationale is parallel-safety (no shared-file wave
conflict). Plans 04 and 05 honor this ("does NOT edit spec.lua"; `spec.lua` absent from
`files_modified`). But Plan 06 lists `cli/spec.lua` in `files_modified` and instructs "Register the
`doctor` subcommand" / "Register the `uninstall-state` subcommand + the three keep-flags in
`cli/spec.lua`", and Plan 07 instructs "Register both `completions` and the hidden `__complete`
subcommands in `cli/spec.lua`". Plan 07's `read_first` further claims spec.lua is "extended by
Plans 04/05/06" — contradicting 04/05's own statements.

**Required outcome:** One authoritative reading. Keep Plan 01 as the sole writer of `cli/spec.lua`
(it already registers all seven subcommands + their flags). Plans 06 and 07 must:
- remove `cli/spec.lua` from `files_modified`;
- rewrite their task actions/acceptance from "register the `<x>` subcommand in cli/spec.lua" to
  "implement the already-registered `<x>` command module" (mirror the exact phrasing Plans 04/05 use);
- Plan 07 must drop the "extended by Plans 04/05/06" claim.
No plan except 01 may write `cli/spec.lua`.

---

## HIGH

### H1 — doctor↔completions coupling
**Resolved by the LOCKED decision above (advisory gate).** Apply it in Plan 06: move "completions
installed" out of the exit-code-affecting core gates into the advisory/printed-only set; keep Plans
06 and 07 in the same wave with no new dependency edge.

### H2 — `./dist/wez <subcommand>` verifications run against a stale binary
Plan 01 builds `dist/wez` via luastatic, which bundles `cli/` **at build time** (cli-language.md:
standalone binary, no `LUA_PATH`, requires resolve inside the bundle). Plans 05, 06, 07 add new
`cli/commands/*.lua` / `cli/lib/*.lua` modules, then their acceptance/verify invoke the *built*
binary (`./dist/wez keys`, `./dist/wez doctor`, `./dist/wez completions zsh|bash`) — but none
rebuilds first, so those commands exercise the Plan-01 stubs, not the new modules.

**Required outcome:** Every plan that adds a command module and then verifies via `./dist/wez <cmd>`
must include a rebuild step (`bash tools/build.sh` or `make build`) **before** the `./dist/wez`
verification — or run the verification through `lua5.4 cli/wez.lua <cmd>` against the source tree.
Make the rebuild explicit in the task action and the verify block. (Plan 04 is already fine — it
verifies via `lua5.4 tests/...` only.)

### H3 — `wez keys` runtime resolution of `keybindings.lua` is unspecified
Plan 05 Task 2 says "load our key table … (resolve its installed path)". `wez` is a standalone
static binary with no implicit load path; "resolve its installed path" is not actionable and two
implementors will invent different strategies.

**Required outcome:** Plan 05 must pin exactly how the binary locates `keybindings.lua` at runtime —
choose one and state it concretely (e.g. compile-time constant
`~/.config/wezterm/wezterm-setup/keybindings.lua`, an env var, a config-dir flag, or reading the
repo path during dev). Also reconcile Plan 05's dependency set: live `wez keys` classification reads
the applied config via `wezterm show-keys --lua`, which presumes the config is installed (Plan 04) —
either add `01-04` to Plan 05 `depends_on`, or scope Plan 05's live verify so it does not assume an
applied install (unit tests on fixtures already cover the classification math).

---

## MEDIUM

### M1 — `make test` dispatches to an uncreated script
`Makefile:28-29` (`test:` → `./tools/run-tests.sh`) and README:141 document `make test`, but no
Phase 1 plan creates `tools/run-tests.sh`. **Required outcome:** either a plan creates
`tools/run-tests.sh` (a thin harness running the `lua5.4 tests/**` suite) or the gap is explicitly
recorded as deferred so `make test` isn't silently broken.

### M2 — RC-file guard markers unspecified (Plans 04 & 07)
Plan 04 Task 2 (OSC 7 source line) and Plan 07 Task 2 (completions fpath/source line) both inject
idempotent rc lines guarded by an unnamed marker. **Required outcome:** specify distinct, namespaced
marker strings (e.g. `# wezterm-setup:osc7` vs `# wezterm-setup:completions`) so the two guards
cannot collide or mutually defeat dedup on reinstall.

### M3 — Plan 04 atomic-write mitigation (T-04-01) missing from the task that implements it
Plan 04's threat model documents write-to-temp-then-atomic-rename for the sentinel injection, but
Task 1's action/acceptance don't require it; a step-by-step executor produces a direct overwrite.
**Required outcome:** Task 1 action must mandate the temp-write + atomic-rename pattern, and the
acceptance must include a verifiable condition (an interrupted write leaves `wezterm.lua` unchanged).

---

## Non-blocking note (not a plan defect — for awareness)
REQUIREMENTS.md INST-01 and README literally say a single `dofile(...)` line; the locked, later
decision **D-17** replaced that with the augment model `require('wezterm-setup').apply(config)`,
which the plans correctly implement. The stale `dofile` wording in REQUIREMENTS/README should be
reconciled separately — the plans follow the authoritative decision and need no change for this.
