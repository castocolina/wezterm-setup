-- cli/lib/shell.lua
--
-- The SINGLE shared home for two security-sensitive helpers that were previously
-- duplicated in cli/commands/tab.lua and cli/commands/scene.lua (IN-02):
--   * shquote      — the single-quote shell escaper applied to EVERY user-derived
--                    string before os.execute / io.popen. Keeping ONE copy means
--                    the one escaping rule cannot diverge between call sites (a
--                    divergence on either path could open a command injection).
--   * decode_json  — the vendored-dkjson decode wrapper, dual-resolving from source
--                    (CWD on package.path) and inside the luastatic bundle.
--
-- PURE BY CONTRACT: no io.*, no os.execute, no os.getenv, no wezterm global. Both
-- helpers are pure-ish string transforms; decode_json only `require`s the vendored
-- decoder (the same allowed dependency-resolution idiom color.lua / scene.lua use).
-- The actual io.popen / os.execute calls that CONSUME these stay in the command
-- modules' I/O sinks — this module never performs I/O itself.

local M = {}

-- Single-quote shell escaper: a single quote is rewritten as '\'' so a value
-- containing a quote or any shell metacharacter cannot break out of the quoting
-- and inject a command. The ONE proven copy (same logic as install_state.shquote,
-- CR-02) — every user-derived os.execute/io.popen argument flows through this.
function M.shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Decode JSON with the vendored dkjson, resolving both from source (CWD on
-- package.path) and inside the luastatic bundle (module baked as cli.vendor.dkjson).
-- Returns the decoded value, or nil when the decoder is unavailable.
function M.decode_json(text)
  local ok, dkjson = pcall(require, "cli.vendor.dkjson")
  if not ok then ok, dkjson = pcall(require, "dkjson") end
  if not ok or type(dkjson) ~= "table" then return nil end
  return dkjson.decode(text)
end

return M
