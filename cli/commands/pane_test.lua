-- Fixture tests for cli/commands/pane.lua.
-- Run from the repo root: `lua5.4 cli/commands/pane_test.lua`

local M = require("cli.commands.pane")

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

-- normalize_color (D-09: alpha PRESERVED, not stripped — shared cli/lib/color)
eq("1 normalize NAVY", M.normalize_color("NAVY"), "navy")
eq("2 normalize Navy", M.normalize_color("Navy"), "navy")
eq("3 normalize #1A2040", M.normalize_color("#1A2040"), "#1a2040")
eq("4 normalize #1a2040cc (alpha PRESERVED, D-09)", M.normalize_color("#1a2040cc"), "#1a2040cc")
eq("5 normalize #1a2c (alpha nibble PRESERVED, D-09)", M.normalize_color("#1a2c"), "#1a2c")
eq("6 normalize #1a2", M.normalize_color("#1a2"), "#1a2")
eq("7 normalize reset", M.normalize_color("reset"), "reset")

-- validate_color (D-09: 8-digit #RRGGBBAA validates and is PRESERVED)
local function vc_ok(input) local ok, v = M.validate_color(input); return ok and v end
local function vc_err(input) local ok = M.validate_color(input); return ok == false end
eq("12 validate navy", vc_ok("navy"), "navy")
eq("13 validate NAVY", vc_ok("NAVY"), "navy")
eq("14 validate #1a2040", vc_ok("#1a2040"), "#1a2040")
eq("15 validate #1a2040cc -> #1a2040cc (alpha preserved, D-09)", vc_ok("#1a2040cc"), "#1a2040cc")
eq("15b validate #1a2c (4-digit) -> #1a2c (D-09)", vc_ok("#1a2c"), "#1a2c")
eq("16 validate #1a2", vc_ok("#1a2"), "#1a2")
eq("17 validate reset", vc_ok("reset"), "reset")
check("18 validate fuschia -> error w/ names+hint", (function()
  local ok, err = M.validate_color("fuschia")
  return ok == false and err:find("unknown color", 1, true) and err:find("navy", 1, true) and err:find("#rrggbb", 1, true)
end)())
check("19 validate #zzzzzz rejected", vc_err("#zzzzzz"))
check("20 validate #12345 (5-digit) rejected", vc_err("#12345"))

-- build_osc11 / reset
eq("21 build_osc11", M.build_osc11("#14151c"), "\27]11;#14151c\27\\")
eq("22 build_reset_osc11", M.build_reset_osc11(), "\27]111\7")

-- build_osc1337 + base64
eq("23 base64(navy)", M._base64("navy"), "bmF2eQ==")
eq("23b build_osc1337 navy", M.build_osc1337("WEZTERM_TAB_COLOR", "navy"),
  "\27]1337;SetUserVar=WEZTERM_TAB_COLOR=bmF2eQ==\7")
eq("24 build_osc1337 empty clears", M.build_osc1337("WEZTERM_TAB_COLOR", ""),
  "\27]1337;SetUserVar=WEZTERM_TAB_COLOR=\7")

-- M.run (run_color) — capture stdout + stderr
local function capture(fn)
  local out, err = {}, {}
  local real_write, real_stderr = io.write, io.stderr
  io.write = function(...) for _, v in ipairs({ ... }) do out[#out + 1] = tostring(v) end end
  io.stderr = { write = function(_self, ...) for _, v in ipairs({ ... }) do err[#err + 1] = tostring(v) end end }
  local code = fn()
  io.write, io.stderr = real_write, real_stderr
  return code, table.concat(out), table.concat(err)
end

-- 25: invalid -> exit 2, stderr error, NO stdout (validate-before-emit)
local c25, o25, e25 = capture(function() return M.run({ pane_cmd = "color", value = "fuschia" }) end)
check("25 invalid: exit 2", c25 == 2)
check("25 invalid: no OSC emitted", o25 == "")
check("25 invalid: stderr has 'wez pane color:' + unknown", e25:find("wez pane color:", 1, true) and e25:find("fuschia", 1, true))

-- 26: navy -> dual write, exit 0
local c26, o26, e26 = capture(function() return M.run({ pane_cmd = "color", value = "navy" }) end)
check("26 navy: exit 0", c26 == 0)
check("26 navy: stdout = OSC11(muted navy) + OSC1337(WEZTERM_TAB_COLOR=navy)",
  o26 == M.build_osc11("#14151c") .. M.build_osc1337("WEZTERM_TAB_COLOR", "navy"))
check("26 navy: no stderr", e26 == "")

-- 27: #rrggbbaa + --opacity (D-09) -> alpha PRESERVED in both escapes, warn once, exit 0.
-- Pitfall 4: WezTerm renders alpha only with window transparency, so a caveat is still warned,
-- but the 8th digit is NO LONGER dropped — the value flows through verbatim.
local c27, o27, e27 = capture(function() return M.run({ pane_cmd = "color", value = "#1a2040cc", opacity = true }) end)
check("27 opacity: exit 0 (soft-degrade)", c27 == 0)
check("27 opacity: alpha PRESERVED in both escapes (D-09)",
  o27 == M.build_osc11("#1a2040cc") .. M.build_osc1337("WEZTERM_TAB_COLOR", "#1a2040cc"))
check("27 opacity: one-time transparency caveat on stderr", e27:find("transparency", 1, true) ~= nil)

-- 28: reset -> OSC 111 + clear var
local c28, o28 = capture(function() return M.run({ pane_cmd = "color", value = "reset" }) end)
check("28 reset: exit 0", c28 == 0)
check("28 reset: stdout = reset OSC11 + cleared var",
  o28 == M.build_reset_osc11() .. M.build_osc1337("WEZTERM_TAB_COLOR", ""))

-- ── 02-04: pane title ─────────────────────────────────────────────────────
eq("t1 resolve_title icon+text", M.resolve_title({ "docker", "compose", "up" }), "🐳 compose up")
eq("t2 resolve_title freeform", M.resolve_title({ "my", "task" }), "my task")
eq("t3 resolve_title emoji passthrough", M.resolve_title({ "🔥", "build" }), "🔥 build")
eq("t4 resolve_title icon only", M.resolve_title({ "docker" }), "🐳")
eq("t5 resolve_title empty -> clear", M.resolve_title({}), "")
eq("t6 resolve_title reset -> clear", M.resolve_title({ "reset" }), "")
eq("t7 resolve_title case-insensitive icon", M.resolve_title({ "Docker", "x" }), "🐳 x")
eq("t7b resolve_title empty-string arg -> clear", M.resolve_title({ "" }), "")

-- title emission via M.run
local ct8, ot8 = capture(function() return M.run({ pane_cmd = "title", words = { "docker", "compose", "up" } }) end)
check("t8 title: exit 0", ct8 == 0)
check("t8 title: emits OSC1337 WEZTERM_TAB_TITLE='🐳 compose up'",
  ot8 == M.build_osc1337("WEZTERM_TAB_TITLE", "🐳 compose up"))

local ct9, ot9 = capture(function() return M.run({ pane_cmd = "title", words = {} }) end)
check("t9 title clear: emits empty-payload var", ot9 == M.build_osc1337("WEZTERM_TAB_TITLE", ""))
check("t9 title clear: exit 0", ct9 == 0)

-- t10: a raw ESC byte in the title is base64-encoded (cannot break out of the OSC)
local _, ot10 = capture(function() return M.run({ pane_cmd = "title", words = { "x\27y" } }) end)
check("t10 title: raw ESC byte does not appear literally in the emitted sequence",
  ot10:find("\27]1337", 1, true) == 1 and ot10:sub(#"\27]1337;SetUserVar=WEZTERM_TAB_TITLE=" + 1):find("\27", 1, true) == nil)

io.write(string.format("\npane_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
