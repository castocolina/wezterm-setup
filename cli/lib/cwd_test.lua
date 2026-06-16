-- Fixture tests for cli/lib/cwd.lua (pure cwd-grammar resolver — D-01/D-07/D-08).
-- Run from the repo root: `lua5.4 cli/lib/cwd_test.lua`
-- Pure: no wezterm / no I/O / no os.getenv. The resolver takes an injected env
-- table so this suite runs deterministically under plain lua5.4 with no live
-- session and no ambient environment. Mirrors cli/lib/scene_test.lua's harness.
--
-- The locked grammar (06.1-CONTEXT.md D-07/D-08, no new research):
--   literal absolute | ~-prefixed | $ENV-expanded | relative, where
--   `.` = the launch dir and `..` = dirname(launch dir). Shell command
--   substitution ($(...) / backticks) is FORBIDDEN and rejected before emit.

local M = require("cli.lib.cwd")

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

local LAUNCH = "/home/u/proj"

-- ============================================================================
-- 1* M.resolve(value, launch_dir, env) -> absolute path (the locked grammar)
-- ============================================================================

-- 1a omitted cwd defaults to the launch dir (D-07).
eq("1a resolve(nil) -> launch dir", M.resolve(nil, LAUNCH, {}), "/home/u/proj")
-- 1b empty string is treated as omitted -> launch dir (D-07).
eq("1b resolve('') -> launch dir", M.resolve("", LAUNCH, {}), "/home/u/proj")
-- 1c "." = the launch dir.
eq("1c resolve('.') -> launch dir", M.resolve(".", LAUNCH, {}), "/home/u/proj")
-- 1d ".." = dirname(launch dir).
eq("1d resolve('..') -> dirname launch", M.resolve("..", LAUNCH, {}), "/home/u")
-- 1e leading "~" -> env.HOME.
eq("1e resolve('~')", M.resolve("~", LAUNCH, { HOME = "/home/u" }), "/home/u")
-- 1f "~/x" -> env.HOME + remainder.
eq("1f resolve('~/x')", M.resolve("~/x", LAUNCH, { HOME = "/home/u" }), "/home/u/x")
-- 1g "$WORK/svc" -> env.WORK + remainder.
eq("1g resolve('$WORK/svc')", M.resolve("$WORK/svc", LAUNCH, { WORK = "/srv" }), "/srv/svc")
-- 1h literal absolute path passes through as-is.
eq("1h resolve('/abs/path')", M.resolve("/abs/path", LAUNCH, {}), "/abs/path")
-- 1i relative path is joined to the launch dir.
eq("1i resolve('sub/dir')", M.resolve("sub/dir", LAUNCH, {}), "/home/u/proj/sub/dir")

-- ============================================================================
-- 2* M.validate(value, env) -> (true) | (false, errmsg)  (validate-before-emit)
-- ============================================================================

-- 2a command substitution $(...) is REJECTED (the security lock).
do
  local ok, err = M.validate("$(rm -rf /)", {})
  check("2a validate('$(rm -rf /)') rejected", ok == false)
  check("2a2 error mentions command substitution",
    type(err) == "string" and err:find("command substitution") ~= nil)
end
-- 2b backtick command substitution is REJECTED.
do
  local ok, err = M.validate("`whoami`", {})
  check("2b validate('`whoami`') rejected", ok == false)
  check("2b2 error is a string", type(err) == "string")
end
-- 2c an unset $ENV reference is REJECTED before emit (never silently empty).
do
  local ok, err = M.validate("$UNSET/x", {})
  check("2c validate('$UNSET/x') with unset env rejected", ok == false)
  check("2c2 error mentions the unset var",
    type(err) == "string" and err:find("UNSET") ~= nil)
end
-- 2d a well-formed ~-prefixed value with HOME set validates true.
do
  local ok, err = M.validate("~/ok", { HOME = "/home/u" })
  check("2d validate('~/ok') ok", ok == true and err == nil)
end
-- 2e a set $ENV reference validates true.
do
  local ok = M.validate("$WORK/svc", { WORK = "/srv" })
  check("2e validate('$WORK/svc') with set env ok", ok == true)
end
-- 2f plain literal/relative values validate true (no env needed).
do
  check("2f validate('/abs') ok", M.validate("/abs", {}) == true)
  check("2g validate('sub/dir') ok", M.validate("sub/dir", {}) == true)
  check("2h validate('.') ok", M.validate(".", {}) == true)
  check("2i validate(nil) ok (omitted -> launch dir)", M.validate(nil, {}) == true)
end

-- 2j a "~"-prefixed value with HOME unset is rejected before emit (no nil concat).
do
  local ok, err = M.validate("~/x", {})
  check("2j validate('~/x') with unset HOME rejected", ok == false)
  check("2j error mentions HOME", type(err) == "string" and err:find("HOME", 1, true) ~= nil)
end

-- 2k WR-02: the unsupported ${NAME} brace form is REJECTED up front so it never
-- slips past the unset-var check and resolves to a literal broken path. Rejected
-- whether the named var is UNSET or SET — the brace form is simply not expanded.
do
  local ok, err = M.validate("${UNSET}/x", {})
  check("2k validate('${UNSET}/x') rejected", ok == false)
  check("2k2 error names the brace form", type(err) == "string"
    and err:find("${NAME}", 1, true) ~= nil)

  local ok2, err2 = M.validate("${PWD}/x", { PWD = "/home/u" })
  check("2l validate('${PWD}/x') rejected even when set", ok2 == false)
  check("2l2 error names the brace form", type(err2) == "string"
    and err2:find("${NAME}", 1, true) ~= nil)
end

io.write(string.format("\ncwd_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
