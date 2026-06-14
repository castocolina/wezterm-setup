# Phase 05: Named Scenes - Pattern Map

**Mapped:** 2026-06-13
**Files analyzed:** 11 new/modified
**Analogs found:** 10 / 11 (1 vendored file has a sibling-precedent only)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `cli/vendor/tinytoml.lua` | vendored library | transform (parse) | `cli/vendor/dkjson.lua`, `cli/vendor/argparse.lua` | sibling-precedent (vendoring discipline only) |
| `cli/lib/recipe.lua` | pure core (loader+mapper) | transform | `cli/lib/scene.lua` (pure-core split + validators reused) | role + flow exact |
| `cli/lib/recipe_test.lua` | test | transform | `cli/lib/scene_test.lua` (co-located `*_test.lua`) | exact |
| `cli/commands/scene.lua` (MODIFY) | command / IO-shell | request-response | self — `M.run_new` is the reuse seam; add `M.run_launch` + route in `M.run` | exact (extend) |
| `cli/commands/seed_scenes.lua` | command / IO-shell | file-I/O (copy-if-absent) | `cli/commands/install_state.lua` (pure decision + `run()` glue) | role + flow exact |
| `cli/commands/seed_scenes_test.lua` | test | file-I/O | `tests/cli/install_state_test.lua` (referenced precedent) | exact |
| `cli/commands/complete.lua` (MODIFY) | command / IO-shell | request-response | self — add `scene-names` to `CONTEXTS` | exact (extend) |
| `cli/commands/completions.lua` (MODIFY) | generator | transform | self — nested `pane)`/`tab)` arms in `gen_zsh`/`gen_bash` | exact (extend) |
| `cli/spec.lua` (MODIFY) | config / registration | declarative | self — `scene` command block (lines 149-167) | exact (extend) |
| `scenes/{dev,ai,docker}.toml` | data fixture | n/a | none in repo (kitty-setup `examples/scenes/*.toml` external) | external-precedent |
| `tools/setup.sh` (MODIFY) | installer glue | file-I/O | self — STEP 4 (`cp -R`) + STEP 6 (`wez install-state` delegation) | exact (extend) |

## Pattern Assignments

### `cli/lib/recipe.lua` (pure core: loader + recipe->args mapper)

**Analog:** `cli/lib/scene.lua` (pure-core grep contract: no `io.*`/`os.execute`/mux globals).

**Vendored-require dual-resolution** — copy verbatim from `cli/commands/scene.lua` lines 60-65 (dkjson idiom), substituting `tinytoml`:
```lua
local ok, toml = pcall(require, "cli.vendor.tinytoml")
if not ok then ok, toml = pcall(require, "tinytoml") end
```

**Parse-pure via load_from_string + mandatory pcall** (tinytoml RAISES, does not return nil+err — Research Pitfall 1):
```lua
local parsed_ok, result = pcall(toml.parse, raw_string, { load_from_string = true })
-- on failure: extract `line (%d+)` from result -> "could not parse TOML at line <N>"
```

**Reuse Phase 4 validators verbatim** — do NOT author new enum copy (UI-SPEC single source). From `cli/lib/scene.lua`:
- `M.validate_layout(name)` (lines 187-194) — exact-match against `M.LAYOUTS = {"tall","tall:mirrored","grid","horizontal"}`.
- `M.validate_color(name)` (lines 205-212) — 10-profile palette, case-insensitive.

**recipe->args mapper (the SCEN-04 seam)** — emit the exact `args` table `M.run_new` consumes (see `cli/commands/scene.lua` lines 116-127 docblock: `args.layout` string, `args.pane` array of raw spec strings, `args.color`, `args.title`). Pane-table->spec-string mapping (Research Pattern 1):
```lua
-- shell pane -> literal "shell" (parse_pane_spec line 146 treats it as the shell keyword)
-- bare single-field command -> the cmd string as-is (parse_pane_spec line 151 bare form)
-- multi-field -> "cmd=<c>, color=<x>, title=<t>"  (BARE-COMMAND FAST PATH, Option 1 — comma-safe for the 3 seeds)
```
> **Planner decision (Research Open Q1 + Pitfall 3):** Option 1 fast path (bare for single-field, `key=value` only for multi-field) avoids the `parse_pane_spec` comma-split corruption (`cli/lib/scene.lua` `split_kv_segments`). Ratify before locking.

**Name guard** (port of kitty `_guard_name`; reject `/` and `..` before any I/O — Research §Code Examples / Pitfall 4) — lives pure but the resolved-parent check is in the IO-shell.

---

### `cli/commands/scene.lua` (MODIFY — add `M.run_launch`, route in `M.run`)

**Analog:** self. The seam is `M.run_new(args)` (lines 124-352) — call it in-process, build NOTHING new (D-03 anti-pattern: no argv/subprocess).

**Subcommand routing** — extend `M.run` (lines 382-389) exactly like the `new` arm:
```lua
function M.run(args)
  local sub = args and args.scene_cmd
  if sub == "new" then return M.run_new(args) end
  if sub == "launch" then return M.run_launch(args) end
  io.stderr:write("wez scene: expected a subcommand (new, launch)\n")
  return 2
end
```

**`M.run_launch` (IO-shell)** — owns the trust boundary: resolve scenes dir, guard name, read file, then hand the raw string to the pure `recipe.lua`, then delegate:
```lua
-- read file (IO-shell only; recipe.lua stays pure):
local fh = io.open(path, "rb"); ... local raw = fh:read("*a"); fh:close()
local args, err = recipelib.load_and_map(raw)   -- pure: parse + validate + map
if not args then io.stderr:write(err .. "\n"); return <1|2 per UI-SPEC> end
return M.run_new(args)                           -- SINGLE materialization path (SCEN-04)
```

**Reuse `shquote`** (lines 53-55) for any path passed to `io.popen`; reuse `decode_json` pattern only if listing via JSON (not needed — glob via `io.popen("ls ...")`).

**Scenes-dir resolver** (shared by launch + completion + seeder — Research Pitfall 6) — port the env-precedence pattern from `cli/commands/uninstall_state.lua` `default_setup_dir` (lines 25-29), appending `/scenes`:
```lua
local explicit = os.getenv("WEZTERM_SETUP_DIR")    -- dogfood/test override
-- else WEZTERM_CONFIG_DIR -> XDG_CONFIG_HOME/wezterm -> ~/.config/wezterm, then /wezterm-setup/scenes
```

**Single-provider recipe listing** (Research Pattern 4) — `M.list_recipe_names(dir)` globs `*.toml`, strips ext, sorts. Mirror `install_state.lua` `M.newest_backup` (lines 119-138) which uses `io.popen("ls -1 -- " .. M.shquote(dir))` + suffix filter. Filter `name:match("%.toml$")`, strip `name:gsub("%.toml$","")`, `table.sort`. Feeds BOTH `complete.lua` and the launch error hint block.

---

### `cli/commands/seed_scenes.lua` (NEW — copy-if-absent seeder)

**Analog:** `cli/commands/install_state.lua` — copy its pure-logic + `run()`-glue split byte-for-byte in shape.

**Pure decision core** (mirror `M.decide` lines 340-363 and `uninstall_state.lua` `M.plan_removal` lines 40-48):
```lua
-- plan_seed(repo_seed_names, existing_dest_names) -> { {name=, action="seed"|"keep"}, ... }
-- pure list logic, no FS — fixture-testable.
```

**FS primitives** — reuse `install_state.lua`'s proven helpers verbatim: `read_all`/`write_all` (lines 73-93, with both write+close error capture, CR-03), and `M.shquote` (lines 111-113, exported). Copy-if-absent: re-check `if dest not exists` at write time (TOCTOU guard, Research Pattern 6).

**`run()` glue** (mirror lines 399-490) — reads repo seed dir + dest dir, applies `plan_seed`, copies each `seed` action, emits UI-SPEC messaging `seeded scene recipe: <name>` / `kept existing scene recipe: <name>`, returns exit code.

---

### `cli/commands/complete.lua` (MODIFY — add `scene-names` context)

**Analog:** self. Add a provider fn (mirror `scene_layouts` lines 90-94) and a `CONTEXTS` entry (lines 96-103):
```lua
local scene = require("cli.commands.scene")   -- complete.lua already requires command modules
local function scene_names() return scene.list_recipe_names(scene.scenes_dir()) end  -- dynamic at Tab time
-- in CONTEXTS table:
["scene-names"] = scene_names,
```
Output contract (lines 107-129): plain tokens, one per line, unknown context emits nothing + exit 0. Empty dir -> no output, exit 0 (SCEN-05).

---

### `cli/commands/completions.lua` (MODIFY — nested `scene) -> launch)` arm)

**Analog:** self — the `pane)`/`tab)` nested arms in `gen_zsh` (lines 139-153) and `gen_bash` (lines 210-226).

**zsh arm** (mirror lines 147-153, dispatch on `$line[2]`):
```sh
        scene)
          case $line[2] in
            launch) compadd ${(f)"$(wez __complete scene-names 2>/dev/null)"} ;;
            new) compadd <new's flags> ;;
            *) compadd new launch ;;
          esac
          ;;
```

**bash arm** (mirror lines 219-226, dispatch on `${COMP_WORDS[2]}`):
```sh
    scene)
      local sub="${COMP_WORDS[2]}"
      case "$sub" in
        launch) COMPREPLY=( $(compgen -W "$(wez __complete scene-names 2>/dev/null)" -- "$cur") ); return 0 ;;
        new) COMPREPLY=( $(compgen -W "<new's flags>" -- "$cur") ); return 0 ;;
        *) COMPREPLY=( $(compgen -W "new launch" -- "$cur") ); return 0 ;;
      esac
      ;;
```
> **Wiring subtlety (Research Open Q3 / Pattern 5):** `scene` has top-level flags (`--layout` etc.), so the GENERIC flag loop (`gen_zsh` lines 129-135, `gen_bash` lines 201-208) ALREADY emits a `scene)` arm — unlike `pane`/`tab` which had none. The nested `scene)` arm must REPLACE (not duplicate) that generic one and merge flag completion into the `new)` sub-case. Order the nested arm so it wins. Flag both `bash -n`/`zsh -n` clean.

---

### `cli/spec.lua` (MODIFY — register `scene launch <name>` + `seed-scenes`)

**Analog:** self — the `scene` command block (lines 155-167). Add a sibling `launch` subcommand under the existing `scene` command so completion + `wez keys` pick it up automatically (D-16):
```lua
local scene_launch = scene:command("launch", "Launch a saved scene recipe by name")
scene_launch:argument("name", "Recipe basename (without .toml) under the scenes dir"):args(1)
```
Register `seed-scenes` as a top-level command alongside the others (and add to `SUBCOMMANDS`/`CATEGORIES` lists — see how existing commands appear in `subcommand_names`, lines 178-185). Hidden? No — user-runnable like `install-state`.

---

### `scenes/{dev,ai,docker}.toml` (NEW — locked seed content, SCEN-06)

**Analog:** none in-repo; kitty-setup `examples/scenes/*.toml` (external, pattern only). Content LOCKED by REQUIREMENTS.md SCEN-06 table + Research §Code Examples (lines 350-379). Schema = `[[panes]]` + `command` (Research Open Q2 recommendation; accept `cmd` alias in mapper). Shell pane MUST encode as `command = "shell"` and round-trip to literal `--pane shell`.
- `dev.toml`: `layout="tall"`, `color="green"`, 2 shell panes, no title.
- `ai.toml`: `layout="tall"`, `color="purple"`, 2 shell panes, no title.
- `docker.toml`: `layout="grid"`, `color="teal"`, 4 panes = `docker stats`, `docker ps`, `docker compose logs -f`, shell.

**INVARIANT (D-06/D-08):** these live in a TOP-LEVEL `scenes/` dir, OUTSIDE `config/wezterm-setup/` (which gets `cp -R`'d and would clobber user edits).

---

### `tools/setup.sh` (MODIFY — exclude scenes/ from cp -R; invoke seeder)

**Analog:** self. Two seams:
1. **STEP 4** (lines 85-88): `cp -R "${REPO_ROOT}/config/wezterm-setup/." "${SETUP_DIR}/"`. Since seeds are NOT under `config/wezterm-setup/` (D-06/D-08), STEP 4 already never touches them — verify no scenes path leaks into that tree. `SETUP_DIR` defined line 46 = `${CONFIG_DIR}/wezterm-setup`.
2. **New STEP 4b** — decision-free delegation, mirror STEP 6's `install-state` invocation (line 171): `"${BIN_DIR}/wez" install-state "$@"`. Add:
```sh
log "seeding example scene recipes (copy-if-absent)…"
"${BIN_DIR}/wez" seed-scenes
```
All copy/keep decisions live in Lua (D-01/D-07); `setup.sh` adds no branching.

## Shared Patterns

### Vendored-require dual-resolution
**Source:** `cli/commands/scene.lua` lines 60-65 (dkjson); `cli/vendor/dkjson.lua`, `argparse.lua` precedent.
**Apply to:** `recipe.lua` requiring `tinytoml`. `pcall(require,"cli.vendor.X")` then fall back to `pcall(require,"X")`.

### Pure-core / IO-shell split (validate-before-emit)
**Source:** `cli/lib/scene.lua` (pure: no `io.*`) + `cli/commands/scene.lua` (the only module that shells out). `M.run_new` Step 0 (lines 128-172) validates EVERY value before any mux call.
**Apply to:** `recipe.lua` (pure parse+map+validate; file read stays in `scene.lua`), `seed_scenes.lua` (pure `plan_seed`; FS in `run()`). A malformed/unknown recipe MUST build ZERO panes.

### Reuse validators, never author new enum copy
**Source:** `cli/lib/scene.lua` `validate_layout` (187-194) + `validate_color` (205-212).
**Apply to:** `recipe.lua` layout/color validation. UI-SPEC forbids new enum wording.

### Shell-quote every user-derived string
**Source:** `cli/commands/scene.lua` `shquote` (53-55) / `cli/commands/install_state.lua` `M.shquote` (111-113, exported).
**Apply to:** any path/value passed to `io.popen`/`os.execute` in `scene.lua` launch + listing and `seed_scenes.lua` (CR-02 injection guard).

### Env-precedence path resolution (single shared resolver)
**Source:** `cli/commands/uninstall_state.lua` `default_setup_dir` (lines 25-29).
**Apply to:** the ONE scenes-dir resolver consumed by launch, completion, and the seeder (Pitfall 6 — drift = completion lists recipes launch can't find).

### Decision-free installer glue
**Source:** `tools/setup.sh` STEP 6 (`wez install-state "$@"`, line 171).
**Apply to:** STEP 4b invoking `wez seed-scenes` (D-01/D-07).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `cli/vendor/tinytoml.lua` | vendored library | transform | Pure fetch-and-pin (v1.0.0 tag, header sha comment) per `dkjson`/`argparse` discipline — no in-repo behavioral analog; `tools/build.sh` auto-globs `cli/**/*.lua` so no build-script edit needed. |
| `scenes/*.toml` | data fixture | n/a | No TOML data files exist in-repo yet; content is externally locked (SCEN-06 table) and shape mirrors kitty-setup. |

## Metadata

**Analog search scope:** `cli/lib/`, `cli/commands/`, `cli/vendor/`, `cli/spec.lua`, `tools/setup.sh`
**Files scanned:** scene.lua (lib+cmd), install_state.lua, uninstall_state.lua, complete.lua, completions.lua, spec.lua, setup.sh
**Pattern extraction date:** 2026-06-13
