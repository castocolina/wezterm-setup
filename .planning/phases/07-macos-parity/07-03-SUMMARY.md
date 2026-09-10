---
phase: 07-macos-parity
plan: 03
subsystem: install
tags: [macos, bootstrap, install_macos, wezterm-app, bundle-siblings, INST-06]

requires:
  - phase: 07-macos-parity
    provides: 07-01 Lua 5.4 resolver + 07-02 Mach-O dist/wez on this Mac
provides:
  - wezterm_macos_asset_url in tools/lib/wezterm-release.sh
  - real install_macos() fetch/integrity-gate/ditto/place/sibling-symlink
  - WEZTERM_APP_DIR scratch-dir override (default ${HOME}/Applications)
  - tests/cli/bootstrap_macos_test.lua ported + strip-ansi-escapes assertion
  - D-07 quarantine evidence recorded from a real curl download on this Mac
affects: [07-macos-parity]

actuals:
  tokens: 4500
  tasks: 2
  commits: 3

tech-stack:
  added: []
  patterns:
    - macOS .zip integrity gate (PK 504b0304 + 1MB floor + unzip -Z1 member-safety) before ditto
    - WEZTERM_APP_DIR override matching WEZTERM_BOOTSTRAP_PREFIX / WEZTERM_BIN_DIR

key-files:
  created:
    - tests/cli/bootstrap_macos_test.lua
  modified:
    - tools/lib/wezterm-release.sh
    - tools/bootstrap-wezterm.sh

key-decisions:
  - "Live install_macos proof must be sourced under bash, not zsh (BASH_SOURCE + set -u)"
  - "D-07: com.apple.quarantine was ABSENT on WezTerm.app after curl+ditto+cp -R on this Mac"

patterns-established:
  - "Scratch-dir install via WEZTERM_BOOTSTRAP_PREFIX + WEZTERM_BIN_DIR + WEZTERM_APP_DIR, never real ~/Applications or ~/.local/bin"
  - "Named four-sibling ln -sfn loop (no wildcard over Contents/MacOS)"

requirements-completed: [INST-06]

coverage:
  - id: D1
    description: wezterm_macos_asset_url builds official-host WezTerm-macos-<tag>.zip URLs
    requirement: INST-06
    verification:
      - kind: unit
        ref: tests/cli/bootstrap_macos_test.lua (wezterm_macos_asset_url text + behavior)
        status: pass
    human_judgment: false
  - id: D2
    description: install_macos fetches, integrity-gates, extracts, places WezTerm.app, and ln -sfn all four bundle siblings
    requirement: INST-06
    verification:
      - kind: unit
        ref: tests/cli/bootstrap_macos_test.lua (32 passed, 0 failed)
        status: pass
      - kind: e2e
        ref: scratch-dir install_macos nightly + tests/e2e/tier1/keys_siblings_e2e_test.lua macOS layer LIVE-ASSERTED
        status: pass
    human_judgment: false
  - id: D3
    description: D-07 quarantine attribute measured on a real download (record only, no strip)
    verification:
      - kind: other
        ref: "xattr -p com.apple.quarantine scratch/WezTerm.app -> No such xattr"
        status: pass
    human_judgment: false

duration: 40min
completed: 2026-09-10
status: complete
---

# Phase 07 Plan 03: real install_macos + bundle-sibling e2e fire

**install_macos() is real: official-host zip fetch, PK-magic integrity gate, ditto extract, WEZTERM_APP_DIR placement, and ln -sfn of all four WezTerm.app siblings — proven non-destructively on this Mac.**

## Performance

- **Duration:** 40 min
- **Started:** 2026-09-10
- **Completed:** 2026-09-10
- **Tasks:** 2
- **Files modified:** 3 (+ this SUMMARY)

## Accomplishments

- Ported `tests/cli/bootstrap_macos_test.lua` from `archive/phase-7-macos` (225 lines, plus one new `strip-ansi-escapes` assertion).
- Added `wezterm_macos_asset_url()` to `tools/lib/wezterm-release.sh` (same host/repo vars as the Linux helper).
- Replaced the design-only `install_macos()` stub with the archived real body, plus `WEZTERM_APP_DIR` override.
- Scratch-dir live proof on this Mac fetched nightly, placed WezTerm.app, linked all four siblings, and made `keys_siblings_e2e_test.lua`'s macOS layer FIRE and PASS.
- Recorded D-07 quarantine evidence: `com.apple.quarantine` was **absent** after curl+ditto+cp -R.

## Task Commits

1. **Task 1 (RED): Port bootstrap_macos_test.lua** - `63c6643` (test)
2. **Task 2 (GREEN): wezterm_macos_asset_url + real install_macos** - `a0856a5` (feat)

**Plan metadata:** this file (docs: summary)

## Task 1 verify (actual output)

`/usr/local/opt/lua@5.4/bin/lua5.4 tests/cli/bootstrap_macos_test.lua` against the design-only stub:

```
  FAIL - wezterm_macos_asset_url() is defined in wezterm-release.sh
  ...
  ok   - install_macos() is defined
  FAIL - install_macos extracts with Apple-native `ditto -x -k`
  ...
  FAIL - install_macos symlinks the sibling `wezterm-gui`
  FAIL - install_macos symlinks the sibling `wezterm-mux-server`

10 passed, 21 failed
```

Genuine RED. Stub-trivial passes: function defined, `${HOME}/Applications` in the stub, shared `fetch_to` elsewhere in the file, no sudo/hdiutil/xattr.

## Task 2 verify (actual output)

### Unit suite (hard gate, network-independent)

```
32 passed, 0 failed
```

Includes the new `strip-ansi-escapes` assertion.

### Network probe

```
curl -fsSL -o /dev/null --max-time 10 https://github.com
NETWORK_PROBE=ok
```

### Scratch-dir live install (bash -c, never real ~/Applications)

Scratch dirs: `/tmp/wez-07-03-prefix.XfQq2Y`, `/tmp/wez-07-03-bin.LmZ34I`, `/tmp/wez-07-03-app.dXCYOO`.

```
sourced ok PREFIX=/tmp/wez-07-03-prefix.XfQq2Y BIN_DIR=/tmp/wez-07-03-bin.LmZ34I
[bootstrap] fetching https://github.com/wez/wezterm/releases/download/nightly/WezTerm-macos-nightly.zip
[bootstrap] placed /tmp/wez-07-03-app.dXCYOO/WezTerm.app
[bootstrap] installed: wezterm 20260909-081506-9fa147c9
[bootstrap] symlinked .../wezterm
[bootstrap] symlinked .../wezterm-gui
[bootstrap] symlinked .../wezterm-mux-server
[bootstrap] symlinked .../strip-ansi-escapes
install_rc=0
```

### D-07 quarantine (literal)

```
$ xattr -p com.apple.quarantine /tmp/wez-07-03-app.dXCYOO/WezTerm.app
xattr: /tmp/wez-07-03-app.dXCYOO/WezTerm.app: No such xattr: com.apple.quarantine

$ xattr -l /tmp/wez-07-03-app.dXCYOO/WezTerm.app
com.apple.macl:
com.apple.provenance: <present>
```

**Verdict:** `com.apple.quarantine` was **not** set on the placed bundle after this curl download on macOS 15.7.9. No xattr strip was performed (D-07 remains verify-then-decide for a later plan).

### keys_siblings_e2e_test.lua (scratch bin on PATH)

```
6 passed, 0 failed
keys-siblings macOS bundle-symlink contract: LIVE-ASSERTED (...)
  ok   - macOS: bundle sibling `wezterm` resolves on PATH (installer symlinked it)
  ok   - macOS: bundle sibling `wezterm-gui` resolves on PATH (installer symlinked it)
  ok   - macOS: bundle sibling `wezterm-mux-server` resolves on PATH (installer symlinked it)
  ok   - macOS: bundle sibling `strip-ansi-escapes` resolves on PATH (installer symlinked it)

4 passed, 0 failed
e2e_rc=0
```

macOS layer **fired** (not skipped) and passed.

### Real-home sanity

```
ls: /Users/ramon/Applications/WezTerm.app: No such file or directory
```

Scratch dirs were `rm -rf`'d after the proof. Pre-existing `~/.local/bin/wezterm` / `wezterm-gui` were not written by this run.

## Files Created/Modified

- `tests/cli/bootstrap_macos_test.lua` — archived suite + `strip-ansi-escapes` sibling assertion
- `tools/lib/wezterm-release.sh` — `wezterm_macos_asset_url()`
- `tools/bootstrap-wezterm.sh` — real `install_macos()` + `WEZTERM_APP_DIR`

## Decisions Made

- Planned archive port, with the one planned deviation: `app_dir="${WEZTERM_APP_DIR:-${HOME}/Applications}"`.
- Live proof invoked with `bash -c 'source tools/bootstrap-wezterm.sh; install_macos nightly'` because this Mac's interactive shell is zsh.

## Deviations from Plan

1. **Live proof must run under bash.** The plan's `( source tools/bootstrap-wezterm.sh; install_macos nightly )` was first attempted in zsh (this environment's shell). `set -u` + unset `BASH_SOURCE[0]` aborted with `install_rc=127` and `.: no such file or directory: .../lib/platform.sh`. Retried under `bash -c` with the same three scratch env vars — that is the intended invocation. Not a product bug.
2. **`WEZTERM_APP_DIR`** — planned, not a scope change.
3. **`strip-ansi-escapes` unit assertion** — planned, not a scope change.

**Total deviations:** 1 invocation-environment fix, 0 scope changes
**Impact on plan:** none — same fetch/extract/place/symlink contract

## Issues Encountered

zsh `source` of `bootstrap-wezterm.sh` is not viable (`BASH_SOURCE` is bash-only). Documented so later plans do not repeat the 127 false-failure.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

INST-06 macOS half is implemented and proven on this Mac. D-07 evidence for a later quarantine plan: `com.apple.quarantine` was absent on a curl-fetched nightly zip extracted with ditto and placed via `cp -R`. `tools/verify-macos.sh` still skip-gates "INST-06 macOS .app bootstrap" as design-only — that skip string is outside this plan's files.

---
*Phase: 07-macos-parity*
*Completed: 2026-09-10*
