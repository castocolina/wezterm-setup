-- Fixture tests for format-tab-title.lua pure helpers.
-- Run from this directory: `lua5.4 format-tab-title_test.lua`
-- No wezterm global required (pure helpers only).

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

io.write(string.format("\nformat-tab-title_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
