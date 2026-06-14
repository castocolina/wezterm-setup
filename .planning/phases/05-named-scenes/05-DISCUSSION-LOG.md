# Phase 5: Named Scenes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-13
**Phase:** 5-named-scenes
**Areas discussed:** Recipe format, launch≡new mechanism, Seeding on install, Recipe dir & names

---

## Recipe format

| Option | Description | Selected |
|--------|-------------|----------|
| TOML only | One `.toml` per scene; vendor a pure-Lua TOML parser; safe declarative data | ✓ |
| Both TOML + Lua | Accept `.toml` and `.lua`; Lua eval'd; precedence rule needed | |
| Lua only | `.lua` returning a table; zero new dep but executable + less hand-edit-friendly | |

**User's choice:** "Al igual que como hicimos con kitty, un `.toml` por scene y el engine lua que lo parsee y lo ponga en la jugada."
**Notes:** TOML-only, one file per scene, parsed by the Lua engine into the scene spec — same model proven in kitty-setup. Implies vendoring a pure-Lua TOML parser into the single binary (zero-dep). → CONTEXT D-01/D-02.

---

## launch≡new mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse pure core in-process | Parse TOML → internal spec table → same `cli/lib/scene.lua` orchestration path; equivalence is structural | ✓ |
| Build argv → shell out | Construct a `wez scene new ...` command line and exec it; literal but adds subprocess + re-quoting surface | |

**User's choice:** Reuse pure core in-process.
**Notes:** One code path = SCEN-04 equivalence by construction, no subprocess. → CONTEXT D-03.

---

## Seeding on install

| Option | Description | Selected |
|--------|-------------|----------|
| Lua command (`wez seed-scenes`) | Dedicated subcommand owns per-recipe copy-if-absent; `setup.sh` is decision-free glue (D-01) | ✓ |
| Fold into install-state | Extend `wez install-state` to also seed; fewer commands but mixes concerns | |
| Per-file logic in setup.sh | Bash `[ -f ]` guard per file; decision logic back in installer (against D-01) | |

**User's choice:** Lua command (`wez seed-scenes`).
**Notes:** Matches the `install-state` precedent — pure, fixture-testable. Triggered the D-06 invariant: scenes co-located under the managed tree must be excluded from the wholesale `cp -R` so user edits survive (SCEN-06). → CONTEXT D-07/D-08.

---

## Recipe dir & names

| Option | Description | Selected |
|--------|-------------|----------|
| `~/.config/wezterm-setup/scenes/` | Honor REQUIREMENTS.md literally — dedicated standalone XDG dir | |
| `~/.config/wezterm/wezterm-setup/scenes/` | Co-locate under the existing managed config tree (`SETUP_DIR`) | ✓ |

**User's choice:** `~/.config/wezterm/wezterm-setup/scenes/` (co-located).
**Notes:** Deviates from REQUIREMENTS.md / ROADMAP.md / UI-SPEC, which all said the standalone path. Follow-up decision: **update those locked docs to the co-located path** (chosen over recording in CONTEXT-only or reverting). All three artifacts were updated this phase. `<name>` = basename without extension → `<dir>/<name>.toml`. → CONTEXT D-04/D-05/D-06.

---

## Claude's Discretion

- Pure-Lua TOML parser choice (must be zero-dep, relative-`require`-safe, luastatic-bundleable).
- Exact TOML key names / pane-table shape, under the D-02 1:1-to-`scene new` mapping.
- Exact seeding subcommand name and in-repo location of the seed `.toml` files.
- The precise `setup.sh` change excluding `scenes/` from `cp -R` + invoking the seeder.
- Whether the recipe loader/mapper is a new `cli/lib/recipe.lua` or folded into `cli/lib/scene.lua`.

## Deferred Ideas

- `wez scene save` (capture a running tab into a recipe) — own capability, not SCEN-03..06.
- Lua-format / executable recipes — rejected for v1 (TOML-only).
- Standalone `~/.config/wezterm-setup/scenes/` path — superseded by D-04.
- Non-TTY/CI launch confirmation output — UI-SPEC keeps launch silent (Phase 4 D-09).
