-- Fixture tests for cli/lib/shell.lua (shared shquote + decode_json — IN-02).
-- Run from the repo root: `lua5.4 cli/lib/shell_test.lua`
-- Pure: no wezterm / no io.popen / no os.execute (decode_json only `require`s the
-- vendored decoder). Make the vendored dkjson requireable regardless of CWD.

local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- cli/lib -> repo root
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local M = require("cli.lib.shell")

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

-- ============================================================================
-- shquote — the single-source escaper. A value is wrapped in single quotes and
-- any embedded single quote is rewritten as '\'' so a metacharacter / quote can
-- never break out and inject a command.
-- ============================================================================
eq("1 shquote plain", M.shquote("hello"), "'hello'")
eq("2 shquote spaces", M.shquote("a b c"), "'a b c'")
-- A semicolon / rm -rf payload stays inside the quotes (no breakout).
eq("3 shquote metacharacters stay quoted", M.shquote("; rm -rf /"), "'; rm -rf /'")
-- An embedded single quote is escaped as '\'' (the proven idiom).
eq("4 shquote embedded single quote", M.shquote("it's"), "'it'\\''s'")
-- A command-substitution attempt is neutralized by quoting.
eq("5 shquote $(...) stays literal", M.shquote("$(whoami)"), "'$(whoami)'")
-- Non-string input is tostring'd first.
eq("6 shquote number", M.shquote(42), "'42'")

-- ============================================================================
-- decode_json — round-trips a JSON array of pane entries via the vendored dkjson.
-- ============================================================================
do
  local data = M.decode_json('[{"pane_id":1,"tab_id":7},{"pane_id":2,"tab_id":7}]')
  check("7 decode_json returns a table", type(data) == "table")
  check("7a decode_json first entry pane_id", type(data) == "table"
    and data[1] ~= nil and data[1].pane_id == 1)
  check("7b decode_json first entry tab_id", type(data) == "table"
    and data[1] ~= nil and data[1].tab_id == 7)
  check("7c decode_json second entry", type(data) == "table"
    and data[2] ~= nil and data[2].pane_id == 2)
end

io.write(string.format("\nshell_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
