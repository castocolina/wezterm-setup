# Phase 2: Pane Identity - Pattern Map

**Mapped:** 2026-06-10
**Files analyzed:** 4
**Analogs found:** 4 / 4 (3 exact/role-match, 1 partial)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `cli/commands/pane.lua` (NEW) | controller (CLI command) | request-response (validate input -> shell-out OSC write) | `cli/commands/keys.lua` | exact (pure-fn + run() split, shell-out, stderr errors) |
| `cli/spec.lua` (MODIFY — add `pane` namespace) | config (argparse spec / allow-list) | CRUD (register subcommand+flags) | `cli/spec.lua` itself (existing `keys`/`install-state`/`completions` registrations) | exact |
| `config/wezterm-setup/format-tab-title.lua` (NEW topic module) | provider / event-handler | event-driven (`wezterm.on("format-tab-title", ...)`) | `config/wezterm-setup/cwd.lua` (AUGMENT contract) + `config/wezterm-setup/init.lua` (wiring) | role-match (AUGMENT contract present, but no event-handler example in repo) |
| `cli/commands/completions.lua` / `cli/commands/complete.lua` (MODIFY — completion path) | utility (codegen / dynamic completion) | transform (spec-walk -> shell script) + request-response (`__complete` dynamic candidates) | `cli/commands/completions.lua` (self) + `cli/wez.lua` dispatcher (`__complete` alias) | exact |

## Pattern Assignments

### `cli/commands/pane.lua` (controller, request-response)

**Analog:** `cli/commands/keys.lua` (full file read, 289 lines)

**File header / contract comment** (lines 1-22):
```lua
-- cli/commands/keys.lua
--
-- The `wez keys` subcommand (DIAG-02/03/04). The subcommand + `--json` flag are
-- ALREADY registered in cli/spec.lua by Plan 01 — this module ONLY implements the
-- behavior; it does NOT edit the spec.
--
-- ... (describes what it does, references decision IDs) ...
--
-- The classify()/build_json() helpers are PURE and fixture-testable with no live
-- WezTerm session (the autonomous gate). run() wires them to the real session.

local M = {}
```
For `pane.lua`, follow this exact shape: header references D-01 (color validation), D-02 (dual-write OSC), D-03/D-06 (opacity/alpha-strip), D-04 (title icon shortcuts). State which functions are PURE/fixture-testable vs. live wiring.

**Pure, fixture-testable function pattern** (lines 98-162, `M.classify`):
```lua
-- classify(effective, baseline, ours) -> (entries, conflicts)
--
-- Pure function (D-14). ... Returns: entries, conflicts
function M.classify(effective, baseline, ours)
  ...
  return entries, conflicts
end
```
For `pane.lua`, mirror this with pure functions like `M.validate_color(input) -> (ok, normalized_or_err)`, `M.strip_alpha(hex) -> hex6`, `M.resolve_icon(name) -> emoji_or_nil`, `M.classify_color_arg(arg)` etc. Each documented with its decision-ID reference and exact return contract.

**Shell-out / capture helper** (lines 204-211):
```lua
-- Run a command and capture stdout. Returns the text, or nil + message on failure.
local function capture(cmd)
  local fh = io.popen(cmd .. " 2>/dev/null")
  if not fh then return nil, "could not spawn: " .. cmd end
  local out = fh:read("*a")
  local ok = fh:close()
  if not ok then return nil, "command failed: " .. cmd end
  return out
end
```
`pane.lua` needs the inverse — WRITING an OSC escape to the live terminal (stdout, not via `io.popen`). Use `io.write` directly for the escape sequences (per CONTEXT.md's reference data: `\033]11;<hex>\033\\`, `\033]1337;SetUserVar=...\007`), keeping the construction of the escape string in a PURE function (e.g. `M.build_osc11(hex)`, `M.build_osc1337(varname, value)` — base64-encode the value) and only the final `io.write(...)` in `run()`.

**Live wiring + error/exit-code pattern** (lines 234-286, `M.run`):
```lua
function M.run(args)
  args = args or {}
  local showkeys = require("cli.lib.showkeys")

  local eff_text, e1 = capture("wezterm show-keys --lua")
  if not eff_text then
    io.stderr:write("wez keys: cannot read live key table (" .. tostring(e1) .. ")\n")
    io.stderr:write("wez keys: a running WezTerm session is required.\n")
    return 1
  end
  ...
  if args.json then
    local json = require("dkjson")
    io.write(json.encode(...))
    io.write("\n")
    return 0
  end
  ...
  return 0
end
```
For `pane.lua`: validate the color/title/opacity argument via the pure functions first; on validation failure, write to `io.stderr` using the EXACT error format from `02-UI-SPEC.md`:
```
error: unknown color "fuschia" — expected one of: red, orange, yellow, green, teal, cyan, blue, navy, purple, pink, or a hex value (#rgb / #rrggbb / #rrggbbaa)
```
and return a non-zero exit code (follow `keys.lua`'s convention: `1` for runtime/session failures — "a running WezTerm session is required" maps directly to pane.lua needing a live session to emit OSC sequences). For the opacity spike-gated warning, use a one-time `io.stderr:write("warning: per-pane opacity is not supported by your WezTerm version — color applied without transparency\n")` and still return `0` (per UI-SPEC, this is a soft-degrade, not an error).

---

### `cli/spec.lua` (config, CRUD — subcommand registration)

**Analog:** `cli/spec.lua` itself (full file read, 142 lines)

**CATEGORIES + SUBCOMMANDS allow-list** (structure observed near top of file):
```lua
local CATEGORIES = {
  ["keys"] = "diagnostics",
  ["install-state"] = "install",
  -- ...
}

local SUBCOMMANDS = {
  "version", "doctor", "keys", "install-state", "uninstall-state",
  "completions", "__complete",
}
```
Add `"pane"` to `SUBCOMMANDS` (the closed allow-list the dispatcher checks via `command_allowset()`) and to `CATEGORIES` (e.g. `["pane"] = "identity"` or similar — pick a category consistent with the eventual `tab`/`scene` namespaces). Note the existing comment: *"The top-level `pane`/`tab`/`scene` namespaces (Phases 2-5) are left intentionally OPEN here"* — this is the exact spot to fill in.

**Command + subcommand + flag registration pattern** (`M.build_parser()`):
```lua
local keys = parser:command("keys", "List active keybindings by category")
keys:flag("--json", "Emit machine-readable JSON")

local install_state = parser:command("install-state", "Inspect / drive install state")
install_state:flag("--force", "Overwrite an existing managed block")
install_state:flag("--restore", "Restore the timestamped backup")
install_state:flag("--skip", "Leave the existing block untouched")

local completions = parser:command("completions", "Generate shell completions from this spec")
completions:argument("shell", "Target shell (bash|zsh)"):args("?")
```
For `pane`, register a parent command with `color`/`title`/(`opacity`, if spike succeeds) as argparse SUBCOMMANDS-of-a-command (argparse supports nested commands via `parser:command(...):command(...)`), e.g.:
```lua
local pane = parser:command("pane", "Inspect / set per-pane identity")
local pane_color = pane:command("color", "Set or reset the current pane's color")
pane_color:argument("value", "Named profile, hex, rgba(), or 'reset'")
local pane_title = pane:command("title", "Set the current pane's tab title")
pane_title:argument("text", "Icon-name shortcut + freeform text, or icon name alone")
```
Mirror `completions:argument("shell", ...):args("?")` for any optional positional. Keep `M.subcommand_names()` and `M.categories()` returning copies — no change needed to those functions themselves, only to the data tables they read from.

---

### `config/wezterm-setup/format-tab-title.lua` (NEW topic module — provider/event-handler)

**Analog 1 — AUGMENT contract shape:** `config/wezterm-setup/cwd.lua` (full file, 36 lines)
```lua
-- wezterm-setup :: cwd
local M = {}
function M.apply(config)
  -- No custom split/spawn logic (cwd-mechanism.md). ...
  return config
end
return M
```
This shows the MINIMAL topic-module shape: header comment `-- wezterm-setup :: <topic>`, `M.apply(config) -> config` (mutate-and-return, never replace).

**Analog 2 — wiring into init.lua's apply():** `config/wezterm-setup/init.lua` (full file, 122 lines)
```lua
local keybindings = require("keybindings")
local cwd = require("cwd")
...
function M.apply(config)
  assert(type(config) == "table", "wezterm-setup.apply: expected a config table")
  local ok, wezterm = pcall(require, "wezterm")
  if not ok then wezterm = nil end
  ...
  -- 4. Apply cwd behavior (no-op augment; inheritance is WezTerm default).
  cwd.apply(config)

  return config
end
```
For the new `format-tab-title.lua`:
1. `require("format-tab-title")` alongside `keybindings`/`cwd` (line ~28).
2. Its `M.apply(config)` should register the event handler via `wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width) ... end)`. Follow the SAME `pcall(require, "wezterm")` guard (lines 81-84) so the module stays import-safe under plain lua5.4 — wrap the `wezterm.on(...)` call in `if wezterm then ... end`.
3. Add a call `format_tab_title.apply(config)` at the end of `init.lua`'s `M.apply`, alongside `cwd.apply(config)` (line 115) — additive, never replacing.
4. Embed the color-profile table (10 named profiles' bg/fg pairs + default `{#333333,#c0c0c0}` from CONTEXT.md/UI-SPEC.md) as a module-level Lua table (`M.color_profiles` or a local `local PROFILES = {...}`), consumed both by the event handler (tab-bar rendering) and potentially by `pane.lua` (for OSC 1337 SetUserVar values / validation — keep the canonical table in ONE place and have `pane.lua` either `require` it or duplicate the validated-name list; prefer requiring it from the CLI side too if `package.path` allows, else duplicate the 10 names as a literal allow-list array in `pane.lua`'s pure validator).
5. Pure-function split (consistent with `keys.lua`/`pane.lua`): keep label-formatting (e.g. `<index>: <name><indicator>`, icon resolution, color-pair lookup) as pure functions taking plain tables, with the `wezterm.on` callback as thin "live wiring" that calls them — this matches the project's pure/testable convention and lets the new module be unit-tested without a live WezTerm session.

---

### `cli/commands/completions.lua` / completion path (MODIFY — utility, transform + request-response)

**Analog:** `cli/commands/completions.lua` (full file, 232 lines) + `cli/wez.lua` dispatcher's `MODULE_ALIASES`

**Spec-walk / describe pattern** (lines 39-83):
```lua
local function describe(parser, names)
  local by_name = {}
  for _, cmd in ipairs(parser._commands or {}) do
    if cmd._name then by_name[cmd._name] = cmd end
  end
  ...
  for _, name in ipairs(ordered) do
    if not HIDDEN[name] then
      local cmd = by_name[name]
      local flags = {}
      if cmd then
        for _, opt in ipairs(cmd._options or {}) do
          for _, alias in ipairs(opt._aliases or {}) do
            if alias:match("^%-%-") and alias ~= "--help" then
              flags[#flags + 1] = alias
            end
          end
        end
      end
      commands[#commands + 1] = { name = name, flags = flags }
    end
  end
  return { commands = commands }
end

local function describe_spec()
  return describe(spec.build_parser(), spec.subcommand_names())
end
```
**Critical implication for Phase 2:** because `describe()` walks the LIVE parser built by `spec.build_parser()`, adding `pane` (with `color`/`title` subcommands and their `--flags`, e.g. an `--opacity` flag if added as a flag rather than nested command) to `cli/spec.lua` makes `wez completions zsh|bash` automatically include `pane` and its flags — **no edit needed to `completions.lua` itself for STATIC completion** (per the file's own header comment, lines 7-12).

**Dynamic candidate routing — `__complete` pattern** (referenced, lines 14-17 + dispatcher alias):
```lua
-- Dynamic values (future phases: colors, scene names) are NOT hardcoded. The
-- generated functions shell out to `wez __complete <context>` (cli/commands/
-- complete.lua) for any computed candidate set, so future contexts plug in by
-- teaching `__complete`, never by regenerating the static scripts.
```
And from `cli/wez.lua` (lines 77-79):
```lua
local MODULE_ALIASES = {
  ["__complete"] = "complete",
}
```
**This IS the file that needs modification for Phase 2's dynamic completions** ("`wez pane color <Tab>` completes named profiles + icon names for title"). The expected file is `cli/commands/complete.lua` (not yet read — was registered as `__complete` in spec.lua and aliased to `cli/commands/complete.lua` per the dispatcher). The pattern to follow: `complete.lua`'s `M.run(args)` should accept a context argument (e.g. `wez __complete pane-colors` or `wez __complete pane-icons`) and `io.write` one candidate per line (newline-separated, matching how `gen_zsh`/`gen_bash` consume `$(wez __complete subcommands ...)` via `${(f)"$(...)"}`/`compgen`). The candidate list for `pane-colors` is the 10 named profile keys (red/orange/yellow/.../pink) plus literal `reset`; for `pane-icons` it is the ~40 icon-name shortcuts from D-04. Since `complete.lua` was not directly read, the EXACT existing `M.run` signature/contract for `__complete` should be confirmed before writing — but the `io.write` newline-list output contract is implied directly by the consuming shell snippets above (`compadd -a _wez_dyn` / `compgen -W "$subcommands $dyn"`).

**Error/exit-code convention** (lines 203-229, from `M.run` of `completions.lua`):
```lua
if type(shell) ~= "string" or shell == "" then
  io.stderr:write("wez completions: a shell is required (zsh|bash)\n")
  return 2
end
...
io.stderr:write(("wez completions: unsupported shell '%s' (want zsh|bash)\n"):format(shell))
return 2
```
Apply the same `io.stderr:write("wez <cmd>: <message>\n"); return 2` shape for unknown `__complete` contexts in `complete.lua`.

---

## Shared Patterns

### Dispatcher allow-list (T-01-02)
**Source:** `cli/wez.lua` lines 44-50, 55-93
```lua
local function command_allowset()
  local set = {}
  for _, name in ipairs(spec.subcommand_names()) do
    set[name] = true
  end
  return set
end
...
local allow = command_allowset()
if not allow[name] then
  io.stderr:write(("wez: unknown command '%s'\n"):format(tostring(name)))
  return 2
end
...
local module_leaf = MODULE_ALIASES[name] or name:gsub("%-", "_")
local module_name = "cli.commands." .. module_leaf
local ok, mod = pcall(require, module_name)
if not ok then
  io.stderr:write(("wez: command '%s' is not implemented yet\n"):format(name))
  return 3
end
```
**Apply to:** `pane.lua` requires NO dispatcher edit — adding `"pane"` to `spec.lua`'s `SUBCOMMANDS` is sufficient; `name:gsub("%-", "_")` maps `"pane"` -> module leaf `"pane"` -> `cli/commands/pane.lua` automatically (no new alias needed since "pane" has no hyphen).

### AUGMENT pattern (D-17)
**Source:** `config/wezterm-setup/init.lua` lines 73-119, `cwd.lua` lines 1-36 (full file)
```lua
function M.apply(config)
  assert(type(config) == "table", "wezterm-setup.apply: expected a config table")
  local ok, wezterm = pcall(require, "wezterm")
  if not ok then wezterm = nil end
  config.keys = config.keys or {}
  for _, b in ipairs(keybindings.keys) do
    table.insert(config.keys, { ... })
  end
  cwd.apply(config)
  return config  -- SAME object, never replaced
end
```
**Apply to:** the new `format-tab-title.lua` topic module — `M.apply(config)` mutates+returns same `config`, called additively from `init.lua`'s `M.apply` after `cwd.apply(config)`.

### `wezterm` global guard (import-safe for unit tests)
**Source:** `config/wezterm-setup/init.lua` lines 33-37, 81-84
```lua
local function resolve_action(wezterm, spec)
  if not (wezterm and wezterm.action) then
    return spec -- test environment: leave the declarative spec in place
  end
  ...
end
...
local ok, wezterm = pcall(require, "wezterm")
if not ok then
  wezterm = nil
end
```
**Apply to:** `format-tab-title.lua` — guard `wezterm.on(...)` registration and any `wezterm.format(...)` calls behind `if wezterm then ... end` so the module loads under plain `lua5.4` for fixture tests.

### Error / exit-code / stderr convention
**Source:** `cli/commands/keys.lua` lines 240-243, 253-256; `cli/commands/completions.lua` lines 207-209, 227-228; `cli/wez.lua` lines 60-61, 86-87, 91-92, 112
```lua
io.stderr:write("wez keys: cannot read live key table (" .. tostring(e1) .. ")\n")
io.stderr:write("wez keys: a running WezTerm session is required.\n")
return 1
```
```lua
io.stderr:write(("wez completions: unsupported shell '%s' (want zsh|bash)\n"):format(shell))
return 2
```
**Apply to:** `pane.lua` and `complete.lua` — prefix every stderr message with `"wez <subcommand>: "` (or `"wez pane color: "` / `"wez pane title: "` for sub-subcommand specificity), return `2` for invalid/unrecognized arguments (validation errors — matches argparse convention), `1` for runtime/session failures (no live WezTerm session to write OSC to), `0` for success including soft-degrade warnings (opacity fallback).

### Pure function / live wiring split (D-13/D-14 convention)
**Source:** `cli/commands/keys.lua` lines 98-197 (pure: `M.classify`, `M.build_json`) vs lines 199-286 (live: `capture`, `load_our_bindings`, `M.run`)
**Apply to:** `pane.lua` (color/title validation, OSC string construction, alpha-stripping, icon-name resolution = pure; `io.write` of the OSC sequence + stderr messaging = live `run()`) and `format-tab-title.lua` (label formatting, color-pair lookup = pure; `wezterm.on` callback = live wiring).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `config/wezterm-setup/format-tab-title.lua` — `wezterm.on("format-tab-title", ...)` event handler body | event-handler | event-driven | No existing topic module in the repo registers a `wezterm.on(...)` callback; `cwd.lua` (the only other topic module) is a no-op `M.apply`. The CONTEXT.md "Reusable Assets" section explicitly notes this handler must be PORTED from a sibling repo (out of scope to read here). Planner should rely on the AUGMENT contract (`init.lua`/`cwd.lua`) for the module SHAPE and on `02-UI-SPEC.md`'s tab-label/color-table spec for the CONTENT. |
| `cli/commands/complete.lua` — `__complete pane-colors` / `__complete pane-icons` contexts | utility | request-response | File registered (`__complete` -> `complete.lua` per dispatcher alias) but not read in this pass; its existing `M.run(args)` contract (context argument shape, output format) should be confirmed by the planner/implementer directly before extending — the newline-per-candidate `io.write` contract is INFERRED from the consuming shell generators in `completions.lua`, not verified against `complete.lua` itself. |

## Metadata

**Analog search scope:** `cli/commands/`, `cli/spec.lua`, `cli/wez.lua`, `config/wezterm-setup/`
**Files scanned:** `cli/commands/keys.lua` (289 lines), `cli/commands/version.lua` (20 lines), `cli/commands/completions.lua` (232 lines), `cli/commands/install_state.lua` (first 80 lines), `cli/wez.lua` (145 lines), `cli/spec.lua` (142 lines), `config/wezterm-setup/init.lua` (122 lines), `config/wezterm-setup/cwd.lua` (36 lines)
**Pattern extraction date:** 2026-06-10
