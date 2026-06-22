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
-- GATE 5 — shadow-detection (D-11). gate_no_shadowing(text) is a PURE text grep:
-- it FAILS when the user's wezterm.lua registers its own
-- `wezterm.on("format-tab-title", ...)` handler (or a shadowing keybinding block)
-- OUTSIDE the wezterm-setup managed sentinel block — the root cause of the
-- `cyan:` literal / no-color / no-cwd bug. A match INSIDE the managed block is the
-- expected managed renderer and must NOT fail. The decision never executes the
-- user's wezterm.lua (T-06-02 preserved) — it only inspects supplied text.
-- ----------------------------------------------------------------------------
do
  check("gate_no_shadowing is a pure function", type(D.gate_no_shadowing) == "function")

  -- (a) clean text — managed block present, no inline handler -> PASS.
  local clean = table.concat({
    "local config = {}",
    "-- >>> wezterm-setup managed block >>>",
    "require('wezterm-setup').apply(config)",
    "-- <<< wezterm-setup managed block <<<",
    "return config",
  }, "\n")
  local g_clean = D.gate_no_shadowing(clean)
  check("shadow gate passes on a clean config (no inline handler)", g_clean.ok == true, g_clean.detail)

  -- (b) an inline format-tab-title handler OUTSIDE the managed block -> FAIL,
  -- with an actionable detail.
  local shadow_dq = table.concat({
    "local wezterm = require('wezterm')",
    "local config = {}",
    'wezterm.on("format-tab-title", function(tab) return tab.active_pane.title end)',
    "-- >>> wezterm-setup managed block >>>",
    "require('wezterm-setup').apply(config)",
    "-- <<< wezterm-setup managed block <<<",
    "return config",
  }, "\n")
  local g_dq = D.gate_no_shadowing(shadow_dq)
  check("shadow gate fails on an inline format-tab-title handler (double quotes)",
    g_dq.ok == false, tostring(g_dq.ok))
  check("shadow gate failure carries an actionable detail mentioning format-tab-title",
    type(g_dq.detail) == "string" and g_dq.detail:find("format-tab-title", 1, true) ~= nil,
    g_dq.detail)

  -- single-quote registration is detected too.
  local shadow_sq = table.concat({
    "local config = {}",
    "wezterm.on('format-tab-title', function(tab) return '' end)",
    "-- >>> wezterm-setup managed block >>>",
    "require('wezterm-setup').apply(config)",
    "-- <<< wezterm-setup managed block <<<",
    "return config",
  }, "\n")
  check("shadow gate fails on an inline format-tab-title handler (single quotes)",
    D.gate_no_shadowing(shadow_sq).ok == false, "expected FAIL")

  -- (c) the SAME registration INSIDE the managed block -> PASS (managed handler
  -- is expected; a managed-block-internal match is NOT a failure).
  local managed_internal = table.concat({
    "local config = {}",
    "-- >>> wezterm-setup managed block >>>",
    'wezterm.on("format-tab-title", function(tab) return tab.title end)',
    "require('wezterm-setup').apply(config)",
    "-- <<< wezterm-setup managed block <<<",
    "return config",
  }, "\n")
  check("shadow gate passes when the only handler is INSIDE the managed block",
    D.gate_no_shadowing(managed_internal).ok == true, "managed-internal handler must not fail")

  -- (d) aggregate() with the shadow gate failing -> non-zero exit code (it gates
  -- the exit code like the other core gates, D-11).
  do
    local core = all_core_pass()
    core[#core + 1] = gate(false, "no shadowing handler", "inline format-tab-title found")
    local res = D.aggregate(core, {})
    check("a failing shadow gate in core returns non-zero", res.code ~= 0, "code=" .. tostring(res.code))
  end

end

-- ----------------------------------------------------------------------------
-- BACKUP GATE — fresh-install exception (07-04). On a clean machine the install
-- CREATES wezterm.lua from scratch, so there is no prior config to back up and
-- the absence of a backup is correct, NOT a failure. The gate passes when a
-- backup exists OR the config is a wezterm-setup fresh creation (detected via the
-- `Created by wezterm-setup` marker, injectable as opts.created_fresh). A genuine
-- missing-backup on a NON-fresh (pre-existing user) config still fails.
-- ----------------------------------------------------------------------------
do
  -- A real backup present -> pass (existing behavior).
  local g_bak = D.gate_backup_exists("/nonexistent/wezterm.lua",
    { backup = "/nonexistent/wezterm.lua.bak.2026-06-22T00-00-00Z" })
  check("backup gate passes when a timestamped backup exists", g_bak.ok == true, g_bak.detail)

  -- No backup, but a fresh wezterm-setup creation -> pass (new exception).
  local g_fresh = D.gate_backup_exists("/nonexistent/wezterm.lua",
    { backup = false, created_fresh = true })
  check("backup gate passes on a fresh install with no backup",
    g_fresh.ok == true, tostring(g_fresh.detail))
  check("fresh-install pass carries an explanatory detail",
    type(g_fresh.detail) == "string"
      and g_fresh.detail:find("fresh install", 1, true) ~= nil, tostring(g_fresh.detail))

  -- No backup AND not a fresh creation (a pre-existing user config that was
  -- modified without a backup) -> still fails loudly.
  local g_miss = D.gate_backup_exists("/nonexistent/wezterm.lua",
    { backup = false, created_fresh = false })
  check("backup gate still fails when a non-fresh config has no backup",
    g_miss.ok == false, tostring(g_miss.ok))
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
