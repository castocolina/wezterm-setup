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

-- resolve_title(words) — ported from pane_test.lua t1-t7b (exact semantics)
eq("1 icon+text", M.resolve_title({ "docker", "compose", "up" }), "🐳 compose up")
eq("2 freeform", M.resolve_title({ "my", "task" }), "my task")
eq("3 emoji passthrough", M.resolve_title({ "🔥", "build" }), "🔥 build")
eq("4 icon only", M.resolve_title({ "docker" }), "🐳")
eq("5 empty -> clear", M.resolve_title({}), "")
eq("6 reset -> clear", M.resolve_title({ "reset" }), "")
eq("7 case-insensitive icon", M.resolve_title({ "Docker", "x" }), "🐳 x")
eq("7b empty-string arg -> clear", M.resolve_title({ "" }), "")

-- resolve_title_str(s) — NEW single-string form for the --title flag
eq("8 str icon+text", M.resolve_title_str("docker compose up"), "🐳 compose up")
eq("9 str freeform", M.resolve_title_str("plain text"), "plain text")
eq("10 str reset -> clear", M.resolve_title_str("reset"), "")
eq("11 str empty -> clear", M.resolve_title_str(""), "")
eq("12 str non-icon single word", M.resolve_title_str("foo"), "foo")
eq("13 str case-insensitive icon", M.resolve_title_str("Docker x"), "🐳 x")
eq("14 str icon only", M.resolve_title_str("docker"), "🐳")

io.write(string.format("\ntitle_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
