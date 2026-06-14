# Phase 5: Named Scenes - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 5 delivers **saved, named scene recipes** layered on top of Phase 4's live `wez scene new`
orchestration. Four capabilities (SCEN-03..06):

- **`wez scene launch <name>`** — load a recipe file by name and materialize it, producing the
  **same result** as the equivalent `wez scene new` call (SCEN-04).
- **Recipe files** — one **TOML** file per scene under `~/.config/wezterm/wezterm-setup/scenes/`,
  parsed by the Lua engine into the scene spec (SCEN-03).
- **Dynamic recipe-name tab completion** — `wez scene launch <Tab>` completes from the recipe files
  present on disk, with no manual regeneration when files are added/removed (SCEN-05).
- **Seeded examples on install** — three recipes (`ai`, `docker`, `dev`) placed **copy-if-absent** so
  user edits survive reinstall (SCEN-06).

**This is the PERSISTENCE + DISCOVERY layer over Phase 4.** It invents no new scene-building
mechanism: launch reuses the Phase 4 pure core verbatim. The net-new work is (1) a TOML recipe
loader, (2) a recipe→spec mapping, (3) a `scene-names` completion context, and (4) a copy-if-absent
seeder owned by a Lua command.

**The launched scene's visual contract** (geometry, palette, clean-pane bar, titles) is inherited
verbatim from Phase 4 via the SCEN-04 equivalence — NOT re-specified here (see `05-UI-SPEC.md`).

**macOS:** Linux-first, designed cross-platform (D-18). Path resolution and file I/O are
platform-neutral; macOS verified in the deferred Mac pass.
</domain>

<decisions>
## Implementation Decisions

### Recipe format (SCEN-03)
- **D-01:** **TOML only — one `.toml` file per scene**, parsed by the Lua engine which maps it into
  the scene spec ("lo parsea y lo pone en la jugada", same model as kitty-setup). **Rejected:** Lua
  recipes (executable code at launch; TOML is the friendlier hand-edit format) and dual TOML+Lua
  (extra loader + precedence rule for no real gain). Implies **vendoring a pure-Lua TOML parser**
  into the luastatic single binary (zero-dep constraint — parser choice is the researcher's, but it
  MUST be pure Lua, no C ext, relative-`require`-safe per `cli-language.md`).
- **D-02:** **The recipe schema mirrors the `wez scene new` surface 1:1.** Top-level `layout`,
  `color`, `title`; an array of pane tables (`[[panes]]` or `[[pane]]` — exact key is the planner's)
  each with `command`/`cmd`, optional `color`, optional `title`. Maps directly onto `--layout` /
  `--color` / `--title` / repeated `--pane` (D-05/D-06 from Phase 4). The exact TOML key names and
  the bare-vs-`cmd=` shape are the planner's, under this 1:1 mapping invariant.

### launch ≡ new equivalence mechanism (SCEN-04)
- **D-03:** **Reuse the Phase 4 pure core in-process.** `scene launch` parses the TOML → builds the
  SAME internal spec table that `cli/lib/scene.lua` already consumes → calls the SAME orchestration
  path `scene new` uses. **Equivalence is structural (one code path), not coincidental.** No
  subprocess. **Rejected:** building a `wez scene new ...` argv and shelling out (adds a subprocess,
  a re-quoting/escaping surface, and a second place errors surface). The launch path MUST NOT
  re-implement layout geometry, palette, or OSC emission — it composes what exists.

### Recipe directory & name resolution (SCEN-03/05/06)
- **D-04:** **Recipes live at `~/.config/wezterm/wezterm-setup/scenes/`** — co-located under the
  existing managed config tree (`SETUP_DIR` in `tools/setup.sh`), NOT at the dedicated
  `~/.config/wezterm-setup/scenes/` that the original requirement text used. **This decision
  supersedes the written path in REQUIREMENTS.md / ROADMAP.md / UI-SPEC — all three were updated to
  the co-located path as part of this phase** (so locked artifacts stay truthful). Resolve under the
  WezTerm config dir (`$WEZTERM_CONFIG_DIR` / `$XDG_CONFIG_HOME/wezterm` / `~/.config/wezterm`), then
  `/wezterm-setup/scenes/`.
- **D-05:** **`<name>` is the recipe basename without extension** → resolves to `<dir>/<name>.toml`.
  With TOML-only (D-01) there is no `.toml`/`.lua` precedence question to settle.
- **D-06 (INVARIANT — not discretionary):** **The user's `scenes/` must NOT be clobbered by the
  installer's wholesale `cp -R`.** Because scenes now co-locate under `SETUP_DIR` (D-04) and
  `setup.sh` currently does `cp -R config/wezterm-setup/. → SETUP_DIR/` (overwrites), the seed
  recipes MUST be excluded from that wholesale copy and delivered ONLY via the copy-if-absent seeder
  (D-07). The managed `cp -R` must not place or overwrite anything under `scenes/`. Mechanism is the
  planner's; the SCEN-06 "user edits survive reinstall" invariant is not.

### Seeding on install (SCEN-06)
- **D-07:** **A dedicated Lua subcommand owns copy-if-absent seeding** (working name `wez
  seed-scenes` — exact name the planner's call); `tools/setup.sh` only invokes it, decision-free
  (D-01: logic in Lua, installer is glue; mirrors the `install-state` precedent). Per-recipe:
  copy the in-repo seed file to the dest **only if the dest does not exist** — never overwrite a
  user-edited recipe. Pure / fixture-testable like `install_state.lua`. **Rejected:** folding into
  `install-state` (mixes config-injection with recipe seeding) and per-file bash logic in `setup.sh`
  (decision logic back in the installer, against D-01, weaker test coverage).
- **D-08:** **The 3 seed recipes ship in-repo as `.toml` files** (new location, planner's call —
  natural candidates: a `scenes/` tree the seeder reads, kept OUT of the `config/wezterm-setup/` tree
  that gets `cp -R`'d, per D-06). Their content is **locked** by the SCEN-06 table in REQUIREMENTS.md
  (`dev`: tall/green/2 shell panes; `ai`: tall/purple/2 shell panes; `docker`: grid/teal/4 panes =
  `docker stats`, `docker ps`, `docker compose logs -f`, shell). The seed `.toml` files must encode
  exactly that and must round-trip through the loader to the same scene as the equivalent `scene new`.

### Completion — `scene-names` context (SCEN-05)
- **D-09:** Mechanism is **already locked by the UI-SPEC + the D-16 `__complete` pattern**: add a
  `scene-names` context to `cli/commands/complete.lua`'s `CONTEXTS` table that lists recipe basenames
  read **dynamically at completion time** from the scenes dir; the generated zsh/bash scripts gain a
  nested `scene) → launch)` arm calling `wez __complete scene-names` (mirroring the `pane)`/`tab)`
  arms in `completions.lua`). No static recipe names, no regeneration on add/remove. The
  recipe-listing function is a **single provider** shared by completion AND the error hint block
  (one source, two consumers).

### Claude's Discretion (planner to propose under the decisions above)
- The pure-Lua TOML parser to vendor (must satisfy zero-dep + relative-`require` + luastatic bundling).
- Exact TOML key names / pane-table shape (under the D-02 1:1-to-`scene new` mapping).
- Exact name of the seeding subcommand (D-07) and the in-repo location of the seed `.toml` files (D-08).
- The precise `setup.sh` change that excludes `scenes/` from the wholesale `cp -R` and invokes the
  seeder (D-06/D-07) — invariant is "no clobber + seeded copy-if-absent", mechanism is open.
- Whether the recipe loader + recipe→spec mapping is a new `cli/lib/recipe.lua` or folded into
  `cli/lib/scene.lua` (must keep the pure-core/IO-shell split from Phase 4).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### This phase's locked contract (read first)
- `.planning/phases/05-named-scenes/05-UI-SPEC.md` — APPROVED UI design contract: exact `scene
  launch` output/error copy, exit codes (`2` usage/no-recipes, `1` not-found/malformed), the
  available-recipes hint block, the recipe→scene-new mapping, and the `scene-names` completion
  contract. Updated to the co-located scenes path + TOML-only this phase.

### In-repo locked decisions
- `.planning/decisions/cli-language.md` — Lua 5.4 CLI, luastatic single-binary; **relative-`require`
  constraint** governs any vendored TOML parser and any new `cli/lib/recipe.lua`.
- `.planning/decisions/wezterm-cli-surface.md` — the orchestration toolbox the inherited `scene new`
  path drives (launch does not touch this directly — it goes through the Phase 4 core).
- `.planning/decisions/tab-title-format.md` — locked `"color:title"` encoding + 10 color profiles +
  pane>tab priority (the recipe `color`/`title` fields ultimately resolve through this).

### Prior phase contexts (the direct base this phase builds on)
- `.planning/phases/04-ad-hoc-scenes/04-CONTEXT.md` — **the foundation.** D-05/D-06 (`--pane`
  inline `cmd=,color=,title=` surface the recipe mirrors), D-08 (run-in-shell), D-09 (clean-pane),
  the pure-core (`cli/lib/scene.lua`) / IO-shell (`cli/commands/scene.lua`) split that D-03 reuses.
- `.planning/phases/01-foundation/01-CONTEXT.md` — **D-16** (spec-driven completion + `wez keys` from
  `cli/spec.lua`; the `scene` namespace is OPEN; `__complete` is the single dynamic-value extension
  point — D-09 here), **D-01** (decision-free `setup.sh`, logic in Lua — governs D-07), **D-17**
  (config AUGMENT model).

### In-repo code to extend / mirror
- `cli/lib/scene.lua` — the **pure scene core** launch reuses in-process (D-03); recipe→spec output
  must produce the exact spec table this module already consumes.
- `cli/commands/scene.lua` — the IO/orchestration half; `scene launch` adds a sibling entry point
  routed via `scene_cmd` (mirror the `new` path).
- `cli/spec.lua` (lines ~149–167) — register `scene launch <name>` under the existing `scene`
  command so completion + `wez keys` pick it up automatically (D-16).
- `cli/commands/complete.lua` — add the `scene-names` context to `CONTEXTS` (D-09).
- `cli/commands/completions.lua` — add the nested `scene) → launch)` dispatch arm (mirror `pane)`/`tab)`).
- `cli/commands/install_state.lua` (+ `install_state_test.lua`) — the **pattern for the seeder**
  (D-07): pure decision logic + fixture tests, run() wires the filesystem; `setup.sh` is glue.
- `tools/setup.sh` (STEP 4, line ~85–88) — the wholesale `cp -R config/wezterm-setup/. → SETUP_DIR/`
  that D-06 must keep away from `scenes/`, plus where the seeder gets invoked.

### External pattern source (not in this tree)
- **kitty-setup** (sibling project) — the proven "one TOML per scene, engine parses it" model the
  user explicitly referenced ("al igual que como hicimos con kitty"). Read directly if available for
  the TOML recipe shape + seeding ergonomics; no scene-launch port exists in `../wezterm-setup_`.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `cli/lib/scene.lua` — pure scene core (split sequencing, spec validation, materialization
  decision). **Launch's whole equivalence guarantee rests on reusing this unchanged (D-03).**
- `cli/commands/scene.lua` — `shquote`, `decode_json`, topology read, two-phase build; `scene
  launch` is a thin new front door over the same orchestration.
- `cli/commands/complete.lua` `CONTEXTS` table + `cli/commands/completions.lua` nested arms — the
  exact pattern for `scene-names` (D-09); `pane color`/`tab` contexts are the templates.
- `cli/commands/install_state.lua` — the pure-logic + fixture-test + `setup.sh`-glue shape the
  copy-if-absent seeder copies (D-07).
- `cli/vendor/` — where the pure-Lua TOML parser gets vendored (alongside `dkjson`, `argparse`).

### Established Patterns
- **Pure-core / IO-shell split** (Phase 4) — recipe loader/mapper stays pure; only `scene.lua`
  shells out. Keeps launch testable without a live mux.
- **Validate-before-emit** (Phase 2 D-01) — a malformed/unknown-name recipe must build ZERO panes;
  reuse `validate_layout`/`validate_color` enum wording verbatim (UI-SPEC malformed-recipe row).
- **Spec-driven completion** (D-16) — register `launch` in `spec.lua`; dynamic names via `__complete
  scene-names`; never hardcode names into shell scripts.
- **Decision-free installer** (D-01) — seeding logic in Lua, `setup.sh` only invokes.
- **Single provider, two consumers** — one recipe-listing function feeds both completion and the
  error hint block.

### Integration Points
- **Launch path:** resolve `<name>` → `<dir>/<name>.toml` (D-04/D-05) → read+parse TOML (vendored
  parser) → map to scene spec (D-02) → validate (reuse Phase 4 validators) → drive the SAME Phase 4
  orchestration (D-03) → focus. Errors surface per the UI-SPEC before any mux call.
- **Completion path:** `wez scene launch <Tab>` → shell arm → `wez __complete scene-names` → list
  `*.toml` basenames in the scenes dir (D-09).
- **Install path:** `setup.sh` STEP 4 places the managed tree EXCLUDING `scenes/`, then invokes the
  seeder (D-07) which copy-if-absent's the 3 seed `.toml`s into `SETUP_DIR/scenes/` (D-06/D-08).
</code_context>

<specifics>
## Specific Ideas

- "Al igual que como hicimos con kitty, un `.toml` por scene y el engine lua que lo parsee y lo ponga
  en la jugada." — the headline format decision (D-01/D-02), referencing the proven kitty-setup model.
- The user deliberately chose to **co-locate scenes under the WezTerm config tree**
  (`~/.config/wezterm/wezterm-setup/scenes/`) over the standalone path the requirement text used, and
  asked that the locked docs (REQUIREMENTS.md + UI-SPEC) be **corrected to match** rather than left
  contradictory (D-04).
</specifics>

<deferred>
## Deferred Ideas

- **`wez scene save`** (capture a running tab back into a recipe file) — not in SCEN-03..06; would be
  its own capability. Note for the roadmap backlog if desired.
- **Lua-format recipes / executable recipes** — rejected for v1 (D-01 chose TOML-only). Revisit only
  with a new decision.
- **Standalone `~/.config/wezterm-setup/scenes/` path** — superseded by D-04 (co-located). Not deferred.
- **Non-TTY/CI launch confirmation output** — UI-SPEC keeps launch silent on success (inherits Phase
  4 D-09); a confirmation affordance would be a new decision.

None beyond the above — discussion stayed within phase scope.
</deferred>

---

*Phase: 5-named-scenes*
*Context gathered: 2026-06-13*
