-- Fixture tests for cli/commands/complete.lua dynamic contexts (02-05).
-- Run from the repo root: `lua5.4 cli/commands/complete_test.lua`

local complete = require("cli.commands.complete")
local pane = require("cli.commands.pane")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else
    fail = fail + 1
    io.stderr:write("FAIL: " .. name .. "\n")
  end
end

-- Capture what `__complete <context>` prints (newline-separated tokens).
local function run_context(ctx)
  local out = {}
  local real = io.write
  io.write = function(...) for _, v in ipairs({ ... }) do out[#out + 1] = tostring(v) end end
  local code = complete.run({ context = ctx })
  io.write = real
  local lines = {}
  for line in (table.concat(out)):gmatch("[^\n]+") do lines[#lines + 1] = line end
  return code, lines
end

local function set_of(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end

-- pane-colors: the 10 curated names + reset
local c1, colors = run_context("pane-colors")
check("pane-colors exits 0", c1 == 0)
check("pane-colors count == 10 names + reset", #colors == #pane.COLOR_NAMES + 1)
local cset = set_of(colors)
check("pane-colors includes navy", cset["navy"] == true)
check("pane-colors includes reset", cset["reset"] == true)
check("pane-colors has no duplicate source (derived from pane.COLOR_NAMES)", (function()
  for _, n in ipairs(pane.COLOR_NAMES) do if not cset[n] then return false end end
  return true
end)())

-- pane-icons: keys of the icon map, sorted
local c2, icons = run_context("pane-icons")
check("pane-icons exits 0", c2 == 0)
local iset = set_of(icons)
check("pane-icons includes docker", iset["docker"] == true)
check("pane-icons includes git", iset["git"] == true)
local n_icons = 0
for _ in pairs(pane.ICONS) do n_icons = n_icons + 1 end
check("pane-icons count matches pane.ICONS", #icons == n_icons)
check("pane-icons sorted", (function()
  for i = 2, #icons do if icons[i] < icons[i - 1] then return false end end
  return true
end)())

-- unknown context: no candidates, exit 0 (closed dispatch, must not error)
local c3, none = run_context("not-a-context")
check("unknown context exits 0", c3 == 0)
check("unknown context emits nothing", #none == 0)

-- subcommands context still works (regression) and now includes pane
local _, subs = run_context("subcommands")
check("subcommands includes pane", set_of(subs)["pane"] == true)
check("subcommands excludes __complete", set_of(subs)["__complete"] ~= true)

-- scene-layouts (04-03): exactly the 4 layout names, in M.LAYOUTS order, derived
-- from cli.lib.scene.LAYOUTS (single source of truth — the expected value is
-- BUILT from the required module, never a hardcoded literal, so the test itself
-- enforces no drift between validation and completion).
local scene = require("cli.lib.scene")
local c4, layouts = run_context("scene-layouts")
check("scene-layouts exits 0", c4 == 0)
check("scene-layouts count == #scene.LAYOUTS", #layouts == #scene.LAYOUTS)
check("scene-layouts is exactly scene.LAYOUTS in order", (function()
  for i, n in ipairs(scene.LAYOUTS) do if layouts[i] ~= n then return false end end
  return #layouts == #scene.LAYOUTS
end)())
check("scene-layouts not alphabetized (tall before grid)", (function()
  local idx = {}
  for i, n in ipairs(layouts) do idx[n] = i end
  return idx["tall"] and idx["grid"] and idx["tall"] < idx["grid"]
end)())

-- scene-colors (A-1 fix): the scene accent palette, derived from scene.COLOR_NAMES
-- (single source — the SAME array validate_color checks). NO `reset` (scene new
-- sets an accent at creation; there's nothing to reset). Expected value is built
-- from the required module, so the test enforces no drift.
local c4c, scolors = run_context("scene-colors")
check("scene-colors exits 0", c4c == 0)
check("scene-colors is exactly scene.COLOR_NAMES in order", (function()
  for i, n in ipairs(scene.COLOR_NAMES) do if scolors[i] ~= n then return false end end
  return #scolors == #scene.COLOR_NAMES
end)())
check("scene-colors does NOT include reset (creation, not reset)", (function()
  for _, n in ipairs(scolors) do if n == "reset" then return false end end
  return true
end)())

-- ----------------------------------------------------------------------------
-- scene-names (05-04, SCEN-05): recipe basenames read DYNAMICALLY at Tab time
-- from the scenes dir, via the SAME single provider launch uses
-- (scene.list_recipe_names(scene.scenes_dir())). The provider reads
-- WEZTERM_SETUP_DIR from the process env and shells out (io.popen "ls -1"), so
-- we seed real *.toml files on disk and drive the resolver from a child
-- `lua5.4 -e` with the env set — the SAME portable pattern as
-- scene_launch_test.lua / seed_scenes_test.lua (lua5.4 has no os.setenv).
-- ----------------------------------------------------------------------------
local function scratch_dir(tag)
  local base = os.getenv("TMPDIR") or "/tmp"
  local dir = string.format("%s/wezsetup-%s-%d-%d", base, tag, os.time(), math.random(1, 1e6))
  assert(os.execute("mkdir -p '" .. dir .. "/scenes'"))
  return dir
end

local function write_file(path, data)
  local fh = assert(io.open(path, "wb"))
  fh:write(data or "")
  fh:close()
end

-- Run `complete.run({context="scene-names"})` in a child with WEZTERM_SETUP_DIR
-- -> <setup>/scenes. Returns (exit_code, stdout_lines). Stdout is the candidate
-- list (one basename per line); stderr is discarded so only the emitted tokens
-- are asserted.
local function run_scene_names_child(setup)
  -- This test is run from the repo root (`lua5.4 cli/commands/complete_test.lua`),
  -- so the child resolves `cli/...` + vendored deps off the cwd-relative paths.
  local pp = "./?.lua;./cli/vendor/?.lua;"
  local body = string.format(
    "package.path=%q..package.path;"
      .. "local c=require('cli.commands.complete');"
      .. "os.exit(c.run({context='scene-names'}))",
    pp)
  local cmd = string.format("WEZTERM_SETUP_DIR=%q lua5.4 -e %q 2>/dev/null", setup, body)
  local p = assert(io.popen(cmd))
  local out = p:read("*a") or ""
  local _, _, code = p:close()
  local lines = {}
  for line in out:gmatch("[^\n]+") do lines[#lines + 1] = line end
  return code, lines
end

-- Case A: a scenes dir with b.toml + a.toml (+ a non-.toml file) -> sorted
-- basenames, no extension, the non-.toml ignored. Dynamic read proven below by
-- adding c.toml and re-running with NO regeneration.
do
  local home = scratch_dir("scene-names")
  write_file(home .. "/scenes/b.toml", "")
  write_file(home .. "/scenes/a.toml", "")
  write_file(home .. "/scenes/notes.txt", "") -- non-.toml MUST be ignored

  local code, names = run_scene_names_child(home)
  check("scene-names exits 0", code == 0 or code == true)
  check("scene-names lists sorted basenames a,b (no ext)",
    #names == 2 and names[1] == "a" and names[2] == "b")
  check("scene-names ignores non-.toml files", set_of(names)["notes"] ~= true)

  -- Dynamic: add c.toml, re-run, expect a,b,c with NO regeneration / no caching.
  write_file(home .. "/scenes/c.toml", "")
  local _, names2 = run_scene_names_child(home)
  check("scene-names is dynamic (c.toml appears with no regeneration)",
    #names2 == 3 and names2[1] == "a" and names2[2] == "b" and names2[3] == "c")

  os.execute("rm -rf '" .. home .. "'")
end

-- Case B: an EMPTY scenes dir -> nothing emitted, exit 0 (Tab-time no-op).
do
  local home = scratch_dir("scene-names-empty")
  local code, names = run_scene_names_child(home)
  check("scene-names empty dir exits 0", code == 0 or code == true)
  check("scene-names empty dir emits nothing", #names == 0)
  os.execute("rm -rf '" .. home .. "'")
end

-- Case C: a MISSING scenes dir -> nothing emitted, exit 0 (Tab-time no-op).
do
  local base = os.getenv("TMPDIR") or "/tmp"
  local home = string.format("%s/wezsetup-scene-names-missing-%d-%d", base, os.time(), math.random(1, 1e6))
  -- Deliberately do NOT create <home>/scenes.
  local code, names = run_scene_names_child(home)
  check("scene-names missing dir exits 0", code == 0 or code == true)
  check("scene-names missing dir emits nothing", #names == 0)
end

io.write(string.format("\ncomplete_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
