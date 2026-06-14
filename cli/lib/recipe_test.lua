-- Fixture tests for cli/lib/recipe.lua (pure TOML recipe loader/mapper/guard).
-- Run from the repo root: `lua5.4 cli/lib/recipe_test.lua`
-- Pure: no wezterm / no I/O. Mirrors cli/lib/scene_test.lua's check/eq/teq harness.

local M = require("cli.lib.recipe")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else
    fail = fail + 1
    io.stderr:write("FAIL: " .. name .. "\n")
  end
end
local function eq(name, got, want)
  check(name .. " (got " .. tostring(got) .. ")", got == want)
end

-- Recursive table comparison (==/eq only compares scalars / table identity).
local function deep_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end
local function dump(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for k, val in pairs(v) do
    parts[#parts + 1] = tostring(k) .. "=" .. (type(val) == "table" and dump(val) or tostring(val))
  end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end
local function teq(name, got, want)
  check(name .. " (got " .. dump(got) .. ")", deep_eq(got, want))
end

-- ============================================================================
-- 1* recipe_to_args(recipe) -> args table run_new consumes
-- ============================================================================

-- 1a valid two-shell-pane recipe: layout/color carried, both panes -> "shell".
teq("1a recipe_to_args two shells", M.recipe_to_args({
  layout = "tall", color = "green",
  panes = { { command = "shell" }, { command = "shell" } },
}), { layout = "tall", color = "green", title = nil, pane = { "shell", "shell" } })

-- 1b docker-shape recipe (grid/teal): bare-command fast path, comma-free commands.
teq("1b recipe_to_args docker shape", M.recipe_to_args({
  layout = "grid", color = "teal",
  panes = {
    { command = "docker stats" },
    { command = "docker ps" },
    { command = "docker compose logs -f" },
    { command = "shell" },
  },
}), {
  layout = "grid", color = "teal", title = nil,
  pane = { "docker stats", "docker ps", "docker compose logs -f", "shell" },
})

-- 1c multi-field pane -> 'cmd=..., color=..., title=...' spec string.
teq("1c recipe_to_args multi-field pane", M.recipe_to_args({
  layout = "tall",
  panes = { { command = "vim", color = "teal", title = "edit" } },
}), { layout = "tall", color = nil, title = nil, pane = { "cmd=vim, color=teal, title=edit" } })

-- 1d `cmd` alias (kitty parity) maps identically to `command`.
teq("1d recipe_to_args cmd alias", M.recipe_to_args({
  layout = "tall",
  panes = { { cmd = "vim", color = "teal", title = "edit" } },
}), { layout = "tall", color = nil, title = nil, pane = { "cmd=vim, color=teal, title=edit" } })

-- 1e a pane with no command at all -> "shell" (D-04 default).
teq("1e recipe_to_args no-command pane -> shell", M.recipe_to_args({
  layout = "tall", panes = { {} },
}), { layout = "tall", color = nil, title = nil, pane = { "shell" } })

-- 1f `pane` accepted as fallback alias for `panes`.
teq("1f recipe_to_args pane alias", M.recipe_to_args({
  layout = "tall", pane = { { command = "htop" } },
}), { layout = "tall", color = nil, title = nil, pane = { "htop" } })

-- 1g top-level title carried through.
teq("1g recipe_to_args title carried", M.recipe_to_args({
  layout = "tall", title = "Dev", panes = { { command = "shell" } },
}), { layout = "tall", color = nil, title = "Dev", pane = { "shell" } })

-- ============================================================================
-- 2* load_and_map(raw_string) -> (args | nil, errmsg)
-- ============================================================================

-- 2a valid recipe string parses, validates, and maps.
do
  local raw = 'layout = "tall"\ncolor = "green"\n[[panes]]\ncommand = "shell"\n[[panes]]\ncommand = "shell"\n'
  local args, err = M.load_and_map(raw)
  check("2a valid recipe -> args, no err", err == nil and type(args) == "table")
  teq("2a2 valid recipe args shape", args,
    { layout = "tall", color = "green", title = nil, pane = { "shell", "shell" } })
end

-- 2b docker-shape recipe string parses + maps.
do
  local raw = table.concat({
    'layout = "grid"', 'color = "teal"',
    '[[panes]]', 'command = "docker stats"',
    '[[panes]]', 'command = "docker ps"',
    '[[panes]]', 'command = "docker compose logs -f"',
    '[[panes]]', 'command = "shell"',
  }, "\n") .. "\n"
  local args, err = M.load_and_map(raw)
  check("2b docker recipe -> args, no err", err == nil and type(args) == "table")
  teq("2b2 docker recipe args shape", args, {
    layout = "grid", color = "teal", title = nil,
    pane = { "docker stats", "docker ps", "docker compose logs -f", "shell" },
  })
end

-- 2c missing top-level layout -> nil + UI-SPEC reason copy.
do
  local args, err = M.load_and_map('color = "green"\n[[panes]]\ncommand = "shell"\n')
  check("2c missing layout -> nil", args == nil)
  eq("2c2 missing layout message", err,
    "error: scene recipe is invalid: missing required field 'layout'")
end

-- 2d unknown layout 'foo' -> nil + EXACT validate_layout string.
do
  local args, err = M.load_and_map('layout = "foo"\n[[panes]]\ncommand = "shell"\n')
  check("2d unknown layout -> nil", args == nil)
  eq("2d2 unknown layout message", err,
    "error: unknown layout 'foo' — expected one of: tall, tall:mirrored, grid, horizontal")
end

-- 2e unknown top-level color 'mauve' -> nil + EXACT validate_color string.
do
  local args, err = M.load_and_map('layout = "tall"\ncolor = "mauve"\n[[panes]]\ncommand = "shell"\n')
  check("2e unknown color -> nil", args == nil)
  eq("2e2 unknown color message", err,
    "error: unknown color 'mauve' — expected one of: red, orange, yellow, green, teal, cyan, blue, navy, purple, pink")
end

-- 2f malformed TOML -> nil + "could not parse TOML at line <N>" (pcall caught, no traceback).
do
  local args, err = M.load_and_map('layout = \n[[panes]]\ncommand = "shell"\n')
  check("2f malformed TOML -> nil", args == nil)
  check("2f2 malformed TOML message (line N)",
    type(err) == "string" and err:match("^error: scene recipe is invalid: could not parse TOML") ~= nil)
end

-- 2g a recipe with no color is valid (color is optional; only layout required).
do
  local args, err = M.load_and_map('layout = "tall"\n[[panes]]\ncommand = "shell"\n')
  check("2g no-color recipe -> args, no err", err == nil and type(args) == "table")
  eq("2g2 no-color recipe color is nil", args and args.color, nil)
end

-- ============================================================================
-- 3* guard_name(name) -> (bool[, errmsg]) — path-traversal guard (T-05-01)
-- ============================================================================
do
  check("3a guard_name empty rejected", M.guard_name("") == false)
  check("3b guard_name nil rejected", M.guard_name(nil) == false)
  check("3c guard_name 'a/b' rejected", M.guard_name("a/b") == false)
  check("3d guard_name '../etc' rejected", M.guard_name("../etc") == false)
  check("3e guard_name '..' rejected", M.guard_name("..") == false)
  check("3f guard_name 'dev' accepted", M.guard_name("dev") == true)
  check("3g guard_name 'docker' accepted", M.guard_name("docker") == true)
end

io.write(string.format("\nrecipe_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
