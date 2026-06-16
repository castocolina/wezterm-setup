-- Fixture tests for cli/commands/tab.lua.
-- Run from the repo root: `lua5.4 cli/commands/tab_test.lua`
--
-- 06.1-03 decouple (D-02/D-03/D-04): `wez tab color` now emits WEZTERM_TAB_COLOR via
-- OSC 1337 (NO `<color>:<title>` prefix); `wez tab title` writes PURE title text via
-- set-tab-title. parse_stored survives ONLY as the warn_legacy_prefix_once parse helper
-- and is exercised here as the legacy parse-and-warn path. (The dead merge_title builder
-- was removed in IN-03 — 6.2 dropped the color:title encoding and nothing calls it.)

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

-- ── pure helpers ───────────────────────────────────────────────────────────

-- validate_color: 10 curated names (case-insensitive), hex (alpha PRESERVED, D-09), reset
local function vc_ok(input) local ok, v = M.validate_color(input); return ok and v end
local function vc_err(input) local ok = M.validate_color(input); return ok == false end
eq("1 validate blue", vc_ok("blue"), "blue")
eq("2 validate BLUE (case-insensitive)", vc_ok("BLUE"), "blue")
eq("3 validate #1e3a5f", vc_ok("#1e3a5f"), "#1e3a5f")
eq("4 validate #1e3a5fff (alpha PRESERVED, D-09)", vc_ok("#1e3a5fff"), "#1e3a5fff")
eq("5 validate reset", vc_ok("reset"), "reset")
check("6 validate mauve -> error", vc_err("mauve"))
do
  local _, err = M.validate_color("mauve")
  check("6b error names the palette + hex", type(err) == "string"
    and err:find("blue", 1, true) ~= nil and err:find("#rgb", 1, true) ~= nil)
end

-- parse_stored: migration helper — first-colon split, empty sides -> nil, bare token is the color
local function ps(s) local c, t = M.parse_stored(s); return c, t end
do local c, t = ps("blue:api"); check("7 'blue:api'", c == "blue" and t == "api") end
do local c, t = ps(":api"); check("8 ':api' (empty color)", c == nil and t == "api") end
do local c, t = ps("blue:"); check("9 'blue:' (empty title)", c == "blue" and t == nil) end
do local c, t = ps("blue:a:b"); check("10 'blue:a:b' (first colon only)", c == "blue" and t == "a:b") end
do local c, t = ps(""); check("11 '' -> nil,nil", c == nil and t == nil) end
do local c, t = ps(nil); check("12 nil -> nil,nil", c == nil and t == nil) end
do local c, t = ps("blue"); check("13 'blue' (bare token is the color)", c == "blue" and t == nil) end

-- merge_title was REMOVED (IN-03): it was the dead read-modify-write builder for the
-- legacy "<color>:<title>" encoding, which 6.2 dropped (D-04/D-05). Assert it is gone
-- so a re-introduction is caught.
check("14 merge_title is removed (IN-03)", M.merge_title == nil)

-- ── I/O surface: stub the seams (read/write), capture io.write OSC ────────────

local function with_seams(fn)
  local writes, osc = {}, {}
  local real_execute_write, real_read, real_iowrite = M.write_tab_title, M.read_current_tab, io.write
  -- capture pure-text set-tab-title writes
  M.write_tab_title = function(str, tab_id) writes[#writes + 1] = str; return 0 end
  -- capture io.write OSC emission (the WEZTERM_TAB_COLOR accent)
  io.write = function(...) for _, v in ipairs({ ... }) do osc[#osc + 1] = tostring(v) end end
  local function set_read(r) M.read_current_tab = function() return r end end
  set_read({ tab_id = nil, tab_title = "" })
  local code = fn(set_read)
  M.write_tab_title, M.read_current_tab, io.write = real_execute_write, real_read, real_iowrite
  return code, table.concat(osc), writes
end

local function cap_stderr(fn)
  local err = {}
  local real = io.stderr
  io.stderr = { write = function(_self, ...) for _, v in ipairs({ ... }) do err[#err + 1] = tostring(v) end end }
  local code = fn()
  io.stderr = real
  return code, table.concat(err)
end

-- 15: `wez tab color green` -> emits WEZTERM_TAB_COLOR OSC, NO set-tab-title write, NO prefix
do
  local code, osc, writes = with_seams(function() return M.run({ tab_cmd = "color", value = "green" }) end)
  check("15 tab color green: exit 0", code == 0)
  check("15 tab color green: emits WEZTERM_TAB_COLOR OSC (no prefix)",
    osc == M.build_osc1337("WEZTERM_TAB_COLOR", "green"))
  check("15 tab color green: NO set-tab-title write (decoupled)", #writes == 0)
  check("15 tab color green: no 'green:' literal anywhere", osc:find("green:", 1, true) == nil)
end

-- 16: `wez tab color reset` -> emits empty WEZTERM_TAB_COLOR (clears accent)
do
  local code, osc, writes = with_seams(function() return M.run({ tab_cmd = "color", value = "reset" }) end)
  check("16 tab color reset: exit 0", code == 0)
  check("16 tab color reset: emits empty WEZTERM_TAB_COLOR",
    osc == M.build_osc1337("WEZTERM_TAB_COLOR", ""))
  check("16 tab color reset: NO set-tab-title write", #writes == 0)
end

-- 17: `wez tab color #1a2040cc` -> validates (D-09) + emits the 8-digit value verbatim
do
  local code, osc = with_seams(function() return M.run({ tab_cmd = "color", value = "#1a2040cc" }) end)
  check("17 tab color #rrggbbaa: exit 0 (D-09)", code == 0)
  check("17 tab color #rrggbbaa: emits the 8-digit value",
    osc == M.build_osc1337("WEZTERM_TAB_COLOR", "#1a2040cc"))
end

-- 18: combined `wez tab color blue --title api` -> TWO distinct writes:
--     OSC WEZTERM_TAB_COLOR=blue AND pure-text set-tab-title 'api' (no encoding)
do
  local code, osc, writes = with_seams(function()
    return M.run({ tab_cmd = "color", value = "blue", title = "api" })
  end)
  check("18 combined: exit 0", code == 0)
  check("18 combined: OSC emits WEZTERM_TAB_COLOR=blue",
    osc == M.build_osc1337("WEZTERM_TAB_COLOR", "blue"))
  check("18 combined: exactly one pure-text set-tab-title write", #writes == 1)
  check("18 combined: title write is PURE 'api' (no color prefix)", writes[1] == "api")
end

-- 19: combined title is literal (D-05 — first word no longer swapped for a glyph)
do
  local _, _, writes = with_seams(function()
    return M.run({ tab_cmd = "color", value = "blue", title = "docker build" })
  end)
  check("19 combined: title is literal 'docker build' (D-05)", writes[1] == "docker build")
end

-- 20: `wez tab title api` -> set-tab-title 'api' PURE text, no color prefix, no OSC
do
  local code, osc, writes = with_seams(function()
    return M.run({ tab_cmd = "title", words = { "api" } })
  end)
  check("20 tab title api: exit 0", code == 0)
  check("20 tab title api: pure-text set-tab-title 'api'", #writes == 1 and writes[1] == "api")
  check("20 tab title api: NO color OSC emitted", osc == "")
end

-- 21: `wez tab title docker compose up` -> literal pure text (D-05, no glyph swap)
do
  local _, _, writes = with_seams(function()
    return M.run({ tab_cmd = "title", words = { "docker", "compose", "up" } })
  end)
  check("21 tab title literal: 'docker compose up' (D-05)", writes[1] == "docker compose up")
end

-- 22: `wez tab title reset` -> set-tab-title '' (empty), no color prefix
do
  local _, osc, writes = with_seams(function()
    return M.run({ tab_cmd = "title", words = { "reset" } })
  end)
  check("22 tab title reset: empty pure-text write", #writes == 1 and writes[1] == "")
  check("22 tab title reset: NO color OSC emitted", osc == "")
end

-- 23: invalid color bails validate-before-emit (exit 2) with ZERO writes
do
  local writes, osc_count = {}, 0
  local code, err = cap_stderr(function()
    local c
    local _, o, w = with_seams(function() c = M.run({ tab_cmd = "color", value = "mauve" }) end)
    osc_count = #o
    for i, v in ipairs(w) do writes[i] = v end
    return c
  end)
  check("23 invalid: exit 2", code == 2)
  check("23 invalid: ZERO OSC bytes emitted (validate-before-emit)", osc_count == 0)
  check("23 invalid: ZERO set-tab-title writes", #writes == 0)
  check("23 invalid: stderr has 'wez tab color:' + the bad token",
    err:find("wez tab color:", 1, true) and err:find("mauve", 1, true))
end

-- 24: migration parse-and-warn — reading a LEGACY '<color>:<title>' stored title warns ONCE,
--     then the steady-state write is still clean (color via OSC, no prefix re-emitted)
do
  local warned
  local _, err = cap_stderr(function()
    return (with_seams(function(set_read)
      set_read({ tab_id = 7, tab_title = "cyan:api" }) -- a legacy-prefixed live tab
      return M.run({ tab_cmd = "color", value = "blue" })
    end))
  end)
  warned = err:find("legacy", 1, true) ~= nil or err:find("migrat", 1, true) ~= nil
  check("24 migration: legacy prefix triggers a one-time warn", warned)
end

-- ── 06.2-02: icon subcommand + --icon on title + --follow-pane-color + legacy warn ──

local title = require("cli.lib.title")

-- with_seams captures io.write OSC + set-tab-title writes; cap_stderr captures stderr.
-- Several 6.2 cases need BOTH at once, so wrap with_seams inside cap_stderr.

-- 25: `wez tab icon node` -> emits WEZTERM_TAB_ICON OSC for the node glyph, NO set-tab-title
do
  local code, osc, writes = with_seams(function() return M.run({ tab_cmd = "icon", value = "node" }) end)
  check("25 tab icon node: exit 0", code == 0)
  check("25 tab icon node: emits WEZTERM_TAB_ICON for the node glyph",
    osc == M.build_osc1337("WEZTERM_TAB_ICON", title.resolve_icon("node")))
  check("25 tab icon node: NO set-tab-title write", #writes == 0)
end

-- 26: `wez tab icon 🔥` (literal glyph, D-02) -> emits the literal verbatim
do
  local _, osc = with_seams(function() return M.run({ tab_cmd = "icon", value = "🔥" }) end)
  check("26 tab icon literal glyph: emits the literal (D-02)",
    osc == M.build_osc1337("WEZTERM_TAB_ICON", "🔥"))
end

-- 27: `wez tab icon reset` / empty -> clears the icon (empty payload)
do
  local _, osc1 = with_seams(function() return M.run({ tab_cmd = "icon", value = "reset" }) end)
  check("27 tab icon reset: clears WEZTERM_TAB_ICON",
    osc1 == M.build_osc1337("WEZTERM_TAB_ICON", ""))
  local _, osc2 = with_seams(function() return M.run({ tab_cmd = "icon", value = nil }) end)
  check("27 tab icon (no value): clears WEZTERM_TAB_ICON",
    osc2 == M.build_osc1337("WEZTERM_TAB_ICON", ""))
end

-- 28: `wez tab title api --icon node` -> TWO writes: pure-text title 'api' AND a WEZTERM_TAB_ICON OSC
do
  local code, osc, writes = with_seams(function()
    return M.run({ tab_cmd = "title", words = { "api" }, icon = "node" })
  end)
  check("28 title --icon: exit 0", code == 0)
  check("28 title --icon: pure-text set-tab-title 'api'", #writes == 1 and writes[1] == "api")
  check("28 title --icon: emits WEZTERM_TAB_ICON for the node glyph",
    osc == M.build_osc1337("WEZTERM_TAB_ICON", title.resolve_icon("node")))
end

-- 29: `wez tab color green` emits ONLY WEZTERM_TAB_COLOR, never WEZTERM_TAB_FOLLOW_PANE (default OFF)
do
  local _, osc = with_seams(function() return M.run({ tab_cmd = "color", value = "green" }) end)
  check("29 tab color (no flag): NO WEZTERM_TAB_FOLLOW_PANE emit (default OFF, D-09)",
    osc:find("WEZTERM_TAB_FOLLOW_PANE", 1, true) == nil)
end

-- 30: `wez tab color green --follow-pane-color` ALSO emits WEZTERM_TAB_FOLLOW_PANE="1"
do
  local code, osc = with_seams(function()
    return M.run({ tab_cmd = "color", value = "green", follow_pane_color = true })
  end)
  check("30 follow-pane-color: exit 0", code == 0)
  check("30 follow-pane-color: emits WEZTERM_TAB_COLOR then WEZTERM_TAB_FOLLOW_PANE='1'",
    osc == M.build_osc1337("WEZTERM_TAB_COLOR", "green")
      .. M.build_osc1337("WEZTERM_TAB_FOLLOW_PANE", "1"))
end

-- 31: legacy-icon-name leading word in a literal title -> title stays literal AND a warn fires.
--     `wez tab title node api`: title text is the literal "node api" (NO swap, D-05), warn to stderr.
do
  title.reset_legacy_icon_warn() -- one-time guard: reset so this case can observe the warn
  local code, err, writes
  code, err = cap_stderr(function()
    local _, _, w = with_seams(function()
      return M.run({ tab_cmd = "title", words = { "node", "api" } })
    end)
    writes = w
    return 0
  end)
  check("31 legacy warn: title text stays literal 'node api' (NO swap, D-05)",
    writes ~= nil and #writes == 1 and writes[1] == "node api")
  check("31 legacy warn: a warn is written to stderr suggesting `wez tab icon`",
    err:find("wez tab icon", 1, true) ~= nil)
  check("31 legacy warn: the warn names the offending word 'node'", err:find("node", 1, true) ~= nil)
  _ = code
end

-- 32: a non-icon leading word emits NO warn.
do
  title.reset_legacy_icon_warn()
  local _, err = cap_stderr(function()
    with_seams(function() return M.run({ tab_cmd = "title", words = { "deploy", "api" } }) end)
    return 0
  end)
  -- "deploy" IS a known ICONS key, so use a truly unknown leading word instead.
  local _, err2 = cap_stderr(function()
    with_seams(function() return M.run({ tab_cmd = "title", words = { "frobnicate", "api" } }) end)
    return 0
  end)
  check("32 non-icon leading word: NO warn", err2:find("looks like a legacy", 1, true) == nil)
  _ = err
end

-- 33: the warn fires AT MOST once per process (one-time guard, D-06).
do
  title.reset_legacy_icon_warn()
  local _, err = cap_stderr(function()
    with_seams(function() return M.run({ tab_cmd = "title", words = { "node", "a" } }) end)
    with_seams(function() return M.run({ tab_cmd = "title", words = { "python", "b" } }) end)
    return 0
  end)
  local _, count = err:gsub("looks like a legacy", "")
  check("33 one-time warn: at most one legacy warn per process", count <= 1)
end

io.write(string.format("\ntab_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
