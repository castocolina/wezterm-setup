# Phase 5: Named Scenes - Research

**Researched:** 2026-06-13
**Domain:** Pure-Lua TOML recipe loading, in-process reuse of the Phase 4 scene core, dynamic shell completion, copy-if-absent install seeding
**Confidence:** HIGH (codebase grounded; TOML parser verified against upstream source)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** TOML only — one `.toml` file per scene, parsed by the Lua engine which maps it into the scene spec. Implies **vendoring a pure-Lua TOML parser** into the luastatic single binary (zero-dep constraint — MUST be pure Lua, no C ext, relative-`require`-safe per `cli-language.md`).
- **D-02:** The recipe schema mirrors the `wez scene new` surface 1:1. Top-level `layout`, `color`, `title`; an array of pane tables each with `command`/`cmd`, optional `color`, optional `title`. Maps directly onto `--layout` / `--color` / `--title` / repeated `--pane`. **Exact TOML key names and bare-vs-`cmd=` shape are the planner's**, under the 1:1 mapping invariant.
- **D-03:** Reuse the Phase 4 pure core in-process. `scene launch` parses TOML → builds the SAME internal spec table `cli/lib/scene.lua` already consumes → calls the SAME orchestration path `scene new` uses. **Equivalence is structural (one code path), not coincidental.** No subprocess. The launch path MUST NOT re-implement layout geometry, palette, or OSC emission.
- **D-04:** Recipes live at `~/.config/wezterm/wezterm-setup/scenes/` — co-located under the managed config tree (`SETUP_DIR`). Resolve under the WezTerm config dir (`$WEZTERM_CONFIG_DIR` / `$XDG_CONFIG_HOME/wezterm` / `~/.config/wezterm`), then `/wezterm-setup/scenes/`.
- **D-05:** `<name>` is the recipe basename without extension → resolves to `<dir>/<name>.toml`. No `.toml`/`.lua` precedence question (TOML-only).
- **D-06 (INVARIANT — not discretionary):** The user's `scenes/` must NOT be clobbered by the installer's wholesale `cp -R`. Seed recipes MUST be excluded from that copy and delivered ONLY via copy-if-absent seeding (D-07). The managed `cp -R` must not place or overwrite anything under `scenes/`.
- **D-07:** A dedicated Lua subcommand owns copy-if-absent seeding (working name `wez seed-scenes`); `tools/setup.sh` only invokes it, decision-free. Per-recipe: copy the in-repo seed file to dest **only if the dest does not exist**. Pure / fixture-testable like `install_state.lua`.
- **D-08:** The 3 seed recipes ship in-repo as `.toml` files (new location, planner's call — kept OUT of the `config/wezterm-setup/` tree that gets `cp -R`'d). Content locked by the SCEN-06 table. Must round-trip through the loader to the same scene as the equivalent `scene new`.
- **D-09:** Add a `scene-names` context to `cli/commands/complete.lua`'s `CONTEXTS` table listing recipe basenames read **dynamically at completion time** from the scenes dir; generated zsh/bash gain a nested `scene) → launch)` arm calling `wez __complete scene-names`. The recipe-listing function is a **single provider** shared by completion AND the error hint block.

### Claude's Discretion
- The pure-Lua TOML parser to vendor (must satisfy zero-dep + relative-`require` + luastatic bundling). **→ This research recommends `tinytoml` (see Standard Stack).**
- Exact TOML key names / pane-table shape (under the D-02 1:1-to-`scene new` mapping).
- Exact name of the seeding subcommand (D-07) and in-repo location of the seed `.toml` files (D-08).
- The precise `setup.sh` change that excludes `scenes/` from `cp -R` and invokes the seeder.
- Whether the recipe loader + recipe→spec mapping is a new `cli/lib/recipe.lua` or folded into `cli/lib/scene.lua` (must keep the pure-core/IO-shell split).

### Deferred Ideas (OUT OF SCOPE)
- **`wez scene save`** (capture a running tab back into a recipe file) — not in SCEN-03..06.
- **Lua-format / executable recipes** — rejected for v1 (D-01 chose TOML-only).
- **Standalone `~/.config/wezterm-setup/scenes/` path** — superseded by D-04 (co-located).
- **Non-TTY/CI launch confirmation output** — UI-SPEC keeps launch silent on success.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCEN-03 | Scene recipes in the scenes dir are TOML files loaded by name | TOML parser selection (`tinytoml`) + recipe→spec mapping + path resolution (this doc, §Standard Stack, §Architecture Patterns) |
| SCEN-04 | `wez scene launch <name>` produces the same result as an equivalent `wez scene new` call | In-process reuse seam: `scene launch` builds the same `args` table `M.run_new(args)` consumes in `cli/commands/scene.lua` (§Architecture Patterns, In-Process Reuse) |
| SCEN-05 | Scene names dynamically complete in zsh + bash from recipe files present, no manual update | `scene-names` `__complete` context + nested `scene)→launch)` shell arm (§Architecture Patterns, Completion) |
| SCEN-06 | Installer seeds 3 example recipes copy-if-absent; user edits survive reinstall | `wez seed-scenes` Lua subcommand mirroring `install_state.lua`; `setup.sh` excludes `scenes/` from `cp -R` (§Architecture Patterns, Seeding) |
</phase_requirements>

## Summary

Phase 5 is a thin persistence + discovery layer over the already-shipped Phase 4 `wez scene new` orchestration. There is **no new scene-building mechanism** — `wez scene launch <name>` reads a TOML recipe, maps it to the exact `args` table that `cli/commands/scene.lua`'s `M.run_new(args)` already consumes, and calls that function in-process. Structural equivalence (SCEN-04) is therefore free: there is literally one materialization code path.

The four net-new pieces are: (1) a vendored pure-Lua TOML parser, (2) a recipe loader + recipe→`args` mapper that preserves the Phase 4 pure-core / IO-shell split, (3) a `scene-names` dynamic completion context, and (4) a `wez seed-scenes` copy-if-absent installer subcommand that mirrors `install_state.lua`. The proven model already exists in the sibling **kitty-setup** project (`src/kitty_setup/scenes/recipe.py` + `installer.py::seed_scenes`), which the user explicitly referenced; this research mirrors its schema shape, security guards (path-traversal name guard), and seeding semantics into Lua.

**Primary recommendation:** Vendor **`tinytoml`** (MIT, single-file, zero-dep, TOML 1.1.0, Lua 5.1–5.5) as `cli/vendor/tinytoml.lua`. Add a new pure module `cli/lib/recipe.lua` (loader + mapper, fixture-testable) plus its IO-shell entry in `cli/commands/scene.lua` (`M.run_launch`). Add a `wez seed-scenes` command modeled byte-for-byte on the `install_state.lua` pure-logic + glue split.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| TOML parsing | Pure core (`cli/lib/recipe.lua`, or vendored parser called with `load_from_string`) | — | No file/mux access — operates on a string the IO-shell read |
| Recipe→`args` mapping | Pure core (`cli/lib/recipe.lua`) | — | Pure table transform; fixture-testable without a session |
| Recipe file read + name resolution | IO-shell (`cli/commands/scene.lua`) | — | Filesystem access is the trust boundary (like `read_topology`) |
| Scene materialization | IO-shell (`cli/commands/scene.lua` `M.run_new`) — **reused verbatim** | Pure core (`cli/lib/scene.lua`) | D-03: launch composes the existing path, builds nothing new |
| Recipe listing (completion + error hint) | IO-shell (single provider fn) | — | Globs the scenes dir — filesystem access |
| `scene-names` completion context | IO-shell (`cli/commands/complete.lua`) | — | Calls the listing provider at Tab time |
| Copy-if-absent seeding | Pure decision (`seed_scenes.lua`) + IO-shell `run()` | Installer glue (`setup.sh`) | Mirrors `install_state.lua`: logic in Lua, installer is glue |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `tinytoml` | 1.0.0 | Pure-Lua TOML decoder, vendored into the luastatic binary | The only actively-maintained, single-file, zero-dependency, Lua-5.4-compatible TOML 1.1.0 parser; mirrors how `dkjson`/`argparse` are already vendored `[VERIFIED: github raw source]` |

### Supporting
Already in-repo, reused unchanged:
| Module | Purpose | When to Use |
|--------|---------|-------------|
| `cli/commands/scene.lua` `M.run_new(args)` | The Phase 4 orchestration `scene launch` delegates to | Every launch — build `args`, call this |
| `cli/lib/scene.lua` `validate_layout` / `validate_color` | Exact UI-SPEC enum error strings | Validate recipe `layout`/`color` before mapping (reuse verbatim — UI-SPEC forbids new enum copy) |
| `cli/commands/install_state.lua` (pattern) | Pure-logic + fixture-test + `setup.sh`-glue shape | Template for `seed_scenes.lua` |
| `cli/vendor/dkjson.lua`, `cli/vendor/argparse.lua` | Existing vendored deps + the `pcall(require, "cli.vendor.X")` → `pcall(require, "X")` dual-resolution idiom | Copy the same require fallback for `tinytoml` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `tinytoml` | `lua-toml` (jonstoler) | **Rejected.** Last release v2.0.0 Nov 2017 (~8 yrs stale); only TOML 0.4.0; arrays-of-tables (`[[x]]`) not confirmed supported — exactly what the pane array needs `[CITED: github.com/jonstoler/lua-toml]` |
| `tinytoml` | `toml.lua` (LebJe), `tomlua` (BirdeeHub) | **Rejected.** Both are C-backed (toml++ / C), violating the pure-Lua + relative-`require` + luastatic-bundleable constraint `[CITED: github.com/LebJe/toml.lua, github.com/BirdeeHub/tomlua]` |
| Vendoring a parser at all | Hand-roll a minimal TOML reader | **Rejected** (see Don't Hand-Roll) — string escapes, arrays-of-tables, UTF-8 validation, multiline strings are real complexity tinytoml already handles |

**Installation (vendor, not npm — this is a Lua project):**
```bash
# Fetch the single source file into cli/vendor/ (mirrors how dkjson/argparse were vendored).
# Pin to the v1.0.0 tag, NOT master, and record the upstream commit/sha in a comment header.
curl -fsSL https://raw.githubusercontent.com/FourierTransformer/tinytoml/v1.0.0/tinytoml.lua \
  -o cli/vendor/tinytoml.lua
```
The build (`tools/build.sh`) auto-collects every `cli/**/*.lua` for luastatic (`find cli -type f -name '*.lua' ! -name 'wez.lua'`), so dropping the file into `cli/vendor/` makes it bundle with **no build-script edit** `[VERIFIED: tools/build.sh codebase read]`.

## Package Legitimacy Audit

> This phase vendors ONE external source file (`tinytoml`). It is a Lua source vendored by hand into `cli/vendor/`, not an npm/PyPI install — there is no package-manager install step to slopcheck. Legitimacy was verified by reading the upstream source directly.

| Package | Registry | Age | Downloads | Source Repo | Verification | Disposition |
|---------|----------|-----|-----------|-------------|--------------|-------------|
| `tinytoml` 1.0.0 | LuaRocks (`fouriertransformer/tinytoml`) | v1.0.0 released 2026-01-17 (~5 mo); repo has 6 releases / active CI | n/a (LuaRocks) | github.com/FourierTransformer/tinytoml | Raw `tinytoml.lua` read: declares `_LICENSE = "MIT"`, `_VERSION = "tinytoml 1.0.0"`, contains **zero `require()` calls**, `return tinytoml` module shape; LuaRocks lists `lua >= 5.1` as the only dependency | **Approved — vendor pinned to v1.0.0 tag** |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

**Provenance note:** `tinytoml` was discovered via WebSearch, then **verified against the authoritative upstream GitHub repo and LuaRocks page** (not registry-existence alone). The vendored copy must be pinned to the `v1.0.0` git tag and carry a header comment recording the upstream URL + version, matching the existing `dkjson`/`argparse` vendoring discipline. The planner should add a `checkpoint:human-verify` only if the maintainer wants to eyeball the vendored file diff before commit; the source itself is verified-clean.

## Architecture Patterns

### System Architecture Diagram

```
  wez scene launch <name>                         wez scene new --layout ... --pane ...
            |                                                   |
            v  (IO-shell: cli/commands/scene.lua M.run_launch)  |
   ┌─────────────────────────────────┐                         |
   │ resolve_scenes_dir()             │  D-04 path              |
   │ guard_name(<name>)               │  reject '/' and '..'    |
   │ read <dir>/<name>.toml           │  filesystem I/O         |
   └───────────────┬─────────────────┘                         |
                   │ raw TOML string                            |
                   v  (PURE: cli/lib/recipe.lua)                |
   ┌─────────────────────────────────┐                         |
   │ tinytoml.parse(str,              │                         |
   │   {load_from_string=true})       │  ← wrap in pcall        |
   │ map recipe table -> args table   │  D-02 1:1 mapping       |
   │   layout/color/title + panes[]   │                         |
   │ (errors: validate_layout/color   │                         |
   │  reused from cli/lib/scene.lua)  │                         |
   └───────────────┬─────────────────┘                         |
                   │ args = {layout=, pane={...}, color=, title=}|
                   v                                            v
            ┌──────────────────────────────────────────────────────┐
            │  cli/commands/scene.lua  M.run_new(args)               │  ← SINGLE code path (D-03/SCEN-04)
            │  validate-before-emit → topology read → Phase A spawn/ │
            │  split → Phase B style+cmd → tab style → focus         │
            └──────────────────────────────────────────────────────┘
                                   │
                                   v
                          live WezTerm panes


  Completion (SCEN-05):                         Install seeding (SCEN-06):
  wez scene launch <Tab>                          tools/setup.sh STEP 4
   → shell _wez scene)→launch) arm                 ├─ cp -R config/wezterm-setup/.  (EXCLUDES scenes/)
   → wez __complete scene-names                    └─ STEP 4b: wez seed-scenes
   → list_recipe_names() (globs scenes dir)             → copy-if-absent each repo seed .toml
   → basenames, sorted                                    into SETUP_DIR/scenes/  (D-06/D-07/D-08)
        (SAME provider feeds the error hint block)
```

### Recommended Project Structure
```
cli/
├── vendor/
│   └── tinytoml.lua            # NEW — vendored, pinned v1.0.0, zero-dep
├── lib/
│   ├── scene.lua               # UNCHANGED (pure core: validators reused)
│   └── recipe.lua              # NEW — pure loader+mapper (parse string → args)
│   └── recipe_test.lua         # NEW — fixture tests (co-located, *_test.lua)
├── commands/
│   ├── scene.lua               # EXTEND — add M.run_launch + route in M.run
│   ├── complete.lua            # EXTEND — add scene-names CONTEXT + provider
│   ├── completions.lua         # EXTEND — nested scene)→launch) arm (zsh+bash)
│   ├── seed_scenes.lua         # NEW — copy-if-absent seeder (install_state shape)
│   └── seed_scenes_test.lua    # NEW (or tests/cli/) — pure + scratch-FS tests
└── spec.lua                    # EXTEND — register `scene launch <name>` + `seed-scenes`
scenes/                         # NEW in-repo seed dir — OUTSIDE config/wezterm-setup/ (D-06/D-08)
├── dev.toml
├── ai.toml
└── docker.toml
tools/setup.sh                  # EXTEND — STEP 4 excludes scenes/; STEP 4b invokes seeder
```

### Pattern 1: In-Process Reuse (SCEN-04 — the structural-equivalence seam)
**What:** `scene launch` constructs the exact `args` table `M.run_new` already accepts, then calls it. No argv, no subprocess.
**The seam (verified in `cli/commands/scene.lua`):** `M.run_new(args)` reads only:
- `args.layout` — string
- `args.pane` (or `args.panes`) — **array of raw `--pane` spec strings**
- `args.color` — optional tab-level color name
- `args.title` — optional tab-level title text

`M.run_new` itself calls `scenelib.parse_pane_spec` on each raw string, so the cleanest mapping is to **emit `--pane`-format strings** from the recipe (not pre-parsed pane tables) — that way every Phase 4 validator and the two-phase build run identically. A pane recipe table `{command="docker stats", color="teal", title="stats"}` maps to the spec string `"cmd=docker stats, color=teal, title=stats"`; a shell pane maps to the literal `"shell"`.

**Example (recipe.lua mapper → run_new):**
```lua
-- Source: derived from cli/commands/scene.lua M.run_new contract (codebase read)
-- recipe table (already TOML-parsed) -> the args table run_new consumes.
local function pane_table_to_spec(p)            -- D-02 1:1 mapping
  if p.command == nil and p.cmd == nil then return "shell" end   -- shell pane (D-04)
  local cmd = p.cmd or p.command
  if (p.color == nil) and (p.title == nil) then return cmd end   -- bare command form
  local segs = { "cmd=" .. cmd }
  if p.color then segs[#segs+1] = "color=" .. p.color end
  if p.title then segs[#segs+1] = "title=" .. p.title end
  return table.concat(segs, ", ")              -- 'cmd=docker stats, color=teal, title=stats'
end

function M.recipe_to_args(recipe)               -- PURE
  local panes = recipe.panes or recipe.pane or {}   -- key name = planner's call (D-02)
  local args = { layout = recipe.layout, color = recipe.color, title = recipe.title, pane = {} }
  for _, p in ipairs(panes) do args.pane[#args.pane+1] = pane_table_to_spec(p) end
  return args
end
-- IO-shell (cli/commands/scene.lua):  return M.run_new(recipe.recipe_to_args(parsed))
```

> **Mapping caveat the planner must settle:** `parse_pane_spec` splits the spec string on **top-level commas** and on the **first `=` per segment**. A recipe `title` or `cmd` value containing a literal comma (e.g. `cmd = "docker compose logs -f, --tail 10"`) would be mis-split if round-tripped through a `--pane` string. The kitty-setup model **builds pane objects directly** to avoid this (TOML values need no comma escaping). Two viable options:
> 1. **Bare-command fast path** (recommended low-risk): pass single-field panes (command-only / shell-only) as bare strings; only multi-field panes go through the `key=value` string. The 3 seed recipes never combine a comma'd command WITH `color=`/`title=`, so they round-trip safely today.
> 2. **Add a structural entry point to `scene.lua`**: refactor `M.run_new` to accept pre-parsed pane tables (skip `parse_pane_spec`), so the recipe maps to structured panes with no string round-trip. Cleaner long-term, but touches the shipped Phase 4 path (needs a regression check that `scene new` still behaves identically).
> Option 1 satisfies SCEN-04/06 with minimal blast radius; Option 2 is the more correct seam if the planner wants comma-safe arbitrary recipes. **This is a real decision, not a detail — flag it for the planner.**

### Pattern 2: Pure parse via `load_from_string` (keeps the IO-shell split)
**What:** tinytoml's `parse(filename)` does file I/O by default; `parse(str, {load_from_string=true})` parses an in-memory string. The IO-shell reads the file; the pure core parses the string.
**Why it matters:** `cli/lib/recipe.lua` must stay pure (the acceptance grep in the Phase 4 precedent bans `io.*`/`os.execute`/mux globals in `cli/lib/*`). Calling `tinytoml.parse(raw, {load_from_string=true})` from the pure mapper keeps that contract; the file read stays in `cli/commands/scene.lua`.
**Example:**
```lua
-- Source: tinytoml.lua parse() signature + options (upstream source read)
local ok, toml = pcall(require, "cli.vendor.tinytoml")
if not ok then toml = require("tinytoml") end       -- dual-resolution like dkjson
local parsed_ok, result = pcall(toml.parse, raw_string, { load_from_string = true })
-- tinytoml RAISES on malformed input (error() with "...line <N>..." in the message),
-- so pcall is MANDATORY. result is the table on success, the error string on failure.
```

### Pattern 3: Recipe loader error translation (UI-SPEC malformed-recipe copy)
**What:** tinytoml raises Lua errors (it does NOT return nil+err). The loader catches via `pcall` and maps the raised message to the UI-SPEC's `could not parse TOML at line <N>` copy.
**How:** tinytoml's error messages embed `line <N>` (verified: `_error` builds `"...line ", sm.line_number, ...`). The loader can regex `:line (%d+)` (or `line (%d+)`) out of the caught message; if no line is recoverable, fall back to `could not parse TOML`. Layout/color validation errors come from reusing `scenelib.validate_layout`/`validate_color` verbatim (UI-SPEC: do not author new enum copy).

### Pattern 4: Single-provider recipe listing (completion + error hint)
**What:** ONE function `list_recipe_names(dir)` globs `<scenes_dir>/*.toml`, strips the extension, sorts, returns basenames. Both the `scene-names` `__complete` context AND the launch error hint block call it (UI-SPEC: single source of truth).
**Where:** Listing touches the filesystem → it lives in the IO-shell (`cli/commands/scene.lua` or a small shared helper required by both `scene.lua` and `complete.lua`). `complete.lua` already requires command modules (`pane`, `tab`, `scene` lib) for its providers, so requiring `cli/commands/scene.lua` for the listing fn fits the established shape.
**Glob portability:** no `ls` shell-out needed if a dir-read primitive is available; otherwise mirror `install_state.lua`'s `newest_backup` which uses `io.popen("ls -1 -- " .. shquote(dir))` and filters by suffix — that exact idiom is already shipped and cross-platform. Filter `name:match("%.toml$")`, strip with `name:gsub("%.toml$","")`, `table.sort`.

### Pattern 5: Completion wiring (mirror the `pane)`/`tab)` arms)
**What:** Add `scene-names` to `complete.lua`'s `CONTEXTS`, and a nested `scene)` arm in both `gen_zsh` and `gen_bash` in `completions.lua` that dispatches `launch)` → `wez __complete scene-names`.
**Exact shapes to copy (from `completions.lua`):**
- zsh: a `scene)` case with inner `case $line[2] in ... launch) compadd ${(f)"$(wez __complete scene-names 2>/dev/null)"} ;; ... esac`
- bash: a `scene)` case with inner `case "$sub" in ... launch) COMPREPLY=( $(compgen -W "$(wez __complete scene-names 2>/dev/null)" -- "$cur") ); return 0 ;; ... esac`

These mirror the existing `pane)`/`tab)` arms 1:1. Note: the generic flag loop already emits a `scene)` arm because `scene new` has flags (`--layout` etc.) — the planner must reconcile the flag-arm vs the nested arm (the existing code places `pane)`/`tab)` AFTER the flag loop and those commands have no top-level flags; `scene` DOES, so the nested `scene)` arm must merge flag completion + the `launch)` name dispatch, or be ordered so the nested arm wins for the `launch` subcommand). **This is a concrete wiring subtlety — flag it.**

### Pattern 6: Copy-if-absent seeder (mirror `install_state.lua`)
**What:** `wez seed-scenes` with a pure decision core + a `run()` that wires the filesystem, and `setup.sh` as decision-free glue.
**Pure core (fixture-testable):** a function like `plan_seed(repo_seed_names, existing_dest_names) -> { {name=, action="seed"|"keep"}, ... }` — pure list logic, no FS. `run()` reads the repo seed dir, reads dest dir, applies `plan_seed`, and for each `seed` action copies the file **only if dest does not exist** (re-check at write time to avoid TOCTOU), emitting the UI-SPEC messaging: `seeded scene recipe: <name>` / `kept existing scene recipe: <name>`.
**kitty-setup precedent (verified):** `installer.py::seed_scenes` returns `(seeded, kept)` counts and copies only `if not dest.exists()`; idempotent; seeded files become user data uninstall never removes. Mirror this exactly.

### Anti-Patterns to Avoid
- **Shelling out to `wez scene new` with a built argv (D-03 explicitly rejects).** Adds a subprocess, a re-quoting surface, and a second error surface. Call `M.run_new(args)` in-process.
- **Re-implementing layout geometry / palette / OSC emission in the launch path.** All of it lives in `M.run_new` + `cli/lib/scene.lua` — compose, don't duplicate.
- **Authoring new layout/color enum error copy.** Reuse `validate_layout`/`validate_color` verbatim (UI-SPEC single-source rule).
- **Putting the parser/mapper in `cli/lib/recipe.lua` but calling `io.open` there.** Breaks the pure-core grep contract. File read stays in the command module.
- **Seeding into the `config/wezterm-setup/` tree.** That tree gets `cp -R`'d (clobbers user edits — violates D-06). Seeds live in a sibling repo dir.
- **Hardcoding recipe names into the static completion scripts.** D-09/D-16 — names are dynamic via `__complete scene-names`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| TOML decoding | A custom TOML reader | `tinytoml` (vendored) | Arrays-of-tables, basic/literal/multiline strings, escape sequences, UTF-8 validation, comments, line-accurate errors — all real complexity already handled and toml-test-validated |
| Scene materialization | Any layout/spawn/split/OSC logic | `cli/commands/scene.lua` `M.run_new` | D-03: structural equivalence requires the single existing path |
| Layout/color validation | New enum checks + error strings | `cli/lib/scene.lua` `validate_layout`/`validate_color` | UI-SPEC single source; drift = inconsistent errors |
| Copy-if-absent + atomic write | Bash file-copy logic in `setup.sh` | `wez seed-scenes` Lua (mirror `install_state.lua`) | D-01/D-07: decision logic in Lua, fixture-testable; installer is glue |
| Shell quoting / path-safe args | Ad-hoc string building | `install_state.lua` `M.shquote` (exported) | Already proven against injection (CR-02) |

**Key insight:** Almost everything Phase 5 "does" already exists. The phase's value is wiring (recipe → existing args) + one vendored decoder + one seeder. Net-new algorithmic logic is small and pure.

## Runtime State Inventory

> This is a feature-addition phase (new files + extending existing modules), NOT a rename/refactor/migration. No existing stored data, service config, OS-registered state, secrets, or build artifacts carry a string being renamed.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no datastore keys/IDs created or renamed. Recipes are flat files written copy-if-absent. | none |
| Live service config | None — no external service holds scene state. | none |
| OS-registered state | None — no Task Scheduler/launchd/pm2/systemd registration. | none |
| Secrets/env vars | New READ-ONLY env vars honored for path resolution (`WEZTERM_CONFIG_DIR`, `WEZTERM_SETUP_DIR`, `XDG_CONFIG_HOME`); none are secrets, none are written. | none |
| Build artifacts | `cli/vendor/tinytoml.lua` becomes a new luastatic-bundled source; `dist/wez` must be rebuilt after adding it. `tools/build.sh` auto-collects `cli/**/*.lua`, so no build-script edit — just rebuild. | rebuild `dist/wez` (reinstall) after the parser is vendored |

**Verified by:** codebase reads of `tools/build.sh` (auto-glob), `cli/commands/uninstall_state.lua` (env-var precedence pattern), and the absence of any datastore/service in the project.

## Common Pitfalls

### Pitfall 1: tinytoml raises instead of returning an error
**What goes wrong:** Calling `tinytoml.parse(str)` without `pcall` crashes `wez` with a raw Lua traceback on a malformed recipe — violating the UI-SPEC's clean `error: scene recipe '<name>' is invalid: ...` contract.
**Why it happens:** tinytoml signals all parse failures (and UTF-8 errors) via `error()`, not `return nil, err` (verified in upstream `_error`).
**How to avoid:** Always `pcall(toml.parse, raw, {load_from_string=true})`. On failure, extract `line (%d+)` from the message → `could not parse TOML at line <N>`.
**Warning signs:** A test feeding a broken `.toml` produces a traceback instead of exit 1 + the UI-SPEC string.

### Pitfall 2: Default `parse(filename)` does file I/O — leaks into the pure core
**What goes wrong:** Putting `tinytoml.parse(path)` in `cli/lib/recipe.lua` makes the "pure" module read the filesystem, breaking the Phase 4 pure-core grep contract.
**How to avoid:** IO-shell reads the file; pure core calls `parse(str, {load_from_string=true})`. Mirror the existing split exactly.

### Pitfall 3: Comma in a recipe command mis-split by `parse_pane_spec`
**What goes wrong:** Round-tripping a pane through a `cmd=...,color=...` string when the command contains a literal comma corrupts the split (see Pattern 1 caveat).
**How to avoid:** Use the bare-command fast path for single-field panes, OR add a structured entry point to `scene.lua`. The 3 seed recipes are safe under the fast path; arbitrary user recipes with comma'd commands + per-pane styling are the edge.
**Warning signs:** A pane command silently truncated at the first comma; an "unknown key" error on the comma's tail.

### Pitfall 4: Path-traversal via the recipe name
**What goes wrong:** `wez scene launch ../../etc/passwd` or `wez scene launch foo/bar` escapes the scenes dir.
**Why it happens:** `<name>` becomes a filename interpolated into a path.
**How to avoid:** Guard the name before any I/O — reject empty, reject `/` (and OS altsep), reject `..` (exactly the kitty-setup `_guard_name`). Verify the resolved path's parent equals the scenes dir.
**Warning signs:** A name with a separator resolves to a file outside `scenes/`.

### Pitfall 5: Installer `cp -R` clobbers user-edited recipes (D-06 violation)
**What goes wrong:** Seeds placed under `config/wezterm-setup/scenes/` get wholesale-copied over user edits on every reinstall.
**How to avoid:** Keep seeds in a repo dir OUTSIDE `config/wezterm-setup/` (e.g. top-level `scenes/`). `setup.sh` STEP 4 (`cp -R config/wezterm-setup/.`) then never touches `scenes/`; a new STEP 4b runs `wez seed-scenes` copy-if-absent. Verify: install, edit a seed, reinstall, confirm the edit survives (`kept existing scene recipe: <name>`).

### Pitfall 6: Scenes-dir path resolution drift
**What goes wrong:** Launch, completion, and the seeder resolve the scenes dir differently → completion lists recipes launch can't find.
**How to avoid:** One shared resolver honoring `WEZTERM_CONFIG_DIR` → `XDG_CONFIG_HOME/wezterm` → `~/.config/wezterm`, then `/wezterm-setup/scenes/`. Reuse the `WEZTERM_SETUP_DIR` env precedent already in `uninstall_state.lua` so dogfood/tests can override the dir. All three consumers call the SAME resolver.

## Code Examples

### Scenes-dir resolution (mirrors the shipped env-precedence pattern)
```lua
-- Source: cli/commands/uninstall_state.lua default_setup_dir (codebase read)
local function scenes_dir()
  local explicit = os.getenv("WEZTERM_SETUP_DIR")
  if explicit and explicit ~= "" then return explicit .. "/scenes" end
  local cfg = os.getenv("WEZTERM_CONFIG_DIR")
  if not cfg or cfg == "" then
    local xdg = os.getenv("XDG_CONFIG_HOME")
    cfg = (xdg and xdg ~= "" and (xdg .. "/wezterm"))
       or ((os.getenv("HOME") or "") .. "/.config/wezterm")
  end
  return cfg .. "/wezterm-setup/scenes"
end
```

### Name guard (port of kitty-setup `_guard_name`)
```lua
-- Source: kitty-setup src/kitty_setup/scenes/recipe.py _guard_name (verified)
local function guard_name(name)
  if not name or name == "" then return false, "scene name is empty" end
  if name:find("/", 1, true) then
    return false, "invalid scene name: must not contain a path separator"
  end
  if name == ".." or name:find("%.%.", 1) then
    return false, "invalid scene name: '..' is not allowed"
  end
  return true
end
```

### Seed-recipe TOML shape (D-08, content locked by SCEN-06)
```toml
# scenes/dev.toml  — Source: REQUIREMENTS.md SCEN-06 table + D-02 1:1 shape
layout = "tall"
color  = "green"
# title is optional; SCEN-06 table specifies no tab title for dev/ai

[[panes]]            # key name "panes" vs "pane" is the planner's call (D-02)
command = "shell"    # shell (cwd) pane — must round-trip to `--pane shell` (no auto-title)

[[panes]]
command = "shell"
```
```toml
# scenes/docker.toml — grid, teal, 4 panes (3 commands + 1 shell)
layout = "grid"
color  = "teal"

[[panes]]
command = "docker stats"

[[panes]]
command = "docker ps"

[[panes]]
command = "docker compose logs -f"   # NOTE: contains a space, no comma — round-trips safely

[[panes]]
command = "shell"
```
> **Shell-pane round-trip check (UI-SPEC):** a `shell (cwd)` pane MUST map to `--pane shell` exactly so Phase 4 injects no auto-title/command (Phase 4 D-04/D-09). If the schema uses `command = "shell"`, `pane_table_to_spec` must emit the literal `"shell"` (not `cmd=shell`), which `parse_pane_spec` treats as the shell keyword. Verify a seeded `shell` pane produces a plain untouched shell.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `lua-toml` (jonstoler) as the go-to pure-Lua TOML lib | `tinytoml` (FourierTransformer) | tinytoml 1.0.0, Jan 2026 | Modern TOML 1.1.0 + arrays-of-tables + maintained; lua-toml is TOML 0.4 and unmaintained since 2017 |

**Deprecated/outdated:**
- `lua-toml` for new projects needing `[[array.of.tables]]`: only TOML 0.4.0, AoT support unconfirmed, ~8 yrs stale.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The kitty-setup seed recipes (`docker-ps`, `docker-memory` aliases) differ from the wezterm SCEN-06 table (`docker stats`, `docker ps`, `docker compose logs -f`, shell); the wezterm REQUIREMENTS.md table is authoritative for content | Code Examples (seed TOMLs) | Low — REQUIREMENTS.md SCEN-06 is locked and explicit; kitty is pattern-only |
| A2 | tinytoml `master`/`v1.0.0` `tinytoml.lua` is byte-identical to what `curl` fetched; pinning to the `v1.0.0` tag is required for reproducibility | Standard Stack / Audit | Low — pin the tag; record sha in the vendored header |
| A3 | `M.run_new` accepts `args.pane` as an array of raw spec strings AND will re-validate them — verified by reading the function, but the planner should confirm no Phase 4 arg the launch path omits (e.g. there is no required arg beyond layout+panes) | Pattern 1 | Low — function read confirms only layout/pane/color/title are consumed |

## Open Questions

1. **Pane-table → args representation (string round-trip vs structured entry point)**
   - What we know: `M.run_new` consumes raw `--pane` strings and parses them itself. Mapping to strings is zero-touch to Phase 4; mapping to structured panes is comma-safe but needs a new `run_new` entry point.
   - What's unclear: whether the planner wants comma-safe arbitrary recipes now (Option 2) or accepts the bare-command fast path (Option 1) for v1.
   - Recommendation: Ship Option 1 (fast path) for v1 — it satisfies all 3 seed recipes and the UI-SPEC. Note Option 2 as a clean follow-up if comma'd-command-plus-styling recipes are reported.

2. **TOML pane-array key name: `[[panes]]` vs `[[pane]]`, and `command` vs `cmd`**
   - What we know: D-02 leaves this to the planner. kitty-setup uses `[[pane]]` + `cmd`. README (per UI-SPEC) documents `[[panes]]` + `command`.
   - What's unclear: which the README/seed files should standardize on.
   - Recommendation: Match whatever the shipped README documents (UI-SPEC references `[[panes]]` with `command`); accept `cmd` as an alias in the mapper for kitty-parity ergonomics. Confirm against README before locking the seed files.

3. **Completion `scene)` arm ordering (flag arm vs nested launch arm)**
   - What we know: `scene new` has top-level flags, so the generic flag loop in `completions.lua` already emits a `scene)` arm; `pane`/`tab` had none.
   - What's unclear: how to merge flag completion for `scene new` with the nested `launch)` name dispatch without one shadowing the other.
   - Recommendation: Make the nested `scene)` arm dispatch on `$line[2]`/`COMP_WORDS[2]` — `launch)` → `scene-names`, `new)` → its flags, `*)` → `new launch`. Replace (don't duplicate) the generic flag arm for `scene`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `lua5.4` | Tests + dev build | ✓ (per existing CI / run-tests.sh) | 5.4 | — |
| `luastatic` + C compiler | Release single-binary build | (build-time only; dev launcher fallback exists) | — | `tools/build.sh` emits a dev launcher when luastatic absent |
| `curl` | Vendoring tinytoml.lua once | ✓ (already used by build/bootstrap) | — | manual download |
| WezTerm session | Live launch verification (integration) | runtime-only | — | unit/fixture tests run with no session (pure core) |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** luastatic (dev launcher covers local verification).

## Validation Architecture

> `.planning/config.json` was not found in the read set; nyquist_validation treated as enabled (absent = enabled). The project uses a co-located `*_test.lua` harness run via `tools/run-tests.sh` (`make test`).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Plain `lua5.4` assertion scripts (custom `check`/`eq`/`teq` harness, e.g. `cli/lib/scene_test.lua`); discovered by `tools/run-tests.sh` |
| Config file | none — `tools/run-tests.sh` globs `*_test.lua` under `tests/`, `cli/`, `config/` |
| Quick run command | `lua5.4 cli/lib/recipe_test.lua` (single file during TDD) |
| Full suite command | `make test` (or `./tools/run-tests.sh`); `WEZTERM_INTEGRATION=1 make test` for live |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCEN-03 | TOML parses to recipe table; bad TOML → clean error w/ line | unit | `lua5.4 cli/lib/recipe_test.lua` | ❌ Wave 0 |
| SCEN-03 | recipe→args mapping (panes, shell pane, color/title, comma fast-path) | unit | `lua5.4 cli/lib/recipe_test.lua` | ❌ Wave 0 |
| SCEN-03 | name guard rejects `/` and `..` | unit | `lua5.4 cli/lib/recipe_test.lua` | ❌ Wave 0 |
| SCEN-04 | launch builds the same args `run_new` consumes; not-found/no-recipes/malformed exit codes (1/1/2) + UI-SPEC copy | unit (mock run_new) + integration | `lua5.4 tests/cli/scene_launch_test.lua` / `WEZTERM_INTEGRATION=1 ...` | ❌ Wave 0 |
| SCEN-05 | `scene-names` context lists sorted basenames; empty dir → no output exit 0 | unit | `lua5.4 cli/commands/complete_test.lua` (extend) | ⚠️ extend existing |
| SCEN-05 | generated zsh/bash carry the `scene)→launch)` arm; `bash -n`/`zsh -n` clean | unit | `lua5.4 tests/cli/completions_test.lua` (extend) | ⚠️ extend existing |
| SCEN-06 | `plan_seed` decides seed/keep; copy-if-absent never overwrites; messaging copy | unit + scratch-FS | `lua5.4 tests/cli/seed_scenes_test.lua` | ❌ Wave 0 |
| SCEN-06 | 3 seed recipes round-trip to the SCEN-06 table scenes | unit (mapper) + integration | `lua5.4 cli/lib/recipe_test.lua` + live | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the single relevant `*_test.lua` (TDD RED→GREEN).
- **Per wave merge:** `make test` (full unit suite).
- **Phase gate:** `make test` green + `WEZTERM_INTEGRATION=1 make test` live launch repro before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `cli/lib/recipe.lua` + `cli/lib/recipe_test.lua` — parse, map, guard (SCEN-03/04)
- [ ] `tests/cli/scene_launch_test.lua` — launch errors + run_new delegation (SCEN-04)
- [ ] `cli/commands/seed_scenes.lua` + `tests/cli/seed_scenes_test.lua` — copy-if-absent (SCEN-06)
- [ ] `scenes/{dev,ai,docker}.toml` — locked seed content (SCEN-06)
- [ ] Vendor `cli/vendor/tinytoml.lua` (pinned v1.0.0) — needed before recipe.lua tests
- [ ] Extend `cli/commands/complete_test.lua` + `tests/cli/completions_test.lua` for `scene-names` (SCEN-05)

## Security Domain

> `security_enforcement` config not located in the read set; treated as enabled. This is a local CLI handling user-authored TOML files and a recipe name argument.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | local single-user CLI; no auth surface |
| V3 Session Management | no | no sessions |
| V4 Access Control | yes | Name-guard prevents reading files outside the scenes dir (path-traversal) |
| V5 Input Validation | yes | TOML parsed by a validated decoder (pcall'd); layout/color reuse shipped validators; pane specs re-validated by `parse_pane_spec`; UTF-8 validation by tinytoml |
| V6 Cryptography | no | none — vendor a pinned source, no crypto |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Path traversal via `<name>` (`../`, `/`) | Tampering / Info Disclosure | `guard_name` rejects separators and `..` before any I/O; verify resolved parent == scenes dir (port of kitty `_guard_name`) |
| Command injection via recipe command into the pane PTY | Tampering / EoP | Inherited from Phase 4: commands are sent as DISTINCT trailing `send-text` lines, never concatenated into escape sequences (T-04-02); `shquote` wraps every user-derived string passed to `os.execute`/`io.popen` |
| Malicious/oversized TOML (DoS) | DoS | tinytoml has `max_filesize` (100MB) and `max_nesting_depth` (1000) guards; recipes are user-authored local files (low threat), but pcall prevents a crash |
| Supply-chain (compromised vendored parser) | Tampering | Pin tinytoml to `v1.0.0` tag, record upstream sha in the vendored header, review the single-file diff at vendor time (matches dkjson/argparse discipline) |

## Sources

### Primary (HIGH confidence)
- Codebase reads: `cli/lib/scene.lua`, `cli/commands/scene.lua`, `cli/commands/complete.lua`, `cli/commands/completions.lua`, `cli/commands/install_state.lua`, `cli/commands/uninstall_state.lua`, `cli/spec.lua`, `cli/wez.lua`, `tools/setup.sh`, `tools/build.sh`, `tools/run-tests.sh` — the real internal contracts every recommendation is grounded in.
- tinytoml upstream source (`raw.githubusercontent.com/FourierTransformer/tinytoml/master/tinytoml.lua`) — verified zero `require()`, MIT, `parse(filename, options)` + `load_from_string`, `error()`-based reporting with line numbers.
- kitty-setup sibling (`../kitty-setup/src/kitty_setup/scenes/recipe.py`, `installer.py`, `examples/scenes/*.toml`) — the proven recipe-schema + name-guard + copy-if-absent seeding model the user referenced.

### Secondary (MEDIUM confidence)
- [github.com/FourierTransformer/tinytoml](https://github.com/FourierTransformer/tinytoml) — license, Lua 5.1–5.5, TOML 1.1.0, AoT support, maintenance (v1.0.0 Jan 2026).
- [luarocks.org/modules/fouriertransformer/tinytoml](https://luarocks.org/modules/fouriertransformer/tinytoml) — `lua >= 5.1` sole dependency, MIT, v1.0.0.

### Tertiary (LOW confidence)
- [github.com/jonstoler/lua-toml](https://github.com/jonstoler/lua-toml) — rejected alternative (TOML 0.4, 2017, AoT unconfirmed).
- [github.com/LebJe/toml.lua](https://github.com/LebJe/toml.lua), [github.com/BirdeeHub/tomlua](https://github.com/BirdeeHub/tomlua) — rejected (C-backed).

## Metadata

**Confidence breakdown:**
- Standard stack (tinytoml): HIGH — verified against upstream source + LuaRocks; only viable pure-Lua AoT-capable candidate.
- Architecture / reuse seam: HIGH — `M.run_new` arg contract read directly; structural-equivalence path confirmed.
- Completion / seeding patterns: HIGH — exact in-repo templates (`install_state.lua`, `completions.lua` arms) read and cited.
- Comma-round-trip caveat: MEDIUM — the limitation is verified from `parse_pane_spec`'s split rules; the chosen mitigation (fast path) is a recommendation the planner must ratify.

**Research date:** 2026-06-13
**Valid until:** 2026-07-13 (tinytoml is young but stable at 1.0.0; re-verify the pinned tag if more than ~30 days pass before vendoring)
