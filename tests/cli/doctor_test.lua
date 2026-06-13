-- tests/cli/doctor_test.lua
-- Plain assert()-based unit tests for `wez doctor` (Plan 06, DIAG-01).
--
-- Focus: the GATE AGGREGATION logic (D-15). doctor runs FOUR core integrity
-- gates that determine the exit code:
--   1. the `wez` binary is on PATH
--   2. the managed sentinel block in wezterm.lua is well-formed
--   3. the managed config dir dofiles cleanly (init.lua loads without error)
--   4. a timestamped backup exists
-- and SEPARATELY runs ADVISORY probes (completions-installed, a live-session
-- reachability check) that are PRINTED but NEVER change the exit code.
--
-- Aggregation is exercised against STUBBED gate results (no real filesystem, no
-- live WezTerm) so this file is an autonomous gate under tools/run-tests.sh. The
-- live `wez doctor; echo $?` evidence on a healthy + a broken install is captured
-- manually in docs/repro/h-diag-doctor.md (R2 verify-before-done).
--
-- Run directly: `lua5.4 tests/cli/doctor_test.lua`.

-- Make `cli/...` and the vendored deps requireable regardless of invocation CWD.
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- tests/cli -> repo root
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

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

local D = require("cli.commands.doctor")

-- ----------------------------------------------------------------------------
-- A "gate result" is { ok = boolean, label = string, detail = string|nil }.
-- aggregate(core, advisory) -> { code = number, ... } where:
--   * code == 0 iff EVERY core gate ok
--   * code ~= 0 iff ANY core gate failed
--   * advisory results NEVER influence code.
-- ----------------------------------------------------------------------------

local function gate(ok, label, detail)
  return { ok = ok, label = label, detail = detail }
end

-- The four core gates, all passing.
local function all_core_pass()
  return {
    gate(true, "wez binary on PATH"),
    gate(true, "sentinel block well-formed"),
    gate(true, "config dofiles cleanly"),
    gate(true, "timestamped backup exists"),
  }
end

-- ----------------------------------------------------------------------------
-- aggregate(): all core gates pass -> exit 0.
-- ----------------------------------------------------------------------------
do
  local res = D.aggregate(all_core_pass(), {})
  check("aggregate exposes a numeric exit code", type(res) == "table" and type(res.code) == "number", res and tostring(res.code))
  check("all four core gates passing returns 0", res.code == 0, "code=" .. tostring(res.code))
end

-- ----------------------------------------------------------------------------
-- aggregate(): ANY core gate failing -> non-zero exit.
-- ----------------------------------------------------------------------------
do
  for i = 1, 4 do
    local core = all_core_pass()
    core[i] = gate(false, core[i].label, "stubbed failure")
    local res = D.aggregate(core, {})
    check("a single failed core gate (#" .. i .. ") returns non-zero",
      res.code ~= 0, "code=" .. tostring(res.code))
  end
end

-- ----------------------------------------------------------------------------
-- aggregate(): an ADVISORY failure with ALL core gates passing still returns 0
-- (the central D-15 invariant — advisory never flips exit 0).
-- ----------------------------------------------------------------------------
do
  local advisory = {
    gate(false, "live wezterm session reachable", "no live session"),
  }
  local res = D.aggregate(all_core_pass(), advisory)
  check("an advisory-probe failure with all core gates passing still returns 0",
    res.code == 0, "code=" .. tostring(res.code))
end

-- ----------------------------------------------------------------------------
-- aggregate(): completions-not-installed is ADVISORY — with all core gates
-- passing the exit is still 0 (per the plan: completions is advisory, NOT one of
-- the four exit-code gates).
-- ----------------------------------------------------------------------------
do
  local advisory = {
    gate(false, "shell completions installed", "completions not installed"),
  }
  local res = D.aggregate(all_core_pass(), advisory)
  check("completions-not-installed with all core gates passing still returns 0",
    res.code == 0, "code=" .. tostring(res.code))
end

-- ----------------------------------------------------------------------------
-- The failed-gate detail must be reportable so run() can print which gate failed.
-- ----------------------------------------------------------------------------
do
  local core = all_core_pass()
  core[2] = gate(false, "sentinel block well-formed", "no managed block found")
  local res = D.aggregate(core, {})
  check("aggregate reports the failed core gates",
    type(res.failed_core) == "table" and #res.failed_core == 1
      and res.failed_core[1].label == "sentinel block well-formed",
    res.failed_core and tostring(#res.failed_core))
end

-- ----------------------------------------------------------------------------
-- The pure gate builders should each return a well-formed gate result table so
-- run() can aggregate them. They take an injectable environment so the unit test
-- never touches the real filesystem / PATH.
-- ----------------------------------------------------------------------------
do
  check("gate_binary_on_path is a pure function", type(D.gate_binary_on_path) == "function")
  check("gate_sentinel_well_formed is a pure function", type(D.gate_sentinel_well_formed) == "function")
  check("gate_config_dofiles is a pure function", type(D.gate_config_dofiles) == "function")
  check("gate_backup_exists is a pure function", type(D.gate_backup_exists) == "function")

  -- gate_sentinel_well_formed inspects supplied config text (no filesystem).
  local present = table.concat({
    "local config = {}",
    "-- >>> wezterm-setup managed block >>>",
    "require('wezterm-setup').apply(config)",
    "-- <<< wezterm-setup managed block <<<",
    "return config",
  }, "\n")
  local g_present = D.gate_sentinel_well_formed(present)
  check("sentinel gate passes on a well-formed managed block", g_present.ok == true, g_present.detail)

  local g_absent = D.gate_sentinel_well_formed("local config = {}\nreturn config\n")
  check("sentinel gate fails when the managed block is absent", g_absent.ok == false, tostring(g_absent.ok))
end

-- ----------------------------------------------------------------------------
-- gate_config_dofiles must replicate WezTerm's <config-dir>/?.lua module
-- resolution: the managed init.lua uses dotted requires
-- (require("wezterm-setup.<sibling>")) that resolve only when the config dir is
-- on package.path as <config-dir>/?.lua. Before the fix (quick 260613-dlh) the
-- gate loaded init.lua under bare lua5.4 and FALSE-FAILED on a config WezTerm
-- loads fine.
-- ----------------------------------------------------------------------------
do
  local base = os.tmpname()
  os.remove(base) -- os.tmpname makes a file; we want a dir at that path
  local setup = base .. "/wezterm-setup"
  assert(os.execute("mkdir -p '" .. setup .. "'"))
  local function writefile(path, content)
    local f = assert(io.open(path, "w")); f:write(content); f:close()
  end

  -- A sibling module that resolves ONLY via <config-dir>/?.lua (config-dir = base).
  writefile(setup .. "/dttest_sibling.lua", "return { ok = true }\n")
  -- The managed init.lua loads the sibling by DOTTED name, like the real config.
  writefile(setup .. "/init.lua",
    "local s = require('wezterm-setup.dttest_sibling')\nassert(s.ok)\nreturn {}\n")

  local path_before = package.path
  local g_dotted = D.gate_config_dofiles(setup .. "/init.lua")
  check("config-dofiles gate passes on dotted requires (WezTerm path replicated)",
    g_dotted.ok == true, g_dotted.detail)

  -- A genuinely broken config (module resolves NOWHERE) must STILL fail — the fix
  -- must not mask real load errors.
  writefile(setup .. "/init.lua",
    "require('wezterm-setup.does_not_exist_anywhere')\nreturn {}\n")
  local g_broken = D.gate_config_dofiles(setup .. "/init.lua")
  check("config-dofiles gate still fails on a genuinely missing module",
    g_broken.ok == false, tostring(g_broken.ok))

  -- The gate must RESTORE package.path (no leak of the temp config dir).
  check("config-dofiles gate restores package.path (no leak)",
    package.path == path_before, "package.path was not restored")

  os.execute("rm -rf '" .. base .. "'")
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
