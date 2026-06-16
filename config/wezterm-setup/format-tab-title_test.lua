-- Fixture tests for format-tab-title.lua pure helpers.
-- Run from this directory (`lua5.4 format-tab-title_test.lua`) OR from the repo
-- root via tools/run-tests.sh — the preamble below makes the bare require resolve
-- regardless of CWD by putting THIS file's directory on package.path.
-- No wezterm global required (pure helpers only).

local here = (arg and arg[0] or ""):match("^(.*)/[^/]+$") or "."
package.path = here .. "/?.lua;" .. package.path

local M = require("format-tab-title")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    io.stderr:write("FAIL: " .. name .. "\n")
  end
end

-- resolve_profile
check("1 resolve navy", M.resolve_profile("navy").bg == "#1a2040" and M.resolve_profile("navy").fg == "#c8cce0")
check("2 resolve NAVY (case-insensitive)", M.resolve_profile("NAVY").bg == "#1a2040")
check("3 resolve nil -> default", M.resolve_profile(nil).bg == "#333333" and M.resolve_profile(nil).fg == "#c0c0c0")
check("4 resolve unknown -> default", M.resolve_profile("fuschia").bg == "#333333")
check("5 resolve raw hex -> hex bg + default fg",
  M.resolve_profile("#1a2040").bg == "#1a2040" and M.resolve_profile("#1a2040").fg == "#c0c0c0")
-- D-09: an 8-digit #RRGGBBAA accent is accepted (alpha not stripped), NOT default-fallback.
-- (Alpha only RENDERS with window transparency — Pitfall 4 — but the value must resolve.)
check("5a resolve #RRGGBBAA (8-digit alpha) -> accepted, not default",
  M.resolve_profile("#1a2040cc").bg == "#1a2040cc" and M.resolve_profile("#1a2040cc").fg == "#c0c0c0")
check("5b resolve #RRGGBBAA case-insensitive",
  M.resolve_profile("#1A2040CC").bg == "#1a2040cc")
-- A malformed/too-long hex still falls back to the default (tamper safety, T-06.1-12).
check("5c resolve 10-digit garbage -> default", M.resolve_profile("#1a2040ccff").bg == "#333333")

-- format_label
local l6 = M.format_label(0, "build", 40)
check("6 format_label index+prefix", l6:sub(1, 8) == "1: build")
local l7 = M.format_label(0, string.rep("x", 100), 20)
check("7 format_label truncates to max_width-4", #l7 <= 20 - 4)

-- build_runs (active)
local navy = M.resolve_profile("navy")
local a = M.build_runs(true, navy, "1: build ")
local a_has_bg = a[1].Background and a[1].Background.Color == "#1a2040"
local a_has_indicator, a_has_bold, a_has_white = false, false, false
for _, run in ipairs(a) do
  if run.Text == " ●-> " then a_has_indicator = true end
  if run.Attribute and run.Attribute.Intensity == "Bold" then a_has_bold = true end
  if run.Foreground and run.Foreground.Color == "#ffffff" then a_has_white = true end
end
check("8 active runs: bg+indicator+bold+white", a_has_bg and a_has_indicator and a_has_bold and a_has_white)

-- build_runs (inactive)
local i = M.build_runs(false, navy, "1: build ")
local i_has_bg = i[1].Background and i[1].Background.Color == "#1a2040"
local i_has_profile_fg, i_has_indicator = false, false
for _, run in ipairs(i) do
  if run.Foreground and run.Foreground.Color == "#c8cce0" then i_has_profile_fg = true end
  if run.Text == " ●-> " then i_has_indicator = true end
end
check("9 inactive runs: bg + profile fg, no indicator", i_has_bg and i_has_profile_fg and not i_has_indicator)

-- profile table completeness
local names = { "red", "orange", "yellow", "green", "teal", "cyan", "blue", "navy", "purple", "pink" }
local count = 0
for _ in pairs(M.color_profiles) do count = count + 1 end
check("10 color_profiles has 10 entries", count == 10)
for _, n in ipairs(names) do
  check("10." .. n .. " present", M.color_profiles[n] ~= nil)
end

-- Handler-body integration: mock the wezterm global, let M.apply register the
-- format-tab-title callback into the mock, then invoke it with fake tabs.
-- This exercises the real handler logic (user_vars read, title fallback,
-- build_runs) without a GUI.
local captured
package.preload["wezterm"] = function()
  return {
    on = function(name, fn) if name == "format-tab-title" then captured = fn end end,
    truncate_right = function(s, n) return s:sub(1, n) end,
  }
end
M.apply({})
check("11 apply registered a format-tab-title handler", type(captured) == "function")

local function fake_tab(uv, is_active, tab_title, pane_title, idx)
  return {
    active_pane = { user_vars = uv or {}, title = pane_title or "" },
    tab_title = tab_title or "",
    is_active = is_active and true or false,
    tab_index = idx or 0,
  }
end

local function find_text(runs)
  local t = ""
  for _, r in ipairs(runs) do if r.Text then t = t .. r.Text end end
  return t
end

-- navy pane color + custom title, active tab
local r_navy = captured(fake_tab({ WEZTERM_TAB_COLOR = "navy", WEZTERM_TAB_TITLE = "build" }, true, "", "sleep", 0), {}, {}, {}, false, 40)
check("12 handler applies navy bg from user var", r_navy[1].Background.Color == "#1a2040")
check("13 handler uses WEZTERM_TAB_TITLE over pane title", find_text(r_navy):find("build", 1, true) ~= nil)
check("14 active tab shows the indicator", find_text(r_navy):find("●%->") ~= nil)

-- no user var -> default profile, falls back to pane title
local r_def = captured(fake_tab({}, false, "", "myshell", 0), {}, {}, {}, false, 40)
check("15 no user var -> default bg", r_def[1].Background.Color == "#333333")
check("16 falls back to pane title when no custom title", find_text(r_def):find("myshell", 1, true) ~= nil)

-- parse_tab_title
local p17c, p17t = M.parse_tab_title("navy:build")
check("17 'navy:build' -> color=navy, title=build", p17c == "navy" and p17t == "build")

local p18c, p18t = M.parse_tab_title("blue")
check("18 'blue' (bare, no colon) -> color=blue, title=nil", p18c == "blue" and p18t == nil)

local p19c, p19t = M.parse_tab_title("teal:")
check("19 'teal:' (trailing colon, empty title) -> color=teal, title=nil", p19c == "teal" and p19t == nil)

local p20c, p20t = M.parse_tab_title("purple:a:b")
check("20 'purple:a:b' (title contains colon) -> color=purple, title='a:b'", p20c == "purple" and p20t == "a:b")

local p21c, p21t = M.parse_tab_title("")
check("21 '' (empty string) -> color=nil, title=nil", p21c == nil and p21t == nil)

local p22c, p22t = M.parse_tab_title(nil)
check("22 nil -> color=nil, title=nil", p22c == nil and p22t == nil)

local p23c, p23t = M.parse_tab_title(":onlytitle")
check("23 ':onlytitle' (empty color, title set) -> color=nil, title=onlytitle", p23c == nil and p23t == "onlytitle")

-- D-02/D-04 steady-state precedence: the ACCENT derives from the active pane's
-- WEZTERM_TAB_COLOR ONLY. The legacy `<color>:<title>` prefix is NO LONGER consulted
-- for the accent in the steady state — it is migration grace for the DISPLAYED title
-- text only (a legacy stored title still renders, prefix stripped, no per-paint warning).

-- legacy stored "blue:api", no pane vars: accent is DEFAULT (prefix color NOT consulted),
-- but the title text "api" still renders (migration grace — display only, no crash).
local r24 = captured(fake_tab({}, false, "blue:api", "", 0), {}, {}, {}, false, 40)
check("24 legacy 'blue:api' -> default accent (prefix color dropped, D-02/D-04)", r24[1].Background.Color == "#333333")
check("24b legacy 'blue:api' -> display title 'api' (migration grace)", find_text(r24):find("api", 1, true) ~= nil)

-- legacy ":api" -> default accent, title still applied
local r25 = captured(fake_tab({}, false, ":api", "", 0), {}, {}, {}, false, 40)
check("25 legacy ':api' -> default accent", r25[1].Background.Color == "#333333")
check("25b legacy ':api' -> display title 'api'", find_text(r25):find("api", 1, true) ~= nil)

-- legacy "blue:" -> default accent (prefix color dropped), falls back to active_pane.title
local r26 = captured(fake_tab({}, false, "blue:", "myshell", 0), {}, {}, {}, false, 40)
check("26 legacy 'blue:' -> default accent (prefix color dropped)", r26[1].Background.Color == "#333333")
check("26b legacy 'blue:' -> falls back to pane title", find_text(r26):find("myshell", 1, true) ~= nil)

-- pane WEZTERM_TAB_COLOR is the ONLY accent source; a legacy prefix is ignored for color
-- but its title text still shows (migration grace).
local r27 = captured(fake_tab({ WEZTERM_TAB_COLOR = "navy" }, false, "blue:api", "", 0), {}, {}, {}, false, 40)
check("27 pane WEZTERM_TAB_COLOR is the accent (navy), prefix ignored", r27[1].Background.Color == "#1a2040")
check("27b legacy prefix title 'api' still displays under migration grace", find_text(r27):find("api", 1, true) ~= nil)

-- active legacy-prefix tab still shows the TAB-05 indicator
local r28 = captured(fake_tab({}, true, "blue:api", "", 0), {}, {}, {}, false, 40)
check("28 active legacy-prefix tab shows indicator", find_text(r28):find("●%->") ~= nil)

-- D-09 end-to-end: an active pane carrying a #RRGGBBAA accent paints that 8-digit color.
local r29 = captured(fake_tab({ WEZTERM_TAB_COLOR = "#1a2040cc" }, false, "", "sh", 0), {}, {}, {}, false, 40)
check("29 pane #RRGGBBAA accent paints the 8-digit color", r29[1].Background.Color == "#1a2040cc")

io.write(string.format("\nformat-tab-title_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
