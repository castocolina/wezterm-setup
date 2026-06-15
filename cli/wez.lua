#!/usr/bin/env lua5.4
-- cli/wez.lua
--
-- The `wez` CLI entry point and dispatcher.
--
-- Responsibilities:
--   1. Load the argparse contract (cli/spec.lua) — the single source of truth.
--   2. Parse the process arg table.
--   3. Resolve the chosen subcommand against the CLOSED allow-list (spec
--      subcommand_names) — never build a require path from raw user input
--      (T-01-02: prevents path-traversal module loads).
--   4. LAZILY require the matching cli/commands/<name>.lua module. A registered
--      but not-yet-implemented module fails GRACEFULLY (clean message + non-zero,
--      never a raw Lua traceback).
--   5. Call the command's run(args) and propagate its numeric exit code (the
--      D-15 prerequisite: doctor will gate exit codes through this path).
--
-- Exposes main(argv) -> number so dispatch is unit-testable without os.exit.
-- Only calls os.exit when run as the program's main chunk.

-- Capture how this chunk was invoked. Lua passes the require KEY as the first
-- vararg to a chunk loaded via `require` (so `... == "cli.wez"` in tests), but the
-- CLI ARGS to a main chunk. This is the ONLY signal that holds across all three
-- runtimes: the dev launcher (`lua5.4 cli/wez.lua` — arg[0] ends with wez.lua),
-- the shipped luastatic single binary (arg[0] is the executable `wez`, NOT a
-- *.lua path), and `require("cli.wez")` in unit tests. The previous arg[0]
-- =~ /wez%.lua$/ heuristic silently disabled main() inside the luastatic binary,
-- so the shipped artifact ran nothing and exited 0 (the bug that made every
-- prebuilt install inert).
local INVOKED_AS = ...

-- Path bootstrap (source runs only): make `cli.*` and the vendored deps
-- requireable regardless of the invocation CWD, by anchoring on this file's
-- directory. Inside the luastatic bundle this is a no-op (modules are baked in
-- and resolve by name), so we add paths defensively without disturbing the
-- bundle's own resolution.
do
  local src = (arg and arg[0]) or ""
  local cli_dir = src:match("^(.*)/[^/]-$") -- .../cli
  if cli_dir and cli_dir ~= "" then
    local repo_root = cli_dir:match("^(.*)/cli$") or (cli_dir .. "/..")
    package.path = table.concat({
      repo_root .. "/?.lua",            -- cli.spec, cli.commands.version
      cli_dir .. "/vendor/?.lua",       -- bare argparse / dkjson fallback
      package.path,
    }, ";")
  end
end

local spec = require("cli.spec")

local M = {}

-- Build the allow-list set once per main() call.
local function command_allowset()
  local set = {}
  for _, name in ipairs(spec.subcommand_names()) do
    set[name] = true
  end
  return set
end

-- Lazily load and run a command module. Returns a numeric exit code.
-- A module that is registered in the spec but whose cli/commands/<name>.lua does
-- not yet exist (downstream-plan stub) is reported cleanly, never as a traceback.
local function dispatch(name, parsed)
  -- Resolve ONLY against the closed allow-list (defense in depth; the parser
  -- already rejects unknown commands, but never trust that alone).
  local allow = command_allowset()
  if not allow[name] then
    io.stderr:write(("wez: unknown command '%s'\n"):format(tostring(name)))
    return 2
  end

  -- Subcommand names may contain hyphens (`install-state`, `uninstall-state`),
  -- but Lua module names map `.` -> `/` and a hyphen is a legal-but-awkward file
  -- character. The command MODULES are named with underscores
  -- (cli/commands/install_state.lua) so they are clean Lua identifiers; map the
  -- hyphenated allow-listed name to its underscored module file. The mapping is
  -- a fixed transform over the already-allow-listed name (no raw user input
  -- reaches the require path — T-01-02 still holds).
  --
  -- A small fixed alias table handles the cases where the spec subcommand name is
  -- not a clean module-leaf identifier. The internal `__complete` hook (Plan 07)
  -- lives in cli/commands/complete.lua — a clean leaf — so we alias the
  -- leading-underscore spec name to it. Aliases are a closed map over the
  -- already-allow-listed name; no raw user input reaches the require path.
  local MODULE_ALIASES = {
    ["__complete"] = "complete",
  }
  local module_leaf = MODULE_ALIASES[name] or name:gsub("%-", "_")
  local module_name = "cli.commands." .. module_leaf
  local ok, mod = pcall(require, module_name)
  if not ok then
    -- Module not implemented yet (no such file) OR it raised on load.
    -- Surface a clean, actionable message — not a raw traceback.
    io.stderr:write(("wez: command '%s' is not implemented yet\n"):format(name))
    return 3
  end

  if type(mod) ~= "table" or type(mod.run) ~= "function" then
    io.stderr:write(("wez: command '%s' is malformed (no run())\n"):format(name))
    return 3
  end

  local code = mod.run(parsed)
  if type(code) ~= "number" then
    return 0
  end
  return code
end

-- main(argv) -> numeric exit code.
function M.main(argv)
  argv = argv or {}
  local parser = spec.build_parser()

  -- pparse never calls os.exit; it returns (ok, result|errmsg). This keeps the
  -- entry point testable and lets us turn parse errors into exit codes.
  local ok, parsed = parser:pparse(argv)
  if not ok then
    -- Parse error (unknown subcommand, bad flag, ...). Print usage + the error.
    io.stderr:write(parser:get_usage() .. "\n\nError: " .. tostring(parsed) .. "\n")
    return 2
  end

  -- Top-level --version short-circuits to the version command.
  if parsed.version then
    return dispatch("version", parsed)
  end

  -- No subcommand given: print usage, exit 0 (a bare `wez` is informational).
  if not parsed.command then
    io.write(parser:get_usage() .. "\n")
    return 0
  end

  return dispatch(parsed.command, parsed)
end

-- Run as a program only when invoked directly (not when required as a module).
-- When loaded via `require("cli.wez")` (unit tests), INVOKED_AS is the module
-- name and we must NOT run main; in every program-entry runtime (dev launcher,
-- luastatic binary) INVOKED_AS is a CLI arg (or nil), never the require key.
local function is_main()
  return INVOKED_AS ~= "cli.wez"
end

if is_main() then
  os.exit(M.main(arg))
end

return M
