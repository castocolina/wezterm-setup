-- cli/commands/uninstall_state.lua
--
-- The `wez uninstall-state` subcommand (INST-04/05). The subcommand + its flags
-- (`--keep-config`, `--keep-backup`, `--keep-cli`) are ALREADY registered in
-- cli/spec.lua by Plan 01 — this module ONLY implements the behavior; it does NOT
-- edit the spec (D-16).
--
-- Per D-01 ALL removal DECISIONS live here in Lua; the bash glue
-- (tools/uninstall.sh) is decision-free — it only translates the Makefile's
-- KEEP_CONFIG/KEEP_CLI/KEEP_BACKUP env into the corresponding flags and surfaces
-- this command's exit code.
--
-- The four managed components and their keep-flags (INST-05):
--   block    — the sentinel-bounded managed block in the user's wezterm.lua
--              (excised EXACTLY, leaving user lines byte-identical — INST-04
--              "no trace", T-06-01). No dedicated keep-flag: removed whenever
--              uninstall runs.
--   config   — the managed config tree ~/.config/wezterm/wezterm-setup/
--              (suppressed by --keep-config). Only this SUBTREE is removed — the
--              user-owned ~/.config/wezterm itself is NEVER touched (T-06-03).
--   cli      — the wez binary ~/.local/bin/wez (suppressed by --keep-cli).
--   backups  — the wezterm.lua.bak.<ts> backups (suppressed by --keep-backup).
--
-- All removals target USER paths — sudo-free (T-06-04). plan_removal() and
-- excise_block() are PURE so the decision + block-rewrite are fixture-testable
-- with no filesystem (the autonomous gate). run() wires them to the real FS.

local install_state = require("cli.commands.install_state")

local M = {}

-- ---------------------------------------------------------------------------
-- PURE removal DECISION
-- ---------------------------------------------------------------------------

-- plan_removal(flags) -> { block, config, cli, backups } booleans.
-- Everything is removed by default; each keep-flag suppresses exactly its own
-- component (INST-05). The sentinel block has no keep-flag (its removal is the
-- core of "uninstall"), so it is always removed.
function M.plan_removal(flags)
  flags = flags or {}
  return {
    block = true,
    config = not flags.keep_config,
    cli = not flags.keep_cli,
    backups = not flags.keep_backup,
  }
end

-- ---------------------------------------------------------------------------
-- PURE sentinel-block excision (T-06-01 — remove EXACTLY the managed range)
-- ---------------------------------------------------------------------------

-- excise_block(text) -> text with the managed block removed.
-- Removes the lines from the open marker through the close marker INCLUSIVE
-- (and the trailing newline of the close-marker line) so the surrounding user
-- lines are left byte-identical. A config with no managed block is returned
-- unchanged (no-op). Reuses the LOCKED markers from install_state — no variants.
function M.excise_block(text)
  text = tostring(text or "")
  local open_at = text:find(install_state.OPEN_MARKER, 1, true)
  local close_at = text:find(install_state.CLOSE_MARKER, 1, true)
  if not (open_at and close_at) or close_at < open_at then
    return text -- no managed block: no-op
  end
  -- Extend the removed range to the END of the close-marker line, including its
  -- trailing newline, so we don't leave a blank line where the block was.
  local line_end = text:find("\n", close_at, true)
  local stop = line_end or #text -- inclusive index of the last removed byte
  return text:sub(1, open_at - 1) .. text:sub(stop + 1)
end

-- ---------------------------------------------------------------------------
-- environment seams (overridable for testing; default to the real environment)
-- ---------------------------------------------------------------------------

local function default_config_file()
  local explicit = os.getenv("WEZTERM_CONFIG_FILE")
  if explicit and explicit ~= "" then return explicit end
  local home = os.getenv("HOME") or ""
  return home .. "/.config/wezterm/wezterm.lua"
end

local function default_setup_dir()
  local explicit = os.getenv("WEZTERM_SETUP_DIR")
  if explicit and explicit ~= "" then return explicit end
  local home = os.getenv("HOME") or ""
  return home .. "/.config/wezterm/wezterm-setup"
end

local function default_cli_path()
  local explicit = os.getenv("WEZ_BIN")
  if explicit and explicit ~= "" then return explicit end
  local home = os.getenv("HOME") or ""
  return home .. "/.local/bin/wez"
end

local function read_all(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local data = fh:read("*a"); fh:close(); return data
end

-- ---------------------------------------------------------------------------
-- filesystem effects (sudo-free; user paths only — T-06-04)
-- ---------------------------------------------------------------------------

-- Remove the managed block from the user's wezterm.lua via write-temp-then-rename
-- (T-06-01: a failed write leaves the original intact). No-op if absent.
local function remove_block(config_file)
  local text = read_all(config_file)
  if not text then return true end -- nothing to do
  if not text:find(install_state.OPEN_MARKER, 1, true) then
    return true -- no managed block
  end
  local stripped = M.excise_block(text)
  local ok, err = install_state.atomic_write(config_file, stripped)
  if not ok then return nil, err end
  return true
end

-- Remove ONLY the managed wezterm-setup/ subtree (never its parent — T-06-03).
local function remove_config_tree(setup_dir)
  -- A defensive guard: only remove a path whose basename is exactly the managed
  -- dir name, so a mis-set seam can never recurse a user-owned parent.
  if setup_dir:match("/wezterm%-setup/?$") then
    -- Quote the path as ONE argument (every embedded `'` -> `'\''`) and add `--`
    -- so a path containing a quote or leading `-` cannot break out of the shell
    -- and inject a command into `rm -rf` (CR-02).
    os.execute("rm -rf -- " .. install_state.shquote(setup_dir))
  end
  return true
end

local function remove_cli(cli_path)
  os.remove(cli_path)
  return true
end

-- Remove every wezterm.lua.bak.<ts> beside the config file.
local function remove_backups(config_file)
  local dir, base = config_file:match("^(.*)/([^/]+)$")
  if not dir then dir, base = ".", config_file end
  local prefix = base .. ".bak."
  local p = io.popen("ls -1 -- " .. install_state.shquote(dir) .. " 2>/dev/null")
  if not p then return true end
  for name in p:lines() do
    if name:sub(1, #prefix) == prefix then
      os.remove(dir .. "/" .. name)
    end
  end
  p:close()
  return true
end

-- ---------------------------------------------------------------------------
-- run() — wire the pure decision to the real filesystem
-- ---------------------------------------------------------------------------

-- run(args [, seams]) -> numeric exit code.
-- `args` carries the parsed flags (argparse maps `--keep-config` to
-- args["keep_config"]). `seams` (optional) overrides the resolved paths for
-- fixture testing.
function M.run(args, seams)
  args = args or {}
  seams = seams or {}

  local config_file = seams.config_file or default_config_file()
  local setup_dir = seams.setup_dir or default_setup_dir()
  local cli_path = seams.cli_path or default_cli_path()

  local flags = {
    keep_config = args.keep_config,
    keep_cli = args.keep_cli,
    keep_backup = args.keep_backup,
  }
  local plan = M.plan_removal(flags)

  if plan.block then
    local ok, err = remove_block(config_file)
    if not ok then
      io.stderr:write("wez uninstall-state: failed to remove managed block: " .. tostring(err) .. "\n")
      return 1
    end
    io.write("wez uninstall-state: removed managed block from " .. config_file .. "\n")
  end

  if plan.config then
    remove_config_tree(setup_dir)
    io.write("wez uninstall-state: removed managed config tree " .. setup_dir .. "\n")
  else
    io.write("wez uninstall-state: preserved config tree (--keep-config)\n")
  end

  if plan.cli then
    remove_cli(cli_path)
    io.write("wez uninstall-state: removed wez binary " .. cli_path .. "\n")
  else
    io.write("wez uninstall-state: preserved wez binary (--keep-cli)\n")
  end

  if plan.backups then
    remove_backups(config_file)
    io.write("wez uninstall-state: removed timestamped backups\n")
  else
    io.write("wez uninstall-state: preserved timestamped backups (--keep-backup)\n")
  end

  return 0
end

return M
