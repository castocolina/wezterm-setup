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
-- WR-03: truncation lands on a codepoint boundary, never inside a multibyte glyph.
-- A label of fire emojis (4 bytes each) at a narrow max_width must NOT end in a
-- bare UTF-8 continuation byte (0x80-0xBF). utf8.len succeeds on a clean cut.
local l7a = M.format_label(0, string.rep("\u{1F525}", 8), 14)
-- The cut is on a codepoint boundary: utf8.len succeeds (every byte belongs to a
-- COMPLETE sequence — a byte-based sub would have left a half glyph that utf8.len
-- rejects with nil). It is also strictly shorter than the un-truncated input.
check("7a format_label keeps a valid UTF-8 cut (no split glyph)",
  utf8.len(l7a) ~= nil)
check("7b format_label actually truncated the multibyte label",
  utf8.len(l7a) ~= nil and utf8.len(l7a) <= 14 - 4)
-- Cross-check the OLD byte-based behaviour WOULD have split a glyph: a raw
-- sub(1, max_width-4) on the same label is NOT valid UTF-8 (proves the fix matters).
local raw_bytecut = (string.rep("\u{1F525}", 8)):sub(1, 14 - 4)
check("7b2 byte-based cut on the same label is invalid UTF-8 (regression guard)",
  utf8.len(raw_bytecut) == nil)
-- A clean ASCII label still truncates by byte/column count as before.
local l7c = M.format_label(0, string.rep("a", 100), 20)
check("7c format_label ASCII still truncates to max_width-4", #l7c <= 20 - 4)

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

-- Explicit `wez tab title` (tab.tab_title via set-tab-title) MUST render when no pane
-- WEZTERM_TAB_TITLE is set — it sits ABOVE the pane PROCESS title in precedence so an
-- explicit tab title beats the inherited "bash"/"sleep" process name (gap found in the
-- 6.2 live repro: the handler previously ignored tab.tab_title entirely).
local r_tt = captured(fake_tab({}, true, "api", "bash", 0), {}, {}, {}, false, 40)
check("16a explicit tab.tab_title renders over the pane process title", find_text(r_tt):find("api", 1, true) ~= nil)
check("16b explicit tab.tab_title suppresses the process title", find_text(r_tt):find("bash", 1, true) == nil)
-- The pane user var still WINS over an explicit tab title (active-pane precedence
-- preserved — this change is purely additive; existing behavior unchanged).
local r_both = captured(fake_tab({ WEZTERM_TAB_TITLE = "web" }, true, "api", "bash", 0), {}, {}, {}, false, 40)
check("16c pane WEZTERM_TAB_TITLE still wins over tab.tab_title", find_text(r_both):find("web", 1, true) ~= nil and find_text(r_both):find("api", 1, true) == nil)

-- ===========================================================================
-- D-05/D-06: parse_tab_title is REMOVED from the render path. The legacy
-- `<color>:<title>` encoding is no longer split — a stored "cyan:api" tab_title
-- renders verbatim (the colon carries no special meaning anymore).
-- ===========================================================================
check("17 parse_tab_title is removed", M.parse_tab_title == nil)

-- D-04: M.compose_label_text(icon, title) — icon left of title, single space.
check("18 compose icon + title", M.compose_label_text("X", "build") == "X build")
check("19 compose empty icon -> title only", M.compose_label_text("", "build") == "build")
check("20 compose nil icon -> title only", M.compose_label_text(nil, "build") == "build")
check("21 compose icon + empty title -> icon only (no trailing space)",
  M.compose_label_text("X", "") == "X")
check("22 compose nil icon + empty title -> empty", M.compose_label_text(nil, "") == "")

-- M.basename (duplicated from cli/lib/title.lua:68-73, lockstep).
check("23 basename '/x/myrepo' -> 'myrepo'", M.basename("/x/myrepo") == "myrepo")
check("24 basename '/' -> '/'", M.basename("/") == "/")
check("25 basename '' -> '/'", M.basename("") == "/")
check("26 basename trailing slash '/a/b/' -> 'b'", M.basename("/a/b/") == "b")
check("27 basename nil -> '/'", M.basename(nil) == "/")

-- M.title_with_fallback(title, icon, launch_dir): D-11/D-13.
check("28 fallback: non-empty title wins (D-11)",
  M.title_with_fallback("build", "X", "/x/repo") == "X build")
check("29 fallback: empty title, no icon -> basename (D-13)",
  M.title_with_fallback("", "", "/x/repo") == "repo")
check("30 fallback: empty title + icon -> icon + basename (D-13)",
  M.title_with_fallback("", "X", "/x/repo") == "X repo")
check("31 fallback: nil title, nil icon -> basename",
  M.title_with_fallback(nil, nil, "/x/repo") == "repo")

-- Handler e2e: icon + title compose
local r_icon = captured(fake_tab({ WEZTERM_TAB_ICON = "ICN", WEZTERM_TAB_TITLE = "build" }, false, "", "sh", 0), {}, {}, {}, false, 40)
check("32 handler composes icon left of title", find_text(r_icon):find("ICN build", 1, true) ~= nil)

-- Handler e2e: empty title falls back to cwd basename via pane title (no cwd available)
local r_fb = captured(fake_tab({}, false, "", "shell", 0), {}, {}, {}, false, 40)
check("33 handler empty title falls back to pane title basename", find_text(r_fb):find("shell", 1, true) ~= nil)

-- Handler e2e: empty title + icon -> icon + basename
local r_fbi = captured(fake_tab({ WEZTERM_TAB_ICON = "ICN" }, false, "", "myshell", 0), {}, {}, {}, false, 40)
check("34 handler empty title + icon -> icon + basename", find_text(r_fbi):find("ICN myshell", 1, true) ~= nil)

-- Handler e2e: a stored legacy "cyan:api" tab_title renders LITERALLY (D-05/D-06),
-- NOT split. With no pane title/cwd, the active_pane.title carries it through.
local r_lit = captured(fake_tab({}, false, "cyan:api", "cyan:api", 0), {}, {}, {}, false, 40)
check("35 legacy 'cyan:api' renders literally (no split, D-05/D-06)", find_text(r_lit):find("cyan:api", 1, true) ~= nil)

-- D-09 end-to-end: an active pane carrying a #RRGGBBAA accent paints that 8-digit color.
local r29 = captured(fake_tab({ WEZTERM_TAB_COLOR = "#1a2040cc" }, false, "", "sh", 0), {}, {}, {}, false, 40)
check("29 pane #RRGGBBAA accent paints the 8-digit color", r29[1].Background.Color == "#1a2040cc")

-- ===========================================================================
-- D-08/D-09/D-10: M.resolve_accent(uv) — three-step precedence.
--   (1) tab WEZTERM_TAB_COLOR wins; else
--   (2) WEZTERM_TAB_FOLLOW_PANE == "1" and WEZTERM_PANE_COLOR -> pane color; else
--   (3) neutral M.DEFAULT_PROFILE.
-- ===========================================================================
local navy_pair = M.resolve_profile("navy")
local cyan_pair = M.resolve_profile("cyan")

-- step 1: explicit tab color wins over a pane color, even when following.
local acc_a = M.resolve_accent({ WEZTERM_TAB_COLOR = "navy", WEZTERM_PANE_COLOR = "cyan", WEZTERM_TAB_FOLLOW_PANE = "1" })
check("30 resolve_accent: tab color wins (D-08 step 1)", acc_a.bg == navy_pair.bg)

-- step 2: no tab color, follow ON + pane color -> pane color.
local acc_b = M.resolve_accent({ WEZTERM_PANE_COLOR = "cyan", WEZTERM_TAB_FOLLOW_PANE = "1" })
check("31 resolve_accent: follow ON + pane color (D-08 step 2)", acc_b.bg == cyan_pair.bg)

-- step 3a: follow unset + a pane color -> neutral default (D-09 default OFF).
local acc_c = M.resolve_accent({ WEZTERM_PANE_COLOR = "cyan" })
check("32 resolve_accent: follow OFF + pane color -> neutral (D-09)", acc_c.bg == M.DEFAULT_PROFILE.bg)

-- step 3b: follow non-"1" + pane color -> neutral (only "1" is ON).
local acc_d = M.resolve_accent({ WEZTERM_PANE_COLOR = "cyan", WEZTERM_TAB_FOLLOW_PANE = "0" })
check("33 resolve_accent: follow '0' + pane color -> neutral", acc_d.bg == M.DEFAULT_PROFILE.bg)

-- step 3c: nothing set -> neutral default (D-10).
local acc_e = M.resolve_accent({})
check("34 resolve_accent: nothing set -> neutral default (D-10)", acc_e.bg == M.DEFAULT_PROFILE.bg)

-- follow ON but no pane color -> neutral (nothing to follow).
local acc_f = M.resolve_accent({ WEZTERM_TAB_FOLLOW_PANE = "1" })
check("35 resolve_accent: follow ON but no pane color -> neutral", acc_f.bg == M.DEFAULT_PROFILE.bg)

-- Handler e2e: follow ON + only pane color paints the pane accent.
local r_follow = captured(fake_tab({ WEZTERM_PANE_COLOR = "cyan", WEZTERM_TAB_FOLLOW_PANE = "1" }, false, "", "sh", 0), {}, {}, {}, false, 40)
check("36 handler follow ON + pane color paints pane accent", r_follow[1].Background.Color == cyan_pair.bg)

-- Handler e2e: follow OFF + pane color -> neutral (pane color NOT painted).
local r_nofollow = captured(fake_tab({ WEZTERM_PANE_COLOR = "cyan" }, false, "", "sh", 0), {}, {}, {}, false, 40)
check("37 handler follow OFF + pane color -> neutral", r_nofollow[1].Background.Color == M.DEFAULT_PROFILE.bg)

io.write(string.format("\nformat-tab-title_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
