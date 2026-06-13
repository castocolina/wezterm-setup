---
phase: 04-ad-hoc-scenes
verified: 2026-06-13T13:10:00Z
status: passed
score: 3/3 roadmap success criteria verified (12/12 load-bearing decisions VERIFIED)
overrides_applied: 0
gaps: []
human_verification: []
warnings:
  - "scene_test.lua and complete_test.lua live under cli/ (not tests/), so `make test` / run-tests.sh does NOT discover them. They pass when run directly (53/0 and 18/0), but are absent from the automated suite — a CI coverage gap, not a goal gap."
  - "The `make test` run reports a doctor core-gate FAIL (`module 'wezterm-setup.keybindings' not found`). This is unrelated Phase-1 install/config noise from running doctor against an installed config from the test CWD (already tracked in memory phase4-paused-and-foundational-bugs); the run-tests harness still reports all 8 files passed and it does not touch any Phase 4 artifact."
---

# Phase 4: Ad-hoc Scenes Verification Report

**Phase Goal:** Users can launch a fully configured multi-pane tab in one command without writing a recipe file (`wez scene new` with layout and styled panes).
**Verified:** 2026-06-13T13:10:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth (Success Criterion) | Status | Evidence |
|---|---------------------------|--------|----------|
| 1 | `wez scene new` accepts layout, pane count (derived), per-pane startup commands, tab color, and tab title as arguments and produces a correctly configured tab | ✓ VERIFIED | spec parses `scene new --layout tall --pane a --pane b --color blue --title x` → `command=scene scene_cmd=new layout=tall color=blue title=x #pane=2` (live run). Pipeline in `cli/commands/scene.lua:124-352` validates → reads topology → spawns/splits → styles → set-tab-title → focus. Repros confirm a real built tab (`h-scene-tall.md:55-72`). |
| 2 | All four required layouts (`tall`, `tall:mirrored`, `grid`, `horizontal`) produce visually correct pane arrangements and accept per-pane startup commands | ✓ VERIFIED | `plan_splits` (`cli/lib/scene.lua:61-132`) implements all 4; 5 headless-mux repros record real topology: tall main-left col0 / mirrored main-right col41 / grid 3×2 N=5 no placeholder / horizontal 19/19/19/20 equal-width. Per-pane `cmd=` runs + D-08 persistence confirmed. |
| 3 | Completion is updated: `wez scene new --layout <Tab>` completes layout names; all `wez scene new` flags complete | ✓ VERIFIED | `wez __complete scene-layouts` → `tall\ntall:mirrored\ngrid\nhorizontal`, exit 0 (live run). Flag completion via spec walker (D-16); zsh/bash scripts reference subcommand `scene` (run-tests output). `cli/commands/complete.lua:90-102`. |

**Score:** 3/3 roadmap success criteria verified.

### Load-Bearing Decision Verification

| Decision | What it requires | Status | Evidence (file:line) |
|----------|------------------|--------|----------------------|
| D-01 pane count derived from `--pane` count | No `--panes` flag; N = #--pane | ✓ VERIFIED | `scene.lua:174` `n = #parsed`; spec has no count flag (`spec.lua:160-167`) |
| D-02 geometry (4 layouts scale to N) | tall/mirrored/grid/horizontal equal-share at arbitrary N | ✓ VERIFIED | `scene.lua:61-132` + tests `scene_test.lua:50-102`; repros confirm real geometry |
| D-06 `--pane` grammar | bare cmd / `shell` / `key=value` order-independent, trimmed | ✓ VERIFIED | `scene.lua:142-167`, tests `2a-2g` `scene_test.lua:108-130` (incl. spaced D-06 form) |
| D-07 title resolution | explicit `title=` overrides; else auto from cmd first-word; `shell` gets none | ✓ VERIFIED | `commands/scene.lua:255-269`; explicit→`resolve_title_str`, else cmd first word; shell skipped |
| D-08 run-in-shell / pane persists | startup cmd sent as a distinct trailing line, pane survives | ✓ VERIFIED | `commands/scene.lua:297-299` (cmd appended as own line, not exec); `h-scene-tall.md:66-67` htop persists |
| D-09 clean panes | no raw OSC residue; printf+clear path | ✓ VERIFIED | `commands/scene.lua:284-293` printf-octal + `clear`; `h-scene-tall.md:68-71` `grep -E '11;#\|1337;\|SetUserVar'` → no match |
| D-10/D-11/D-12 materialization | 1-pane→reuse same tab; ≥2→new tab same window; exact N, never N+1 | ✓ VERIFIED | `scene.lua:249-270` (pure decider, tests `7a/7b`); `h-scene-materialization.md` both cases: reuse 1→2 same tab; new-tab same window, original intact, exactly N=2 |
| D-16 spec-driven completion | single source `M.LAYOUTS`; validate + complete derive from it | ✓ VERIFIED | `scene.lua:176-194` (LAYOUTS → LAYOUT_SET → validate_layout); `complete.lua:90-92` iterates `scene.LAYOUTS`; tests `8a-8c`, `complete_test` (18/0) |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `cli/lib/scene.lua` | pure core: plan_splits, parse_pane_spec, validators, decide_materialization, M.LAYOUTS | ✓ VERIFIED | 272 lines, all exports present, provably pure (no mux/IO), 53 tests green |
| `cli/lib/scene_test.lua` | fixture suite | ✓ VERIFIED | 53 assertions, exit 0 (run directly) |
| `cli/commands/scene.lua` | live orchestrator M.run_new/M.run | ✓ VERIFIED | 391 lines; full validate→spawn/split→style→tab→focus pipeline; loads under lua5.4 |
| `cli/spec.lua` | scene argspec | ✓ VERIFIED | `spec.lua:155-167`; parses correctly, `scene` in subcommand_names |
| `cli/commands/complete.lua` | scene-layouts context | ✓ VERIFIED | `complete.lua:90-102`; emits 4 names exit 0 |
| `docs/repro/h-scene-{tall,tall-mirrored,grid,horizontal,materialization}.md` | recorded e2e | ✓ VERIFIED | All 5 exist, filled with real observed topology + PASS verdicts (not templates) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| commands/scene.lua | lib/scene.lua | `require("cli.lib.scene")` | ✓ WIRED | `commands/scene.lua:41`; calls plan_splits/parse_pane_spec/validators/decide_materialization |
| commands/scene.lua | commands/pane.lua | MUTED_BG / build_osc11 / build_osc1337 | ✓ WIRED | `commands/scene.lua:42,246-268`; symbols confirmed in pane.lua:38,100,126 |
| commands/scene.lua | commands/tab.lua | parse_stored / merge_title / write_tab_title | ✓ WIRED | `commands/scene.lua:43,327-339`; signatures match tab.lua:78,97,150 |
| commands/scene.lua | wezterm cli | spawn/split-pane/send-text/set-tab-title/activate-pane/list | ✓ WIRED | `commands/scene.lua:75,196,214,302,347` |
| spec.lua | commands/scene.lua | dispatcher allow-list (unchanged) | ✓ WIRED | `wez.lua` lazily requires `cli.commands.scene` from `subcommand_names()`; no dispatcher edit |
| complete.lua | lib/scene.lua | `require("cli.lib.scene").LAYOUTS` | ✓ WIRED | `complete.lua:29,92` |

### Behavioral Spot-Checks (run live, headless — no WezTerm session)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full suite | `make test` | run-tests: all 8 file(s) passed (exit 0) | ✓ PASS |
| Scene pure core | `lua5.4 cli/lib/scene_test.lua` | scene_test: 53 passed, 0 failed | ✓ PASS |
| Completion context | `lua5.4 cli/commands/complete_test.lua` | complete_test: 18 passed, 0 failed | ✓ PASS |
| Arg parse end-to-end | `spec:parse({scene,new,...})` | command=scene scene_cmd=new layout=tall color=blue title=x #pane=2 | ✓ PASS |
| Layout completion | `wez __complete scene-layouts` | tall / tall:mirrored / grid / horizontal, exit 0 | ✓ PASS |
| Zero --pane error | `wez scene new --layout grid` | `error: wez scene new requires at least one --pane (got 0)`, exit 2 | ✓ PASS |
| Unknown layout error | `wez scene new --layout bogus --pane shell` | exact UI-SPEC string, exit 2, zero mux calls | ✓ PASS |
| Unknown color error | `... --color mauve` | exact UI-SPEC string, exit 2 | ✓ PASS |
| Malformed --pane error | `--pane 'cmd=htop,foo=bar'` | exact UI-SPEC string, exit 2 | ✓ PASS |

### Skeptical Check: tall/mirrored geometry (the prior "test mirrors implementation" failure mode)

The prompt flagged that this phase previously had a unit test asserting the planner's own *inverted* geometry model (a test that mirrored the implementation rather than reality). **This is resolved and independently cross-validated:**

- Fix commit `cab0a55` corrected both the implementation AND the test to the real WezTerm `split-pane --<dir>` semantics (the NEW pane lands on `<dir>`, so to keep main LEFT the first stack split goes RIGHT).
- Implementation (`scene.lua:75`): `first_dir = (layout == "tall:mirrored") and "left" or "right"`.
- Test (`scene_test.lua:58-68`) now asserts tall→`right` first split, mirrored→`left`.
- **Ground-truth corroboration independent of the planner model:** the repros record actual mux column positions — `h-scene-tall.md` main at `col=0` (LEFT), `h-scene-tall-mirrored.md` main at `col=41` (RIGHT). Real topology, not the model's self-assertion. The two agree. Failure mode closed.

### Anti-Patterns Found

None blocking. `cli/lib/scene.lua` returns `{}` defensively for unknown layout (`scene.lua:131`) but that path is gated by `validate_layout` upstream — not a stub. No TBD/FIXME/XXX debt markers in any Phase 4 file. No hollow data: all rendered data flows from real `wezterm cli list` topology and validated pane ids.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SCEN-01 | 04-02 | Launch ad-hoc multi-pane tab with per-pane commands + styling | ✓ SATISFIED | Live pipeline + 5 repros |
| SCEN-02 | 04-01, 04-03 | Four layouts produce correct arrangements | ✓ SATISFIED | plan_splits + geometry repros |

### Human Verification Required

None outstanding. The visual color-rendering checks (per-pane OSC-11 backgrounds, tab accent) — the only items grep cannot verify — were already performed in a live GUI session with explicit user sign-off, recorded in each repro's "Observed" section (`h-scene-tall.md:73-74`, etc.). Geometry/materialization/clean-pane were verified headlessly against a real mux (stronger than by-eye).

### Gaps Summary

No goal gaps. Phase 4 delivers a working `wez scene new` on Linux: all 3 roadmap success criteria and all 8 load-bearing decision groups are verified in code, tests, and recorded e2e evidence that independently corroborates the implementation's model.

Two non-blocking WARNINGS (do not affect the phase goal):

1. **Scene unit tests are outside the automated suite.** `scene_test.lua` (53) and `complete_test.lua` (18) live under `cli/lib/` and `cli/commands/`, but `tools/run-tests.sh` only discovers `tests/**/*_test.lua`. They pass when run directly, but a future regression in `cli/lib/scene.lua` would NOT be caught by `make test`. Recommend moving/symlinking them under `tests/` (or broadening discovery) so the scene core is guarded by CI. This is a maintainability gap for Phase 5, not a Phase 4 deliverable miss.
2. **Doctor core-gate noise in `make test`.** The harness prints a `module 'wezterm-setup.keybindings' not found` doctor FAIL — a known Phase-1 install/config issue (already tracked) triggered by running doctor against an installed config from the test CWD. It is orthogonal to Phase 4 and the run-tests aggregate still reports all 8 files passed.

---

_Verified: 2026-06-13T13:10:00Z_
_Verifier: Claude (gsd-verifier)_
