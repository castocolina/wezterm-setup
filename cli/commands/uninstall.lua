-- cli/commands/uninstall.lua
--
-- The `wez uninstall` subcommand (INST-07/08/09) — the documented FRONT DOOR over
-- the `uninstall_state` removal engine (D-09). Unlike `wez uninstall-state` (the
-- decision engine, driven by `make uninstall` glue), this command is the
-- human-facing command that works in the binary-only case (no repo checkout):
-- it confirms-then-removes-everything by default on a TTY, REQUIRES `--yes` on a
-- non-TTY pipe (D-11/D-03), surfaces the engine's `--keep-config`/`--keep-cli`/
-- `--keep-backup` flags, and orders removal so the running `wez` binary
-- self-deletes LAST (D-10).
--
-- D-09 DELEGATION (CRITICAL): this is a THIN front door. It NEVER re-implements
-- block excision, config-tree removal, or backup removal — all of that is owned by
-- the audited `uninstall_state` engine (cli/commands/uninstall_state.lua). The ONLY
-- NEW logic here is (1) the interactivity/confirm gate (D-11) and (2) the binary-
-- removed-LAST ordering (D-10). It adds NO new path globs (T-06.3-01-02).
--
-- D-10 binary self-deletion LAST: a process CAN unlink its own running executable
-- on Linux/macOS — the inode persists until the process exits (Pattern: rename(2)/
-- unlink(2) keep the open inode alive). So we call the engine with keep_cli=true
-- (it removes block+config+backups but LEAVES the binary), then os.remove the
-- resolved cli path ourselves as the FINAL step.
--
-- D-11 no-TTY abort: the destructive default must NOT fire on a stray pipe. On a
-- non-interactive stdin WITHOUT `--yes`, abort non-zero and remove NOTHING (the
-- engine is never called). The tty probe uses the pinned Lua 5.4 idiom
-- `os.execute("test -t 0") == true` (os.execute returns true|nil as its FIRST
-- value in 5.4 — NOT an integer), so a real pipe is correctly detected as non-TTY.
--
-- TEST SEAMS (FROZEN by the plan's <seam_contract>): `seams.config_file` /
-- `seams.setup_dir` / `seams.cli_path` pass STRAIGHT THROUGH to the engine (same
-- names it already accepts). `seams.is_tty` (boolean) overrides the interactivity
-- probe; `seams.assume_yes` (boolean) stands in for the interactive io.read answer.
-- These exist purely for fixture testing without a real terminal / stdin.

local install_state = require("cli.commands.install_state") -- shquote / path defaults
local uninstall_state = require("cli.commands.uninstall_state") -- the engine (D-09)

local M = {}

-- Resolve the cli path the SAME way the engine does (uninstall_state default_cli_path
-- lines 91-96): an explicit seam wins, else $WEZ_BIN, else ~/.local/bin/wez. This is
-- the path the front door unlinks LAST (D-10).
local function resolve_cli_path(seams)
  if seams.cli_path and seams.cli_path ~= "" then
    return seams.cli_path
  end
  local explicit = os.getenv("WEZ_BIN")
  if explicit and explicit ~= "" then
    return explicit
  end
  local home = os.getenv("HOME") or ""
  return home .. "/.local/bin/wez"
end

-- run(args [, seams]) -> numeric exit code (mirrors update.lua / uninstall_state.lua).
function M.run(args, seams)
  args = args or {}
  seams = seams or {}

  local cli_path = resolve_cli_path(seams)

  -- Interactivity probe with the FROZEN `seams.is_tty` override. PIN THE LUA 5.4
  -- IDIOM: os.execute returns `true | nil` (NOT an integer) as its FIRST value for
  -- the run-and-check form, so we compare the FIRST return against `true`
  -- (defensively also accepting 0 for parity with update.lua run_status()). Writing
  -- the probe as `os.execute("test -t 0") == 0` alone would be ALWAYS false in 5.4
  -- and trip the non-TTY gate on every run — that is the forbidden bug.
  local is_tty
  if type(seams.is_tty) == "boolean" then
    is_tty = seams.is_tty
  else
    local ok = os.execute("test -t 0")
    is_tty = (ok == true or ok == 0)
  end

  -- D-11 no-TTY gate: a non-interactive pipe WITHOUT --yes must abort and remove
  -- nothing (the engine is never called). --yes on a pipe is the intentional path.
  if not is_tty and not args.yes then
    io.stderr:write(
      "wez uninstall: refusing to remove on a non-interactive pipe without --yes\n"
        .. "wez uninstall: re-run with --yes to confirm (e.g. `wez uninstall --yes`)\n"
    )
    return 1
  end

  -- TTY confirm gate: on an interactive TTY with no --yes, print what will be removed
  -- and proceed only on an affirmative answer. The `seams.assume_yes` test seam
  -- stands in for the io.read answer when set (so the prompt path runs without stdin).
  if is_tty and not args.yes then
    io.write("wez uninstall: this removes the managed block, the wezterm-setup config tree,\n")
    io.write("wez uninstall: the wezterm.lua.bak.* backups, and the wez binary itself.\n")
    io.write("wez uninstall: proceed? [y/N] ")
    local answer
    if type(seams.assume_yes) == "boolean" then
      answer = seams.assume_yes
    else
      answer = (tostring(io.read("l") or ""):match("^[Yy]") ~= nil)
    end
    if not answer then
      io.write("wez uninstall: aborted — nothing was removed\n")
      return 1
    end
  end

  -- D-09 delegation + D-10 ordering: force keep_cli=true so the engine removes
  -- block+config+backups but NOT the binary; we unlink the binary ourselves LAST.
  local engine_args = {
    keep_config = args.keep_config,
    keep_cli = true,
    keep_backup = args.keep_backup,
  }
  local code = uninstall_state.run(engine_args, {
    config_file = seams.config_file,
    setup_dir = seams.setup_dir,
    cli_path = cli_path,
  })
  if code ~= 0 then
    -- Surface the engine's failure; do NOT proceed to unlink the binary.
    return code
  end

  -- D-10 binary self-deletion LAST: with no --keep-cli, unlink the running wez
  -- binary as the FINAL step (safe — inode persists until this process exits).
  if not args.keep_cli then
    os.remove(cli_path)
    io.write("wez uninstall: removed wez binary " .. cli_path .. " (self-delete, last step)\n")
  else
    io.write("wez uninstall: preserved wez binary (--keep-cli)\n")
  end

  return 0
end

return M
