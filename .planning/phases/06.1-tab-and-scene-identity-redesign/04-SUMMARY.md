---
phase: 06.1-tab-and-scene-identity-redesign
plan: 04
subsystem: cli-scene
tags: [scene, recipe, cwd, focus, size, osc, clean-pane, d-01, d-05, d-06, d-07, d-08]
requires:
  - cli/lib/scene.lua (parse_pane_spec / plan_splits / validators)
  - cli/lib/cwd.lua (Plan 02 — the ONE pure cwd resolver/validator, D-01)
  - cli/lib/color.lua (Plan 01 — build_user_var_octal for WEZTERM_TAB_COLOR)
  - cli/commands/tab.lua (write_tab_title pure-text sink)
provides:
  - "--pane / [[pane]] entries accept cwd/focus/size in addition to cmd/color/title (D-05/D-06/D-07)"
  - "scene panes spawn with `wezterm cli spawn/split-pane --cwd <resolved>` — clean pane, no `cd` line (D-08)"
  - "per-pane size= overrides the equal-share split --percent for its step (D-06)"
  - "focus=true pane is activated after build; >1 focus=true is a validate-before-emit error (D-05)"
  - "scene tab color rides WEZTERM_TAB_COLOR via OSC (no <color>:<title> encoding); scene.lua drops the parse_stored/merge_title dependency (D-02/D-03/D-04)"
  - "recipe schema gains per-pane cwd/focus/size + top-level cwd + [[pane]] alias + migration aliases (D-04/D-07)"
  - "cwd/focus/size + tab-level --cwd registered in cli/spec.lua for completion + `wez keys` (D-16)"
affects:
  - cli/commands/scene.lua (the live spawn path now applies cwd/size/focus)
  - .planning Plan 07 (live spawn --cwd round-trip + refreshed comma-safe seeds)
tech-stack:
  added: []
  patterns:
    - "Validate-before-emit extended to cwd (cwdlib.validate per-pane + tab-level) and focus>1 (scene.validate_focus) — zero mux calls on failure"
    - "cwd resolved at the IO-shell boundary (launch dir = $PWD, env snapshot) and passed to spawn --cwd (D-08 clean pane); the pure cwd.lua never touches the shell"
    - "Pane-targeted user-var emit via color.build_user_var_octal + printf-octal send-text (Pitfall 2 cross-shell path)"
    - "Bare-command fast path dropped the moment ANY extra recipe pane field (color/title/cwd/focus/size) is present"
key-files:
  created: []
  modified:
    - cli/lib/scene.lua
    - cli/lib/scene_test.lua
    - cli/lib/recipe.lua
    - cli/lib/recipe_test.lua
    - cli/commands/scene.lua
    - cli/spec.lua
    - tests/cli/spec_test.lua
decisions:
  - "D-05: focus parsed as boolean (focus=true -> true, absent -> nil so 'no focus' is distinguishable); validate_focus errors on >1; IO-shell activates the focus pane else pane 1"
  - "D-06: size is an integer percent 1..100 (out-of-range/non-integer is a validate-before-emit error); size_percent overrides the plan_splits equal-share --percent for that step"
  - "D-07: cwd carried RAW through the pure layer; top-level recipe cwd becomes args.cwd (tab-level default); panes omitting cwd inherit tab cwd then launch dir"
  - "D-08: cwd applied at spawn time via --cwd on spawn AND split-pane — no spawn-then-cd, the pane opens clean. Reuse-mode pane 1 already sits in the launch dir (D-07 default), so no --cwd is applied to an already-open pane"
  - "D-02/D-03/D-04: scene tab color emits WEZTERM_TAB_COLOR via color.build_user_var_octal (pane-targeted printf-octal send-text); title is pure set-tab-title text; parse_stored/merge_title dependency removed and dead read_current_tab_title deleted"
  - "D-01: cwd resolution reuses cli/lib/cwd, color emit reuses cli/lib/color.build_user_var_octal, title sink reuses tablib.write_tab_title — no parallel copies"
metrics:
  duration: ~30m
  completed: 2026-06-15
  tasks: 3
  files: 7
  net_source_lines: "+420 / -83 across cli/ + tests/ (incl. dead read_current_tab_title removal)"
---

# Phase 06.1 Plan 04: Rich Scene/Recipe Model (cwd/focus/size) + Clean-Pane Spawn + OSC Tab Color Summary

Extended the scene/recipe model with `cwd`/`focus`/`size` (D-05/D-06/D-07), applied cwd at spawn time via `wezterm cli spawn/split-pane --cwd <resolved>` so panes open directly in their target dir with no visible `cd` (D-08 clean pane), and finished the tab-color decouple on the scene path — scene tab color now rides `WEZTERM_TAB_COLOR` via OSC and `scene.lua` no longer depends on `tablib.parse_stored`/`merge_title` (D-02/D-03/D-04).

## What Was Built

### Task 1 — pure scene.lua: parse cwd/focus/size + focus>1 + size% (D-05/D-06/D-07)
- `parse_pane_spec` now accepts `cwd` (carried RAW — resolution is the IO-shell's job), `focus` (boolean: `focus=true` -> `true`, absent -> `nil` so "no focus" is distinguishable from "focus=false"), and `size` (integer percent `1..100`).
- `size` out of range or non-integer is a validate-before-emit error: `error: invalid --pane value '<spec>' — size must be an integer 1..100`.
- The unknown-key error message now lists the extended allowed set: `(expected cmd, color, title, cwd, focus, size)`.
- New `M.validate_focus(parsed_list)` — `(true)` for zero/one focus pane, `(false, "error: more than one pane marked focus=true")` for >1 (D-05).
- New `M.size_percent(parsed, default_pct)` — returns the explicit size or the default (D-06).
- Module stays PURE (purity grep returns 0).

### Task 2 — recipe.lua schema: per-pane cwd/focus/size + top-level cwd + [[pane]] alias + migration (D-04/D-07)
- `pane_table_to_spec` appends `cwd=`/`focus=true`/`size=N` segments; the bare-command fast path is dropped the moment ANY extra field (color/title/cwd/focus/size) is present, so the keyed `cmd=...` form round-trips through the extended `parse_pane_spec`.
- `recipe_to_args` carries top-level `recipe.cwd` into `args.cwd` (the tab-level default cwd panes inherit, D-07).
- `[[pane]]` (singular) is accepted as an alias of `[[panes]]` (D-04); deprecated top-level `color`/`title` remain accepted (migration). Both already worked through `recipe.panes or recipe.pane` + the pass-through; the new round-trip tests lock them.
- Module stays PURE (the only purity-grep hit is the `-- PURE BY CONTRACT: no io.*` comment — see Deviations).

### Task 3 — scene.lua IO-shell: clean-pane --cwd + OSC tab color + size/focus apply + spec (D-01/D-02/D-03/D-06/D-08/D-16)
- Added `require("cli.lib.color")` + `require("cli.lib.cwd")` and a small IO-shell boundary: `launch_dir()` = `os.getenv("PWD")` (RESEARCH Open Q1) and a metatable-backed `env_snapshot()` that defers `os.getenv` so `cwd.lua` stays pure while this module owns the single env trust boundary.
- **Step 0 (validate-before-emit):** every per-pane `cwd` + the tab-level `cwd` is validated via `cwdlib.validate` ($(...)/backtick/unset-$ENV rejected) and `scenelib.validate_focus` rejects >1 focus — both bail with ZERO mux calls (T-06.1-08).
- **Phase A (clean-pane spawn, D-08):** the new-tab spawn and every split-pane pass `--cwd <shquote(resolved)>`, resolving each pane's cwd via `cwdlib.resolve(raw, launch_dir, env)` (default = tab cwd, then launch dir, D-07). A per-pane `size=` overrides the split's equal-share `--percent` via `scenelib.size_percent` (D-06).
- **Tab styling (D-02/D-03/D-04):** if `--color`, emit `WEZTERM_TAB_COLOR` to pane 1's TTY via `color.build_user_var_octal` through the printf-octal send-text path (Pitfall 2 cross-shell); if `--title`, write PURE text via `tablib.write_tab_title`. The `parse_stored`/`merge_title` read-modify-write is gone, and the now-dead `M.read_current_tab_title` was removed.
- **Step 4 (focus, D-05):** activate the `focus=true` pane if present, else default to pane 1.
- **spec.lua / spec_test.lua (D-16):** the `--pane` help string lists `cmd/color/title/cwd/focus/size`, a tab-level `--cwd` flag was added to `scene new`, and `spec_test.lua` asserts both the `--cwd` parse and the advertised segment grammar.

## TDD Gate Compliance

Both pure tasks followed RED -> GREEN; Task 3 is a GREEN-only IO-shell wiring task whose gate is the unit + spec suite (per the plan).
- Task 1: `test(06.1-04)` c8f1985 (RED) -> `feat(06.1-04)` 96137b6 (GREEN)
- Task 2: `test(06.1-04)` b541efd (RED) -> `feat(06.1-04)` 63bfc87 (GREEN)
- Task 3: `feat(06.1-04)` 699f10b (GREEN — IO-shell + spec)

## Verification

- `lua5.4 cli/lib/scene_test.lua` -> 72 passed, 0 failed (RED was the pre-GREEN run).
- `lua5.4 cli/lib/recipe_test.lua` -> 42 passed, 0 failed.
- `lua5.4 tests/cli/spec_test.lua` -> 37 passed, 0 failed (exit 0).
- `./tools/run-tests.sh` -> all 23 files passed (no regression).
- `grep -q -- '--cwd' cli/commands/scene.lua` -> present (clean-pane spawn).
- `grep -q 'WEZTERM_TAB_COLOR' cli/commands/scene.lua` -> present (OSC tab color).
- Non-comment `parse_stored`/`merge_title` references in `scene.lua` -> 0 (encoding dependency removed, D-04).
- scene.lua + recipe.lua purity (real io/os.execute/os.getenv/wezterm calls, comments stripped) -> 0.
- Live spawn `--cwd` round-trip + the refreshed comma-safe seeds are Plan 07's cross-plan scope (integration test under `WEZTERM_INTEGRATION=1`).

## Threat Surface

All threat-register mitigations applied:
- **T-06.1-08** (cwd -> spawn elevation): `cwdlib.validate` rejects `$(...)`/backticks/unset `$ENV` before emit; the resolved path is `shquote`'d before `os.execute` (spawn + split-pane).
- **T-06.1-09** (per-pane command -> send-text): the startup command remains a DISTINCT trailing line, never concatenated into an escape (T-04-02 preserved); the send-text payload is `shquote`'d.
- **T-06.1-10** (WEZTERM_TAB_COLOR OSC): emitted via `color.build_user_var_octal` (base64 value, octal-escaped printf payload) — control bytes neutralized.
- **T-06.1-11** (malformed recipe TOML): `recipe.load_and_map` still pcall-wraps tinytoml — no traceback (unchanged).

No new security surface introduced.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Plan's recipe.lua purity grep is defeated by its own `-n` flag**
- **Found during:** Task 2 GREEN verification.
- **Issue:** the plan's gate `grep -nE '...' cli/lib/recipe.lua | grep -vE '^\s*--' | wc -l | grep -qx 0` returns `1`, not `0`. The single hit is the pre-existing `-- PURE BY CONTRACT: no io.*` comment on line 10. The `grep -n` line-number prefix (`10:-- PURE...`) makes the line start with `10:` not `--`, so the `^\s*--` comment filter never strips it. This was already failing on the committed baseline `recipe.lua` BEFORE my edit (verified via `git show HEAD:cli/lib/recipe.lua | grep ...`), so it is a pre-existing quirk in the plan's verify command, not impurity I introduced.
- **Fix:** verified actual purity with the corrected command (no `-n`): `grep -E '...' cli/lib/recipe.lua | grep -vE '^\s*--' | wc -l` -> `0`. The module has zero real io/os/wezterm calls.
- **Files modified:** none (verification-only).

**2. [Rule 1 - Cleanup] Removed dead `M.read_current_tab_title`**
- **Found during:** Task 3.
- **Issue:** once the tab-level styling stopped using `parse_stored`/`merge_title`, the `M.read_current_tab_title` helper (which read back the legacy `<color>:<title>` stored string) had no remaining caller in the repo (grep across `*.lua` found none).
- **Fix:** deleted the dead function — it is the last consumer of the retired encoding on the scene path, completing the D-04 consolidation.
- **Files modified:** cli/commands/scene.lua
- **Commit:** 699f10b

Otherwise the plan executed as written.

## Known Stubs

None. cwd/focus/size are wired end-to-end (parse -> recipe -> spawn). The live `--cwd` spawn round-trip verification and the refreshed comma-safe seed recipes are intentionally Plan 07's scope (the plan's verification note assigns them there), not stubs in this plan.

## Self-Check: PASSED

- `cli/lib/scene.lua` — FOUND (validate_focus + size_percent + cwd/focus/size parse; pure)
- `cli/lib/recipe.lua` — FOUND (cwd/focus/size segments + top-level cwd; pure)
- `cli/commands/scene.lua` — FOUND (--cwd spawn + WEZTERM_TAB_COLOR; no non-comment parse_stored/merge_title)
- `cli/spec.lua` + `tests/cli/spec_test.lua` — FOUND (--cwd flag + segment grammar registered/asserted)
- Commits c8f1985, 96137b6, b541efd, 63bfc87, 699f10b — all FOUND in git log.
