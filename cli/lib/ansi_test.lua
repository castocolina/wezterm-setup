-- Fixture tests for cli/lib/ansi.lua (pure ANSI SGR text-color helper).
-- Run from the repo root: `lua5.4 cli/lib/ansi_test.lua`
-- Pure: no wezterm / no I/O.
--
-- Byte-exact contract from 06.5-UI-SPEC.md "Color":
--   conflict rows           -> red       `\27[31m`  … `\27[0m`  (SGR 31 / reset 0)
--   conflict summary header -> bold red  `\27[1;31m` … `\27[0m` (SGR 1;31 / reset 0)

local M = require("cli.lib.ansi")

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

-- M.red(s) wraps s in SGR 31 (red foreground) + reset 0, byte-exact.
eq("1 red wraps in SGR 31 + reset", M.red("x"), "\27[31mx\27[0m")

-- M.bold_red(s) wraps s in SGR 1;31 (bold red) + reset 0, byte-exact.
eq("2 bold_red wraps in SGR 1;31 + reset", M.bold_red("x"), "\27[1;31mx\27[0m")

-- Empty input round-trips with no extra bytes (no crash).
eq("3 red empty round-trips", M.red(""), "\27[31m\27[0m")
eq("3b bold_red empty round-trips", M.bold_red(""), "\27[1;31m\27[0m")

-- The argument is wrapped VERBATIM — no interior transform/escape.
-- ANSI-injection safety is the CALLER's job; this helper only ever wraps our
-- own fixed fields, never the untrusted action string.
eq("4 red wraps verbatim", M.red("a b!"), "\27[31ma b!\27[0m")

io.write(string.format("\nansi_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
