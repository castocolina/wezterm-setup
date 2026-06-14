-- cli/lib/recipe.lua
--
-- Pure TOML recipe core for `wez scene launch <name>` (SCEN-03). Parses a recipe
-- STRING into a recipe table, validates layout/color by REUSING the shipped
-- cli/lib/scene.lua validators (UI-SPEC single source of truth — no new enum
-- copy), and maps the recipe into the exact `args` table cli/commands/scene.lua
-- M.run_new(args) consumes (SCEN-04 structural-equivalence seam). Also the
-- path-traversal name guard (T-05-01).
--
-- PURE BY CONTRACT: no io.*, no os.execute, no os.getenv, no mux globals. The
-- recipe FILE read lives in 05-03's IO-shell; this module only parses the raw
-- string via tinytoml's load_from_string option. This keeps the whole module
-- fixture-testable under plain lua5.4 with no live session (mirrors scene.lua).

local M = {}

-- Resolve the vendored TOML decoder, dual-resolving from source (CWD on
-- package.path) and inside the luastatic bundle (baked as cli.vendor.tinytoml).
-- Mirrors the dkjson dual-resolution idiom in cli/commands/scene.lua.
local ok_toml, toml = pcall(require, "cli.vendor.tinytoml")
if not ok_toml then ok_toml, toml = pcall(require, "tinytoml") end

-- Reuse the shipped layout/color validators verbatim — authoring NO new enum
-- copy keeps the UI-SPEC single-source rule (a recipe's bad layout/color must
-- surface the EXACT string `wez scene new` already emits).
local scene = require("cli.lib.scene")

-- ---------------------------------------------------------------------------
-- M.guard_name(name) -> true | (false, errmsg).
-- Port of kitty-setup `_guard_name` (05-RESEARCH §Code Examples) — runs BEFORE
-- any I/O (the IO-shell calls this before interpolating <name> into a path).
-- Rejects empty/nil, any '/' separator, and any '..'. Pure (string checks only);
-- the resolved-parent==scenes-dir check is the IO-shell's defense-in-depth (05-03).
-- ---------------------------------------------------------------------------
function M.guard_name(name)
  if not name or name == "" then
    return false, "scene name is empty"
  end
  if name:find("/", 1, true) then
    return false, "invalid scene name: must not contain a path separator"
  end
  if name:find("%.%.") then
    return false, "invalid scene name: '..' is not allowed"
  end
  return true
end

-- ---------------------------------------------------------------------------
-- private: one recipe pane table -> a single raw `--pane` spec string that
-- scene.parse_pane_spec consumes (SCEN-04). Option-1 BARE-COMMAND FAST PATH
-- (ratified planner decision):
--   * no command/cmd (or command=="shell")     -> "shell"  (D-04 plain shell)
--   * single-field command-only pane            -> the command string AS-IS (bare)
--   * multi-field pane (command + color/title)  -> "cmd=..., color=..., title=..."
-- Accepts `cmd` as an alias for `command` (kitty parity, Open Q2).
--
-- COMMA CAVEAT (Pitfall 3): a comma INSIDE a multi-field command value would
-- mis-split via parse_pane_spec (it splits on top-level commas). This is the v1
-- limitation — the 3 seed recipes never combine a comma'd command WITH
-- color=/title=, so they round-trip safely. The comma-safe fix is a structured
-- M.run_new entry point (deliberately NOT implemented here).
-- ---------------------------------------------------------------------------
local function pane_table_to_spec(p)
  local cmd = p.cmd or p.command
  if cmd == nil or cmd == "shell" then
    return "shell"
  end
  if p.color == nil and p.title == nil then
    return cmd -- bare command form (comma-safe for the seeds)
  end
  local segs = { "cmd=" .. cmd }
  if p.color then segs[#segs + 1] = "color=" .. p.color end
  if p.title then segs[#segs + 1] = "title=" .. p.title end
  return table.concat(segs, ", ")
end

-- ---------------------------------------------------------------------------
-- M.recipe_to_args(recipe) -> args table. PURE transform (05-RESEARCH Pattern 1).
-- Reads panes from recipe.panes (the chosen key, matching README/UI-SPEC
-- `[[panes]]`), accepting recipe.pane as a fallback alias. Builds the exact
-- shape M.run_new consumes: { layout, color, title, pane = { <spec strings> } }.
-- ---------------------------------------------------------------------------
function M.recipe_to_args(recipe)
  local panes = recipe.panes or recipe.pane or {}
  local args = {
    layout = recipe.layout,
    color = recipe.color,
    title = recipe.title,
    pane = {},
  }
  for _, p in ipairs(panes) do
    args.pane[#args.pane + 1] = pane_table_to_spec(p)
  end
  return args
end

-- ---------------------------------------------------------------------------
-- M.load_and_map(raw_string) -> (args | nil, errmsg).
-- Parse a recipe STRING, validate it (reusing the shipped validators), and map
-- it to the run_new args table. tinytoml RAISES on malformed input (Pitfall 1),
-- so the parse is wrapped in pcall and the raised message is translated to the
-- UI-SPEC "could not parse TOML at line <N>" copy — a crafted recipe yields
-- error text, never a Lua traceback (T-05-02 mitigation).
--
-- Error reasons use the load_and_map form `error: scene recipe is invalid: ...`
-- (no <name> — this operates on a raw string; the IO-shell in 05-03 wraps the
-- per-file `'<name>'` framing). Layout/color reasons are the EXACT shipped
-- validate_layout/validate_color strings (single source).
-- ---------------------------------------------------------------------------
function M.load_and_map(raw_string)
  if not ok_toml or type(toml) ~= "table" then
    return nil, "error: scene recipe is invalid: TOML decoder unavailable"
  end

  local parsed_ok, result = pcall(toml.parse, raw_string, { load_from_string = true })
  if not parsed_ok then
    -- result is the raised error message; extract a line number when present.
    local line = tostring(result):match("line (%d+)")
    if line then
      return nil, "error: scene recipe is invalid: could not parse TOML at line " .. line
    end
    return nil, "error: scene recipe is invalid: could not parse TOML"
  end

  local recipe = result
  if type(recipe) ~= "table" or recipe.layout == nil then
    return nil, "error: scene recipe is invalid: missing required field 'layout'"
  end

  local layout_ok, layout_err = scene.validate_layout(recipe.layout)
  if not layout_ok then
    return nil, layout_err
  end

  if recipe.color ~= nil then
    local color_ok, color_err = scene.validate_color(recipe.color)
    if not color_ok then
      return nil, color_err
    end
  end

  return M.recipe_to_args(recipe)
end

return M
