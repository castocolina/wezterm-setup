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
-- 1.5* per-pane cwd/focus/size + top-level cwd + [[pane]] alias (D-04/D-07)
-- ============================================================================

-- 1h per-pane cwd/focus/size map to cwd=/focus=/size= segments (alongside cmd/color/title).
teq("1h recipe_to_args per-pane cwd/focus/size", M.recipe_to_args({
  layout = "tall",
  panes = { { command = "top", color = "teal", cwd = "~/x", focus = true, size = 30 } },
}), {
  layout = "tall", color = nil, title = nil, cwd = nil,
  pane = { "cmd=top, color=teal, cwd=~/x, focus=true, size=30" },
})

-- 1i cwd-only pane (bare-command fast path is dropped when ANY extra field present).
teq("1i recipe_to_args cwd-only pane", M.recipe_to_args({
  layout = "tall", panes = { { command = "vim", cwd = "/srv/app" } },
}), { layout = "tall", color = nil, title = nil, cwd = nil, pane = { "cmd=vim, cwd=/srv/app" } })

-- 1j top-level recipe cwd carried into args.cwd (tab-level default cwd, D-07).
teq("1j recipe_to_args top-level cwd carried", M.recipe_to_args({
  layout = "tall", cwd = "~/proj", panes = { { command = "shell" } },
}), { layout = "tall", color = nil, title = nil, cwd = "~/proj", pane = { "shell" } })

-- 1k size-only pane still emits a cmd= spec (size forces the keyed form).
teq("1k recipe_to_args size-only pane", M.recipe_to_args({
  layout = "horizontal", panes = { { command = "logs", size = 40 } },
}), { layout = "horizontal", color = nil, title = nil, cwd = nil, pane = { "cmd=logs, size=40" } })

-- 1l focus-only pane emits focus=true segment.
teq("1l recipe_to_args focus-only pane", M.recipe_to_args({
  layout = "tall", panes = { { command = "claude", focus = true } },
}), { layout = "tall", color = nil, title = nil, cwd = nil, pane = { "cmd=claude, focus=true" } })

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

-- 2h [[pane]] (singular) is accepted as an alias of [[panes]] through the loader.
do
  local raw = 'layout = "tall"\n[[pane]]\ncommand = "shell"\n[[pane]]\ncommand = "htop"\n'
  local args, err = M.load_and_map(raw)
  check("2h [[pane]] alias -> args, no err", err == nil and type(args) == "table")
  teq("2h2 [[pane]] alias args shape", args,
    { layout = "tall", color = nil, title = nil, cwd = nil, pane = { "shell", "htop" } })
end

-- 2i top-level cwd parses + is carried into args.cwd (D-07).
do
  local raw = 'layout = "tall"\ncwd = "~/proj"\n[[panes]]\ncommand = "shell"\n'
  local args, err = M.load_and_map(raw)
  check("2i top-level cwd -> args, no err", err == nil and type(args) == "table")
  eq("2i2 top-level cwd carried", args and args.cwd, "~/proj")
end

-- 2j per-pane cwd/focus/size round-trip through the loader into the spec string.
do
  local raw = table.concat({
    'layout = "tall"',
    '[[panes]]',
    'command = "top"', 'color = "teal"', 'cwd = "~/x"', 'focus = true', 'size = 30',
  }, "\n") .. "\n"
  local args, err = M.load_and_map(raw)
  check("2j per-pane fields -> args, no err", err == nil and type(args) == "table")
  teq("2j2 per-pane fields spec string", args, {
    layout = "tall", color = nil, title = nil, cwd = nil,
    pane = { "cmd=top, color=teal, cwd=~/x, focus=true, size=30" },
  })
end

-- 2k migration alias: a deprecated top-level color/title is still accepted (D-04).
do
  local raw = 'layout = "tall"\ncolor = "green"\ntitle = "Dev"\n[[panes]]\ncommand = "shell"\n'
  local args, err = M.load_and_map(raw)
  check("2k migration top-level color/title -> args, no err", err == nil and type(args) == "table")
  eq("2k2 migration color carried", args and args.color, "green")
  eq("2k3 migration title carried", args and args.title, "Dev")
end

-- 2l STYLED shell pane (06.1-07): a shell pane that ALSO carries color must
-- emit the multi-field `cmd=shell, color=...` form (NOT the bare `shell` fast
-- path) so the tint survives — D-13/D-14's teal working shell. A plain shell
-- pane with no styling still collapses to the bare `shell` keyword.
do
  local raw = table.concat({
    'layout = "tall"',
    '[[panes]]', 'command = "shell"', -- plain -> bare "shell"
    '[[panes]]', 'command = "shell"', 'color = "teal"', -- styled -> cmd=shell, color=teal
  }, "\n") .. "\n"
  local args, err = M.load_and_map(raw)
  check("2l styled shell -> args, no err", err == nil and type(args) == "table")
  teq("2l2 plain shell bare, teal shell carries color", args, {
    layout = "tall", color = nil, title = nil, cwd = nil,
    pane = { "shell", "cmd=shell, color=teal" },
  })
end

-- ============================================================================
-- 2.9* SEED FILES (06.1-07): the refreshed in-repo dev/ai seeds round-trip
-- through the loader to the exact run_new args shape (SCEN-04 launch ≡ new),
-- proving D-13/D-14 content + comma-safety (Pitfall 5). Reads the real shipped
-- files relative to the repo root so a future edit that breaks the schema fails
-- here, not silently at install time.
-- ============================================================================
do
  -- locate the repo root from this test file's path (cli/lib/ -> repo root).
  local this = (arg and arg[0]) or "cli/lib/recipe_test.lua"
  local root = this:match("^(.*)/cli/lib/[^/]+$") or "."
  local function load_seed(rel)
    local fh = io.open(root .. "/" .. rel, "rb")
    if not fh then return nil, "missing " .. rel end
    local raw = fh:read("*a"); fh:close()
    return M.load_and_map(raw)
  end

  -- dev: tall:mirrored, green, 3 panes (editor green / shell teal / git yellow),
  -- each titled with the {cwd} token (comma-free, so the --pane round-trip is safe).
  local dev, dev_err = load_seed("scenes/dev.toml")
  check("2.9a dev.toml round-trips, no err", dev_err == nil and type(dev) == "table")
  teq("2.9b dev.toml maps to the D-13 args", dev, {
    layout = "tall:mirrored", color = "green", title = "dev {cwd}", cwd = nil,
    pane = {
      "cmd=$EDITOR, color=green, title=edit {cwd}",
      "cmd=shell, color=teal, title=shell {cwd}",
      "cmd=git status, color=yellow, title=git {cwd}",
    },
  })

  -- ai: tall, purple, 2 panes (claude purple / shell teal).
  local ai, ai_err = load_seed("scenes/ai.toml")
  check("2.9c ai.toml round-trips, no err", ai_err == nil and type(ai) == "table")
  teq("2.9d ai.toml maps to the D-14 args", ai, {
    layout = "tall", color = "purple", title = nil, cwd = nil,
    pane = {
      "cmd=claude, color=purple",
      "cmd=shell, color=teal",
    },
  })
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
