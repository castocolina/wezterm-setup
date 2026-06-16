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
--   * any extra field (color/title/cwd/focus/size)
--                                               -> "cmd=..., color=..., title=...,
--                                                   cwd=..., focus=true, size=N"
-- Accepts `cmd` as an alias for `command` (kitty parity, Open Q2). The
-- cwd/focus/size fields (D-05/D-06/D-07) are appended as their own segments and
-- round-trip through scene.parse_pane_spec (order-independent).
--
-- COMMA CAVEAT (Pitfall 5 / WR-01): a comma INSIDE a multi-field field value
-- would mis-split via parse_pane_spec (it splits on top-level commas), producing
-- a downstream "unknown key 'b'" parse error attributed to the user's spec (or a
-- silent field loss). v1's --pane mini-grammar uses `,` as the segment delimiter
-- and `=` as the key/value separator, so neither may appear in a field value.
-- Rather than let that surface as a confusing runtime parse error, we VALIDATE-
-- BEFORE-EMIT at map time (the project's standing pattern): a field value with a
-- comma is rejected with a clear, attributable diagnostic naming the field + value.
-- The comma-safe long-term fix is a structured M.run_new entry point (NOT here).
-- ---------------------------------------------------------------------------
local function assert_comma_free(field, value)
  if value ~= nil and tostring(value):find(",", 1, true) then
    return nil, string.format(
      "error: scene recipe is invalid: %s value must not contain a comma "
      .. "(v1 --pane grammar limitation): '%s'", field, tostring(value))
  end
  return true
end

-- Returns (spec_string | nil, errmsg). nil+errmsg when a field value carries a
-- comma the v1 --pane grammar cannot round-trip (WR-01).
local function pane_table_to_spec(p)
  local cmd = p.cmd or p.command
  local is_shell = (cmd == nil or cmd == "shell")
  -- A shell pane with NO styling is the plain `shell` keyword (D-04 — truly
  -- untouched, nothing sent). But a shell pane that ALSO carries
  -- color/cwd/focus/size (D-13/D-14's teal working shell) must round-trip its
  -- styling: emit the multi-field `cmd=shell, color=...` form, which
  -- parse_pane_spec demotes back to a shell pane (shell=true) while keeping the
  -- styling. Without this the bare-`shell` fast path would silently drop the tint.
  if is_shell and p.color == nil and p.title == nil and p.cwd == nil
    and p.focus == nil and p.size == nil and p.icon == nil then
    return "shell"
  end
  if is_shell then
    cmd = "shell"
  end
  -- WR-01: reject a comma in ANY field value that round-trips through the
  -- comma-delimited --pane spec, BEFORE building it. cmd is checked even on the
  -- bare-command fast path (a comma there would split into a bogus extra segment).
  for _, fv in ipairs({
    { "command", cmd }, { "color", p.color }, { "title", p.title },
    { "cwd", p.cwd }, { "icon", p.icon },
  }) do
    local ok_field, field_err = assert_comma_free(fv[1], fv[2])
    if not ok_field then
      return nil, field_err
    end
  end
  -- Bare-command fast path ONLY when no extra field is present (comma-safe seeds).
  -- D-03: a per-pane `icon` is an extra field, so it drops the fast path too.
  if p.color == nil and p.title == nil and p.cwd == nil
    and p.focus == nil and p.size == nil and p.icon == nil then
    return cmd
  end
  local segs = { "cmd=" .. cmd }
  if p.color then segs[#segs + 1] = "color=" .. p.color end
  if p.title then segs[#segs + 1] = "title=" .. p.title end
  if p.cwd then segs[#segs + 1] = "cwd=" .. p.cwd end
  if p.focus == true then segs[#segs + 1] = "focus=true" end
  if p.size ~= nil then segs[#segs + 1] = "size=" .. tostring(p.size) end
  -- D-03: per-pane icon round-trips as an icon= segment (raw name/glyph) consumed
  -- by scene.parse_pane_spec, mirroring the color= append above.
  if p.icon then segs[#segs + 1] = "icon=" .. p.icon end
  return table.concat(segs, ", ")
end

-- ---------------------------------------------------------------------------
-- M.recipe_to_args(recipe) -> (args table | nil, errmsg). PURE transform
-- (05-RESEARCH Pattern 1). Reads panes from recipe.panes (the chosen key, matching
-- README/UI-SPEC `[[panes]]`), accepting recipe.pane as a fallback alias ([[pane]],
-- D-04). Carries the top-level tab keys (color/title + the new top-level cwd, D-07)
-- so the IO-shell can apply a tab-level default cwd. Builds the exact shape
-- M.run_new consumes: { layout, color, title, cwd, pane = { <spec strings> } }.
-- WR-01: returns (nil, errmsg) when a pane field value carries a comma the v1
-- --pane grammar cannot round-trip.
-- ---------------------------------------------------------------------------
function M.recipe_to_args(recipe)
  local panes = recipe.panes or recipe.pane or {}
  local args = {
    layout = recipe.layout,
    color = recipe.color,
    title = recipe.title,
    cwd = recipe.cwd,
    -- D-03/D-09: tab-level icon + the follow_pane_color opt-in (default OFF when
    -- absent -> nil). Carried beside color/title/cwd so the IO-shell applies them
    -- to pane 1 (icon + the WEZTERM_TAB_FOLLOW_PANE carrier). launch ≡ new.
    icon = recipe.icon,
    follow_pane_color = recipe.follow_pane_color,
    pane = {},
  }
  for _, p in ipairs(panes) do
    local spec, spec_err = pane_table_to_spec(p)
    if spec == nil then
      return nil, spec_err
    end
    args.pane[#args.pane + 1] = spec
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
