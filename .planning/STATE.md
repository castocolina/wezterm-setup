---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: Phase 06 complete (verified passed-with-concerns) — Phase 07 (macOS) remaining
last_updated: "2026-06-15T12:41:07.841Z"
progress:
  total_phases: 8
  completed_phases: 7
  total_plans: 33
  completed_plans: 33
  percent: 88
---

# Project State: wezterm-setup

## Project Reference

**Core Value**: A working WezTerm install that is easy to understand, audit, and extend — where every shipped behavior is verified against a real running session before it integrates.

**Project file**: `.planning/PROJECT.md`  
**Roadmap**: `.planning/ROADMAP.md`  
**Requirements**: `.planning/REQUIREMENTS.md`

---

## Current Position

Phase: 06 (installer) — COMPLETE + verified (passed-with-concerns)
Plan: 6 of 6 executed, verified, committed
**Current Phase**: Phase 6 — Ergonomic Installer SHIPPED (INST-07 + INST-08 + INST-09)
**Next action**: `/gsd-plan-phase 7` (macOS Parity Pass) — requires a real Mac; or cut the first `v*` release tag (Open Q3) to light up the live binary download.
**What shipped (6 plans, 21 commits, +1038 lines, suite 21/21):** `tools/install.sh` (pipe-safe one-liner: main()-last-line, /dev/tty open-probe, codeload tarball + mktemp/trap cleanup, WEZ_REMOTE_BOOTSTRAP=1 handoff, WEZ_REF pin); `tools/build.sh` repointed castocolina + per-asset .sha256 + portable verify; `tools/publish.sh` + `make build/publish`; `.github/workflows/release.yml` (matrix ubuntu/macos-15-intel/macos-14, arm64 codesign); `tools/ci-setup-toolchain.sh`; `tools/bootstrap-wezterm.sh` nightly-default + update-in-place + `wezterm_install_is_user_path` predicate; `cli/commands/update.lua` (`wez update`, split semver/datestamp comparators, system-install guard) + `cli/spec.lua` registration; README via crafting-effective-readmes; `bash -n` gate in run-tests.sh.
**Verification:** 06-VERIFICATION.md status=passed-with-concerns, 8/8 SC. Live-checked: `wez update` refuses the system /usr/bin wezterm (P6-D09 holds); install.sh temp cleanup fixed (eb8a691, live-dogfound bug); deterministic headless-abort.
**Known interim (deferred-by-design, NOT failures):** (1) no `v*` release tag cut yet → live wez-binary download not exercised end-to-end; dev source-launcher/local-checkout fallback keeps the installer working (Open Q3, maintainer action). (2) macOS on-Mac verification = Phase 7 (`install_macos()` stub; macOS asset BUILD is wired in CI). Coverage 34/34 reqs mapped (INST-07/08/09 added). Phases 0–6 done; Phase 7 is the v1 close gate.
**Open user decisions:** whether to `sudo apt purge wezterm-nightly` (system install) to dogfood the sudo-free user-path download; when to cut the first `v*` tag.

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
| 1 | Foundation | Complete | 2026-06-10 |
| 2 | Pane Identity | Complete | 2026-06-11 |
| 3 | Tab Identity | Complete | 2026-06-12 |
| 4 | Ad-hoc Scenes | Complete | 2026-06-13 |
| 5 | Named Scenes | Complete | 2026-06-14 |
| 6 | Ergonomic Installer | Complete (passed-with-concerns) | 2026-06-15 |
| 7 | macOS Parity Pass (D-18) | Pending — needs a Mac | - |

---

## Quick Tasks Completed

| Quick ID | Slug | Summary | Date | Commit |
|----------|------|---------|------|--------|
| 260613-dlh | doctor-config-path | `wez doctor` GATE 3 now replicates WezTerm's `<config-dir>/?.lua` path so the installed config's dotted requires resolve (fixes a false `[FAIL] config dofiles cleanly`) | 2026-06-13 | aace2ff |
| 260613-dup | ci-colocated-tests | `make test` now discovers co-located `*_test.lua` under `cli/` and `config/` (8 → 14 files); 6 previously-orphaned suites (pane/tab/title/scene/complete/format-tab-title) now run in CI | 2026-06-13 | 77b76bb |

---

## Performance Metrics

**Plans executed**: 4 (Phase 0)  
**Plans verified**: 4 (goal-backward against ROADMAP Success Criteria 1–4)  
**Requirements delivered**: 0/29 (Phase 0 produces decisions, no REQUIREMENTS items)  
**Phases complete**: 1/6

---

## Accumulated Context

### Roadmap Evolution

- 2026-06-14: Phase 6 added — **Ergonomic Installer** (one-line `curl|bash` remote bootstrap + README; new requirement INST-07).
- 2026-06-14: Phase 7 added — **macOS Parity Pass (D-18)**; macOS verification promoted from a deferred note to a real phase (final gate before v1 close). No new requirement IDs.

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

**Single tracker:** [`.planning/MACOS-PARITY-AND-FOLLOWUPS.md`](MACOS-PARITY-AND-FOLLOWUPS.md) — all post-Phase-5 pending work. Phases 1–4 are CLOSED, so items are NOT scattered into those dirs.

- **macOS batched pass (D-18)** — the next milestone-level activity. Run `bash tools/verify-macos.sh` (auto, non-destructive) for the gate, then drive `docs/macos-verification.md` top-to-bottom on a real Mac (pair with `agent-ui-ux-designer` for the visual/UX steps). Tracker §C.
- **✅ A-1 RESOLVED 2026-06-14: `wez scene new --layout`/`--color <Tab>` value completion** — wired into both generated scripts (`--layout)→scene-layouts`, `--color)→scene-colors`; new `scene.COLOR_NAMES` single source + `scene-colors` context). Bash runtime proven; zsh confirm on the runbook §6. Suite 17/17. Tracker §A-1. (`--pane`/`--title` values remain uncompleted — minor.)
- **UX backlog** (deferred, non-blocking): `wez scene list`, did-you-mean, unify error prefixes, dead dispatcher branch, README recipe caveats. Tracker §A-2.
- **Clarified (NOT bugs):** `bg` == `wez pane color`; no separate `bg`/`opacity` ships in v1 (new requirement if wanted). Tracker §B.

### Blockers

*(None)*

### Discoveries

- `wezterm cli set-user-var` does NOT exist — pane user vars must use OSC 1337 escape
- WezTerm hot-reloads `~/.config/wezterm/wezterm.lua` on file save; no restart needed during development
- Active config is `~/.config/wezterm/wezterm.lua`; repo config will live under `~/.config/wezterm/wezterm-setup/` post-install

---

## Session Continuity

**Last session**: 2026-06-14 — Executed Plan 05-04 (dynamic recipe-name completion, SCEN-05 DONE). Task 1 (`677c811`, `feat`): `cli/commands/complete.lua` now requires the COMMAND module `cli.commands.scene` and adds a `scene_names()` provider returning `scene.list_recipe_names(scene.scenes_dir())` read DYNAMICALLY at Tab time (no caching); registered `["scene-names"]` in the CONTEXTS table. Reuses the SINGLE launch provider (Pitfall 6 / D-16) — completion can never advertise a recipe set launch resolves differently. The existing run() loop emits sorted basenames one-per-line and no-ops on unknown context, so empty/missing scenes dir -> `{}` -> nothing emitted, exit 0 (Tab-time-never-fails, T-05-13). `complete_test.lua` +8 assertions via child `lua5.4 -e` with `WEZTERM_SETUP_DIR` set (lua5.4 has no os.setenv): sorted basenames no-ext, non-`.toml` ignored, new file appears on re-run with NO regeneration (dynamic), empty + missing dir no-op exit 0. Task 2 (`d6a0279`, `feat`): `cli/commands/completions.lua` — the generic flag loop in BOTH gen_zsh + gen_bash now SKIPS `scene`, and a hand-written nested `scene)` arm is emitted beside pane)/tab): launch->`wez __complete scene-names`, new->`--layout --pane --color --title`, *->`new launch`. This REPLACES the generic flag arm (ratified Open Q3) because `scene` has top-level flags AND subcommands — the flagless pane/tab template can't be cloned. Recipe names never hardcoded; they flow through scene-names (D-09/D-16). `completions_test.lua` +14 assertions: exactly ONE scene) arm (no duplicate), launch->scene-names routing, new->flags, *->new launch, dynamic launch candidates, + `bash -n` (mandatory) / `zsh -n` (skipped if zsh absent) syntax checks on the generated scripts. Verified end-to-end against the real `dist/wez` source launcher: `__complete scene-names` prints sorted basenames and is dynamic; both `completions bash|zsh` pass `-n`. complete_test 26/26, completions_test 69/69, full suite 17/17. No deviations. SCEN-05 Done (Linux). Phase 5 now 4/4 complete; progress 27/27 (100%). Next: batched macOS pass, then `/gsd-transition`.

**Older session**: 2026-06-13 — Executed Plan 05-02 (copy-if-absent install seeding, SCEN-06 DONE). Task 1 (`a46ec88`, `feat`): authored the 3 locked seed recipes `scenes/{dev,ai,docker}.toml` at the repo TOP LEVEL (sibling to cli/config/tools), OUTSIDE `config/wezterm-setup/` so STEP 4's wholesale `cp -R config/wezterm-setup/.` can never place or clobber them (D-06/D-08 INVARIANT). Each encodes EXACTLY the SCEN-06 table (dev=tall/green/2 shell; ai=tall/purple/2 shell; docker=grid/teal/[docker stats, docker ps, docker compose logs -f, shell]), uses `command = "shell"` for shell panes (round-trips to literal `--pane shell`, no auto-title), no `title` key; all 3 round-trip through `recipe.load_and_map` to the expected args. Task 2 (`17d844a`, `feat`): `cli/commands/seed_scenes.lua` mirrors `install_state.lua`'s pure-decision + run()-glue split — PURE `plan_seed(repo_names, dest_names) -> {name, action=seed|keep}` (fixture-testable, no FS), `run()` lists src+dest via shquote'd `io.popen("ls -1")` (T-05-06), applies plan_seed, RE-CHECKS dest absence at write time (TOCTOU, T-05-05) and copies bytes, emitting EXACT UI-SPEC copy `seeded scene recipe: <name>` / `kept existing scene recipe: <name>` (never "skipped"). Dest resolver: `WEZTERM_SETUP_DIR` → `WEZTERM_CONFIG_DIR/wezterm-setup` → `XDG_CONFIG_HOME/wezterm/wezterm-setup` → `~/.config/wezterm/wezterm-setup`, then `/scenes`. Src resolver: relative to the running script via `debug.getinfo` source, with `WEZ_SEED_SRC_DIR` override. Registered `seed-scenes` in `cli/spec.lua` (parser command + SUBCOMMANDS allow-list + CATEGORIES=install). `tests/cli/seed_scenes_test.lua`: pure plan_seed cases (all-new→seed, all-existing→keep, mixed) + scratch-FS run() proving first run writes 3 and a user edit SURVIVES a second run byte-identical (lua5.4 lacks `os.setenv`, so the FS test uses a child-`lua5.4 -e` fallback with env set). 14/14 green; `dist/wez seed-scenes` dispatches against a scratch WEZTERM_SETUP_DIR (first run seeds 3, second keeps 3, exit 0); plan_seed purity grep clean. Task 3 (`5213314`, `feat`): `tools/setup.sh` STEP 4b mirrors STEP 6's decision-free `install-state` delegation — `WEZ_SEED_SRC_DIR=${REPO_ROOT}/scenes WEZTERM_SETUP_DIR=${SETUP_DIR} "${BIN_DIR}/wez" seed-scenes`; STEP 4 cp -R untouched (3 refs all `config/wezterm-setup/.`); no recipe copy/keep branching in bash (D-01/D-07). `bash -n` + `shellcheck -x` clean; full suite 16/16. README scene path corrected from the stale standalone `~/.config/wezterm-setup/scenes/` to the co-located D-04 `~/.config/wezterm/wezterm-setup/scenes/`. No deviations. SCEN-06 Done (Linux). Plan now 2/4 in Phase 5; progress 25/27 (93%). Next: 05-03 (launch IO-shell) + 05-04 (completion).

**Older session**: 2026-06-13 — Executed Plan 05-01 (recipe core, SCEN-03 logic) as a continuation agent after the Task-1 supply-chain checkpoint was human-approved. Task 1 (`cbeb1eb`, `feat`): committed the already-vendored, SHA-256-verified `cli/vendor/tinytoml.lua` (pure-Lua TOML 1.1.0 decoder, pinned upstream tag `1.0.0`/commit `663e319` — NOT `v1.0.0`, upstream tags without the v; provenance header carries URL+tag+SHA-256; zero `require(`, MIT, `return tinytoml`; bundles via the existing `cli/**/*.lua` build glob, no build.sh edit). Task 2 TDD: RED (`d5aedd3`, `test`) — `cli/lib/recipe_test.lua` (28 assertions mirroring scene_test's check/eq/teq+deep_eq harness) fails on absent `cli.lib.recipe`. GREEN (`053dbf6`, `feat`) — `cli/lib/recipe.lua` exports `guard_name` (rejects empty/`/`/`..` pre-I/O, T-05-01), `recipe_to_args` (pure; `panes` key + `pane` alias; Option-1 bare-command fast path — `command=="shell"`/none→`"shell"`, single-field→bare command, multi-field→`cmd=,color=,title=`; `cmd` alias), and `load_and_map` (MANDATORY `pcall(toml.parse, raw, {load_from_string=true})` since tinytoml RAISES — Pitfall 1; extracts `line (%d+)`→`could not parse TOML at line <N>`, never a traceback, T-05-02; missing-layout reason; reuses `scene.validate_layout`/`validate_color` verbatim for EXACT enum strings, UI-SPEC single source). PURE by contract: pure-core grep clean (`io%.|os%.execute|os%.getenv|wezterm`); dual-resolution `pcall(require,"cli.vendor.tinytoml")`. 28/28 recipe_test green, full suite 15/15, no regression. No REFACTOR commit (GREEN already clean). recipe error reasons use the no-name `error: scene recipe is invalid: ...` form — the per-file `'<name>'` framing is 05-03's IO-shell job. Plan now 1/4 in Phase 5; progress 24/27 (89%). Next: 05-02 (seed-scenes copy-if-absent) + 05-03 (launch IO-shell: file read → guard_name → load_and_map → run_new).

**Older session**: 2026-06-13 — Executed Plan 04-01 (scene pure-logic core, logic half of SCEN-02) via full TDD RED→GREEN→REFACTOR. Built two net-new files `cli/lib/scene.lua` + `cli/lib/scene_test.lua` mirroring the `cli/lib/title.lua` module style and the `cli/lib/title_test.lua` check/eq harness (added a recursive `deep_eq`/`teq` for table-returning functions). RED (`4a77af2`, `test`): require of absent `cli.lib.scene` fails, exit 1. GREEN (`19a8b38`, `feat`): implemented `plan_splits` (equal-share split sequencer — `round_pct(remaining)=floor(100/remaining+0.5)` — for tall/tall:mirrored/horizontal/grid with creation-order pane-index targeting; N≤1→`{}`), `parse_pane_spec` (shell/bare/key=value grammar, first-`=` split, unknown-key validate-before-emit error echoing original spec), `validate_layout`/`validate_color` (exact UI-SPEC error strings, color case-insensitive with original-case echo), `validate_pane_id`=`validate_tab_id` (integer coerce+range), and `decide_materialization` (D-10 reuse when `tab_pane_count==1` else D-11 new-tab; `n` is signature-only, NOT a mode factor — per plan body over the research sketch's `&& N==1`). Module is provably pure: `rg -c 'wezterm|io.popen|os.execute' cli/lib/scene.lua`==0 (reworded doc comments to avoid the literal banned tokens; no `cli.lib.title` require — auto-title (D-07) is a 04-02 live-wrapper job). REFACTOR (`eff22e8`, `refactor`): `round_pct`/`split_kv_segments` already sole-sited from GREEN, so this added only edge-case fixtures (tall N=2, horizontal N=2, grid N=4 perfect-square=3 steps, empty-spec→bare `cmd=""`). Final suite `scene_test: 49 passed, 0 failed`, exit 0. SCEN-02 left **Pending** — layouts don't render live until 04-02, so marking it now would over-report. 04-02 owns the I/O boundary: must call `validate_pane_id`/`validate_tab_id` on every list-JSON id before shelling out and resolve auto pane-titles via `cli/lib/title.lua` at spawn. Plan now 2/3 in Phase 4; progress 21/23 (91%).

**Older session**: 2026-06-09 — Executed Plan 01-07 (shell completions, DIAG-05). TDD Task 1: RED test → `cli/commands/completions.lua` + `cli/commands/complete.lua` (`d7930e8`). The generator WALKS the argparse parser built by `cli/spec.lua` (`_commands` + each command's `_options._aliases`), enumerating every VISIBLE subcommand + its long flags (drops auto `-h/--help` and hidden `__complete`) and emits a `#compdef wez` zsh function / `complete -F _wez` bash function — spec-driven (D-16), so adding a subcommand to spec.lua extends coverage with no generator edit. Generated scripts shell out to `wez __complete subcommands` for dynamic candidates; `complete.lua` is the hidden hook (closed context dispatch, plain tokens only, unknown context → empty + exit 0, T-07-02). Rule-3 fix in `cli/wez.lua`: the `-`→`_` module transform leaves `__complete` unchanged, so the dispatcher couldn't reach `complete.lua`; added a closed `MODULE_ALIASES` map (`__complete`→`complete`) over the already-allow-listed name (T-01-02 holds); spec.lua untouched (D-16). 47 spec-driven assertions green; both scripts pass `bash -n`/`zsh -n`. Task 2 (`aea68ef`): `tools/setup.sh` STEP 5b generates both scripts via explicit `wez completions zsh|bash`, writes to user-owned dirs (`~/.local/share/zsh/site-functions/_wez`, `~/.local/share/bash-completion/completions/wez`), and registers idempotently under `# wezterm-setup:completions` (distinct from + coexisting with Plan 04's `# wezterm-setup:osc7`); sudo-free (T-07-03), shellcheck -x clean, satisfies doctor's ADVISORY completions line (never flips exit code, D-15). Installer dogfood: scripts written, re-install idempotent (marker count stays 1), osc7 line preserved. R2 repro `docs/repro/h-diag-completions.md`: observed live bash `compgen` `wez <Tab>` subcommands + `wez keys --<Tab>` `--json`; zsh `_wez` loaded by compinit without error with the same candidate set. Full suite 8/8. DIAG-05 Done (Linux). **Phase 1 is feature-complete on Linux** — schedule the batched macOS pass before closing.

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

## Decisions

- [Phase ?]: scene.lua materialization mode driven solely by tab_pane_count==1 (reuse) else new-tab (04-01)
- [Phase 5]: tinytoml vendored at upstream tag `1.0.0` (NOT `v1.0.0` — upstream tags without leading v; plan URL was a typo); provenance header records URL + tag + SHA-256, human-approved (T-05-SC) (05-01)
- [Phase 5]: recipe panes key is `panes` (matches README/UI-SPEC `[[panes]]`), `pane` accepted as fallback alias; Option-1 bare-command fast path keeps the 3 seeds comma-safe through `--pane` round-trip (05-01)
- [Phase 5]: `recipe.load_and_map` error reasons use the no-name form `error: scene recipe is invalid: ...`; per-file `'<name>'` framing is the 05-03 IO-shell's job (05-01)
- [Phase 5]: seed recipes live at the repo TOP LEVEL `scenes/` (outside `config/wezterm-setup/`) so the installer's wholesale `cp -R` never clobbers user-edited recipes — the `wez seed-scenes` copy-if-absent seeder is the ONLY writer of the dest scenes dir (D-06 INVARIANT) (05-02)
- [Phase 5]: `wez seed-scenes` owns all copy/keep decisions in Lua (pure `plan_seed` + run() TOCTOU re-check, never overwrite); `setup.sh` STEP 4b is decision-free glue passing `WEZ_SEED_SRC_DIR`/`WEZTERM_SETUP_DIR` (D-01/D-07) (05-02)
- [Phase 5]: seeder dest resolver precedence = `WEZTERM_SETUP_DIR` → `WEZTERM_CONFIG_DIR/wezterm-setup` → `XDG_CONFIG_HOME/wezterm/wezterm-setup` → `~/.config/wezterm/wezterm-setup`, then `/scenes` (05-02)
- [Phase 5]: `scene-names` completion reuses the SINGLE `scene.list_recipe_names(scene.scenes_dir())` provider launch uses (no second lister), read dynamically at Tab time — adding/removing a `.toml` changes the set with no regeneration (Pitfall 6 / D-16) (05-04)
- [Phase 5]: the nested `scene)` generator arm REPLACES the generic flag arm (skip `scene` in the flag loop) because `scene` has both top-level flags and subcommands — launch->scene-names, new->flags, *->new launch (ratified Open Q3) (05-04)
