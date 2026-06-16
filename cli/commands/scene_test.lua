-- Fixture tests for cli/commands/scene.lua M.build_pane_escapes — the PURE
-- per-pane escape builder for the scene Phase B loop.
-- Run from the repo root: `lua5.4 cli/commands/scene_test.lua`
--
-- These cover the split identity carriers + the per-pane cwd-basename title
-- fallback added in Plan 06.2-04 (D-03/D-07/D-09/D-12/D-13) WITHOUT a live mux:
--   * a pane with icon= emits WEZTERM_TAB_ICON (resolved glyph, base64'd); a pane
--     with no own icon inherits the tab icon glyph (tab_icon_value fallback)
--   * a per-pane color emits WEZTERM_PANE_COLOR (distinct from the tab accent)
--   * the tab's OWN color (tab_color_value) + the follow carrier ride EVERY pane
--     (not pane-1-only) so the tab identity is stable across focus changes
--   * an empty-title pane self-labels by basename(ldir); with an icon -> glyph+base
--   * an explicit title always wins over the fallback
--   * every value flows through build_osc1337 (base64) — no raw-byte injection
--
-- Make `cli/...` + vendored deps requireable regardless of invocation CWD.
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- cli/commands -> repo root
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local M = require("cli.commands.scene")
local panelib = require("cli.commands.pane")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else
    fail = fail + 1
    io.stderr:write("FAIL: " .. name .. "\n")
  end
end

-- Does the concatenated escapes array contain the EXACT OSC-1337 SetUserVar for
-- (varname, value)? Builds the expected escape via the SAME builder the code uses,
-- so a base64 mismatch (e.g. raw-byte injection) fails this assertion.
local function has_uservar(escapes, varname, value)
  local want = panelib.build_osc1337(varname, value)
  return table.concat(escapes):find(want, 1, true) ~= nil
end

-- Does the array contain ANY SetUserVar for varname (regardless of value)?
local function has_uservar_name(escapes, varname)
  return table.concat(escapes):find("SetUserVar=" .. varname .. "=", 1, true) ~= nil
end

-- ============================================================================
-- 1* per-pane icon -> WEZTERM_TAB_ICON (D-03), resolved through titlelib.resolve_icon
-- ============================================================================

-- 1a a named icon resolves to its glyph and rides WEZTERM_TAB_ICON.
do
  local esc = M.build_pane_escapes({ cmd = "top", icon = "node", shell = false },
    { is_pane1 = false, ldir = "/home/u/repo" })
  check("1a icon=node emits WEZTERM_TAB_ICON (resolved glyph)",
    has_uservar(esc, "WEZTERM_TAB_ICON", "💚"))
end

-- 1b a literal-glyph icon passes through verbatim.
do
  local esc = M.build_pane_escapes({ cmd = "x", icon = "🔥", shell = false },
    { is_pane1 = false, ldir = "/home/u/repo" })
  check("1b literal-glyph icon rides WEZTERM_TAB_ICON verbatim",
    has_uservar(esc, "WEZTERM_TAB_ICON", "🔥"))
end

-- 1c no icon -> NO WEZTERM_TAB_ICON escape.
do
  local esc = M.build_pane_escapes({ cmd = "top", title = "Mon", shell = false },
    { is_pane1 = false, ldir = "/home/u/repo" })
  check("1c no icon -> no WEZTERM_TAB_ICON", not has_uservar_name(esc, "WEZTERM_TAB_ICON"))
end

-- ============================================================================
-- 2* split color carriers — per-pane WEZTERM_PANE_COLOR vs tab WEZTERM_TAB_COLOR (D-07)
-- ============================================================================

-- 2a a per-pane color emits WEZTERM_PANE_COLOR (the accent), NOT WEZTERM_TAB_COLOR.
do
  local esc = M.build_pane_escapes({ cmd = "top", color = "teal", shell = false },
    { is_pane1 = false, ldir = "/home/u/repo" })
  check("2a per-pane color -> WEZTERM_PANE_COLOR=teal",
    has_uservar(esc, "WEZTERM_PANE_COLOR", "teal"))
  check("2a2 per-pane color (non-pane1) does NOT emit WEZTERM_TAB_COLOR",
    not has_uservar_name(esc, "WEZTERM_TAB_COLOR"))
end

-- 2b pane 1 with a tab color emits the tab's OWN WEZTERM_TAB_COLOR.
do
  local esc = M.build_pane_escapes({ cmd = "top", shell = false },
    { is_pane1 = true, tab_color_value = "green", ldir = "/home/u/repo" })
  check("2b pane1 tab color -> WEZTERM_TAB_COLOR=green",
    has_uservar(esc, "WEZTERM_TAB_COLOR", "green"))
end

-- 2c pane 1 with BOTH a per-pane color AND a tab color emits the SPLIT carriers.
do
  local esc = M.build_pane_escapes({ cmd = "top", color = "teal", shell = false },
    { is_pane1 = true, tab_color_value = "green", ldir = "/home/u/repo" })
  check("2c split: pane1 emits WEZTERM_PANE_COLOR=teal (accent)",
    has_uservar(esc, "WEZTERM_PANE_COLOR", "teal"))
  check("2c2 split: pane1 emits WEZTERM_TAB_COLOR=green (tab's own)",
    has_uservar(esc, "WEZTERM_TAB_COLOR", "green"))
end

-- ============================================================================
-- 3* follow_pane_color -> WEZTERM_TAB_FOLLOW_PANE="1" on pane 1 (D-09, default OFF)
-- ============================================================================

-- 3a follow_pane_color set -> the LOCKED carrier on pane 1.
do
  local esc = M.build_pane_escapes({ cmd = "top", shell = false },
    { is_pane1 = true, follow_pane_color = true, ldir = "/home/u/repo" })
  check("3a follow_pane_color -> WEZTERM_TAB_FOLLOW_PANE=1",
    has_uservar(esc, "WEZTERM_TAB_FOLLOW_PANE", "1"))
end

-- 3b follow_pane_color UNSET -> no follow carrier (default OFF).
do
  local esc = M.build_pane_escapes({ cmd = "top", shell = false },
    { is_pane1 = true, ldir = "/home/u/repo" })
  check("3b follow_pane_color unset -> NO WEZTERM_TAB_FOLLOW_PANE (default OFF)",
    not has_uservar_name(esc, "WEZTERM_TAB_FOLLOW_PANE"))
end

-- 3c the follow carrier rides EVERY pane (was pane-1-only — the defect that made
-- the tab flip to neutral the moment a non-pane-1 was focused). A non-pane-1 pane
-- with follow_pane_color set now emits WEZTERM_TAB_FOLLOW_PANE="1".
do
  local esc = M.build_pane_escapes({ cmd = "top", shell = false },
    { follow_pane_color = true, ldir = "/home/u/repo" })
  check("3c follow carrier rides every pane (not pane-1-only)",
    has_uservar(esc, "WEZTERM_TAB_FOLLOW_PANE", "1"))
end

-- 3d the tab's OWN color rides every pane too, so the tab accent is stable across
-- focus changes (the "tab color permutes with the panes" regression).
do
  local esc = M.build_pane_escapes({ cmd = "top", color = "teal", shell = false },
    { tab_color_value = "green", ldir = "/home/u/repo" })
  check("3d tab color rides a non-pane-1 pane -> WEZTERM_TAB_COLOR=green",
    has_uservar(esc, "WEZTERM_TAB_COLOR", "green"))
  check("3d2 the pane keeps its own WEZTERM_PANE_COLOR distinct",
    has_uservar(esc, "WEZTERM_PANE_COLOR", "teal"))
end

-- 3e tab-icon fallback (D-03): a pane with NO own icon inherits the tab icon glyph,
-- so an icon always renders regardless of which pane is focused.
do
  local esc = M.build_pane_escapes({ cmd = "top", shell = false },
    { tab_icon_value = "🔨", ldir = "/home/u/repo" })
  check("3e iconless pane inherits the tab icon -> WEZTERM_TAB_ICON=🔨",
    has_uservar(esc, "WEZTERM_TAB_ICON", "🔨"))
end

-- 3f a pane's OWN icon wins over the tab-icon fallback.
do
  local esc = M.build_pane_escapes({ cmd = "top", icon = "git", shell = false },
    { tab_icon_value = "🔨", ldir = "/home/u/repo" })
  check("3f pane's own icon wins over the tab fallback -> WEZTERM_TAB_ICON=🔀",
    has_uservar(esc, "WEZTERM_TAB_ICON", "🔀"))
end

-- ============================================================================
-- 4* per-pane empty-title cwd-basename fallback (D-12) — icon-aware (D-13)
-- ============================================================================

-- 4a a labelless pane (no title, no cmd-derived title -> shell pane) self-labels
-- by basename(ldir) via the shared fallback_title (D-12).
do
  local esc = M.build_pane_escapes({ shell = true },
    { is_pane1 = false, ldir = "/home/u/myrepo" })
  check("4a empty-title shell pane -> WEZTERM_TAB_TITLE=basename(ldir)",
    has_uservar(esc, "WEZTERM_TAB_TITLE", "myrepo"))
end

-- 4b a labelless pane WITH an icon emits icon + " " + basename (D-13).
do
  local esc = M.build_pane_escapes({ shell = true, icon = "node" },
    { is_pane1 = false, ldir = "/home/u/myrepo" })
  check("4b empty-title + icon -> WEZTERM_TAB_TITLE='💚 myrepo' (D-13)",
    has_uservar(esc, "WEZTERM_TAB_TITLE", "💚 myrepo"))
end

-- 4c an explicit non-empty title ALWAYS wins over the fallback (D-11).
do
  local esc = M.build_pane_escapes({ shell = true, title = "Logs", icon = "node" },
    { is_pane1 = false, ldir = "/home/u/myrepo" })
  check("4c explicit title wins over the cwd fallback",
    has_uservar(esc, "WEZTERM_TAB_TITLE", "Logs"))
  check("4c2 explicit title -> the basename is NOT emitted",
    not has_uservar(esc, "WEZTERM_TAB_TITLE", "myrepo"))
end

-- 4d the {cwd} token in an explicit title still expands to basename(ldir).
do
  local esc = M.build_pane_escapes({ cmd = "git status", title = "git {cwd}", shell = false },
    { is_pane1 = false, ldir = "/home/u/myrepo" })
  check("4d {cwd} token expands to basename(ldir)",
    has_uservar(esc, "WEZTERM_TAB_TITLE", "git myrepo"))
end

-- ============================================================================
-- 5* injection safety (T-06.2-08): every value is base64'd, so a control-byte
-- value cannot break out of the escape. The bytes appear ONLY base64-encoded.
-- ============================================================================
do
  local nasty = "x\27]0;pwn\7"
  local esc = M.build_pane_escapes({ cmd = "top", icon = nasty, shell = false },
    { is_pane1 = false, ldir = "/home/u/repo" })
  local joined = table.concat(esc)
  -- the icon carrier exists, base64'd...
  check("5a malicious icon still emits a (base64'd) WEZTERM_TAB_ICON",
    has_uservar(esc, "WEZTERM_TAB_ICON", nasty))
  -- ...and the raw injected OSC-0 title-set sequence does NOT appear verbatim.
  check("5b raw injected control sequence does not appear unescaped",
    joined:find("\27]0;pwn", 1, true) == nil)
end

io.write(string.format("\nscene command_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
