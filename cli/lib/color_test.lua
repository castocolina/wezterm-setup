-- Fixture tests for cli/lib/color.lua (the shared color module — D-01 consolidation).
-- Run from the repo root: `lua5.4 cli/lib/color_test.lua`
-- Pure: no wezterm / no I/O. Mirrors cli/lib/scene_test.lua's check/eq/teq harness.
--
-- RED-first: this suite is authored BEFORE cli/lib/color.lua exists, so the
-- top-level require() fails and the run exits non-zero (the RED state). Once the
-- module lands (Task 2 / GREEN) every assertion below must pass.
--
-- D-09 lock: an 8-digit #RRGGBBAA color is ACCEPTED and PRESERVED (the alpha is
-- no longer stripped). The inverted cases vs. the old pane_test (which asserted a
-- strip to 6 digits) are intentional — they encode the new behavior.

local M = require("cli.lib.color")

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

-- Recursive table comparison for array/table fixtures (mirrors scene_test).
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
-- 1* normalize_color — lowercase; reset pass-through; alpha PRESERVED (D-09)
-- ============================================================================
eq("1a normalize GREEN -> green", M.normalize_color("GREEN"), "green")
eq("1b normalize Navy -> navy", M.normalize_color("Navy"), "navy")
eq("1c normalize reset", M.normalize_color("reset"), "reset")
eq("1d normalize #1A2040 -> #1a2040", M.normalize_color("#1A2040"), "#1a2040")
-- D-09: the 8-digit value is PRESERVED, NOT stripped to #1a2040.
eq("1e normalize #1A2040CC preserved (D-09)", M.normalize_color("#1A2040CC"), "#1a2040cc")
eq("1f normalize #1a2 unchanged", M.normalize_color("#1a2"), "#1a2")

-- ============================================================================
-- 2* validate_color — (ok, normalized) or (false, error_string)
-- ============================================================================
local function vc_ok(input) local ok, v = M.validate_color(input); return ok and v end
local function vc_err(input) local ok = M.validate_color(input); return ok == false end

eq("2a validate green", vc_ok("green"), "green")
eq("2b validate cyan", vc_ok("cyan"), "cyan")
eq("2c validate #1a2", vc_ok("#1a2"), "#1a2")
eq("2d validate #1a2040", vc_ok("#1a2040"), "#1a2040")
-- D-09 regression lock: 8-digit accepted AND preserved.
eq("2e validate #1a2040cc preserved (D-09)", vc_ok("#1a2040cc"), "#1a2040cc")
eq("2f validate reset", vc_ok("reset"), "reset")
check("2g validate bogus rejected", vc_err("bogus"))

-- The error string must list the 10 names AND the hex forms incl. #rrggbbaa.
do
  local ok, err = M.validate_color("bogus")
  check("2h bogus error is false", ok == false)
  for _, n in ipairs({ "red", "orange", "yellow", "green", "teal", "cyan", "blue", "navy", "purple", "pink" }) do
    check("2i error lists name " .. n, err:find(n, 1, true) ~= nil)
  end
  check("2j error lists #rrggbbaa", err:find("#rrggbbaa", 1, true) ~= nil)
end

-- ============================================================================
-- 3* palette + muted-bg map (verbatim from pane.lua)
-- ============================================================================
teq("3a COLOR_NAMES exact order", M.COLOR_NAMES,
  { "red", "orange", "yellow", "green", "teal", "cyan", "blue", "navy", "purple", "pink" })
eq("3b MUTED_BG green", M.MUTED_BG.green, "#161c17")
eq("3c MUTED_BG navy", M.MUTED_BG.navy, "#14151c")
do
  local all = true
  for _, n in ipairs(M.COLOR_NAMES) do
    if type(M.MUTED_BG[n]) ~= "string" then all = false end
  end
  check("3d MUTED_BG covers every name", all)
end

-- ============================================================================
-- 4* OSC builders (lifted verbatim from pane.lua)
-- ============================================================================
-- base64("green") under RFC 4648 == "Z3JlZW4=".
eq("4a _base64 green", M._base64("green"), "Z3JlZW4=")
eq("4b build_osc1337 WEZTERM_TAB_COLOR green",
  M.build_osc1337("WEZTERM_TAB_COLOR", "green"),
  "\27]1337;SetUserVar=WEZTERM_TAB_COLOR=" .. M._base64("green") .. "\7")
eq("4c build_osc11 #161c17", M.build_osc11("#161c17"), "\27]11;#161c17\27\\")
eq("4d build_reset_osc11", M.build_reset_osc11(), "\27]111\7")

-- ============================================================================
-- 5* build_user_var_octal — octal printf-payload form of the OSC 1337 bytes.
-- Computed FROM build_osc1337's bytes so the two stay coupled (Pitfall 2 reuse).
-- ============================================================================
do
  local raw = M.build_osc1337("WEZTERM_TAB_COLOR", "green")
  local expected = raw:gsub(".", function(c)
    return string.format("\\%03o", string.byte(c))
  end)
  eq("5a build_user_var_octal couples to build_osc1337",
    M.build_user_var_octal("WEZTERM_TAB_COLOR", "green"), expected)
end

-- ============================================================================
-- 6* rgba() discretion (D-09): the floor is #RRGGBBAA. rgba() is rejected
-- CLEANLY here (no traceback) — validate_color returns (false, <string>).
-- ============================================================================
do
  local ok, err = M.validate_color("rgba(30,95,46,0.5)")
  check("6a rgba rejected cleanly (false)", ok == false)
  check("6b rgba error is a string (no traceback)", type(err) == "string")
end

io.write(string.format("\ncolor_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
