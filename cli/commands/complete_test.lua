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

io.write(string.format("\ncomplete_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
