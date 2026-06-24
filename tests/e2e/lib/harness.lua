-- tests/e2e/lib/harness.lua
--
-- Shared TAP-ish E2E harness for the wez subcommand battery (Phase 06.6+).
--
-- Every test file under tests/ used to re-declare the SAME check/run_capture/
-- shquote/scratch_dir block (keys_integration_test.lua's own header even says
-- "tiny harness (copied from scene_cwd_integration_test.lua)"). This module
-- HOISTS that block once so the Tier 1 files (Plan 02/03) and every later tier
-- (06.7-06.9) `require("harness")` instead of copy-pasting it.
--
-- API DECISION (resolves round-2 MR1 duality): the PRIMARY documented API is the
-- MODULE-LEVEL helpers — M.check / M.run_capture / M.run_capture_all / M.shquote /
-- M.scratch_dir / M.footer / M.WEZ. Plans 02/03 consume them at module level:
--
--     local h = require("harness")
--     h.check("`wez version` ran", exit == 0, ...)
--     ...
--     os.exit(h.footer())
--
-- The running pass/failed tally is a module-level pair that M.check increments;
-- M.footer() (or M.footer(counts) with an explicit counts table) prints the
-- standard "\n%d passed, %d failed" line and RETURNS 0 when failed == 0 else 1,
-- so every Tier 1 file ends identically with `os.exit(h.footer())`.
--
-- ADDITIONALLY, M.new() returns a FRESH instance object owning its OWN
-- passed/failed counters (with :check/:run_capture/:run_capture_all/:footer bound
-- to that instance) for the OPTIONAL case where a file wants counter isolation
-- across multiple require sites. The module-level helpers remain the API the
-- Tier 1 files actually use; M.new() is a convenience, not the default path.
--
-- PURITY-ISH: this is a TEST utility, so it legitimately shells out via io.popen
-- and touches the filesystem via scratch_dir — but it sets NO process env (which
-- lua5.4 cannot do anyway) and reads only TMPDIR / WEZ_BIN. The subprocess
-- exit-capture idiom (io.popen + `local ok, _, code = p:close()`) is the ONLY
-- exit-code capture mechanism in the repo; this module is its single home.

local M = {}

-- ---------------------------------------------------------------------------
-- Subprocess capture (no instance state). Lifted VERBATIM from
-- keys_integration_test.lua 75-98: the io.popen + p:close() 3-return
-- `(ok, _, code)` idiom is THE exit-code capture pattern in the repo.
-- ---------------------------------------------------------------------------

-- Shell-quote a string for safe interpolation into a command line.
function M.shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Run a command (stdout only, stderr discarded) -> (text, exit_code).
function M.run_capture(cmd)
  local p = io.popen(cmd .. " 2>/dev/null", "r")
  if not p then return "", 1 end
  local out = p:read("*a") or ""
  local ok, _, code = p:close()
  local exit = code or (ok and 0 or 1)
  return out, exit
end

-- Run a command capturing BOTH stdout and stderr merged -> (text, exit_code).
function M.run_capture_all(cmd)
  local p = io.popen(cmd .. " 2>&1", "r")
  if not p then return "", 1 end
  local out = p:read("*a") or ""
  local ok, _, code = p:close()
  local exit = code or (ok and 0 or 1)
  return out, exit
end

-- Scratch directory under TMPDIR/tmp (never the user's real ~/.config/wezterm).
-- Lifted from scene_launch_test.lua 51-56 / seed_scenes_test.lua: unique per run
-- via os.time + a random suffix so concurrent runs never collide (T-06.6-01).
function M.scratch_dir(tag)
  local base = os.getenv("TMPDIR") or "/tmp"
  local dir = string.format("%s/wezsetup-%s-%d-%d", base, tag, os.time(), math.random(1, 1e6))
  assert(os.execute("mkdir -p '" .. dir .. "'"))
  return dir
end

-- Resolve the `wez` binary under test: a $WEZ_BIN override wins (CI points it at
-- the freshly built luastatic ./dist/wez; make e2e exports dist/wez locally),
-- else fall back to the installed launcher on PATH. Lifted from
-- keys_integration_test.lua 100-103.
M.WEZ = os.getenv("WEZ_BIN")
if not M.WEZ or M.WEZ == "" then M.WEZ = "wez" end

-- ---------------------------------------------------------------------------
-- Module-level tally + helpers (the PRIMARY API the Tier 1 files consume).
-- ---------------------------------------------------------------------------
local passed, failed = 0, 0

-- TAP-ish ok/FAIL emitter; the run-e2e.sh / run-tests.sh aggregator keys only off
-- the per-file process exit code, but these lines are the human-readable trace.
-- Lifted VERBATIM from keys_integration_test.lua 57-65.
function M.check(label, ok, detail)
  if ok then
    passed = passed + 1
    print(string.format("  ok   - %s", label))
  else
    failed = failed + 1
    print(string.format("  FAIL - %s%s", label, detail and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

-- Standard footer. With no argument it prints the module-level tally; pass an
-- explicit {passed=, failed=} table to print a caller-owned tally instead.
-- Returns 0 when failed == 0 else 1, so `os.exit(h.footer())` ends a file the
-- same way every existing test does (keys_test.lua 191-192).
function M.footer(counts)
  local p = counts and counts.passed or passed
  local f = counts and counts.failed or failed
  print(string.format("\n%d passed, %d failed", p, f))
  return f == 0 and 0 or 1
end

-- ---------------------------------------------------------------------------
-- M.new() — OPTIONAL fresh instance owning its OWN counters, for files that want
-- counter isolation across multiple require sites. check/run_capture/
-- run_capture_all/footer are bound to the instance; shquote/scratch_dir/WEZ are
-- stateless and re-exported as-is.
-- ---------------------------------------------------------------------------
function M.new()
  local inst = { passed = 0, failed = 0 }
  inst.shquote = M.shquote
  inst.run_capture = M.run_capture
  inst.run_capture_all = M.run_capture_all
  inst.scratch_dir = M.scratch_dir
  inst.WEZ = M.WEZ

  function inst.check(label, ok, detail)
    if ok then
      inst.passed = inst.passed + 1
      print(string.format("  ok   - %s", label))
    else
      inst.failed = inst.failed + 1
      print(string.format("  FAIL - %s%s", label, detail and ("  (" .. tostring(detail) .. ")") or ""))
    end
  end

  function inst.footer()
    print(string.format("\n%d passed, %d failed", inst.passed, inst.failed))
    return inst.failed == 0 and 0 or 1
  end

  return inst
end

return M
