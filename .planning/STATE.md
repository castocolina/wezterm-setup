---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: Ready to plan
last_updated: "2026-06-12T10:45:43.145Z"
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 20
  completed_plans: 20
  percent: 67
---

# Project State: wezterm-setup

## Project Reference

**Core Value**: A working WezTerm install that is easy to understand, audit, and extend — where every shipped behavior is verified against a real running session before it integrates.

**Project file**: `.planning/PROJECT.md`  
**Roadmap**: `.planning/ROADMAP.md`  
**Requirements**: `.planning/REQUIREMENTS.md`

---

## Current Position

Phase: 4
Plan: Not started
**Current Phase**: Phase 1 — Foundation (all 7 plans complete on Linux; macOS verification + phase close pending)  
**Current Plan**: 01-07 complete — Phase 1 feature-complete on Linux  
**Status**: Phase 1 Linux-complete; schedule the batched macOS verification pass + `/gsd-transition` before closing Phase 1 (D-04/D-05/D-18)

### Progress Bar

```
Phase 0  [██████████]  Complete (2026-06-07)
Phase 1  [░░░░░░░░░░]  Not started
Phase 2  [░░░░░░░░░░]  Not started
Phase 3  [░░░░░░░░░░]  Not started
Phase 4  [░░░░░░░░░░]  Not started
Phase 5  [░░░░░░░░░░]  Not started
```

**Overall**: 1/6 phases complete

---

## Phase Status

| Phase | Name | Status | Completed |
|-------|------|--------|-----------|
| 0 | Spikes & Alignment | Complete | 2026-06-07 |
| 1 | Foundation | Pending | - |
| 2 | Pane Identity | Pending | - |
| 3 | Tab Identity | Complete | 2026-06-12 |
| 4 | Ad-hoc Scenes | Pending | - |
| 5 | Named Scenes | Pending | - |

---

## Performance Metrics

**Plans executed**: 4 (Phase 0)  
**Plans verified**: 4 (goal-backward against ROADMAP Success Criteria 1–4)  
**Requirements delivered**: 0/29 (Phase 0 produces decisions, no REQUIREMENTS items)  
**Phases complete**: 1/6

---

## Accumulated Context

### Key Decisions (from PROJECT.md)

| Decision | Status |
|----------|--------|
| Tab color stored in tab title prefix (`"color:title"`) | Proven 2026-06-07 |
| Pane-level color via OSC 1337 `SetUserVar` | Proven 2026-06-07 |
| Companion CLI language: Lua preferred, Python/uv fallback | Pending — Phase 0 spike |
| Bash excluded as CLI language | Confirmed |
| Hypothesis-first development | Active policy |
| Non-destructive install via sentinel blocks | Active policy |
| `cli/spec.lua` is the single source-of-truth command contract (Plans 04/05/06/07 add command modules, never edit the spec) | Locked 01-01 (D-16) |
| `wez` dispatch resolves subcommands against a closed allow-list before lazy require | Locked 01-01 (T-01-02) |
| `tools/build.sh` download fallback pins the release tag + verifies SHA-256 before chmod +x | Locked 01-01 (T-01-01) |
| `keybindings.lua` returns key table + disabled-defaults as DATA; consumed by both `apply()` and `wez keys` | Locked 01-03 (D-09/D-12) |
| `apply(config)` mutates the passed config by reference (augment, never replace); appends keys, never reassigns | Locked 01-03 (D-17, T-03-01) |
| README backslash split chord replaced with layout-stable `Alt+Shift+H/V` | Locked 01-03 (D-10) |
| OSC 7 emitters shipped for bash+zsh; TTY-guarded, idempotent, no /proc/GNU-only flags | Locked 01-03 (FOUND-01, T-03-02/03) |
| Bootstrap installs emulator sudo-free via `.Ubuntu<base>.tar.xz` -> `~/.local`, symlink `~/.local/bin/wezterm`; never AppImage/FUSE/sudo (D-04/D-05) | Locked 01-02 (INST-06) |
| Detection-first reuse: existing wezterm `>=` pinned minimum `20260604-145453` reused untouched; system installs never modified (D-07) | Locked 01-02 |
| Version model = rolling `nightly` + last 5 dated (TTY selector); non-TTY uses pinned `20260604-145453` (D-08); leading YYYYMMDD is the comparator | Locked 01-02 |
| Pre-extract integrity (xz magic + size) + member validation (no absolute/`..`) before extraction (T-02-01/T-02-02) | Locked 01-02 |
| `wez keys` data source = live `wezterm show-keys --lua` (effective) + `wezterm -n show-keys --lua` (baseline) + installed keybindings.lua; `key_tables` (copy_mode/search_mode) excluded (D-13) | Locked 01-05 |
| D-14 classification: setup = ours ∩ baseline ∩ effective; default = baseline ∩ effective not ours; user = effective only; conflict = ours absent from effective | Locked 01-05 |
| show-keys text parsed line-by-line, never `load()`/eval'd; action kept as opaque string; malformed lines skipped+counted (T-05-01) | Locked 01-05 |
| keybindings.lua read from installed path `$HOME/.config/wezterm/wezterm-setup/keybindings.lua` at runtime (luastatic bundle has no LUA_PATH) | Locked 01-05 |
| Sentinel markers LOCKED: `-- >>> wezterm-setup managed block >>>` / `-- <<< wezterm-setup managed block <<<`; canonical parse contract reused by downstream plans (Plan 06) | Locked 01-04 (INST-01) |
| INJECT uses write-temp-then-`os.rename` over the target; timestamped backup taken first so an interrupted write leaves the original intact | Locked 01-04 (T-04-01) |
| `wez.lua` dispatcher maps hyphenated subcommand names to underscored module files (`install-state` -> `install_state`); allow-list still gates it (T-01-02 holds) | Locked 01-04 (bug fix, also unblocks `uninstall-state` Plan 06) |
| `wez doctor` exit code gated by FOUR core integrity gates ONLY (binary-on-PATH, sentinel well-formed, config dofiles cleanly, backup exists); completions-installed + live-session are ADVISORY (printed, never flip exit 0) | Locked 01-06 (D-15; PLAN spec overrode looser CONTEXT prose) |
| doctor loads the managed `wezterm-setup/init.lua` under a protected `pcall`, never executing the user's `wezterm.lua` side effects | Locked 01-06 (T-06-02) |
| `wez uninstall-state` owns all removal decisions (`plan_removal` honors --keep-config/--keep-cli/--keep-backup); `excise_block` removes EXACTLY the sentinel range leaving user lines byte-identical; only the `wezterm-setup/` subtree is removed, never its parent | Locked 01-06 (INST-04/05, T-06-01/03) |
| `tools/uninstall.sh` is decision-free glue (D-01): maps Makefile KEEP_* env to --keep-* flags, delegates to `wez uninstall-state`; sudo-free, no `rm` branching | Locked 01-06 (T-06-04) |
| Completions GENERATED by walking the argparse parser (`_commands`/`_options`) from `cli/spec.lua` — coverage grows with the spec, no per-phase generator edits; dynamic values route through hidden `wez __complete <context>` (single extension point for colors/scene names) | Locked 01-07 (D-16) |
| Dispatcher aliases spec name `__complete` -> module leaf `complete` (cli/commands/complete.lua); closed map over the allow-listed name (T-01-02 holds) | Locked 01-07 (bug fix) |
| Installer STEP 5b writes zsh/bash completions to user-owned dirs and registers idempotently under `# wezterm-setup:completions` (distinct from + coexisting with `# wezterm-setup:osc7`); sudo-free | Locked 01-07 (DIAG-05, T-07-01/03) |

### Validated Capabilities (pre-Phase 0)

- Tab-level persistent color via `set-tab-title` prefix convention (`"color:title"` or `"color"`)
- Pane-level color override via `WEZTERM_TAB_COLOR` user var (OSC 1337 escape)
- Active tab visual differentiation (indicator + bold text)
- Color profiles: red, orange, yellow, green, teal, cyan, blue, navy, purple, pink

### Active Todos

*(None yet — roadmap just created)*

### Blockers

*(None)*

### Discoveries

- `wezterm cli set-user-var` does NOT exist — pane user vars must use OSC 1337 escape
- WezTerm hot-reloads `~/.config/wezterm/wezterm.lua` on file save; no restart needed during development
- Active config is `~/.config/wezterm/wezterm.lua`; repo config will live under `~/.config/wezterm/wezterm-setup/` post-install

---

## Session Continuity

**Last session**: 2026-06-09 — Executed Plan 01-07 (shell completions, DIAG-05). TDD Task 1: RED test → `cli/commands/completions.lua` + `cli/commands/complete.lua` (`d7930e8`). The generator WALKS the argparse parser built by `cli/spec.lua` (`_commands` + each command's `_options._aliases`), enumerating every VISIBLE subcommand + its long flags (drops auto `-h/--help` and hidden `__complete`) and emits a `#compdef wez` zsh function / `complete -F _wez` bash function — spec-driven (D-16), so adding a subcommand to spec.lua extends coverage with no generator edit. Generated scripts shell out to `wez __complete subcommands` for dynamic candidates; `complete.lua` is the hidden hook (closed context dispatch, plain tokens only, unknown context → empty + exit 0, T-07-02). Rule-3 fix in `cli/wez.lua`: the `-`→`_` module transform leaves `__complete` unchanged, so the dispatcher couldn't reach `complete.lua`; added a closed `MODULE_ALIASES` map (`__complete`→`complete`) over the already-allow-listed name (T-01-02 holds); spec.lua untouched (D-16). 47 spec-driven assertions green; both scripts pass `bash -n`/`zsh -n`. Task 2 (`aea68ef`): `tools/setup.sh` STEP 5b generates both scripts via explicit `wez completions zsh|bash`, writes to user-owned dirs (`~/.local/share/zsh/site-functions/_wez`, `~/.local/share/bash-completion/completions/wez`), and registers idempotently under `# wezterm-setup:completions` (distinct from + coexisting with Plan 04's `# wezterm-setup:osc7`); sudo-free (T-07-03), shellcheck -x clean, satisfies doctor's ADVISORY completions line (never flips exit code, D-15). Installer dogfood: scripts written, re-install idempotent (marker count stays 1), osc7 line preserved. R2 repro `docs/repro/h-diag-completions.md`: observed live bash `compgen` `wez <Tab>` subcommands + `wez keys --<Tab>` `--json`; zsh `_wez` loaded by compinit without error with the same candidate set. Full suite 8/8. DIAG-05 Done (Linux). **Phase 1 is feature-complete on Linux** — schedule the batched macOS pass before closing.

**Prior session**: 2026-06-09 — Executed Plan 01-06 (`wez doctor` DIAG-01 + granular `uninstall-state` INST-04/05). TDD Task 1: RED test → `cli/commands/doctor.lua` (`a06febe`) — `aggregate(core, advisory)` exits 0 iff all FOUR core integrity gates pass (binary-on-PATH, sentinel well-formed via reused `install_state.parse`, config dofiles cleanly via protected `pcall` of managed init.lua [T-06-02], backup exists via reused `newest_backup`); completions-installed + live `wezterm cli list` are ADVISORY (printed, never flip exit 0, D-15). 15 gate-aggregation assertions green. R2 repro `docs/repro/h-diag-doctor.md`: scratch HEALTHY install exits 0 even with the advisory completions probe FAILing; excising the sentinel block flips it to exit 1 naming the failed gate. TDD Task 2: RED test → `cli/commands/uninstall_state.lua` (`3dcf337`) — pure `plan_removal(flags)` (each keep-flag suppresses exactly its component) + pure `excise_block` (removes EXACTLY the sentinel range, user lines byte-identical, T-06-01) via reused `atomic_write`; only the `wezterm-setup/` subtree removed, never its parent (T-06-03); all user paths, no sudo (T-06-04). `tools/uninstall.sh` decision-free glue reads KEEP_CONFIG/KEEP_CLI/KEEP_BACKUP → --keep-* flags, delegates to the binary; shellcheck -x clean. 37 assertions green (pure + scratch-FS run for full + each keep-flag). Live dogfood through the bash glue: full uninstall removed block+config+cli+backups, exit 0, wezterm.lua user lines byte-identical to the pre-install original. spec.lua untouched (D-16). Full suite 7/7. DIAG-01 + INST-04/05 Done (Linux). Phase 1 success criteria #2 (granular uninstall) + the doctor half of #4 satisfied.

**Prior session**: 2026-06-09 — Executed Plan 01-04 (non-destructive installer, INST-01/02/03). TDD Task 1: RED test then `cli/commands/install_state.lua` (`7b71b0d`) — PARSE (locked sentinel markers), BACKUP (`.bak.<UTC>` before any write), INJECT (single block wiring `apply(config)` via write-temp-then-`os.rename`, T-04-01), DECIDE (no-TTY re-install aborts non-zero naming `--force/--restore/--skip`, D-03); 28 fixture/temp-fs assertions green; spec.lua untouched. Task 2: `tools/setup.sh` (`46cc24a`) decision-free glue — bootstrap WezTerm → build/place wez → copy config tree → register OSC 7 (marker-guarded idempotent) → delegate to `wez install-state` surfacing its exit code; sudo-free, shellcheck -x clean. The Task-2 dogfood surfaced a Rule-1 bug: `wez.lua` mapped the hyphenated `install-state` to `cli/commands/install-state.lua` (hyphen) instead of the underscored module — fixed with a `-`→`_` transform on the allow-listed name (+ spec_test regression). Dogfooded against a scratch HOME with a copy of the real 112-line wezterm.lua: clean install = 1 block + timestamped backup == original + intact user lines; no-TTY re-install aborts exit 3; `--skip` no-op; `--force` re-yields one block. INST-01/02/03 Done (Linux); FOUND-04 now fully closed (config installed). Full suite 5/5 green.

**Prior session**: 2026-06-09 — Executed Plan 01-05 (`wez keys`, DIAG-02/03/04). TDD: RED test (`ba51ffc`) → `cli/lib/showkeys.lua` parser (`aa1cad4`, excludes copy_mode/search_mode, never eval's untrusted text) → `cli/commands/keys.lua` (`ad07225`, pure D-14 classify + category grouping + jq-valid `--json` via dkjson; reads installed keybindings.lua at runtime; spec.lua untouched). 21/21 fixture assertions green; full suite 4/4. Live-verified on Linux: grouped table (3 category headers), `wez keys --json | jq .` exits 0, 0 conflicts on the un-installed host (every binding = default/user, expected until Plan 04 installs config). R6 probe + `docs/repro/h-diag-keys.md` (R2) capture the real show-keys shape. DIAG-02/03/04 Done; FOUND-04 tool delivered (full closure once config installed via Plan 04).

**Prior session**: 2026-06-09 — Resumed and completed Plan 01-02 (sudo-free WezTerm emulator bootstrap, INST-06). Task 1 (`tools/lib/wezterm-release.sh` + R6 probes) was already committed (`5af3301`) and left intact; finished Task 2: reconciled the untracked `tools/bootstrap-wezterm.sh` draft against spec, removed a dead `REPO_ROOT` (shellcheck SC2034), verified the DETECT/REUSE path on this host (system wezterm `20260604-145453` reused untouched, exit 0), and added the missing `docs/repro/h-inst06-bootstrap.md` R2 repro. Committed atomically (`b2db8e6`). No sudo/AppImage/FUSE; macOS `.app` branch present-but-deferred (D-06/D-18). INST-06 marked Done (Linux). Probes remain in gitignored `.tmp/`.

**Prior session**: 2026-06-09 — Executed Plan 01-03 (config layer): `config/wezterm-setup/init.lua` (`apply(config)` augment entry point, D-17), `keybindings.lua` (curated `mapped:` table + disabled-defaults as data, FOUND-02..05), `cwd.lua` (no-op augment; inheritance is WezTerm default), `shell-integration/osc7.sh`+`osc7.zsh` (TTY-guarded idempotent OSC 7 emitters, FOUND-01). 14/14 lua test assertions green; bash+zsh emitters verified over a pty (`file://host/path` URL-encoded). R6 probe (config-var-name) verdict `holds`, encoded in init.lua comments. FOUND-01/02/03/05 marked done (Linux; macOS deferred); FOUND-04 pending `wez keys` (Plan 05)  
**Next action**: Phase 1 is feature-complete on Linux (all 7 plans done). Schedule the batched macOS verification pass (re-run cwd probe, fill the cli-surface macOS column, build the universal binary, verify INST-06 `.app` placement, verify completions registration on macOS shells) and then run `/gsd-transition` to close Phase 1 before starting Phase 2 (pane identity). (D-04/D-05/D-18)

**Key Phase 0 outcomes (for Phase 1):**

- CLI = **Lua 5.4**; packaging = vendored pure-Lua deps + `luastatic` single binary + `curl|bash` installer (sudo-free for users); dev/CI provisions Lua SDK + musl (Linux) + Mac runner
- CWD = OSC 7 (ship shell integration emitting it for zsh+bash) + WezTerm OS read backstop
- `wezterm cli` surface catalogued in `.planning/decisions/wezterm-cli-surface.md` (no `set-user-var` → OSC 1337)
- Tab color = `"color:title"` title prefix; pane color = OSC 1337 `WEZTERM_TAB_COLOR`

---

*State initialized: 2026-06-07*  
*Last updated: 2026-06-07 after Phase 0 completion*
