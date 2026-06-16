-- Fixture tests for cli/lib/title.lua (shared icon-name title resolver).
-- Run from the repo root: `lua5.4 cli/lib/title_test.lua`
-- Pure: no wezterm / no I/O.

local M = require("cli.lib.title")

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

-- ICONS map present + key glyphs intact (D-03 verbatim lift from pane.lua)
check("0 ICONS is a table", type(M.ICONS) == "table")
eq("0a ICONS.docker", M.ICONS.docker, "🐳")
eq("0b ICONS.rust", M.ICONS.rust, "🦀")
eq("0c ICONS.node", M.ICONS.node, "💚")

-- resolve_title(words) — D-05: first word is NO LONGER swapped for a glyph.
-- Titles are fully literal; only "reset"/empty still clear to "".
eq("1 literal multi-word", M.resolve_title({ "docker", "compose", "up" }), "docker compose up")
eq("2 freeform", M.resolve_title({ "my", "task" }), "my task")
eq("3 emoji passthrough", M.resolve_title({ "🔥", "build" }), "🔥 build")
eq("4 known-name literal (no swap)", M.resolve_title({ "docker" }), "docker")
eq("5 empty -> clear", M.resolve_title({}), "")
eq("6 reset -> clear", M.resolve_title({ "reset" }), "")
eq("7 case preserved, no swap", M.resolve_title({ "Docker", "x" }), "Docker x")
eq("7b empty-string arg -> clear", M.resolve_title({ "" }), "")
eq("7c node+api literal (D-05)", M.resolve_title({ "node", "api" }), "node api")

-- resolve_title_str(s) — D-05: literal; first word never swapped for a glyph.
eq("8 str literal multi-word", M.resolve_title_str("docker compose up"), "docker compose up")
eq("9 str freeform", M.resolve_title_str("plain text"), "plain text")
eq("10 str reset -> clear", M.resolve_title_str("reset"), "")
eq("11 str empty -> clear", M.resolve_title_str(""), "")
eq("12 str non-icon single word", M.resolve_title_str("foo"), "foo")
eq("13 str case preserved, no swap", M.resolve_title_str("Docker x"), "Docker x")
eq("14 str known-name literal (no swap)", M.resolve_title_str("docker"), "docker")
eq("14b str node api literal (D-05)", M.resolve_title_str("node api"), "node api")

-- resolve_icon(input) — D-02: known name (case-insensitive) -> glyph; any other
-- input passes through verbatim; nil/empty -> "".
eq("26 resolve_icon known name", M.resolve_icon("node"), "💚")
eq("27 resolve_icon case-insensitive", M.resolve_icon("NODE"), "💚")
eq("28 resolve_icon docker", M.resolve_icon("docker"), "🐳")
eq("29 resolve_icon literal glyph passthrough", M.resolve_icon("🔥"), "🔥")
eq("30 resolve_icon unknown literal", M.resolve_icon("anything-else"), "anything-else")
eq("31 resolve_icon empty -> empty", M.resolve_icon(""), "")
eq("32 resolve_icon nil -> empty", M.resolve_icon(nil), "")

-- basename(path) — pure last-segment helper for the {cwd} token
eq("15 basename plain", M.basename("/home/u/git/myproj"), "myproj")
eq("16 basename trailing slash", M.basename("/home/u/git/myproj/"), "myproj")
eq("17 basename single segment", M.basename("myproj"), "myproj")
eq("18 basename root", M.basename("/"), "/")
eq("19 basename empty -> /", M.basename(""), "/")

-- expand_cwd(s, launch_dir) — {cwd} token = basename(launch_dir); shell-free (D-08)
eq("20 expand tab title", M.expand_cwd("rust {cwd}", "/home/u/git/rustthing"), "rust rustthing")
eq("21 expand mid-string", M.expand_cwd("docker stats @ {cwd}", "/srv/app"), "docker stats @ app")
eq("22 expand no token untouched", M.expand_cwd("plain title", "/x/y"), "plain title")
eq("23 expand all occurrences", M.expand_cwd("{cwd}/{cwd}", "/a/b/proj"), "proj/proj")
eq("24 expand nil passthrough", M.expand_cwd(nil, "/x/y"), nil)
-- {cwd} is NOT shell: a $(...) in a title is left literal, never evaluated (D-08).
eq("25 no shell eval", M.expand_cwd("x $(rm -rf /) {cwd}", "/a/safe"), "x $(rm -rf /) safe")

-- fallback_title(title, icon, launch_dir) — D-11/D-12/D-13. The SINGLE shared
-- helper both the tab-side (Plan 03 render) and the pane-side (Plan 04 scene loop)
-- call for the empty-title cwd fallback.
eq("33 empty title -> basename (D-11/D-12)", M.fallback_title("", nil, "/x/myrepo"), "myrepo")
eq("34 explicit title always wins (D-11)", M.fallback_title("api", nil, "/x/myrepo"), "api")
eq("35 empty title + icon -> icon + basename (D-13)", M.fallback_title("", M.ICONS.node, "/x/myrepo"), "💚 myrepo")
eq("36 empty title + icon on root basename", M.fallback_title("", M.ICONS.node, "/"), "💚 /")
eq("37 empty title no icon on root", M.fallback_title("", nil, "/"), "/")
eq("38 nil title treated as empty", M.fallback_title(nil, nil, "/x/myrepo"), "myrepo")

-- emit_icon(emit_fn, raw) — IN-01: the ONE shared icon-emit body (reset
-- normalization + resolve + OSC 1337), reused by `wez tab icon` / `wez pane icon`.
-- The emitted bytes must equal build_osc1337("WEZTERM_TAB_ICON", resolve_icon(raw)).
do
  local color = require("cli.lib.color")
  local function capture(raw)
    local seen = nil
    M.emit_icon(function(s) seen = s end, raw)
    return seen
  end
  eq("39 emit_icon resolves a known name to its glyph",
    capture("docker"), color.build_osc1337("WEZTERM_TAB_ICON", M.ICONS.docker))
  eq("39a emit_icon passes a literal glyph through",
    capture("🔥"), color.build_osc1337("WEZTERM_TAB_ICON", "🔥"))
  eq("39b emit_icon reset clears the carrier (empty payload)",
    capture("reset"), color.build_osc1337("WEZTERM_TAB_ICON", ""))
  eq("39c emit_icon nil clears the carrier",
    capture(nil), color.build_osc1337("WEZTERM_TAB_ICON", ""))
  eq("39d emit_icon empty string clears the carrier",
    capture(""), color.build_osc1337("WEZTERM_TAB_ICON", ""))
end

io.write(string.format("\ntitle_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
