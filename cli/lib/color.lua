-- cli/lib/color.lua
--
-- The single shared color module (D-01 / `/reducing-entropy` consolidation).
-- Owns the curated 10-name palette + muted-background map, color normalize/
-- validate, a pure-Lua base64 encoder, and the OSC 11 / OSC 1337 builders plus
-- an octal printf-payload emitter for pane-targeted send-text writes.
--
-- This module is the ONE implementation every entry point consumes (pane, tab,
-- scene, recipe render). The duplicate copies in cli/commands/pane.lua and
-- cli/commands/tab.lua are rewired to re-export from here in a later wave
-- (Plan 03 deletes the duplicates) — this plan only ADDS the shared module.
--
-- PURITY: no require("wezterm"), no io.*, no os.execute, no os.getenv. The
-- module loads under plain lua5.4 so its logic is unit-testable in isolation.
--
-- D-09 alpha behavior: #RRGGBBAA is ACCEPTED and PRESERVED — the 8th hex pair is
-- no longer stripped. validate_color accepts #rgb / #rgba / #rrggbb / #rrggbbaa.
-- Caveat (Pitfall 4): WezTerm ignores the alpha channel except for selection_fg/
-- selection_bg, so alpha only renders with window transparency; accepting it just
-- stops IDE-inserted alpha from breaking validation.
--
-- rgba() CSS-function parsing (D-09 discretion): NOT added. The committed floor
-- is #RRGGBBAA; rgba() input is rejected cleanly (false, error_string) with no
-- traceback. Adding it later is a small pure extension to validate_color.

local M = {}

-- The curated palette (D-01). Order matters for the error message + completion.
M.COLOR_NAMES = { "red", "orange", "yellow", "green", "teal", "cyan", "blue", "navy", "purple", "pink" }

-- Muted per-pane OSC-11 background hex per name (D-02, verbatim from pane.lua).
M.MUTED_BG = {
  red = "#1f1617", orange = "#1f1916", yellow = "#1c1c16", green = "#161c17",
  teal = "#151b1a", cyan = "#142127", blue = "#161a1f", navy = "#14151c",
  purple = "#1a161f", pink = "#1f1619",
}

-- Membership set for the curated names (built once).
local NAME_SET = {}
for _, n in ipairs(M.COLOR_NAMES) do NAME_SET[n] = true end

--- Pure normalization (no membership validation): lowercase; "reset" passes
-- through; hex-shaped input is lowercased with the alpha PRESERVED (D-09); named
-- input is lowercased. (strip_alpha is intentionally gone — D-09.)
function M.normalize_color(input)
  local low = tostring(input):lower()
  if low == "reset" then return "reset" end
  return low
end

-- The friendly error message listing valid inputs, including #rrggbbaa (D-09).
local function unknown_color_error(original)
  return string.format(
    'unknown color "%s" — expected one of: %s, or a hex value (#rgb / #rgba / #rrggbb / #rrggbbaa)',
    tostring(original), table.concat(M.COLOR_NAMES, ", ")
  )
end

--- Validate-before-emit gate. Returns (true, normalized) or (false, error_string).
-- Accepts the 10 curated names (case-insensitive), the literal "reset", and a hex
-- value in 3/4/6/8-digit form (D-09: alpha preserved, not stripped).
function M.validate_color(input)
  local norm = M.normalize_color(input)
  if norm == "reset" then
    return true, "reset"
  end
  if norm:sub(1, 1) == "#" then
    -- D-09: valid hex is exactly 3, 4, 6, or 8 hex digits (alpha kept).
    if norm:match("^#%x%x%x$")
      or norm:match("^#%x%x%x%x$")
      or norm:match("^#%x%x%x%x%x%x$")
      or norm:match("^#%x%x%x%x%x%x%x%x$") then
      return true, norm
    end
    return false, unknown_color_error(input)
  end
  if NAME_SET[norm] then
    return true, norm
  end
  return false, unknown_color_error(input)
end

--- OSC 11: set the pane (terminal) background color. ST-terminated.
function M.build_osc11(hex)
  return "\27]11;" .. hex .. "\27\\"
end

--- OSC 111: reset the dynamic background color to the theme default. BEL-terminated.
function M.build_reset_osc11()
  return "\27]111\7"
end

-- Pure-Lua RFC 4648 base64 (no external deps; standalone-binary constraint).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64_encode(data)
  return ((data:gsub(".", function(x)
    local r, b = "", x:byte()
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
    return r
  end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
    if #x < 6 then return "" end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
    return B64:sub(c + 1, c + 1)
  end) .. ({ "", "==", "=" })[#data % 3 + 1])
end
M._base64 = base64_encode -- exposed for tests

--- OSC 1337 SetUserVar: value is base64-encoded (neutralizes control bytes).
function M.build_osc1337(varname, value)
  return "\27]1337;SetUserVar=" .. varname .. "=" .. base64_encode(value or "") .. "\7"
end

--- Octal printf-payload form of the OSC 1337 user-var bytes: every byte rendered
-- as a `\nnn` octal escape. This is the proven cross-shell path (Pitfall 2) for
-- pane-TARGETED writes — raw OSC bytes sent via `wezterm cli send-text` are eaten
-- by the shell's line editor, so the bytes must arrive as a `printf '\nnn'`
-- payload the shell EXECUTES. Generalizes the scene.lua idiom into ONE emitter.
function M.build_user_var_octal(varname, value)
  return (M.build_osc1337(varname, value):gsub(".", function(c)
    return string.format("\\%03o", string.byte(c))
  end))
end

return M
