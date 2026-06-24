-- tests/e2e/tier1/scene_edge_e2e_test.lua
--
-- Tier 1 (deterministic subcommand layer) — the SCENE-LAUNCH EDGE-CASE exit-code
-- contracts per PRD Appendix A.1 "Edge cases". Each path is asserted by its exact
-- exit code AND the UI-SPEC error copy, WITHOUT a live mux (every error exits before
-- any mux call — validate-before-emit, so a bad launch builds ZERO panes):
--
--   unknown scene name (recipes present)      -> exit 1 + not-found error copy
--   empty recipes dir (no name given)         -> exit 2 + no-name usage copy
--   path-traversal `../../etc/passwd`          -> exit 1 + the `invalid scene name` guard
--
-- These run via a child `lua5.4 -e` (NOT the dev-launcher subprocess) calling
-- cli.commands.scene.run_launch directly, exactly as scene_launch_test's
-- run_launch_child does. That is the ONLY way to get the REAL exit code for the
-- WEZTERM_SETUP_DIR-dependent paths (lua5.4 has no os.setenv, so the env rides the
-- child process), and it captures the genuine os.exit() code rather than masking it
-- through the dev launcher's head/od pipes.
--
-- T-06.6-05 (Tampering): the `../../etc/passwd` input is asserted to be REJECTED
-- (exit 1). No file outside the scratch dir is read or written — this is a GUARD
-- test of the existing traversal block, not a vulnerability being introduced.
--
-- The reinstall-over-existing-block edge (explicit `wez install-state --force` ->
-- exit 0) lives in install_cycle_e2e_test.lua (per checker H-1, the no-flag default
-- is a Plan-04 contract not verifiable at this wave) — it is NOT duplicated here.
--
-- Run directly:  lua5.4 tests/e2e/tier1/scene_edge_e2e_test.lua

-- package.path bootstrap (three `..` -> repo root; + harness lib + cli/vendor).
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../../.." -- tests/e2e/tier1 -> repo root (three ..)
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/tests/e2e/lib/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local h = require("harness")
local check = h.check
local shquote = h.shquote
local scratch_dir = h.scratch_dir

local function write_file(path, data)
  local fh = assert(io.open(path, "wb"))
  fh:write(data)
  fh:close()
end
local function rmrf(dir)
  os.execute("rm -rf " .. shquote(dir))
end

-- Run `wez scene launch <name>` in a child lua5.4 with WEZTERM_SETUP_DIR pointed at
-- `setup` (so M.scenes_dir() resolves to <setup>/scenes), calling run_launch
-- DIRECTLY so we get its real os.exit() code and NO mux runs. `name == nil` exercises
-- the no-name path. Returns (exit_code, combined_stdout_stderr).
local function run_launch_child(setup, name)
  local namelit = name == nil and "nil" or string.format("%q", name)
  local body = string.format(
    "package.path=%q..package.path;"
      .. "local s=require('cli.commands.scene');"
      .. "os.exit(s.run_launch({name=%s}))",
    repo_root .. "/?.lua;" .. repo_root .. "/cli/vendor/?.lua;",
    namelit)
  local cmd = string.format(
    "WEZTERM_SETUP_DIR=%s lua5.4 -e %s 2>&1",
    shquote(setup), shquote(body))
  local p = assert(io.popen(cmd, "r"))
  local out = p:read("*a") or ""
  local _, _, code = p:close()
  return code, out
end

-- ---------------------------------------------------------------------------
-- Unknown scene name (recipes present) -> exit 1 + not-found error copy.
-- ---------------------------------------------------------------------------
do
  local setup = scratch_dir("e2e-edge-unknown")
  local scenes = setup .. "/scenes"
  os.execute("mkdir -p " .. shquote(scenes))
  write_file(scenes .. "/dev.toml", 'layout = "tall"\n[[panes]]\ncommand = "shell"\n')

  local code, out = run_launch_child(setup, "nope")
  check("unknown scene name -> exit 1", code == 1, "code=" .. tostring(code))
  check("unknown scene name -> not-found error copy",
    out:find("error: no scene recipe named 'nope'", 1, true) ~= nil, out)
  rmrf(setup)
end

-- ---------------------------------------------------------------------------
-- Empty recipes dir (no name given) -> exit 2 + no-name usage copy.
-- ---------------------------------------------------------------------------
do
  local setup = scratch_dir("e2e-edge-empty")
  os.execute("mkdir -p " .. shquote(setup .. "/scenes"))

  local code, out = run_launch_child(setup, nil)
  check("empty recipes dir + no name -> exit 2", code == 2, "code=" .. tostring(code))
  check("empty recipes dir -> no-name usage error copy",
    out:find("error: wez scene launch requires a recipe name (got none)", 1, true) ~= nil, out)
end

-- ---------------------------------------------------------------------------
-- Path-traversal `../../etc/passwd` -> exit 1 + the `invalid scene name` guard
-- (rejected BEFORE any io.open — T-06.6-05 / T-05-08).
-- ---------------------------------------------------------------------------
do
  local setup = scratch_dir("e2e-edge-traversal")
  local scenes = setup .. "/scenes"
  os.execute("mkdir -p " .. shquote(scenes))
  write_file(scenes .. "/dev.toml", 'layout = "tall"\n[[panes]]\ncommand = "shell"\n')

  local code, out = run_launch_child(setup, "../../etc/passwd")
  check("path-traversal name -> exit 1 (guarded before io.open)", code == 1,
    "code=" .. tostring(code))
  check("path-traversal name -> `invalid scene name` guard copy",
    out:find("invalid scene name", 1, true) ~= nil, out)
  rmrf(setup)
end

os.exit(h.footer())
