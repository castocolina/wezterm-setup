# Repro: `wez doctor` — exit code gated by FOUR core integrity gates (DIAG-01 / D-15)

R2 verify-before-done evidence for Plan 01-06 Task 1. `wez doctor` output **and its
exit code** ARE the evidence — no "should work".

## Claim under test (D-15)

`wez doctor` exits **0 on a healthy install** and **non-zero (with printed failure
detail) on a broken one**. The exit code is gated by **exactly FOUR CORE integrity
gates**:

1. the `wez` binary is on PATH
2. the managed sentinel block in `wezterm.lua` is well-formed
3. the managed config dir dofiles cleanly (`wezterm-setup/init.lua` loads without error)
4. a timestamped `wezterm.lua.bak.<ts>` backup exists

`completions-installed` and the live-session reachability probe are **ADVISORY ONLY**:
printed, but they **never** change the exit code. The healthy run below proves this —
the advisory `shell completions installed` probe **FAILs** yet the run still **exits 0**.

## Environment

- Host: Linux (D-18 — macOS verification batched before Phase 1 closes)
- Build: `tools/build.sh` dev source-launcher (`dist/wez` execs `lua5.4` against in-repo
  sources; the luastatic single binary is the shipping artifact)
- Seams used to stage a scratch install without touching the real `~/.config`:
  `WEZTERM_CONFIG_FILE`, `WEZTERM_SETUP_DIR`, and a scratch `PATH` carrying `wez`.

## Scratch healthy install

```
$SCRATCH/wezterm/wezterm.lua              # carries a well-formed managed block
$SCRATCH/wezterm/wezterm-setup/init.lua   # loads cleanly (returns a table, no side effects)
$SCRATCH/wezterm/wezterm.lua.bak.2026-06-09T00-00-00Z   # a timestamped backup
$SCRATCH/bin/wez                          # wez on PATH
```

## Result 1 — healthy install exits 0

```
$ PATH="$SCRATCH/bin:$PATH" \
  WEZTERM_CONFIG_FILE="$SCRATCH/wezterm/wezterm.lua" \
  WEZTERM_SETUP_DIR="$SCRATCH/wezterm/wezterm-setup" \
  wez doctor; echo $?

wez doctor — install health

Core integrity gates (determine exit code):
  [PASS] wez binary on PATH
  [PASS] sentinel block well-formed
  [PASS] config dofiles cleanly
  [PASS] timestamped backup exists

Advisory probes (informational; never affect exit code):
  [FAIL] shell completions installed — completions not installed yet (run `wez completions <shell>`) — advisory only
  [PASS] live WezTerm session reachable

OK: all core integrity gates passed (exit 0)
0
```

**Key D-15 observation:** the advisory `shell completions installed` probe FAILed, and
the exit code is STILL `0`. Advisory probes never flip a healthy exit 0.

## Result 2 — broken install (sentinel block removed) exits non-zero

After excising the managed block from `wezterm.lua`, gate #2 fails — the other three
core gates still pass, the advisory probes are unchanged, and the exit code flips
non-zero with the failing gate named:

```
$ wez doctor; echo $?

wez doctor — install health

Core integrity gates (determine exit code):
  [PASS] wez binary on PATH
  [FAIL] sentinel block well-formed — no wezterm-setup managed block found in wezterm.lua
  [PASS] config dofiles cleanly
  [PASS] timestamped backup exists

Advisory probes (informational; never affect exit code):
  [FAIL] shell completions installed — completions not installed yet (run `wez completions <shell>`) — advisory only
  [PASS] live WezTerm session reachable

FAIL: 1 core integrity gate(s) failed (exit 1)
  - sentinel block well-formed: no wezterm-setup managed block found in wezterm.lua
1
```

## Verdict

**HOLDS.** `wez doctor` exits 0 on a healthy install (including when completions are not
installed) and non-zero with a named failing gate on a broken one. The exit code is gated
by the four core integrity gates only; completions-installed and the live-session probe are
advisory and never change the exit code (D-15). Gate-aggregation unit test:
`lua5.4 tests/cli/doctor_test.lua` → 15 passed, 0 failed.
