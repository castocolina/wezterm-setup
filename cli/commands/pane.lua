-- cli/commands/pane.lua
--
-- The `wez pane` subcommand surface (Phase 2: Pane Identity).
--   wez pane color <name|hex|rgba>   set the pane background + tab-bar accent
--   wez pane color reset             restore the default background + clear accent
--   (wez pane title ...              added by plan 02-04)
--
-- Color model (D-01): a curated 10-name palette OR a hex value (#rgb / #rrggbb /
-- #rrggbbaa). Input is normalized (lowercase, optional `#`, alpha stripped) and
-- VALIDATED BEFORE any escape byte is emitted — an unknown color exits non-zero
-- with NO OSC written (no half-applied state).
--
-- Rendering is a dual write (D-02), because each pane is its own terminal:
--   OSC 11   -> the real per-pane background tint (a muted variant of the color)
--   OSC 1337 SetUserVar=WEZTERM_TAB_COLOR -> the tab-bar accent, read by the
--            config-layer format-tab-title handler (plan 02-02).
-- There is NO `wezterm cli set-user-var`; the OSC escape is the only path.
--
-- Opacity (D-03/D-06): per the 02-01 spike, WezTerm has no per-pane opacity, so
-- M.OPACITY_SUPPORTED is false: alpha is stripped, the pane renders solid, and a
-- one-time warning is printed (soft-degrade, exit 0). OS-window opacity is never
-- used (it would dim siblings).
--
-- D-05 target/sink seam: the pure build_* functions construct escape strings and
-- take no I/O; M.run is the ONLY function that writes. A future `--pane-id` sink
-- (Phase 4 scenes) reuses the builders with a different write target.

local M = {}

-- Icon-name title resolution now lives in the shared cli/lib/title.lua (D-03),
-- consumed by both `wez pane title` and `wez tab title`.
local title = require("cli.lib.title")

-- The curated palette (D-01). Order matters for the error message + completion.
M.COLOR_NAMES = { "red", "orange", "yellow", "green", "teal", "cyan", "blue", "navy", "purple", "pink" }

-- Muted per-pane OSC-11 background hex per name (D-02, verbatim from CONTEXT).
M.MUTED_BG = {
  red = "#1f1617", orange = "#1f1916", yellow = "#1c1c16", green = "#161c17",
  teal = "#151b1a", cyan = "#161c1c", blue = "#161a1f", navy = "#14151c",
  purple = "#1a161f", pink = "#1f1619",
}

-- Per the 02-01 opacity spike (verdict NO): WezTerm has no per-pane opacity.
-- Accept opacity input but strip alpha + render solid + warn once.
M.OPACITY_SUPPORTED = false

-- Membership set for the curated names (built once).
local NAME_SET = {}
for _, n in ipairs(M.COLOR_NAMES) do NAME_SET[n] = true end

--- Strip the alpha component from a 4- or 8-digit hex; 3/6-digit pass through.
function M.strip_alpha(hex)
  local digits = hex:match("^#(%x+)$")
  if not digits then return hex end
  if #digits == 8 then return "#" .. digits:sub(1, 6) end
  if #digits == 4 then return "#" .. digits:sub(1, 3) end
  return hex
end

--- Pure normalization (no validation of membership): lowercase; "reset" passes
-- through; hex-shaped input has its alpha stripped; named input is lowercased.
function M.normalize_color(input)
  local low = tostring(input):lower()
  if low == "reset" then return "reset" end
  if low:match("^#%x+$") then
    return M.strip_alpha(low)
  end
  return low
end

-- The friendly error message listing valid inputs.
local function unknown_color_error(original)
  return string.format(
    'unknown color "%s" — expected one of: %s, or a hex value (#rgb / #rrggbb / #rrggbbaa)',
    tostring(original), table.concat(M.COLOR_NAMES, ", ")
  )
end

--- Validate-before-emit gate. Returns (true, normalized) or (false, error_string).
function M.validate_color(input)
  local norm = M.normalize_color(input)
  if norm == "reset" then
    return true, "reset"
  end
  if norm:sub(1, 1) == "#" then
    -- After alpha-strip a valid solid hex is exactly 3 or 6 digits.
    if norm:match("^#%x%x%x$") or norm:match("^#%x%x%x%x%x%x$") then
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

-- The single write sink (D-05): all stdout escape emission goes through here so
-- a future --pane-id sink can swap the target without touching the builders.
local function emit(str)
  io.write(str)
end

local OPACITY_WARNING =
  "warning: per-pane opacity is not supported by your WezTerm version — color applied without transparency\n"

--- Handle `wez pane color <value> [--opacity]` / `wez pane color reset`.
-- Returns the process exit code.
function M.run_color(args)
  local ok, normalized = M.validate_color(args.value)
  if not ok then
    io.stderr:write("wez pane color: " .. normalized .. "\n")
    return 2
  end

  if normalized == "reset" then
    emit(M.build_reset_osc11() .. M.build_osc1337("WEZTERM_TAB_COLOR", ""))
    return 0
  end

  -- Resolve the OSC-11 background hex: curated name -> its muted hex; raw hex ->
  -- the hex itself. The WEZTERM_TAB_COLOR accent value is the name (or hex),
  -- which 02-02's format-tab-title resolves against its own profile table.
  local bg_hex = M.MUTED_BG[normalized] or normalized

  if args.opacity and not M.OPACITY_SUPPORTED then
    -- Alpha was already stripped by normalize_color; nothing to apply. Warn once.
    io.stderr:write(OPACITY_WARNING)
  end

  emit(M.build_osc11(bg_hex) .. M.build_osc1337("WEZTERM_TAB_COLOR", normalized))
  return 0
end

-- Icon map + title resolver re-exported from the shared lib (D-03) so the pane
-- public surface (M.ICONS / M.resolve_title) and M.run_title are unchanged while
-- the single source of truth lives in cli/lib/title.lua.
M.ICONS = title.ICONS
M.resolve_title = title.resolve_title

--- Handle `wez pane title <words...>` / `wez pane title reset`.
function M.run_title(args)
  local title = M.resolve_title(args.words)
  emit(M.build_osc1337("WEZTERM_TAB_TITLE", title))
  return 0
end

--- Command entry. Branches on the selected `pane` subcommand.
function M.run(args)
  local sub = args and args.pane_cmd
  if sub == "color" then
    return M.run_color(args)
  elseif sub == "title" then
    return M.run_title(args)
  end
  io.stderr:write("wez pane: expected a subcommand (color | title)\n")
  return 2
end

return M
