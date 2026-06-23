---
phase: quick-260623-gn7
plan: 01
subsystem: companion-cli / installer-glue
tags: [uninstall, idempotency, bash, tdd, D-01]
requires:
  - "tools/uninstall.sh (decision-free glue, D-01)"
  - "wez uninstall-state (removal engine, owns all rm decisions)"
provides:
  - "Idempotent tools/uninstall.sh: no reachable wez -> warn + exit 0 (was exit 1)"
  - "Regression guard: tests/cli/uninstall_idempotent_test.lua"
affects:
  - "make uninstall (re-runnable)"
  - "make uninstall install from a clean / half-installed state (no longer aborts before install)"
tech-stack:
  added: []
  patterns:
    - "Run-the-script (not source) test harness with controlled env (PATH= + empty WEZ_BIN_DIR)"
    - "Absolute bash path resolved before PATH is emptied, so PATH= only starves command -v wez"
    - "Comment-filtered grep idiom for the decision-free rm-guard (no -n on first grep)"
key-files:
  created:
    - tests/cli/uninstall_idempotent_test.lua
  modified:
    - tools/uninstall.sh
decisions:
  - "Not-found else branch: err()+exit 1 -> log() warning + exit 0 (idempotent no-op success)"
  - "Removed the now-dead err() helper (its only two call sites were this branch) to clear SC2329"
  - "Kept the glue decision-free (D-01): no rm, no path-branching, no config inspection"
metrics:
  duration: ~3min
  completed: 2026-06-23
requirements: [T-06-04]
---

# Quick Task 260623-gn7: Uninstall Idempotent When wez Absent Summary

`tools/uninstall.sh` now treats a missing `wez` binary as a no-op success (warn + `exit 0`) instead of aborting with `err` + `exit 1`, making `make uninstall` re-runnable and unblocking `make uninstall install` from a clean / half-installed state — guarded by a committed RED->GREEN regression test.

## What Changed

### Task 1 (RED) — regression test — commit `2798d6f`
Created `tests/cli/uninstall_idempotent_test.lua`. The harness RUNS `tools/uninstall.sh` directly (the script has no `$0`/`BASH_SOURCE` sourcing guard) under a controlled env where no `wez` is reachable: `PATH` is emptied (so `command -v wez` misses) and `WEZ_BIN_DIR` points at a freshly-created EMPTY temp dir (so the `[ -x ${BIN_DIR}/wez ]` fallback also misses). It captures combined stdout+stderr and the exit status, with stdin from `/dev/null`.

Three checks:
1. exit 0 with no reachable wez (RED against the old `exit 1`);
2. output carries a `[uninstall]` warning naming the not-found binary AND contains NO `ERROR:` token (RED against the old `ERROR:` lines);
3. decision-free guard — no non-comment bare `rm ` line in the script (green before and after, proves D-01 holds).

Confirmed RED for the right reason against the unmodified script: `exit status=1`, output `[uninstall] ERROR: wez binary not found ...` / `[uninstall] ERROR: if you only need to remove the binary, it is already gone` (2 passed, 2 failed; the warning-line and rm-guard already passed).

### Task 2 (GREEN) — the fix — commit `9d117cd`
Edited ONLY the not-found `else` branch of `tools/uninstall.sh`: the two `err(...)` calls and `exit 1` became two `log(...)` warning lines and `exit 0`. The warning states the binary was not found (PATH + `${BIN_DIR}/wez`) and that the setup is already uninstalled / nothing to remove, plus a prose-only hint that any remaining config artifacts need the binary present to be cleaned. No `rm`, no path-branching, no config inspection (D-01). The now-dead `err()` helper was removed (see Deviations). `set -euo pipefail`, the `keep_flag` KEEP_* translation, and the `"${WEZ}" uninstall "${FLAGS[@]}"` delegation (line 66) are byte-for-byte unchanged.

## Verification (verify-before-done, recorded real output)

Live repro (`PATH=` only starves `command -v wez`; invoked via an absolute `/bin/bash` because `PATH= /usr/bin/env bash` would 127 looking up `bash` itself before the script runs):

```
$ WEZ_BIN_DIR=$(mktemp -d) PATH= /bin/bash tools/uninstall.sh </dev/null; echo "exit=$?"
[uninstall] wez binary not found (looked on PATH and at /var/folders/.../wez); already uninstalled, nothing to remove
[uninstall] if config artifacts remain, reinstall the wez binary to clean them (removal is owned by the binary, D-01)
exit=0
```

`exit=0` (was `1`); a `[uninstall]` warning with no `ERROR:` token.

> Note: the plan's literal repro string `WEZ_BIN_DIR=$(mktemp -d) PATH= /usr/bin/env bash tools/uninstall.sh` exits 127 with `env: bash: No such file or directory` — that is `env` failing to resolve `bash` under an emptied PATH, BEFORE the script executes, not a script behavior. Invoking bash by absolute path exercises the actual not-found branch and yields `exit=0` as shown.

- Regression test: `PATH="$(brew --prefix lua@5.4)/bin:$PATH" lua5.4 tests/cli/uninstall_idempotent_test.lua` -> `4 passed, 0 failed`.
- Full suite: `PATH="$(brew --prefix lua@5.4)/bin:$PATH" tools/run-tests.sh` -> `all 33 file(s) passed` (SUITE_EXIT=0), including the `bash -n` + `shellcheck -x` gate over `tools/*.sh`; `PASS bash -n tools/uninstall.sh` and `PASS shellcheck -x tools/uninstall.sh`.
- Happy path structurally unchanged: `git diff` touches only the dead `err()` helper line and the not-found branch; the delegation `"${WEZ}" uninstall "${FLAGS[@]}"` (line 66) + `exit $?` + KEEP_* translation are intact.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed the now-dead `err()` helper**
- **Found during:** Task 2 (full-suite run).
- **Issue:** Replacing the only two `err(...)` call sites with `log(...)` left `err()` defined-but-unused. The suite's `shellcheck -x tools/uninstall.sh` (advisory) then flagged SC2329 ("This function is never invoked"), a new advisory introduced by this change (it was clean on HEAD).
- **Fix:** Deleted the `err()` definition line. The plan scoped the edit to "the not-found else branch", but the helper existed solely to support the error behavior just removed; leaving dead code that triggers a fresh advisory is the wrong outcome. After removal `shellcheck -x` is clean (rc=0) and the suite reports `PASS shellcheck -x tools/uninstall.sh`. No call sites remained (`grep -n 'err' tools/uninstall.sh` -> only the definition).
- **Files modified:** tools/uninstall.sh
- **Commit:** 9d117cd

**2. [Test-harness clarification] Absolute-bash invocation in the harness**
- **Found during:** Task 1 (first RED run).
- **Issue:** Following the plan's `/usr/bin/env bash` idea verbatim under `PATH=` made `env` fail to find `bash` (exit 127) BEFORE the script ran — the not-found branch was never reached, so the RED state was for the wrong reason.
- **Fix:** The harness resolves an absolute `bash` path from the real PATH first, then empties PATH only for the inner script invocation, so `PATH=` starves `command -v wez` (the condition under test) without starving the interpreter. This is a test-only refinement of the plan's controlled-env-run intent; the asserted not-found branch still uses only bash builtins (printf + exit).
- **Files modified:** tests/cli/uninstall_idempotent_test.lua
- **Commit:** 2798d6f

## Known Stubs

None.

## Self-Check: PASSED

- FOUND: tests/cli/uninstall_idempotent_test.lua
- FOUND: tools/uninstall.sh (modified)
- FOUND commit: 2798d6f (test — RED)
- FOUND commit: 9d117cd (fix — GREEN)

## TDD Gate Compliance

- RED gate: `test(260623-gn7): add failing idempotent-uninstall regression test` (2798d6f) — confirmed failing for the right reason (exit 1 + ERROR lines) before any source change.
- GREEN gate: `fix(260623-gn7): make uninstall idempotent when wez binary is absent` (9d117cd) — after it, `4 passed, 0 failed` + full suite green.
- REFACTOR: none required.
