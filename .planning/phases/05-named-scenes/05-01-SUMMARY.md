---
phase: 05-named-scenes
plan: 01
subsystem: cli-recipe-core
tags: [toml, recipe, scene, pure-core, tdd, vendoring, supply-chain]
requires:
  - cli/lib/scene.lua (validate_layout, validate_color, parse_pane_spec grammar)
  - cli/commands/scene.lua (M.run_new args contract — SCEN-04 seam)
provides:
  - cli/vendor/tinytoml.lua (vendored pure-Lua TOML 1.1.0 decoder, pinned 1.0.0)
  - cli.lib.recipe.load_and_map (raw TOML string -> run_new args | nil, errmsg)
  - cli.lib.recipe.recipe_to_args (pure recipe table -> args mapper)
  - cli.lib.recipe.guard_name (path-traversal name guard, T-05-01)
affects:
  - 05-02 (seed-scenes round-trip — consumes recipe shape)
  - 05-03 (scene launch IO-shell — reads file, calls load_and_map + run_new)
tech-stack:
  added:
    - tinytoml 1.0.0 (vendored, MIT, FourierTransformer/tinytoml @ 663e319)
  patterns:
    - dual-resolution require (cli.vendor.X then bare X) — mirrors dkjson
    - pure-core / IO-shell split (parse via load_from_string, no io.* in lib)
    - validator reuse (single-source UI-SPEC enum copy, no duplication)
    - bare-command fast path for recipe->--pane spec mapping (comma-safe seeds)
key-files:
  created:
    - cli/vendor/tinytoml.lua
    - cli/lib/recipe.lua
    - cli/lib/recipe_test.lua
  modified: []
decisions:
  - "recipe panes key is `panes` (matches README/UI-SPEC [[panes]]); `pane` accepted as fallback alias"
  - "Option-1 bare-command fast path: single-field panes pass as bare strings; only multi-field panes use cmd=,color=,title= (comma caveat documented inline)"
  - "load_and_map error reasons use the no-name form `error: scene recipe is invalid: ...`; the per-file `'<name>'` framing is the 05-03 IO-shell's job"
  - "upstream tinytoml tag is `1.0.0` (no leading v); the plan's v1.0.0 URL was a typo, corrected in the vendored header"
metrics:
  duration: ~12m
  completed: 2026-06-13
  tasks: 2
  files: 3
  commits: 3
  tests: "28/28 recipe_test assertions; full suite 15/15 files green"
---

# Phase 5 Plan 01: Recipe Core (Vendored TOML + Pure Loader/Mapper/Guard) Summary

Vendored the pure-Lua `tinytoml` 1.0.0 TOML decoder and built `cli/lib/recipe.lua` — a PURE
loader/mapper/guard that parses a recipe TOML string, validates layout/color by reusing the shipped
`cli/lib/scene.lua` validators, and maps the recipe into the exact `args` table
`cli/commands/scene.lua` `M.run_new` consumes (SCEN-04 structural-equivalence seam), plus the
path-traversal name guard (T-05-01). Full TDD RED→GREEN; no refactor commit needed.

## What Was Built

### Task 1 — Vendored tinytoml 1.0.0 (commit `cbeb1eb`, `feat`)
- `cli/vendor/tinytoml.lua` — single pure-Lua file, provenance header records upstream URL,
  tag `1.0.0` (commit `663e319179c7800b414afbe58fe29bbe5cba3dec`), and the fetched-file SHA-256
  (`0a0ad7e…`). Declares `_LICENSE="MIT"`, `_VERSION="tinytoml 1.0.0"`, ends `return tinytoml`.
- Zero `require(` calls (no transitive module loads). Bundles automatically via the existing
  `tools/build.sh` `cli/**/*.lua` glob — no build-script edit.
- **Human-approved** supply-chain review (threat T-05-SC, blocking-human checkpoint).
- The file was independently SHA-256-verified against the upstream tag before this continuation
  agent committed it; not re-fetched or modified.

### Task 2 — Pure recipe loader/mapper/guard, TDD (commits `d5aedd3` test / `053dbf6` feat)
- `cli/lib/recipe.lua` (145 lines) exports `load_and_map`, `recipe_to_args`, `guard_name`.
  - `guard_name(name)` — rejects empty/nil, any `/`, any `..`; returns `true` otherwise. Runs
    before any I/O (T-05-01 mitigation).
  - `recipe_to_args(recipe)` — pure transform. Reads `recipe.panes` (fallback `recipe.pane`).
    Bare-command fast path: no command / `command=="shell"` → `"shell"`; single-field command-only
    → the command string as-is; multi-field → `"cmd=…, color=…, title=…"`. Accepts `cmd` alias.
  - `load_and_map(raw_string)` — `pcall(toml.parse, raw, {load_from_string=true})` (tinytoml RAISES,
    Pitfall 1). On parse failure, extracts `line (%d+)` → `"could not parse TOML at line <N>"`
    (never a traceback, T-05-02). On success: missing `layout` → UI-SPEC reason; then reuses
    `scene.validate_layout` / `scene.validate_color` for the EXACT shipped error strings.
- `cli/lib/recipe_test.lua` (177 lines) — mirrors `scene_test.lua`'s check/eq/teq + deep_eq harness;
  28 assertions covering every behavior bullet.

## Verification

- `lua5.4 cli/lib/recipe_test.lua` → `28 passed, 0 failed`, exit 0.
- `make test` → `15 file(s) passed` (no regression in scene/title/install/uninstall/config suites).
- Pure-core grep clean: `grep -nE 'io%.|os%.execute|os%.getenv|wezterm' cli/lib/recipe.lua`
  (comments stripped) returns nothing.
- Dual-resolution idiom present: `pcall(require, "cli.vendor.tinytoml")` matches.
- Validator reuse confirmed: `require("cli.lib.scene")` + `scene.validate_layout`/`validate_color`
  calls; no second literal enum list authored in recipe.lua.
- Task 1 acceptance: `grep -c 'require(' cli/vendor/tinytoml.lua` == 0; license/version/return shape
  confirmed; `lua5.4 -e 'assert(type(require("cli.vendor.tinytoml").parse)=="function")'` exits 0.

## Threat Mitigations Applied

- **T-05-SC** (supply-chain tampering): pinned tag + SHA-256 provenance header + human review.
- **T-05-01** (path traversal): `guard_name` rejects `/` and `..` before any I/O (test-proven).
- **T-05-02** (DoS/crash on malformed TOML): `pcall` around `toml.parse`, error translated to
  UI-SPEC copy — never a Lua traceback (test-proven via `2f`).
- **T-05-03** (input validation): layout/color reuse the shipped enum validators — a recipe cannot
  inject an out-of-enum value.

## Deviations from Plan

None affecting behavior. Two clarifications resolved at the approved checkpoint:
1. Upstream tinytoml tags WITHOUT a leading `v` — the plan's `v1.0.0` raw URL 404s; the correct tag
   is `1.0.0`. The vendored header records the corrected URL + tag (human-approved).
2. No REFACTOR commit: the GREEN implementation was already clean (extracted `pane_table_to_spec`,
   single-source validators) — TDD flow commits refactor only if changes are made.

## Known Stubs

None. `cli/lib/recipe.lua` is fully wired against the live tinytoml decoder and the shipped scene
validators; every exported function is exercised by passing tests.

## Self-Check: PASSED

- FOUND: cli/vendor/tinytoml.lua, cli/lib/recipe.lua, cli/lib/recipe_test.lua
- FOUND commits: cbeb1eb (vendor), d5aedd3 (RED test), 053dbf6 (GREEN feat)

## TDD Gate Compliance

- RED gate: `d5aedd3` (`test(05-01)`) — failing test, module absent, exit 1. ✓
- GREEN gate: `053dbf6` (`feat(05-01)`) — 28/28 assertions pass. ✓
- REFACTOR gate: not needed (no changes; GREEN was already clean).
