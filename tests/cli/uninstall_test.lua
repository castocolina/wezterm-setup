-- tests/cli/uninstall_test.lua
-- Plain assert()-based unit tests for the `wez uninstall` FRONT DOOR (Plan 06.3-01,
-- INST-07/08/09). The front door is a thin Lua command over the audited
-- `uninstall_state` removal engine (D-09): it confirms-then-removes everything on a
-- TTY, REQUIRES `--yes` on a non-TTY pipe (D-11/D-03), surfaces the engine's
-- `--keep-config`/`--keep-cli`/`--keep-backup` flags, and orders removal so the
-- running `wez` binary self-deletes LAST (D-10).
--
-- Covers:
--   * the module interface: `cli.commands.uninstall` loads and exposes `run`.
--   * the spec 3-place registration that makes `wez uninstall` tab-complete (D-16):
--     in subcommand_names(), categorized "install", parseable by build_parser().
--   * flag pass-through: a full `--yes` uninstall removes block+config+backups+cli;
--     each `--keep-*` preserves exactly its component.
--   * the D-11 no-TTY gate: a non-TTY pipe WITHOUT `--yes` aborts non-zero and
--     removes NOTHING (the engine is never reached); the same fixture with `--yes`
--     proceeds to 0.
--   * the TTY confirm path: decline (assume_yes=false) aborts intact; confirm
--     (assume_yes=true) proceeds to 0.
--   * the D-10 ordering: under a fixture where the cli lives beside config/backups,
--     a full uninstall leaves all four (block/config/backups/cli) absent.
--
-- The FROZEN front-door seam keys (per the plan's <seam_contract>): the engine's
-- existing path seams `config_file` / `setup_dir` / `cli_path`, PLUS the front-door
-- TEST-ONLY seams `is_tty` (boolean — override the interactivity probe) and
-- `assume_yes` (boolean — stand in for the interactive io.read answer). These five
-- keys are used VERBATIM here; Task 2's implementation honors exactly the same keys.
--
-- All assertions are FIXTURE / TEMP-FS driven (no real ~/.config edits, sudo-free,
-- no real terminal), so this file is an autonomous gate under tools/run-tests.sh.
--
-- Run directly: `lua5.4 tests/cli/uninstall_test.lua`.

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

-- ----------------------------------------------------------------------------
-- fixture helpers (mirror uninstall_state_test.lua build_fixture/run_with/exists)
-- ----------------------------------------------------------------------------
local function read_file(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local data = fh:read("*a"); fh:close(); return data
end
local function write_file(path, data)
  local fh = assert(io.open(path, "wb")); fh:write(data); fh:close()
end
local function exists(path)
  local ok = os.execute("test -e '" .. path .. "'")
  return ok == true or ok == 0
end

local HEAD = "local wezterm = require 'wezterm'\nlocal config = wezterm.config_builder()\nconfig.font = wezterm.font 'JetBrains Mono'\n"
local BLOCK = "-- >>> wezterm-setup managed block >>>\nrequire('wezterm-setup').apply(config)\n-- <<< wezterm-setup managed block <<<\n"
local TAIL = "return config\n"

-- Build a scratch installed layout with the cli binary living BESIDE the config
-- + backups (so the D-10 ordering assertion exercises a co-located binary).
local function build_fixture()
  local base = os.getenv("TMPDIR") or "/tmp"
  local root = string.format("%s/wezsetup-uninst-front-%d-%d", base, os.time(), math.random(1, 1e6))
  assert(os.execute("mkdir -p '" .. root .. "/wezterm/wezterm-setup' '" .. root .. "/bin'"))
  local cfg = root .. "/wezterm/wezterm.lua"
  write_file(cfg, HEAD .. BLOCK .. TAIL)
  write_file(cfg .. ".bak.2026-06-09T00-00-00Z", "original backup\n")
  write_file(root .. "/wezterm/wezterm-setup/init.lua", "return {}\n")
  write_file(root .. "/bin/wez", "#!/bin/sh\n")
  return {
    root = root,
    cfg = cfg,
    backup = cfg .. ".bak.2026-06-09T00-00-00Z",
    setup_dir = root .. "/wezterm/wezterm-setup",
    cli = root .. "/bin/wez",
  }
end

-- Drive the front door via require("cli.commands.uninstall").run(args, seams),
-- passing the FROZEN seam keys: the engine path seams (config_file/setup_dir/
-- cli_path) PLUS the front-door test seams (is_tty/assume_yes) merged in.
local UN = require("cli.commands.uninstall")
local function run_with(fx, args, extra_seams)
  local seams = {
    config_file = fx.cfg,
    setup_dir = fx.setup_dir,
    cli_path = fx.cli,
  }
  if extra_seams then
    for k, v in pairs(extra_seams) do seams[k] = v end
  end
  return UN.run(args, seams)
end

-- ----------------------------------------------------------------------------
-- Interface contract: the module loads and exposes run().
-- ----------------------------------------------------------------------------
check("uninstall module loads", type(UN) == "table")
check("uninstall exposes run()", type(UN.run) == "function")

-- ----------------------------------------------------------------------------
-- spec 3-place registration: `uninstall` is in the closed allow-list, categorized
-- "install", and build_parser() parses `{uninstall,--yes,--keep-config}` (D-16).
-- (mirror update_test.lua lines 126-136)
-- ----------------------------------------------------------------------------
do
  local spec = require("cli.spec")
  local found = false
  for _, n in ipairs(spec.subcommand_names()) do
    if n == "uninstall" then found = true end
  end
  check("uninstall is registered in spec.subcommand_names()", found)
  check("uninstall is categorized under 'install'",
    spec.categories()["uninstall"] == "install")
  local p = spec.build_parser()
  local ok, r = p:pparse({ "uninstall", "--yes", "--keep-config" })
  check("build_parser parses {uninstall,--yes,--keep-config}", ok, tostring(r))
  check("parsed command == 'uninstall'", ok and r.command == "uninstall")
  check("parsed --yes is truthy", ok and r.yes and true or false)
  check("parsed --keep-config is truthy", ok and r.keep_config and true or false)
end

-- ----------------------------------------------------------------------------
-- Flag pass-through: a full `--yes` uninstall removes ALL FOUR components and the
-- D-10 ordering leaves block/config/backups/cli absent post-run (exit 0).
-- ----------------------------------------------------------------------------
do
  local fx = build_fixture()
  local code = run_with(fx, { yes = true })
  check("full --yes uninstall exits 0", code == 0, "code=" .. tostring(code))
  local cfg = read_file(fx.cfg)
  check("full --yes uninstall excises the block (no trace)",
    cfg ~= nil and cfg:find("managed block", 1, true) == nil, cfg)
  check("full --yes uninstall leaves surrounding user lines intact",
    cfg == HEAD .. TAIL, cfg)
  check("full --yes uninstall removes the config tree", not exists(fx.setup_dir))
  check("full --yes uninstall removes the backups", not exists(fx.backup))
  check("full --yes uninstall removes the cli binary LAST (D-10)", not exists(fx.cli))
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- --keep-cli preserves the binary; removes the rest.
do
  local fx = build_fixture()
  local code = run_with(fx, { yes = true, keep_cli = true })
  check("--keep-cli exits 0", code == 0, "code=" .. tostring(code))
  check("--keep-cli preserves the cli binary", exists(fx.cli))
  check("--keep-cli still removes the config tree", not exists(fx.setup_dir))
  check("--keep-cli still removes the backups", not exists(fx.backup))
  check("--keep-cli still excises the block",
    (read_file(fx.cfg) or ""):find("managed block", 1, true) == nil)
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- --keep-config preserves the config tree; removes the rest (incl. cli LAST).
do
  local fx = build_fixture()
  run_with(fx, { yes = true, keep_config = true })
  check("--keep-config preserves the config tree", exists(fx.setup_dir))
  check("--keep-config still removes the cli", not exists(fx.cli))
  check("--keep-config still removes the backups", not exists(fx.backup))
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- --keep-backup preserves the backups; removes the rest (incl. cli LAST).
do
  local fx = build_fixture()
  run_with(fx, { yes = true, keep_backup = true })
  check("--keep-backup preserves the backups", exists(fx.backup))
  check("--keep-backup still removes the config tree", not exists(fx.setup_dir))
  check("--keep-backup still removes the cli", not exists(fx.cli))
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- ----------------------------------------------------------------------------
-- D-11 no-TTY gate: a non-TTY pipe WITHOUT `--yes` aborts non-zero and removes
-- NOTHING (the engine is never reached). The frozen `is_tty=false` seam drives it.
-- ----------------------------------------------------------------------------
do
  local fx = build_fixture()
  local code = run_with(fx, {}, { is_tty = false })
  check("no-TTY without --yes aborts non-zero", code ~= 0, "code=" .. tostring(code))
  check("no-TTY abort leaves the block intact",
    (read_file(fx.cfg) or ""):find("managed block", 1, true) ~= nil)
  check("no-TTY abort leaves the config tree intact", exists(fx.setup_dir))
  check("no-TTY abort leaves the cli intact", exists(fx.cli))
  check("no-TTY abort leaves the backups intact", exists(fx.backup))
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- Same fixture, non-TTY, but WITH --yes -> proceeds to 0 and removes everything.
do
  local fx = build_fixture()
  local code = run_with(fx, { yes = true }, { is_tty = false })
  check("no-TTY WITH --yes proceeds (exit 0)", code == 0, "code=" .. tostring(code))
  check("no-TTY WITH --yes removes the config tree", not exists(fx.setup_dir))
  check("no-TTY WITH --yes removes the cli", not exists(fx.cli))
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- ----------------------------------------------------------------------------
-- TTY confirm path: decline (assume_yes=false) aborts intact; confirm
-- (assume_yes=true) proceeds. Driven by the frozen is_tty + assume_yes seams.
-- ----------------------------------------------------------------------------
do
  local fx = build_fixture()
  local code = run_with(fx, {}, { is_tty = true, assume_yes = false })
  check("TTY decline aborts non-zero", code ~= 0, "code=" .. tostring(code))
  check("TTY decline leaves the block intact",
    (read_file(fx.cfg) or ""):find("managed block", 1, true) ~= nil)
  check("TTY decline leaves the config tree intact", exists(fx.setup_dir))
  check("TTY decline leaves the cli intact", exists(fx.cli))
  check("TTY decline leaves the backups intact", exists(fx.backup))
  os.execute("rm -rf '" .. fx.root .. "'")
end

do
  local fx = build_fixture()
  local code = run_with(fx, {}, { is_tty = true, assume_yes = true })
  check("TTY confirm proceeds (exit 0)", code == 0, "code=" .. tostring(code))
  check("TTY confirm removes the config tree", not exists(fx.setup_dir))
  check("TTY confirm removes the cli", not exists(fx.cli))
  check("TTY confirm removes the backups", not exists(fx.backup))
  check("TTY confirm excises the block",
    (read_file(fx.cfg) or ""):find("managed block", 1, true) == nil)
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
