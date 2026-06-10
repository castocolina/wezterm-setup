-- cli/commands/complete.lua
--
-- The HIDDEN `wez __complete <context>` subcommand (D-16). The subcommand is
-- ALREADY registered in cli/spec.lua by Plan 01 (marked `_hidden`) — this module
-- ONLY implements the behavior; it does NOT edit the spec.
--
-- Purpose: the generated zsh/bash completion scripts (cli/commands/completions.lua)
-- never hardcode dynamic candidate lists. Instead, for any value that is computed
-- at completion time, the shell function shells out to `wez __complete <context>`
-- and consumes the newline-separated tokens it prints. This is the single
-- extension point for future phases: teaching `__complete` a NEW context (e.g.
-- `colors`, `scene-names`) makes that completion work WITHOUT regenerating or
-- editing the static completion scripts.
--
-- Phase 1 contexts are minimal but the dispatch structure is established:
--   subcommands  -> the visible (non-hidden) top-level subcommand names from spec
--
-- Security (T-07-02): candidates are PLAIN tokens drawn from the closed spec set;
-- this module emits no shell metacharacters, so the shell treats the output as
-- data during Tab expansion, never as code. Unknown contexts emit nothing and
-- still exit 0 — the hook must never become an error surface mid-expansion.

local spec = require("cli.spec")

local M = {}

-- Hidden / internal subcommands that must NOT be advertised as user-facing
-- completion candidates. `__complete` itself is the obvious one.
local HIDDEN = {
  ["__complete"] = true,
}

-- Return the list of visible (non-hidden) subcommand names from the spec. This is
-- the SAME closed set the dispatcher allow-lists, minus the internal hooks — so
-- the candidates are always in sync with the real command tree (D-16).
local function visible_subcommands()
  local out = {}
  for _, n in ipairs(spec.subcommand_names()) do
    if not HIDDEN[n] then out[#out + 1] = n end
  end
  return out
end

-- The closed context dispatch. Each entry returns a list of candidate tokens.
-- Future phases add entries here (colors, scene names, ...) without touching the
-- generated shell scripts.
local CONTEXTS = {
  subcommands = visible_subcommands,
}

-- run(args): print newline-separated candidates for args.context. Unknown context
-- prints nothing. Always returns 0 (a Tab-time hook must not fail the shell).
function M.run(args)
  args = args or {}
  local context = args.context
  if type(context) ~= "string" or context == "" then
    -- No context: nothing to complete. Clean no-op.
    return 0
  end

  local provider = CONTEXTS[context]
  if not provider then
    -- Unknown context: emit nothing, exit clean (closed dispatch).
    return 0
  end

  for _, token in ipairs(provider()) do
    -- Emit plain tokens only (T-07-02). spec names are a closed set of
    -- [%w_-] identifiers, so no quoting/escaping is required; we still avoid
    -- printing anything but the bare token + newline.
    io.write(tostring(token))
    io.write("\n")
  end
  return 0
end

return M
