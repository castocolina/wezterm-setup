-- cli/commands/version.lua
--
-- The `wez version` subcommand. Exposes run(args) -> exit code.
-- The version string is read from cli/spec.lua's VERSION constant, the single
-- place the build/installer stamps, so the spec and this command never drift.

local spec = require("cli.spec")

local M = {}

-- run(args): print the version string to stdout, return 0.
-- `args` is the parsed argparse result table (unused here but part of the
-- uniform command contract: every command module exposes run(args) -> number).
function M.run(_args)
  io.write("wez " .. tostring(spec.VERSION) .. "\n")
  return 0
end

return M
