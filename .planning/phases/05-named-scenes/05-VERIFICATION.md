---
phase: 05-named-scenes
verified: 2026-06-14T00:00:00Z
status: passed
score: 13/13 must-have truths verified (3/3 roadmap success criteria met; both UI-SPEC error-copy gaps remediated in c9c2bd5)
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 11/13 must-have truths verified
  remediation_commit: c9c2bd5
  remediation_summary: >
    Both WARNING gaps fixed and behaviorally re-verified against the built dist/wez,
    then locked with 5 new regression assertions in scene_launch_test.lua that
    exercise the real argparse path (the path the original direct-call tests bypassed).
    Gap 1: cli/spec.lua scene-launch `name` positional changed from :args(1) to
    :args("?") so M.run_launch owns the no-name path — `wez scene launch` now emits
    `error: wez scene launch requires a recipe name (got none)` + the available-recipes
    hint at exit 2. Gap 2: M.run_launch now strips a leading `error: ` from the reused
    validator string, so an invalid layout/color reads `error: scene recipe '<name>'
    is invalid: unknown layout '<value>' — expected one of: ...` with a single prefix.
    Full suite 17/17; scene_launch_test 25/25.
gaps:
  - truth: "No name -> exit 2 with the UI-SPEC usage error + available-recipes hint (or no-recipes guidance)"
    status: resolved
    resolved_in: c9c2bd5
    reason: >
      `scene launch` registers `name` as a REQUIRED positional (`:argument("name", ...):args(1)` in
      cli/spec.lua line 180), so argparse rejects `wez scene launch` (no arg) with its generic
      `Error: missing argument 'name'` BEFORE M.run_launch ever runs. Exit code is 2 (correct), but
      the UI-SPEC-prescribed copy `error: wez scene launch requires a recipe name (got none)` and the
      available-recipes hint block are NEVER emitted through the real CLI. The custom no-name branch in
      cli/commands/scene.lua (lines 466-474) is unreachable dead code. The scene_launch_test "no name"
      assertion passes only because it calls M.run_launch({name=nil}) DIRECTLY, bypassing argparse —
      giving a false "verified by tests" signal (05-03-SUMMARY line 39/68 claims exact copy + exit 2,
      verified by tests).
    artifacts:
      - path: "cli/spec.lua"
        issue: "line 180 — `name` is a required positional (:args(1)); argparse intercepts the no-arg case before run_launch, so the spec'd copy/hint never fire."
      - path: "cli/commands/scene.lua"
        issue: "lines 466-474 — no-name copy + hint block is dead code; unreachable via the real `wez scene launch` dispatch."
      - path: "tests/cli/scene_launch_test.lua"
        issue: "lines 87-90 — exercises run_launch({name=nil}) directly, bypassing argparse; the test does not prove end-to-end CLI behavior."
    missing:
      - "Either make `name` an optional positional (:args('?')) so run_launch owns the no-name UI-SPEC copy + hint block, OR update the UI-SPEC/SUMMARY to accept argparse's generic usage error (exit 2) as the no-name contract and remove the dead branch + the misleading direct-call test."
  - truth: "An unknown layout/color in a recipe yields the EXACT shipped validate_layout/validate_color enum copy"
    status: resolved
    resolved_in: c9c2bd5
    reason: >
      validate_layout/validate_color (cli/lib/scene.lua lines 192, 210) return strings ALREADY prefixed
      with `error: `. In M.run_launch the reframing (cli/commands/scene.lua lines 510-511) strips only its
      own `^error: scene recipe is invalid: ` prefix, so a bad layout/color in a recipe surfaces a DOUBLED
      prefix: `error: scene recipe 'badlayout' is invalid: error: unknown layout 'bogus' — expected one of: ...`.
      The UI-SPEC malformed-recipe row prescribes `error: scene recipe '<name>' is invalid: unknown layout
      '<value>' — expected one of: ...` (single `error:`). The enum WORDING is exact (single source upheld),
      but the composed line has a redundant `error: error:`. No test feeds an invalid layout/color through
      launch, so it went undetected.
    artifacts:
      - path: "cli/commands/scene.lua"
        issue: "lines 508-512 — load_and_map returns layout_err/color_err verbatim (already `error:`-prefixed); run_launch's gsub only removes the `scene recipe is invalid:` framing, leaving a nested `error:`."
      - path: "cli/lib/recipe.lua"
        issue: "lines 130-140 — returns scene.validate_layout/validate_color strings directly as map_err; those strings carry their own `error:` prefix."
    missing:
      - "Strip the leading `error: ` from the validator string before composing the recipe-is-invalid line (or have recipe.lua normalize layout/color reasons to bare text), so the launch error reads `error: scene recipe '<name>' is invalid: unknown layout '...' — expected one of: ...` per the UI-SPEC."
      - "Add a launch test that feeds an invalid layout AND an invalid color recipe and asserts the exact single-prefix UI-SPEC string."
deferred:
  - truth: "macOS parity for launch / completion / seeding"
    addressed_in: "Deferred batched macOS pass (D-18, docs/macos-verification.md)"
    evidence: "CONTEXT D-18 + REQUIREMENTS traceability mark SCEN-05/06 'Linux; macOS deferred D-18'; docs/macos-verification.md exists. Linux is the bar for this phase per the verification method; macOS is known-deferred, not a failure."
---

# Phase 5: Named Scenes Verification Report

**Phase Goal:** Users can save and replay workspace layouts by name, with tab completion and seeded examples on install.
**Verified:** 2026-06-14
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Roadmap Success Criteria (the contract)

| # | Success Criterion | Status | Evidence |
| - | ----------------- | ------ | -------- |
| 1 | A TOML recipe in the scenes dir is launchable by name via `wez scene launch <name>` and produces the SAME result as an equivalent `wez scene new` (SCEN-03/04) | ✓ VERIFIED | `M.run_launch` resolves dir → guards name → reads `<name>.toml` → `recipelib.load_and_map(raw)` → `return M.run_new(mapped)` (scene.lua:517). Single code path, no argv/subprocess/re-implemented geometry (D-03). docker.toml round-trips to `grid`/`teal` + panes `docker stats`/`docker ps`/`docker compose logs -f`/`shell` — the exact specs `run_new` consumes. Delegation test passes (scene_launch_test line 195-207). |
| 2 | `wez scene launch <Tab>` dynamically completes recipe names; add/remove a file updates completion with no manual step (SCEN-05) | ✓ VERIFIED | `scene-names` context (complete.lua:107-118) calls `scene_cmd.list_recipe_names(scene_cmd.scenes_dir())` at call time (no caching). Behavioral: empty dir → no output, exit 0; after seeding → `ai/dev/docker` emitted, exit 0. Both generated zsh+bash scripts carry the nested `scene)→launch)` arm and pass `zsh -n` / `bash -n`. |
| 3 | A fresh install seeds `ai/docker/dev` via copy-if-absent; reinstall never overwrites user edits (SCEN-06) | ✓ VERIFIED | Behavioral: seed into empty dir → 3 `seeded scene recipe:` lines; reseed after a user edit → 3 `kept existing scene recipe:` lines; user edit survived. D-06 invariant holds: seeds live in top-level `scenes/` (OUTSIDE `config/wezterm-setup/`), setup.sh STEP 4 `cp -R` cannot touch them; seeder is the only writer of `SETUP_DIR/scenes` (setup.sh STEP 4b). TOCTOU re-check at write time (seed_scenes.lua:176). |

**All 3 roadmap success criteria — the phase goal — are met.**

### PLAN Must-Have Truths

| #   | Truth   | Status     | Evidence       |
| --- | ------- | ---------- | -------------- |
| 1 | Valid TOML recipe parses into a recipe table | ✓ VERIFIED | recipe.lua `load_and_map`; recipe_test 28/28 pass |
| 2 | Malformed TOML → `could not parse TOML at line <N>`, no traceback | ✓ VERIFIED | Behavioral: `broken.toml` → `error: scene recipe 'broken' is invalid: could not parse TOML at line 1`, exit 1, no traceback (pcall wrap recipe.lua:115-123) |
| 3 | Unknown layout/color → EXACT shipped enum copy | ✗ FAILED | Enum wording is exact (single source), but composed launch line shows a DOUBLE `error: error:` prefix — see gap 2 |
| 4 | Recipe maps to run_new args (layout/pane[]/color/title) | ✓ VERIFIED | `recipe_to_args` (recipe.lua:83-95); docker round-trip confirmed |
| 5 | `command='shell'` → literal `shell` spec | ✓ VERIFIED | `pane_table_to_spec` (recipe.lua:65); docker pane[4]=`shell` |
| 6 | Bare single-field command → command string as-is | ✓ VERIFIED | recipe.lua:68-70; docker `docker stats`/`docker ps` round-trip bare |
| 7 | Multi-field pane → `cmd=..., color=..., title=...` | ✓ VERIFIED | recipe.lua:71-74; recipe_test asserts |
| 8 | `guard_name` rejects empty/`/`/`..` before I/O | ✓ VERIFIED | recipe.lua:35-46; behavioral `../../etc/passwd` → exit 1, guard error pre-`io.open` |
| 9 | Seed `ai/docker/dev` into scenes dir; copy-if-absent | ✓ VERIFIED | Behavioral seed/reseed (SCEN-06) |
| 10 | `seeded` / `kept existing` exact messaging | ✓ VERIFIED | Behavioral output matches UI-SPEC row 126 verbatim |
| 11 | `cp -R` never places/overwrites under scenes/ (D-06) | ✓ VERIFIED | No scenes/ in config tree; setup.sh STEP 4b is sole writer |
| 12 | 3 seeds encode the SCEN-06 table exactly | ✓ VERIFIED | dev: tall/green/2 shell; ai: tall/purple/2 shell; docker: grid/teal/4 incl docker stats/ps/compose |
| 13 | No name → exit 2 with UI-SPEC usage error + hint | ✗ FAILED | Exit 2 correct, but argparse emits generic copy; spec'd copy+hint is dead code — see gap 1 |
| 14 | scene launch delegates to M.run_new (one path) | ✓ VERIFIED | scene.lua:517 `return M.run_new(mapped)` |
| 15 | Dynamic scene-names, single provider, empty→exit 0 | ✓ VERIFIED | complete.lua:107-118 reuses `list_recipe_names`; behavioral |
| 16 | Generated zsh/bash carry scene)→launch) arm, pass -n | ✓ VERIFIED | completions.lua:163-169 (zsh), 249-256 (bash); `zsh -n`/`bash -n` OK |

**Score:** 11/13 distinct must-have truths verified (truths 3 and 13 are the two FAILED items; remaining duplicates across plans collapse into these 16 rows). All 3 roadmap success criteria PASS.

### Deferred Items

| # | Item | Addressed In | Evidence |
|---|------|-------------|----------|
| 1 | macOS parity (launch/completion/seeding) | Deferred macOS pass (D-18) | REQUIREMENTS traceability + docs/macos-verification.md; Linux is the phase bar per the verification method. |

### Required Artifacts

| Artifact | Expected    | Status | Details |
| -------- | ----------- | ------ | ------- |
| `cli/vendor/tinytoml.lua` | Pinned pure-Lua TOML decoder | ✓ VERIFIED | 1550 lines; provenance header pins tag 1.0.0, commit 663e319, SHA-256 of upstream pre-header file recorded, MIT license. |
| `cli/lib/recipe.lua` | loader + mapper + guard | ✓ VERIFIED | exports load_and_map/recipe_to_args/guard_name; pure (no io); recipe_test 28/28. |
| `cli/commands/scene.lua` | run_launch + scenes_dir + list_recipe_names + routing | ✓ VERIFIED | run_launch delegates to run_new; M.run branches launch (scene.lua:529-531). |
| `cli/commands/seed_scenes.lua` | copy-if-absent seeder | ✓ VERIFIED | plan_seed (pure) + run (FS glue + TOCTOU); seed_scenes_test pass. |
| `cli/commands/complete.lua` | scene-names context | ✓ VERIFIED | complete_test 26/26. |
| `cli/commands/completions.lua` | nested scene)→launch) arm both shells | ✓ VERIFIED | completions_test pass; -n syntax OK. |
| `scenes/{dev,ai,docker}.toml` | SCEN-06 table verbatim | ✓ VERIFIED | values match the locked table. |
| `cli/spec.lua` | scene launch <name> + seed-scenes registered | ✓ VERIFIED | lines 121, 179-180. (line 180 `:args(1)` is the root of gap 1.) |

### Key Link Verification

| From | To  | Via | Status |
| ---- | --- | --- | ------ |
| recipe.lua | cli.vendor.tinytoml | `pcall(require, "cli.vendor.tinytoml")` dual-resolution | ✓ WIRED (recipe.lua:20-21) |
| recipe.lua | cli.lib.scene | validate_layout/validate_color reuse | ✓ WIRED (recipe.lua:26,130,136) |
| scene.lua run_launch | scene.lua run_new | in-process call with mapped args | ✓ WIRED (scene.lua:517) |
| complete.lua | scene.lua list_recipe_names/scenes_dir | scene_names provider | ✓ WIRED (complete.lua:34,108) |
| completions.lua | `wez __complete scene-names` | nested arm both generators | ✓ WIRED (completions.lua:165,252) |
| setup.sh | `wez seed-scenes` | STEP 4b decision-free invocation | ✓ WIRED (setup.sh:100-101) |
| spec.lua | seed-scenes command | parser:command + SUBCOMMANDS/CATEGORIES | ✓ WIRED (spec.lua:45,60,121) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
| -------- | ------- | ------ | ------ |
| Empty scenes-dir completion | `wez __complete scene-names` | no output, exit 0 | ✓ PASS |
| Seed into empty dir | `wez seed-scenes` | 3 `seeded scene recipe:` lines, exit 0 | ✓ PASS |
| Dynamic completion after seed | `wez __complete scene-names` | `ai/dev/docker`, exit 0 | ✓ PASS |
| Copy-if-absent reseed | `wez seed-scenes` (after user edit) | 3 `kept existing`, user edit survived | ✓ PASS |
| Unknown name | `wez scene launch nonexistent` | not-found + sorted hint + try-line, exit 1 | ✓ PASS |
| Malformed TOML | `wez scene launch broken` | clean `could not parse TOML at line 1`, exit 1 | ✓ PASS |
| Missing layout | `wez scene launch nolayout` | `missing required field 'layout'`, exit 1 | ✓ PASS |
| Bad layout | `wez scene launch badlayout` | **double `error: error:` prefix**, exit 1 | ✗ FAIL (gap 2) |
| Path traversal | `wez scene launch ../../etc/passwd` | guard error, exit 1, pre-io.open | ✓ PASS |
| No name (real CLI) | `wez scene launch` | argparse generic `Error: missing argument 'name'`, exit 2 (NOT the UI-SPEC copy/hint) | ✗ FAIL (gap 1) |
| zsh script syntax | `wez completions zsh \| zsh -n` | OK | ✓ PASS |
| bash script syntax | `wez completions bash \| bash -n` | OK | ✓ PASS |

### Test Suite

`bash tools/run-tests.sh` → **all 17 files passed** (recipe_test 28/28, complete_test 26/26, scene_launch_test/seed_scenes_test/completions_test/spec_test all PASS). NOTE: the green suite masks gaps 1 and 2 — the no-name test calls `run_launch` directly (bypassing argparse), and no test feeds an invalid layout/color through launch.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
| ----------- | ----------- | ------ | -------- |
| SCEN-03 | 05-01, 05-03 | ✓ SATISFIED | TOML recipe loaded by name; clean errors; guard. (One error sub-path copy deviates — gap 2.) |
| SCEN-04 | 05-03 | ✓ SATISFIED | Structural equivalence via single `run_new` path; round-trip confirmed. |
| SCEN-05 | 05-04 | ✓ SATISFIED | Dynamic completion, single provider, empty→exit 0, both shells valid. |
| SCEN-06 | 05-02 | ✓ SATISFIED | Copy-if-absent seeding; D-06 no-clobber invariant holds; exact table. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
| ---- | ---- | ------- | -------- | ------ |
| cli/commands/scene.lua | 466-474 | Unreachable no-name branch (dead code) | ⚠️ Warning | UI-SPEC no-name copy/hint never fires via real CLI (gap 1). |
| cli/commands/scene.lua | 508-512 | Error-prefix not normalized before composition | ⚠️ Warning | Double `error: error:` on bad layout/color (gap 2). |

No `TODO`/`FIXME`/`XXX`/`HACK` debt markers found in the phase's modified files. The `COMMA CAVEAT` note (recipe.lua:56-61) is a documented, intentional v1 limitation that the 3 seeds avoid — not a debt marker.

### Human Verification Required

None blocking. The launched scene's live pane geometry/colors/titles are inherited verbatim from Phase 4 (SCEN-04 equivalence) and were verified in Phase 4; the launch path builds no new visual mechanism (D-03), so no new human visual check is introduced by this phase. macOS parity is a known-deferred batched pass (D-18), not a Phase 5 human-verify item.

### Gaps Summary

The phase GOAL is achieved: all three roadmap success criteria (launch-by-name + structural equivalence, dynamic completion, copy-if-absent seeding) are behaviorally verified on Linux, and the SCEN-04 single-code-path guarantee is genuine (not a divergent reimplementation). The two gaps are UI-SPEC copywriting/correctness defects on launch ERROR sub-paths, both surfaced by my own behavioral runs and both masked by tests that don't exercise the real dispatch:

1. **No-name copy is unreachable.** `name` is a required positional in spec.lua, so argparse short-circuits the no-arg case with a generic message before `run_launch`'s spec'd copy + hint block can run. Exit code (2) is right; the copy is wrong. The 05-03-SUMMARY "verified by tests / exact copy" claim is false for the real CLI path.
2. **Double `error:` prefix on bad layout/color.** The reused validator strings already carry an `error:` prefix that the launch composition does not strip, yielding `error: scene recipe '<name>' is invalid: error: unknown layout ...`.

Both are small, localized fixes. Neither blocks the phase goal, but both contradict the locked UI-SPEC and a SUMMARY accuracy claim, so the phase status is `gaps_found` (WARNING-level) pending either a copy fix or a UI-SPEC/SUMMARY override.

---

_Verified: 2026-06-14_
_Verifier: Claude (gsd-verifier)_
