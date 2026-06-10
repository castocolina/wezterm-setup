-- tests/cli/uninstall_state_test.lua
-- Plain assert()-based unit tests for `wez uninstall-state` (Plan 06, INST-04/05).
--
-- Covers:
--   * the PURE removal-DECISION core: plan_removal(flags) -> which of the four
--     components {block, config, cli, backups} to remove, honoring
--     --keep-config / --keep-backup / --keep-cli (INST-05).
--   * the PURE sentinel-block excision: excise_block(text) removes EXACTLY the
--     managed sentinel-bounded range, leaving surrounding user lines
--     byte-identical (INST-04 "no trace", T-06-01).
--   * the filesystem run against a scratch fixture layout: full uninstall removes
--     block+config+cli+backups; each keep-flag preserves exactly its component.
--
-- All assertions are FIXTURE / TEMP-FS driven (no real ~/.config edits, sudo-free),
-- so this file is an autonomous gate under tools/run-tests.sh.
--
-- Run directly: `lua5.4 tests/cli/uninstall_state_test.lua`.

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

local US = require("cli.commands.uninstall_state")

-- ----------------------------------------------------------------------------
-- PURE removal decision: plan_removal(flags) -> { block, config, cli, backups }.
-- With NO flags everything is removed; each keep-flag suppresses exactly one
-- component (INST-05). --keep-config preserves the config TREE; the sentinel
-- block in wezterm.lua is its own component (always removed unless... it has no
-- dedicated keep-flag, so it is removed whenever uninstall runs).
-- ----------------------------------------------------------------------------
do
  local all = US.plan_removal({})
  check("no flags -> remove block", all.block == true, tostring(all.block))
  check("no flags -> remove config", all.config == true, tostring(all.config))
  check("no flags -> remove cli", all.cli == true, tostring(all.cli))
  check("no flags -> remove backups", all.backups == true, tostring(all.backups))

  local kc = US.plan_removal({ keep_config = true })
  check("--keep-config preserves config", kc.config == false, tostring(kc.config))
  check("--keep-config still removes cli", kc.cli == true)
  check("--keep-config still removes backups", kc.backups == true)
  check("--keep-config still removes block", kc.block == true)

  local kcli = US.plan_removal({ keep_cli = true })
  check("--keep-cli preserves cli", kcli.cli == false, tostring(kcli.cli))
  check("--keep-cli still removes config", kcli.config == true)
  check("--keep-cli still removes block", kcli.block == true)
  check("--keep-cli still removes backups", kcli.backups == true)

  local kb = US.plan_removal({ keep_backup = true })
  check("--keep-backup preserves backups", kb.backups == false, tostring(kb.backups))
  check("--keep-backup still removes config", kb.config == true)
  check("--keep-backup still removes cli", kb.cli == true)
  check("--keep-backup still removes block", kb.block == true)
end

-- ----------------------------------------------------------------------------
-- PURE sentinel-block excision: removes EXACTLY the managed block, leaving the
-- surrounding user lines byte-identical (INST-04 no-trace / T-06-01).
-- ----------------------------------------------------------------------------
do
  local HEAD = "local wezterm = require 'wezterm'\nlocal config = wezterm.config_builder()\nconfig.font = wezterm.font 'JetBrains Mono'\n"
  local BLOCK = "-- >>> wezterm-setup managed block >>>\nrequire('wezterm-setup').apply(config)\n-- <<< wezterm-setup managed block <<<\n"
  local TAIL = "return config\n"
  local managed = HEAD .. BLOCK .. TAIL

  local stripped = US.excise_block(managed)
  check("excision removes the open marker", stripped:find("managed block >>>", 1, true) == nil, stripped)
  check("excision removes the close marker", stripped:find("managed block <<<", 1, true) == nil)
  check("excision removes the apply call", stripped:find("require('wezterm-setup').apply", 1, true) == nil)
  -- Surrounding user lines survive BYTE-IDENTICAL: HEAD..TAIL with nothing else.
  check("surrounding user lines are byte-identical after excision",
    stripped == HEAD .. TAIL, "[[" .. stripped .. "]]")

  -- Excising a config with NO managed block is a no-op (leaves text unchanged).
  local clean = HEAD .. TAIL
  check("excision on a config without a managed block is a no-op",
    US.excise_block(clean) == clean)
end

-- ----------------------------------------------------------------------------
-- Filesystem run against a scratch fixture layout. We build a fake "installed"
-- tree and drive run() with seam env vars pointing at it, then assert which
-- components survive for each flag combination.
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

-- Build a scratch installed layout; returns a table of the relevant paths.
local function build_fixture()
  local base = os.getenv("TMPDIR") or "/tmp"
  local root = string.format("%s/wezsetup-untest-%d-%d", base, os.time(), math.random(1, 1e6))
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

local function run_with(fx, flags)
  return US.run(flags, {
    config_file = fx.cfg,
    setup_dir = fx.setup_dir,
    cli_path = fx.cli,
  })
end

-- Full uninstall: block excised, config tree gone, cli gone, backups gone.
do
  local fx = build_fixture()
  local code = run_with(fx, {})
  check("full uninstall exits 0", code == 0, "code=" .. tostring(code))
  local cfg = read_file(fx.cfg)
  check("full uninstall excises the block (no trace)",
    cfg ~= nil and cfg:find("managed block", 1, true) == nil, cfg)
  check("full uninstall leaves surrounding user lines intact",
    cfg == HEAD .. TAIL, cfg)
  check("full uninstall removes the config tree", not exists(fx.setup_dir))
  check("full uninstall removes the cli binary", not exists(fx.cli))
  check("full uninstall removes the backups", not exists(fx.backup))
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- --keep-config preserves the config tree; removes the rest.
do
  local fx = build_fixture()
  run_with(fx, { keep_config = true })
  check("--keep-config preserves the config tree", exists(fx.setup_dir))
  check("--keep-config still removes the cli", not exists(fx.cli))
  check("--keep-config still removes the backups", not exists(fx.backup))
  check("--keep-config still excises the block",
    (read_file(fx.cfg) or ""):find("managed block", 1, true) == nil)
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- --keep-cli preserves the wez binary; removes the rest.
do
  local fx = build_fixture()
  run_with(fx, { keep_cli = true })
  check("--keep-cli preserves the cli binary", exists(fx.cli))
  check("--keep-cli still removes the config tree", not exists(fx.setup_dir))
  check("--keep-cli still removes the backups", not exists(fx.backup))
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- --keep-backup preserves the backups; removes the rest.
do
  local fx = build_fixture()
  run_with(fx, { keep_backup = true })
  check("--keep-backup preserves the backups", exists(fx.backup))
  check("--keep-backup still removes the config tree", not exists(fx.setup_dir))
  check("--keep-backup still removes the cli", not exists(fx.cli))
  os.execute("rm -rf '" .. fx.root .. "'")
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
