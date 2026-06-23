-- tests/cli/uninstall_idempotent_test.lua
-- Regression-guard for the idempotent-uninstall fix (quick 260623-gn7).
-- tools/uninstall.sh USED to `err()` + `exit 1` in the not-found `else` branch
-- when no reachable `wez` binary existed. Because `wez` self-deletes as the LAST
-- step of its own uninstall (D-01: the glue delegates all removal to the binary),
-- a re-run -- or a `make uninstall install` from a clean / half-installed state --
-- hit the not-found branch and aborted with a non-zero exit BEFORE `install` ran.
--
-- The fix: in the not-found `else` branch ONLY, the `err()` + `exit 1` becomes a
-- `log()` warning + `exit 0` ("already uninstalled; nothing to remove"). The glue
-- stays decision-free (D-01): NO `rm`, NO path-branching, NO config inspection.
--
-- Unlike build_dev_launcher_test.lua (which SOURCES its target), uninstall.sh has
-- NO $0/BASH_SOURCE sourcing guard, so this test RUNS the script directly with a
-- controlled env (PATH= + WEZ_BIN_DIR pointed at an empty temp dir) and captures
-- the exit status + combined output. The rm-guard (Test 3) reuses the
-- comment-filtered grep idiom from setup_dev_test.lua / build_dev_launcher_test.lua.
--
-- Run directly: `lua5.4 tests/cli/uninstall_idempotent_test.lua`.

local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- tests/cli -> repo root

local passed, failed = 0, 0
local function check(label, ok, detail)
  if ok then
    passed = passed + 1
    print(string.format("  ok   - %s", label))
  else
    failed = failed + 1
    print(string.format("  FAIL - %s%s", label, detail and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local SCRIPT = repo_root .. "/tools/uninstall.sh"

-- ----------------------------------------------------------------------------
-- BEHAVIOR harness: run uninstall.sh directly with a controlled env where NO
-- `wez` is reachable -- PATH is emptied (so `command -v wez` misses) AND
-- WEZ_BIN_DIR points at a freshly-created EMPTY temp dir (so the
-- `[ -x ${BIN_DIR}/wez ]` fallback also misses). uninstall.sh is invoked via an
-- ABSOLUTE bash path resolved BEFORE PATH is emptied -- not via `env`, since with
-- PATH= an `/usr/bin/env bash` lookup fails (127) before the script ever runs.
-- The not-found branch only runs bash builtins (printf + exit), so no external
-- coreutils are required for the asserted path. stdin is /dev/null
-- (non-interactive). Returns (exit_status:number, output:string).
-- ----------------------------------------------------------------------------
-- Resolve an absolute bash path from the CURRENT (real) PATH, so the driver can
-- launch the script even after it empties PATH for the `command -v wez` miss.
local BASH_BIN
do
  local p = assert(io.popen("command -v bash 2>/dev/null || true"))
  BASH_BIN = ((p:read("*a") or ""):gsub("%s+$", ""))
  p:close()
  if BASH_BIN == "" then BASH_BIN = "/bin/bash" end
end

local function run_uninstall_no_wez()
  local empty_dir = os.tmpname()
  os.remove(empty_dir)
  local out_file = os.tmpname()
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "w"))
  fh:write("#!/usr/bin/env bash\n")
  fh:write("set -u\n")
  -- Freshly-created EMPTY temp dir for WEZ_BIN_DIR: no `wez` lives here.
  fh:write("mkdir -p '" .. empty_dir .. "'\n")
  fh:write("export WEZ_BIN_DIR='" .. empty_dir .. "'\n")
  -- Empty PATH so `command -v wez` finds nothing.
  fh:write("export PATH=\n")
  -- Run uninstall.sh via an ABSOLUTE bash path (resolved before PATH was emptied,
  -- shebang not needed). Capture stdout+stderr together; stdin from /dev/null
  -- (non-interactive). The not-found branch is pure bash builtins (printf + exit).
  fh:write("'" .. BASH_BIN .. "' '" .. SCRIPT .. "' </dev/null\n")
  fh:write("rc=$?\n")
  -- Propagate the script's exit code as this driver's exit code.
  fh:write("exit $rc\n")
  fh:close()
  -- Run the driver, redirecting BOTH streams of the inner script to out_file.
  local cmd = "bash '" .. tmp .. "' >'" .. out_file .. "' 2>&1"
  local _, _, code = os.execute(cmd)
  local status = tonumber(code) or 0
  local ofh = io.open(out_file, "rb")
  local text = ""
  if ofh then
    text = ofh:read("*a") or ""
    ofh:close()
  end
  os.remove(tmp)
  os.remove(out_file)
  os.execute("rm -rf '" .. empty_dir .. "' 2>/dev/null || true")
  return status, text
end

local status, output = run_uninstall_no_wez()

-- RED Test 1 (exit code): with no reachable wez, uninstall.sh exits 0.
-- FAILS against the unmodified source (it exits 1) -- that is the RED state.
check("uninstall.sh exits 0 when no reachable wez binary exists",
  status == 0, "exit status=" .. tostring(status))

-- RED Test 2 (warning, no ERROR): output has a `[uninstall]` line mentioning the
-- binary is not found / already uninstalled, AND contains NO `ERROR:` token.
-- The old branch emits `[uninstall] ERROR: wez binary not found ...`, so the
-- no-ERROR assertion FAILS -- also RED.
do
  local has_uninstall_line = output:find("%[uninstall%]") ~= nil
  local has_not_found = output:find("not found", 1, true) ~= nil
  local has_error_token = output:find("ERROR:", 1, true) ~= nil
  check("output carries a `[uninstall]` warning noting the binary is not found",
    has_uninstall_line and has_not_found,
    "output=" .. output:gsub("%s+", " "))
  check("output contains NO `ERROR:` token (warn, do not error)",
    not has_error_token,
    "output=" .. output:gsub("%s+", " "))
end

-- Guard Test 3 (TEXT, green both before and after -- proves the glue stays
-- decision-free per D-01): no NON-COMMENT line introduces a bare `rm ` command.
-- Comment-filtered grep idiom (no `-n` on the first grep -- it prepends LINENUM:
-- and defeats the `^[[:space:]]*#` comment anchor, a known trap).
do
  local p = assert(io.popen(
    "grep -E 'rm ' '" .. SCRIPT .. "' | grep -vc '^[[:space:]]*#' || true"))
  local n = tonumber((p:read("*a") or "0"):match("%d+")) or 0
  p:close()
  check("no non-comment line introduces a bare `rm ` command (decision-free glue, D-01)",
    n == 0, "non-comment bare-`rm ` lines=" .. tostring(n))
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
