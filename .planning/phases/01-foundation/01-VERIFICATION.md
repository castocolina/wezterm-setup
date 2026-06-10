---
phase: 01-foundation
verified: 2026-06-10T11:20:00Z
status: passed
score: 21/21 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 17/21
  gaps_closed:
    - "INST-01/INST-03: --force/override over a Shape-B (`return wezterm.config_builder()`) config now keeps exactly one managed block AND a top-level return; a failed re-inject never persists a broken file (CR-01)."
    - "INST-04: ls/rm shell-outs no longer break or inject on paths containing a single quote / shell metacharacter; `--` guards added (CR-02)."
    - "INST-02: write_all now checks both fh:write and fh:close return values, so a truncated/failed backup propagates an error instead of reporting success (CR-03)."
  gaps_remaining: []
  regressions: []
gaps: []
deferred: []
---

# Phase 1: Foundation Verification Report

**Phase Goal:** Foundation — non-destructive install/uninstall, CWD reporting (OSC 7), the locked clear keybinding, curated keybindings, `wez doctor`, and `wez keys`. Every shipped behavior verified against a real running session before it integrates.
**Verified:** 2026-06-10
**Status:** passed
**Re-verification:** Yes — after CR-01/CR-02/CR-03 blocker closure

## Re-verification Summary

The prior verification returned `gaps_found` (17/21) with three reproduced BLOCKERs in the
install/uninstall safety layer. Each defect was **independently re-reproduced against the current
code** (not trusting the fix commits or the in-repo regression tests) using fresh standalone
`lua5.4` scripts:

- **CR-01 (Shape-B override corruption)** — FIXED. A Shape-B config
  (`return wezterm.config_builder()`) is first injected so the managed block CONTAINS the only
  top-level return (`local __wezterm_setup_config = (wezterm.config_builder())` … `return
  __wezterm_setup_config`). `restore_original_text` round-trips it **byte-exact** back to the
  original via a `%b()` balanced-paren unwrap, and `inject_into_text` re-injects entirely in
  memory. Confirmed: the override yields **exactly one** managed block AND a top-level return; the
  on-disk file is never mutated before the single final `atomic_write`; and a return-less input
  fails cleanly (`nil`+err) leaving the file untouched. Independent repro asserted disk equality
  before the final write and a surviving `return` after.

- **CR-02 (shell injection on quoted paths)** — FIXED. `shquote()` rewrites every embedded `'` as
  `'\''` and is applied to the `ls` listing in `newest_backup`/`remove_backups` and the `rm -rf`
  in `remove_config_tree`, all with `--` guards. Confirmed: `newest_backup` resolves the newest
  backup inside a directory literally named `…d'ir…`; and a crafted setup_dir containing
  `$(touch <canary>)` did **not** create the canary (no command injection) while the path was still
  removed safely.

- **CR-03 (false backup success)** — FIXED. `write_all` now captures and checks both `fh:write`
  and `fh:close` returns and propagates the error. Confirmed (running as **non-root**, uid 1000):
  `backup()` of an unreadable source returns `nil`+err; `atomic_write` into an unwritable location
  returns `nil`+err; and a backup into a `chmod 0500` read-only directory returns
  `nil, "… Permission denied"` instead of reporting success.

All four previously-BLOCKED requirement IDs (INST-01, INST-02, INST-03, INST-04) are now SATISFIED.
The full 8-file test suite passes. No regressions in the 17 truths that previously passed.

## Goal Achievement

### Observable Truths

| #  | Truth (plan) | Status | Evidence |
| -- | ------------ | ------ | -------- |
| 1  | `wez` binary builds via luastatic with release-download fallback (01-01) | VERIFIED | tools/build.sh implements toolchain detect + download fallback (D-02); `dist/wez` present |
| 2  | `wez` no-args usage; `--version` prints version, exit 0 (01-01) | VERIFIED | Ran `dist/wez --version` → `wez 0.1.0` |
| 3  | spec.lua is the single source of truth for the Phase-1 subcommand surface (01-01) | VERIFIED | cli/spec.lua consumed by commands + completions; no later plan edits it (D-16) |
| 4  | Bootstrap downloads/extracts `.tar.xz` to `~/.local`, symlinks binary, sudo-free, no AppImage (01-02) | VERIFIED | tools/bootstrap-wezterm.sh; promoted repro docs/repro/h-inst06-bootstrap.md |
| 5  | Bootstrap reuses an adequate existing WezTerm untouched, no download (01-02) | VERIFIED | Detection-first reuse branch present (D-07) |
| 6  | TTY version selection (nightly + last 5); non-TTY installs pinned dated release (01-02) | VERIFIED | tools/lib/wezterm-release.sh lists releases + builds asset URL; pinned default present |
| 7  | `apply(config)` augments and returns the same config without replacing user settings (01-03) | VERIFIED | tests/config/apply_test.lua passes: identity returned, user font + key binding preserved |
| 8  | New tabs/panes inherit cwd on Linux via shipped OSC 7 (bash + zsh) (01-03, FOUND-01) | VERIFIED (Linux) | osc7.sh + osc7.zsh emit `ESC ] 7 ; file://HOST/path`; macOS deferred (D-18) |
| 9  | Curated bindings; Super+K clears screen+scrollback; replaced defaults disabled (01-03) | VERIFIED | keybindings_test.lua passes all category + locked-clear assertions |
| 10 | First install injects a single sentinel block; **--force RE-install keeps one block + top-level return** (01-04, INST-01) | VERIFIED | CR-01 independently re-reproduced: Shape-B override yields exactly one block + a `return`; failed reinject never persists |
| 11 | Installer creates a timestamped backup before any write, and **verifies the backup write succeeded** (01-04, INST-02) | VERIFIED | CR-03 re-reproduced: read-only-dir backup returns nil+err (non-root); write_all checks fh:write/fh:close |
| 12 | Re-run prompts override/restore/skip with TTY; aborts non-zero without TTY; **override branch is non-destructive** (01-04, INST-03) | VERIFIED | decide() dispatcher tested; CR-01 confirms the override branch it dispatches to is now safe |
| 13 | `wez keys` lists active bindings grouped by category (01-05, DIAG-02) | VERIFIED | Prior live run: grouped `== Tabs/Panes/... ==` from live `wezterm show-keys --lua`; wiring intact |
| 14 | `wez keys` does 3-way classification + conflict/who-wins from live effective table (01-05, DIAG-03) | VERIFIED | keys.lua + showkeys.lua parse live table; `[default]`/`[setup]` labels |
| 15 | `wez keys --json` emits valid JSON (01-05, DIAG-04) | VERIFIED | Prior live run produced well-formed JSON; requires installed config (absent in clean env), wiring intact |
| 16 | `wez doctor` exits 0 on healthy install, non-zero on broken; core gates gate exit, advisory do not (01-06, DIAG-01) | VERIFIED | Ran `dist/wez doctor` on absent install → 4 core gates FAIL, exit 1; advisory probes separated, never flip exit (D-15) |
| 17 | Uninstall removes managed config, CLI, sentinel block with no trace; **rm/ls shell-outs are injection-safe** (01-06, INST-04) | VERIFIED | CR-02 re-reproduced: quoted-path resolution works; `$(touch canary)` not executed |
| 18 | Uninstall honors --keep-config/--keep-backup/--keep-cli (01-06, INST-05) | VERIFIED | uninstall_state_test.lua: 37 assertions pass; each keep-flag preserves exactly its component |
| 19 | Completions generated from argparse spec so coverage grows automatically (01-07, DIAG-05) | VERIFIED | Ran `dist/wez completions zsh` → script generated from cli/spec.lua (D-16) |
| 20 | `make install` registers completions; `wez <Tab>` completes subcommands/flags (01-07) | VERIFIED | tools/setup.sh registers generated scripts; completions_test.lua passes |
| 21 | Dynamic values via `wez __complete` hidden command (01-07) | VERIFIED | cli/commands/complete.lua emits candidates; wired into generated shell functions |

**Score:** 21/21 truths verified

### Required Artifacts

All declared artifacts exist, are substantive, and are wired. The two formerly-defective files are
now correct.

| Artifact | Status | Details |
| -------- | ------ | ------- |
| cli/wez.lua, spec.lua, vendor/*, commands/* | VERIFIED | Present, substantive; dispatch wired through spec.lua |
| config/wezterm-setup/init.lua, keybindings.lua, cwd.lua, osc7.sh, osc7.zsh | VERIFIED | apply() wires modules; OSC 7 emitters for both shells |
| tools/setup.sh, uninstall.sh, build.sh, bootstrap-wezterm.sh, lib/platform.sh, lib/wezterm-release.sh, run-tests.sh | VERIFIED | Present and substantive |
| cli/commands/install_state.lua (483 lines) | VERIFIED | CR-01 + CR-03 fixed: in-memory strip+reinject single-write; restore_original_text round-trip; write_all integrity checks |
| cli/commands/uninstall_state.lua (213 lines) | VERIFIED | CR-02 fixed: shquote() + `--` guards on all shell-outs |
| 5 probes + 4 repros (.tmp/probes, docs/repro) | VERIFIED | All present |
| 8 test files (tests/cli, tests/config) | VERIFIED | Suite passes 8/8 files; now includes Shape-B + CR-02/CR-03 regressions |

### Key Link Verification

| From | To | Via | Status |
| ---- | -- | --- | ------ |
| version.lua / all commands | cli/spec.lua | central argparse dispatch | WIRED |
| tools/build.sh | cli/wez.lua | luastatic bundle | WIRED |
| bootstrap-wezterm.sh | lib/wezterm-release.sh + lib/platform.sh | sourced helpers | WIRED |
| init.lua | keybindings.lua + cwd.lua | apply() requires + merges | WIRED |
| setup.sh | install_state.lua | shells out to wez for sentinel decisions | WIRED |
| install_state.lua (injected block) | config/wezterm-setup/init.lua | require('wezterm-setup').apply(config) | WIRED |
| keys.lua | keybindings.lua + showkeys.lua | source-of-truth + live effective table | WIRED |
| doctor.lua | install_state.lua | reuses sentinel parser | WIRED |
| uninstall.sh | uninstall_state.lua | delegates removal decisions | WIRED |
| uninstall_state.lua | install_state.shquote | shared shell-safe quoter (CR-02) | WIRED |
| completions.lua | cli/spec.lua | generator walks spec | WIRED |
| setup.sh | completions.lua | install-time registration | WIRED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Version | `dist/wez --version` | `wez 0.1.0` | PASS |
| Doctor exit on broken install | `dist/wez doctor` (absent config) | 4 core gates FAIL, exit 1, advisory separated | PASS |
| Completions generation | `dist/wez completions zsh` | `#compdef wez` script from spec | PASS |
| Test suite | `bash tools/run-tests.sh` | `run-tests: all 8 file(s) passed` | PASS |
| CR-01 re-reproduction | Shape-B override (independent lua5.4 script) | exactly one block + top-level return; disk untouched until single write; return-less input fails cleanly | PASS (fixed) |
| CR-02 re-reproduction | `newest_backup` on `d'ir` + `$(touch canary)` injection (independent script) | resolves quoted path; canary NOT created | PASS (fixed) |
| CR-03 re-reproduction | backup to read-only dir as non-root (independent script) | `nil, Permission denied` — failure propagated | PASS (fixed) |

### Probe Execution

No executable `scripts/*/tests/probe-*.sh` exist in this repo. Plan probes are recorded promotion
artifacts (`.tmp/probes/phase-1/*.md`). The canonical driver `tools/run-tests.sh` was executed.

| Driver | Command | Result | Status |
| ------ | ------- | ------ | ------ |
| Test suite | `bash tools/run-tests.sh` | `run-tests: all 8 file(s) passed` | PASS |

### Requirements Coverage

All 16 phase requirement IDs are declared across plan frontmatter and match REQUIREMENTS.md
exactly — no orphaned IDs.

| Requirement | Source Plan | Status | Evidence |
| ----------- | ----------- | ------ | -------- |
| INST-01 | 01-03, 01-04 | SATISFIED | First install single block; Shape-B --force override keeps one block + return (CR-01 re-reproduced fixed) |
| INST-02 | 01-04 | SATISFIED | Backup before write; write_all verifies fh:write/fh:close, failures propagate (CR-03 re-reproduced fixed) |
| INST-03 | 01-04 | SATISFIED | decide() dispatcher tested; override branch now non-destructive (CR-01) |
| INST-04 | 01-06 | SATISFIED | Uninstall removes block/config/cli/backups; rm/ls shell-outs injection-safe (CR-02 re-reproduced fixed) |
| INST-05 | 01-06 | SATISFIED | keep-flags honored; uninstall_state_test.lua 37 assertions pass |
| INST-06 | 01-02 | SATISFIED | Bootstrap sudo-free tar.xz; repro promoted (Linux; macOS deferred D-06/D-18) |
| FOUND-01 | 01-03 | SATISFIED (Linux) | OSC 7 emitters + cwd.lua; macOS verify deferred (D-18) |
| FOUND-02 | 01-03 | SATISFIED | Super+K clear binding; keybindings_test asserts locked clear |
| FOUND-03 | 01-03 | SATISFIED | Curated tabs/panes/font/word bindings present and tested |
| FOUND-04 | 01-05 | SATISFIED | `wez keys` resolves bindings at runtime from live show-keys |
| FOUND-05 | 01-03 | SATISFIED | Single SUPER token = Cmd/Super; cross-platform identical except modifier |
| DIAG-01 | 01-01, 01-06 | SATISFIED | doctor: 4 core gates gate exit, advisory never flips (verified live) |
| DIAG-02 | 01-01, 01-05 | SATISFIED | `wez keys` grouped by category (verified live) |
| DIAG-03 | 01-01, 01-05 | SATISFIED | 3-way classification from live effective table |
| DIAG-04 | 01-01, 01-05 | SATISFIED | `wez keys --json` valid JSON (verified live) |
| DIAG-05 | 01-01, 01-07 | SATISFIED | zsh + bash completions generated from spec; setup.sh registers |

### Anti-Patterns Found

The three BLOCKER anti-patterns from the prior verification are resolved. Two INFO-level items
remain and do not affect the goal.

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| cli/commands/install_state.lua | 191-195 | dead no-op conditional in find_final_return | Info | WR-04 — misleading dead code; no behavioral effect |
| cli/commands/install_state.lua | 150 | unseeded math.random for temp suffix | Info | WR-05 — predictable temp name; temp is sibling-of-target + atomic rename, low risk |

No unreferenced TBD/FIXME/XXX debt markers in phase-modified files (debt-marker gate clear).

### Human Verification Required

None blocking automated status. macOS parity for INST-06 / FOUND-01 is explicitly deferred by
decision D-18 and tracked for a later phase — per the verification scope it is NOT counted as a
Phase-1 gap.

### Gaps Summary

No gaps. The Foundation phase goal is achieved. All 21 observable truths are VERIFIED and all 16
requirement IDs are SATISFIED. The three reproduced BLOCKER defects (CR-01 Shape-B override
corruption, CR-02 shell injection on quoted paths, CR-03 false backup success) were each
**independently re-reproduced against the current code with fresh standalone scripts** — not taken
from the fix commits or the in-repo tests — and all three are confirmed fixed. The full 8-file
test suite passes, live `wez --version`/`doctor`/`completions` behave correctly, and no regressions
were introduced in the previously-passing truths.

Note: the CR-01 fix is present and behaviorally correct in `install_state.lua` (the
`restore_original_text` inverse + in-memory single-write override), even though that specific change
does not appear under the `380913d` hash in this file's `git log`; verification is based on the code
and its observed behavior, not commit attribution.

---

_Verified: 2026-06-10T11:20:00Z_
_Verifier: Claude (gsd-verifier)_
