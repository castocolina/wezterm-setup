-- cli/lib/showkeys.lua
--
-- Parser for the textual `wezterm show-keys --lua` output (D-13).
--
-- `wezterm show-keys --lua` prints a Lua MODULE of the form:
--
--   local wezterm = require 'wezterm'
--   local act = wezterm.action
--   return {
--     keys = {
--       { key = 'k', mods = 'SUPER', action = act.ClearScrollback 'ScrollbackOnly' },
--       ...
--     },
--     key_tables = {
--       copy_mode = { ... },
--       search_mode = { ... },
--     },
--   }
--
-- We parse ONLY the top-level `keys = { ... }` array — the live "who wins"
-- effective table — into normalized `{ key, mods, action }` records. The
-- `key_tables` block (copy_mode / search_mode) is EXCLUDED (D-13): those are
-- modal bindings, not part of the global key map `wez keys` classifies.
--
-- SECURITY (T-05-01): the show-keys text is UNTRUSTED process output. We parse it
-- line-by-line with patterns and NEVER `load()`/`eval` it as Lua code. The
-- `action` is kept as an opaque verbatim STRING — we report it, we never run it.
-- Malformed record lines are skipped (and counted), never executed.

local M = {}

-- Unescape the standard Lua string escapes that appear inside the single-quoted
-- key literal: \" \' \\ . We deliberately keep this minimal — show-keys only
-- emits these for the punctuation key names.
local function unescape_key(s)
  s = s:gsub("\\(['\"\\])", "%1")
  return s
end

-- Parse `text` (the full `--lua` module) into a list of { key, mods, action }.
-- Returns: records (list), dropped (number of malformed record lines skipped).
--
-- Algorithm: scan lines. The top-level `keys = {` opens the effective array; the
-- first top-level `key_tables = {` ends it (everything after is modal and
-- excluded). Within the effective block, each `{ key = ..., mods = ..., action =
-- ... }` line yields one record.
function M.parse(text)
  local records = {}
  local dropped = 0
  if type(text) ~= "string" then
    return records, dropped
  end

  local in_keys = false

  for line in (text .. "\n"):gmatch("(.-)\n") do
    -- Enter the effective `keys` array. Match an assignment to a `keys` field
    -- that opens a table (`keys = {`), tolerating leading whitespace.
    if not in_keys and line:match("^%s*keys%s*=%s*{%s*$") then
      in_keys = true
    -- The `key_tables = {` line ends the effective array: copy_mode / search_mode
    -- live below it and are excluded (D-13).
    elseif in_keys and line:match("^%s*key_tables%s*=%s*{") then
      in_keys = false
      break
    elseif in_keys then
      -- A record line looks like:
      --   { key = 'X', mods = 'A|B', action = act.Foo ... },
      -- Extract key + mods (single-quoted literals) and the raw action tail.
      local key = line:match("key%s*=%s*'(.-)'")
      local mods = line:match("mods%s*=%s*'(.-)'")
      local action = line:match("action%s*=%s*(.-)%s*}%s*,?%s*$")
      if key and mods and action and action ~= "" then
        records[#records + 1] = {
          key = unescape_key(key),
          mods = mods,
          action = action,
        }
      elseif line:match("[%w]") and not line:match("^%s*}%s*,?%s*$") then
        -- A non-empty, non-closing line inside the keys block that did not parse
        -- as a record: count it as dropped (defensive, never fatal).
        dropped = dropped + 1
      end
    end
  end

  return records, dropped
end

-- Parse a captured no-config baseline (produced via `wezterm -n show-keys --lua`)
-- with the IDENTICAL scanner, so default-detection compares like with like (D-14).
function M.parse_baseline(text)
  return (M.parse(text))
end

return M
