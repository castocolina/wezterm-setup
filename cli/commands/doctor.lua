-- cli/commands/doctor.lua
--
-- The `wez doctor` subcommand (DIAG-01). The subcommand is ALREADY registered in
-- cli/spec.lua by Plan 01 — this module ONLY implements the behavior; it does NOT
-- edit the spec (D-16).
--
-- Per D-01 all of the health DECISIONS live here in Lua; the Makefile `doctor`
-- target is decision-free glue that just shells out to `wez doctor`.
--
-- D-15 — what gates the EXIT CODE (the headless / CI install-health gate, R2):
-- exactly FOUR CORE integrity gates, each contributing to the exit code:
--   1. the `wez` binary is on PATH
--   2. the managed sentinel block in wezterm.lua is well-formed (reuse the
--      install_state PARSE contract — same LOCKED markers, no variants)
--   3. the managed config dir dofiles cleanly: loading
--      ~/.config/wezterm/wezterm-setup/init.lua raises no error (in a protected
--      pcall — T-06-02: doctor never executes the user's wezterm.lua side effects,
--      only loads the managed init.lua chunk to test it parses/loads)
--   4. a timestamped backup (wezterm.lua.bak.<ts>) exists
-- If ALL four pass -> exit 0; if ANY fails -> non-zero, printing each failed gate.
--
-- ADVISORY probes (PRINTED, but NEVER change the exit code — D-15): the
-- completions-installed check and a live-session reachability probe
-- (`wezterm cli list`). An advisory failure on a healthy install keeps exit 0;
-- live behavior is integration-test territory (R7), not the headless gate.
--
-- aggregate() and the gate_* builders are PURE / injectable so the gate-
-- aggregation logic is fixture-testable with no real filesystem, PATH, or live
-- WezTerm (the autonomous gate, tests/cli/doctor_test.lua). run() wires them to
-- the real environment.

local install_state = require("cli.commands.install_state")

local M = {}

-- ---------------------------------------------------------------------------
-- gate result shape + aggregation (PURE)
-- ---------------------------------------------------------------------------

-- A gate result: { ok = boolean, label = string, detail = string|nil }.
local function gate(ok, label, detail)
  return { ok = ok, label = label, detail = detail }
end
M.gate = gate

-- aggregate(core, advisory) -> { code = <0|non-zero>, core = {...},
--                                advisory = {...}, failed_core = {...} }
-- The exit code is gated SOLELY by the core gates (D-15): 0 iff every core gate
-- passed, non-zero otherwise. Advisory results are carried through for printing
-- but never influence `code`.
function M.aggregate(core, advisory)
  core = core or {}
  advisory = advisory or {}
  local failed_core = {}
  for _, g in ipairs(core) do
    if not g.ok then
      failed_core[#failed_core + 1] = g
    end
  end
  return {
    code = (#failed_core == 0) and 0 or 1,
    core = core,
    advisory = advisory,
    failed_core = failed_core,
  }
end

-- ---------------------------------------------------------------------------
-- environment seams (overridable for testing; default to the real environment)
-- ---------------------------------------------------------------------------

-- Resolve the user's wezterm.lua (honors WEZTERM_CONFIG_FILE like install_state).
local function config_path()
  local explicit = os.getenv("WEZTERM_CONFIG_FILE")
  if explicit and explicit ~= "" then return explicit end
  local home = os.getenv("HOME") or ""
  return home .. "/.config/wezterm/wezterm.lua"
end
M.config_path = config_path

-- The installed managed config tree (Plan 03 places this; Plan 04 wires it).
local function setup_dir()
  local explicit = os.getenv("WEZTERM_SETUP_DIR")
  if explicit and explicit ~= "" then return explicit end
  local home = os.getenv("HOME") or ""
  return home .. "/.config/wezterm/wezterm-setup"
end
M.setup_dir = setup_dir

local function read_all(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local data = fh:read("*a")
  fh:close()
  return data
end

-- ---------------------------------------------------------------------------
-- CORE gate builders (each returns a gate result). Side-effect inputs are passed
-- in (text / path) so the pure decision is unit-testable.
-- ---------------------------------------------------------------------------

-- GATE 1 — the `wez` binary is on PATH. `which` is portable across Linux+macOS
-- (no /proc, D-18). Injectable via opts.found for testing.
function M.gate_binary_on_path(opts)
  opts = opts or {}
  local found = opts.found
  if found == nil then
    local ok = os.execute("command -v wez >/dev/null 2>&1")
    found = (ok == true or ok == 0)
  end
  if found then
    return gate(true, "wez binary on PATH")
  end
  return gate(false, "wez binary on PATH", "`wez` not found on PATH")
end

-- GATE 2 — the managed sentinel block in wezterm.lua is well-formed. Reuses the
-- install_state PARSE contract (same LOCKED markers). Takes the config TEXT so
-- the decision is pure (run() reads the file and passes its contents).
function M.gate_sentinel_well_formed(text)
  if not text then
    return gate(false, "sentinel block well-formed", "could not read wezterm.lua")
  end
  local parsed = install_state.parse(text)
  if parsed.state == "present" then
    return gate(true, "sentinel block well-formed")
  end
  return gate(false, "sentinel block well-formed",
    "no wezterm-setup managed block found in wezterm.lua")
end

-- GATE 3 — the managed config dir dofiles cleanly: loadfile()+pcall the managed
-- init.lua. Loading is done in a PROTECTED pcall so a config error is REPORTED,
-- never propagated, and doctor never executes the user's wezterm.lua side effects
-- (T-06-02). Injectable via opts.loader for testing.
function M.gate_config_dofiles(init_path, opts)
  opts = opts or {}
  local loader = opts.loader
  local ok, err
  if loader then
    ok, err = loader(init_path)
  else
    -- Replicate WezTerm's module resolution before loading: WezTerm puts
    -- `<config-dir>/?.lua` on its Lua path, so the managed init.lua's DOTTED
    -- requires (`require("wezterm-setup.keybindings")`, ...) resolve to
    -- `<config-dir>/wezterm-setup/<name>.lua`. Plain lua5.4 does NOT, so without
    -- this the gate FALSE-FAILS on a config WezTerm loads cleanly. The config dir
    -- is the PARENT of init.lua's directory
    -- (init_path = <config-dir>/wezterm-setup/init.lua). Prepend it, then restore
    -- package.path on EVERY exit path (loadfile error or pcall) so the gate leaks
    -- nothing. Still loads ONLY the managed init.lua chunk — no user wezterm.lua
    -- side effects (T-06-02).
    local init_dir = tostring(init_path):match("^(.*)/[^/]+$")
    local config_dir = init_dir and init_dir:match("^(.*)/[^/]+$")
    local saved_path = package.path
    if config_dir and config_dir ~= "" then
      package.path = config_dir .. "/?.lua;" .. config_dir .. "/?/init.lua;" .. package.path
    end
    -- loadfile compiles the chunk; pcall runs it under protection. A module that
    -- only `return`s a table loads cleanly without side effects.
    local chunk, lerr = loadfile(init_path)
    if not chunk then
      ok, err = false, lerr
    else
      ok, err = pcall(chunk)
    end
    package.path = saved_path
  end
  if ok then
    return gate(true, "config dofiles cleanly")
  end
  return gate(false, "config dofiles cleanly",
    "loading " .. tostring(init_path) .. " failed: " .. tostring(err))
end

-- GATE 4 — a timestamped backup exists beside wezterm.lua. Reuses the
-- install_state newest_backup selector. Injectable via opts.backup for testing.
function M.gate_backup_exists(target, opts)
  opts = opts or {}
  local backup = opts.backup
  if backup == nil then
    backup = install_state.newest_backup(target)
  end
  if backup then
    return gate(true, "timestamped backup exists")
  end
  return gate(false, "timestamped backup exists",
    "no wezterm.lua.bak.<timestamp> backup found")
end

-- ---------------------------------------------------------------------------
-- ADVISORY probes (PRINTED, never gate the exit code — D-15)
-- ---------------------------------------------------------------------------

-- ADVISORY — shell completions installed. Checks for the completions marker in
-- the user's rc files (Plan 07 registers it). Absence is INFORMATIONAL only.
function M.probe_completions_installed(opts)
  opts = opts or {}
  local installed = opts.installed
  if installed == nil then
    local home = os.getenv("HOME") or ""
    local marker = "# wezterm-setup:completions"
    installed = false
    for _, rc in ipairs({ home .. "/.bashrc", home .. "/.zshrc" }) do
      local data = read_all(rc)
      if data and data:find(marker, 1, true) then
        installed = true
        break
      end
    end
  end
  if installed then
    return gate(true, "shell completions installed")
  end
  return gate(false, "shell completions installed",
    "completions not installed yet (run `wez completions <shell>`) — advisory only")
end

-- ADVISORY — live WezTerm session reachable (`wezterm cli list`). A missing live
-- session (e.g. headless CI) is EXPECTED; never affects the exit code (R7).
function M.probe_live_session(opts)
  opts = opts or {}
  local reachable = opts.reachable
  if reachable == nil then
    local ok = os.execute("wezterm cli list >/dev/null 2>&1")
    reachable = (ok == true or ok == 0)
  end
  if reachable then
    return gate(true, "live WezTerm session reachable")
  end
  return gate(false, "live WezTerm session reachable",
    "no live WezTerm session (expected when run headless) — advisory only")
end

-- ---------------------------------------------------------------------------
-- printing
-- ---------------------------------------------------------------------------

local function print_section(title, gates)
  io.write(title .. "\n")
  for _, g in ipairs(gates) do
    local mark = g.ok and "PASS" or "FAIL"
    if g.detail and g.detail ~= "" then
      io.write(string.format("  [%s] %s — %s\n", mark, g.label, g.detail))
    else
      io.write(string.format("  [%s] %s\n", mark, g.label))
    end
  end
end

-- ---------------------------------------------------------------------------
-- run() — wire the pure logic to the real environment
-- ---------------------------------------------------------------------------

function M.run(_args)
  local target = config_path()
  local cfg_text = read_all(target)
  local init_path = setup_dir() .. "/init.lua"

  local core = {
    M.gate_binary_on_path(),
    M.gate_sentinel_well_formed(cfg_text),
    M.gate_config_dofiles(init_path),
    M.gate_backup_exists(target),
  }

  local advisory = {
    M.probe_completions_installed(),
    M.probe_live_session(),
  }

  local result = M.aggregate(core, advisory)

  io.write("wez doctor — install health\n\n")
  print_section("Core integrity gates (determine exit code):", core)
  io.write("\n")
  print_section("Advisory probes (informational; never affect exit code):", advisory)
  io.write("\n")

  if result.code == 0 then
    io.write("OK: all core integrity gates passed (exit 0)\n")
  else
    io.write(string.format("FAIL: %d core integrity gate(s) failed (exit %d)\n",
      #result.failed_core, result.code))
    for _, g in ipairs(result.failed_core) do
      io.write("  - " .. g.label .. (g.detail and (": " .. g.detail) or "") .. "\n")
    end
  end

  return result.code
end

return M
