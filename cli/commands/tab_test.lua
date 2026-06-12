-- Fixture tests for cli/commands/tab.lua pure helpers.
-- Run from the repo root: `lua5.4 cli/commands/tab_test.lua`
-- No wezterm/session required (pure validate_color / parse_stored / merge_title).

local M = require("cli.commands.tab")

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

-- validate_color: 10 curated names (case-insensitive), hex (alpha stripped), reset
local function vc_ok(input) local ok, v = M.validate_color(input); return ok and v end
local function vc_err(input) local ok = M.validate_color(input); return ok == false end
eq("1 validate blue", vc_ok("blue"), "blue")
eq("2 validate BLUE (case-insensitive)", vc_ok("BLUE"), "blue")
eq("3 validate #1e3a5f", vc_ok("#1e3a5f"), "#1e3a5f")
eq("4 validate #1e3a5fff (alpha stripped)", vc_ok("#1e3a5fff"), "#1e3a5f")
eq("5 validate reset", vc_ok("reset"), "reset")
check("6 validate mauve -> error", vc_err("mauve"))
do
  local _, err = M.validate_color("mauve")
  check("6b error names the palette + hex", type(err) == "string"
    and err:find("blue", 1, true) ~= nil and err:find("#rgb", 1, true) ~= nil)
end

-- parse_stored: first-colon split, empty sides -> nil, bare token is the color
local function ps(s) local c, t = M.parse_stored(s); return c, t end
do local c, t = ps("blue:api"); check("7 'blue:api'", c == "blue" and t == "api") end
do local c, t = ps(":api"); check("8 ':api' (empty color)", c == nil and t == "api") end
do local c, t = ps("blue:"); check("9 'blue:' (empty title)", c == "blue" and t == nil) end
do local c, t = ps("blue:a:b"); check("10 'blue:a:b' (first colon only)", c == "blue" and t == "a:b") end
do local c, t = ps(""); check("11 '' -> nil,nil", c == nil and t == nil) end
do local c, t = ps(nil); check("12 nil -> nil,nil", c == nil and t == nil) end
do local c, t = ps("blue"); check("13 'blue' (bare token is the color)", c == "blue" and t == nil) end

-- merge_title: read-modify-write builder; colon ALWAYS present (D-02)
eq("14 swap color, keep title",
  M.merge_title({ cur_color = "green", cur_title = "api", set_color = "blue" }), "blue:api")
eq("15 fresh tab + color -> always-write-colon",
  M.merge_title({ cur_color = nil, cur_title = nil, set_color = "blue" }), "blue:")
eq("16 reset color, keep title",
  M.merge_title({ cur_color = "green", cur_title = "api", set_color = "" }), ":api")
-- structural: exactly one ':' separator in every form
local function one_colon(s) return type(s) == "string" and select(2, s:gsub(":", "")) == 1 end
check("17 ':api' has one colon",
  one_colon(M.merge_title({ cur_color = "green", cur_title = "api", set_color = "" })))
check("18 'blue:' has one colon",
  one_colon(M.merge_title({ cur_color = nil, cur_title = nil, set_color = "blue" })))
check("19 'blue:api' has one colon",
  one_colon(M.merge_title({ cur_color = "green", cur_title = "api", set_color = "blue" })))

-- 03-03: combined form — both set_color AND set_title in one merge (TAB-03)
eq("20 both halves set -> 'blue:api'",
  M.merge_title({ cur_color = nil, cur_title = nil, set_color = "blue", set_title = "api" }), "blue:api")
eq("21 title-only merge keeps color",
  M.merge_title({ cur_color = "blue", cur_title = "old", set_title = "api" }), "blue:api")
eq("22 empty title clears, keeps color",
  M.merge_title({ cur_color = "blue", cur_title = "api", set_title = "" }), "blue:")

io.write(string.format("\ntab_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
