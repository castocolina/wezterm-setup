# Phase 1: Foundation - Context

**Gathered:** 2026-06-08
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 1 delivers a working, diagnosable wezterm-setup install: non-destructive install/
uninstall, cwd inheritance, the curated keybinding set (incl. instant clear), `wez doctor`,
`wez keys`, and shell completions — verified on Linux, designed cross-platform.

Scope was **expanded during discussion** to also bootstrap the WezTerm emulator itself
(INST-06, sudo-free, user-path, version-selectable). macOS is designed-for but verified in
a separate deferred Mac pass (the user has only intermittent Mac access).
</domain>

<decisions>
## Implementation Decisions

### Installer & bootstrap boundary (INST-01..05)
- **D-01:** Bash is allowed **only for the bootstrap/installer layer** (detect platform,
  fetch/build, place files, inject the sentinel block). ALL logic with decisions —
  install-state inspection, sentinel parsing, doctor, keys — lives in the Lua `wez` binary.
  Honors PROJECT.md "Bash excluded" (the CLI is Lua) and the Makefile R3 "thin glue" rule;
  resolves the bootstrap chicken-and-egg (something must run before the binary exists).
- **D-02:** `make install` builds the `wez` binary **locally via luastatic**, with a
  **fallback to downloading a release binary** when the Lua toolchain is absent.
- **D-03:** Re-install (INST-03) with an existing managed block and **no interactive TTY**
  → **abort non-zero**, instruct the user to re-run with an explicit flag
  (`--force` / `--restore` / `--skip`). Never silently overwrite (zero-surprise).

### WezTerm bootstrap — NEW requirement INST-06 (in Phase 1)
- **D-04:** wezterm-setup also bootstraps the **WezTerm emulator**, sudo-free, into a
  user path. kitty-setup parity. This is a new requirement added to REQUIREMENTS.md/ROADMAP.
- **D-05:** **Linux mechanism = generic `.tar.xz`** (`wezterm-nightly.Ubuntu<base>.tar.xz`
  matched to the host's Ubuntu base) extracted to `~/.local/opt/wezterm` + symlink into
  `~/.local/bin`. **NOT AppImage** — Pop!_OS / Ubuntu 24.04 drop `libfuse2`, the real cause
  of the user's prior AppImage failures. No FUSE, no sudo.
- **D-06:** **macOS mechanism = `.app` from the macOS zip → `~/Applications`.** Design-only
  now; verified in the deferred Mac pass.
- **D-07:** **Detection-first / non-destructive:** if a usable WezTerm meets a **minimum
  version** (`wezterm --version`), **reuse it and leave it intact** (optional warning); only
  fetch/install when missing or below minimum. Never touch a system install; our copy lives
  in user-path and the `wez` CLI ensures the right binary is used.
- **D-08:** **Version selector (corrected model):** `nightly` is ONE rolling tag; the
  listable set is the **dated releases**. With a TTY: list the rolling `nightly` + the **last
  5 dated releases** (GitHub API) and let the user pick. Without a TTY: default to a
  **pinned known-good dated release** (the audited `20260604-145453`) for reproducibility.

### Keybindings (FOUND-02..05)
- **D-09:** **`mapped:` bindings (by produced character)** with explicit
  `key_map_preference = "Mapped"`. Rationale: the user wants the **printed key** to fire the
  action across keyboards/layouts (US-ANSI ↔ ES) and `wez keys` to report a combo he can
  always reproduce — NOT physical-position lock. (`phys:` was the initial wrong rec; corrected
  against WezTerm docs.)
- **D-10:** Curated set restricted to **layout-stable keys**: letters, digits, and named
  keys (arrows, Tab, Enter, `+`/`-`). **Avoid punctuation that shifts or needs AltGr on ES**
  (`[ ] { } / \ ;`). Design referenced on US-ANSI; trigger is by character.
- **D-11:** **Direct modifier combos, no leader/prefix.** Fresh, simple scheme (WezTerm
  defaults judged "rebuscados"). The concrete chord table is the planner's to propose under
  these rules; user reviews it there. `Super+K` / `Cmd+K` clear stays locked.
- **D-12:** **Replaced WezTerm defaults are explicitly disabled** (one action = one binding)
  so `wez keys` classification (DIAG-03) is truthful.

### `wez keys` / `wez doctor` introspection (DIAG-01..04)
- **D-13:** `wez keys` data source is a **combination**: `wezterm show-keys --lua` (live
  effective table = "who wins") + our `keybindings.lua` (single source of truth for the
  wezterm-setup set) + a **captured baseline default table** (show-keys with no config) for
  default-detection. Parse the `--lua` form; exclude `copy_mode`/`search_mode`.
- **D-14:** **Real 3-way classification + true precedence/conflict detection** (NOT the
  conservative static-list option) — achievable because show-keys gives the live effective
  table. setup = ours ∩ effective; default = baseline ∩ effective, not ours; user = the rest;
  conflict / "who wins" = our binding absent from effective (overridden) or same key+mods →
  different action.
- **D-15:** `wez doctor` — **install-integrity core gates the exit code** (binary on PATH,
  sentinel block well-formed, config dir dofiles cleanly, backup exists, completions
  installed). Live-session probes are **advisory only**, never affect exit 0 (doctor is the
  headless/CI install-health gate per R2; live behavior is integration-test territory per R7).

### Completions (DIAG-05)
- **D-16:** **Generated from the argparse spec** (single source = the CLI definition) so
  coverage grows automatically per phase; **dynamic values** (colors, scene names — future
  phases) completed via functions that shell out to `wez` (e.g. `wez __complete`).

### Sentinel block integration (INST-01)
- **D-17:** **Augment model:** the managed block exposes `require('wezterm-setup').apply(config)`
  that **mutates/extends the user's `config` object** before their `return config`. Truly
  non-destructive (user settings survive, ours add on top). Managed config lives under
  `~/.config/wezterm/wezterm-setup/` (R3-composable topic files behind one entry point).
  **R6 probe required:** robustly referencing the user's `config` variable (its name varies).

### macOS scope
- **D-18:** **Linux-first; macOS = tracked follow-up.** Design cross-platform (installer
  detects `uname`, code never assumes `/proc`); verify Linux now. The Mac pass (re-run cwd
  probe, fill the cli-surface macOS column, build the universal binary, verify INST-06 `.app`
  placement) must close before "v1 done" but does NOT block Phase 1 Linux completion.
  Phase 1 success criterion #3 splits per platform.

### Claude's Discretion
- D-01 (bash boundary), D-12 (disable replaced defaults), D-14 (classification depth),
  D-15 (doctor scope), D-07/D-08 (reuse + selector defaults) were delegated ("vos decidís")
  and resolved as above with rationale.
- The concrete keybinding chord table (D-11) is the planner's to propose under D-09/D-10/D-12;
  user reviews at plan time.
- Exact sentinel marker text and topic-file split are planner detail under D-17 + R3.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 0 locked decisions (foundational — read first)
- `.planning/decisions/cli-language.md` — Lua 5.4 CLI + luastatic single-binary packaging model
- `.planning/decisions/cwd-mechanism.md` — OSC 7 primary + OS-read backstop; FOUND-01 path
- `.planning/decisions/wezterm-cli-surface.md` — audited `wezterm cli` subcommands + gaps
- `.planning/decisions/tab-title-format.md` — tab color-prefix format (Phase 3, context)

### Project-level
- `.planning/PROJECT.md` — constraints, Key Decisions, non-destructive/sudo-free philosophy
- `.planning/REQUIREMENTS.md` — INST-01..06, FOUND-01..05, DIAG-01..05
- `.planning/ROADMAP.md` §"Phase 1: Foundation" — goal + success criteria
- `docs/agent-iteration.md` — R1–R7 operating rules (R6 probes, R3 composable config, R2 verify)
- `Makefile` — existing thin-glue scaffold (install/uninstall/doctor/test targets)

### Runtime facts verified this session (encode as R6 probe Why: lines in Phase 1)
- `wezterm show-keys --lua` — effective merged key table, phys/mapped distinction (D-13/D-14)
- WezTerm release model — rolling `nightly` vs retained dated releases; `*.Ubuntu*.tar.xz`
  sudo-free Linux asset; `WezTerm-macos-nightly.zip` (D-05/D-06/D-08)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Makefile` — already scaffolds `install`/`uninstall`/`doctor`/`test` dispatching into
  `tools/*.sh` and `wez`; the bash-bootstrap boundary (D-01) matches its R3 header comment.
- Active `~/.config/wezterm/wezterm.lua` — real config to dogfood install against; already
  defines custom keys (word-nav, splits) useful as `wez keys` classification test fixtures.

### Established Patterns
- R6 probe-before-assume + R1 hypothesis-before-promote (docs/agent-iteration.md) govern how
  every WezTerm/CLI/escape assumption in this phase is proven before integration.
- R3 composable config: one topic file per behavior under `~/.config/wezterm/wezterm-setup/`,
  dofiled from a single entry point — the Augment model (D-17) plugs into this.

### Integration Points
- Sentinel block in the user's `wezterm.lua` → `require('wezterm-setup').apply(config)`.
- `wez` CLI ↔ WezTerm via `wezterm cli` + `wezterm show-keys` (out-of-process; no in-VM access).

</code_context>

<specifics>
## Specific Ideas

- Keyboard layout portability is the user's explicit driver: "que la tecla impresa dispare el
  action… que si cambio a ES no me complique saber la combinación, y que `wez keys` me diga
  algo que pueda reproducir." → `mapped:` (D-09/D-10).
- AppImage explicitly rejected for Linux based on the user's lived Pop!_OS failures with
  VS Code/Chrome AppImages (libfuse2) → `.tar.xz` path (D-05).
- Interactive WezTerm version picker desired (D-08).

</specifics>

<deferred>
## Deferred Ideas

- **macOS live verification (Mac pass)** — cwd probe re-run, cli-surface macOS column,
  universal binary build, INST-06 `.app`→`~/Applications` verify. Tracked; before v1 done.
- **musl-static Linux build of `wez`** for full-distro portability (Phase 0 noted; CI step).
- Concrete keybinding chord table — produced at plan time, not here.

</deferred>

---

*Phase: 1-Foundation*
*Context gathered: 2026-06-08*
