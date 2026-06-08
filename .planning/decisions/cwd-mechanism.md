# Decision: CWD inheritance mechanism

**Decision:** Standardize on **OSC 7 (shell-emitted `file://HOST/path`) via shell integration** as
the primary, portable cwd mechanism, with **WezTerm's OS-level cwd read** (`/proc` on Linux,
libproc on macOS) as the backstop. Pane-split / new-tab cwd inheritance is **WezTerm default
behavior** — no special config is required beyond ensuring the shell emits OSC 7.

**Status:** Locked on Linux evidence 2026-06-07 (Phase 0 spike). **macOS verification deferred** to
the batched Mac pass before Phase 1 closes (D-04/D-05) — macOS has no `/proc`; WezTerm uses libproc,
and OSC 7 is the cross-platform guarantee, so the OSC 7 path is expected to hold but must be confirmed.

**Serves:** FOUND-01 ("new tabs and panes open in the cwd of the active pane, Linux + macOS").
**Phase 0 plan:** `00-02-PLAN.md`.

## Evidence (Linux, isolated headless mux; reproducible via `.tmp/h03-cwd-mechanism/run.sh`)

| Case | Shell | Source pane cwd | Split pane cwd | Inherited? |
|---|---|---|---|---|
| A | `bash -l` (emits OSC 7 via vte-2.91.sh) | `file://pop-os/tmp/cwdtest-AAA/` | `file://pop-os/tmp/cwdtest-AAA/` | ✓ (OSC 7) |
| B | `env -i bash --norc --noprofile` (no OSC 7) | `file:///home/user-zero/` (display lagged) | `file://pop-os/tmp/cwdtest-BBB/` | ✓ (OS /proc read at spawn) |

**Key distinction (the `cwd` URI host reveals the source):**
- `file://<host>/path` (e.g. `file://pop-os/...`) → **OSC 7**, shell-reported. Immediate, accurate, portable.
- `file:///path` (empty host) → **WezTerm OS read** of the process cwd. Linux backstop; can lag in display.

Both inherit correctly on split. Even with OSC 7 disabled (Case B), WezTerm spawned the split in the
real cwd because it reads the source process cwd at spawn time.

## Candidates evaluated
1. **`$WEZTERM_PANE`** — not a cwd mechanism; only a pane handle. Rejected as the mechanism.
2. **OSC 7** — chosen primary. Portable, immediate, authoritative.
3. **WezTerm OS-level read** — chosen backstop (Linux `/proc`, macOS libproc).

## Phase 1 implication
- `cwd.lua` needs **no custom split/spawn logic** — inheritance is WezTerm default.
- The shipped config/shell-integration MUST ensure **OSC 7 is emitted** on both platforms and both
  shells (zsh + bash) so cwd tracking is accurate regardless of distro rc quirks. On Pop!_OS,
  `bash -l` already emits it via `vte-2.91.sh`; do not rely on that being universal — ship our own
  OSC 7 emission in the shell integration.
- macOS: re-run `.tmp/h03-cwd-mechanism/run.sh` on the Mac pass to confirm libproc + OSC 7 behavior
  before FOUND-01 ships. A macOS failure would trigger reconsideration (D-05).

## Scratch (gitignored `.tmp/`)
`.tmp/h03-cwd-mechanism/run.sh` + `actual.txt`; `.tmp/probes/phase-0/02-cwd-mechanisms.md`.
