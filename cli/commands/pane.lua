-- cli/commands/pane.lua
--
-- The `wez pane` subcommand surface (Phase 2: Pane Identity).
--   wez pane color <name|hex|rgba>   set the pane background + tab-bar accent
--   wez pane color reset             restore the default background + clear accent
--   (wez pane title ...              added by plan 02-04)
--
-- Color model (D-01): a curated 10-name palette OR a hex value (#rgb / #rgba /
-- #rrggbb / #rrggbbaa). Input is normalized (lowercase, optional `#`, alpha
-- PRESERVED per D-09) and VALIDATED BEFORE any escape byte is emitted — an unknown
-- color exits non-zero with NO OSC written (no half-applied state).
--
-- Rendering is a dual write (D-02), because each pane is its own terminal:
--   OSC 11   -> the real per-pane background tint (a muted variant of the color)
--   OSC 1337 SetUserVar=WEZTERM_TAB_COLOR -> the tab-bar accent, read by the
--            config-layer format-tab-title handler (plan 02-02).
-- There is NO `wezterm cli set-user-var`; the OSC escape is the only path.
--
-- D-01 / `/reducing-entropy`: the palette, normalize/validate, base64 and the OSC
-- 11 / OSC 1337 builders are NO LONGER defined here — they live ONCE in
-- cli/lib/color.lua and are re-exported below so the public surface (M.COLOR_NAMES,
-- M.MUTED_BG, M.normalize_color, M.validate_color, M.build_osc11, M.build_osc1337,
-- M._base64) is unchanged for existing callers.
--
-- Opacity (D-03/D-06/D-09): per the 02-01 spike, WezTerm has no per-pane opacity,
-- and (Pitfall 4) it ignores the alpha channel except for selection_fg/bg, so alpha
-- renders only with window transparency. D-09: the 8th hex pair is NO LONGER
-- stripped — it flows through verbatim; the --opacity path just warns once that
-- transparency depends on the window, then renders. OS-window opacity is never used
-- (it would dim siblings).
--
-- D-05 target/sink seam: the pure build_* functions construct escape strings and
-- take no I/O; M.run is the ONLY function that writes. A future `--pane-id` sink
-- (Phase 4 scenes) reuses the builders with a different write target.

local M = {}

-- The single shared color module (D-01). Owns the palette, MUTED_BG, normalize/
-- validate (alpha-preserving, D-09), base64, and the OSC 11 / OSC 1337 builders.
local color = require("cli.lib.color")

-- Icon-name title resolution now lives in the shared cli/lib/title.lua (D-03),
-- consumed by both `wez pane title` and `wez tab title`.
local title = require("cli.lib.title")

-- Public surface re-exported from the shared module (no local re-definition, D-01).
M.COLOR_NAMES = color.COLOR_NAMES
M.MUTED_BG = color.MUTED_BG
M.normalize_color = color.normalize_color
M.validate_color = color.validate_color
M.build_osc11 = color.build_osc11
M.build_reset_osc11 = color.build_reset_osc11
M.build_osc1337 = color.build_osc1337
M._base64 = color._base64 -- exposed for tests

-- Per the 02-01 opacity spike (verdict NO): WezTerm has no per-pane opacity, and
-- WezTerm ignores the alpha channel except for selection (Pitfall 4). D-09: alpha
-- is accepted + preserved; the pane still renders solid unless the window itself is
-- transparent, so a one-time caveat is warned (soft-degrade, exit 0).
M.OPACITY_SUPPORTED = false

-- The single write sink (D-05): all stdout escape emission goes through here so
-- a future --pane-id sink can swap the target without touching the builders.
local function emit(str)
  io.write(str)
end

local OPACITY_WARNING =
  "warning: per-pane opacity is not supported by your WezTerm version — alpha renders only with window transparency\n"

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
    -- D-09: alpha is PRESERVED in the emitted hex, but WezTerm renders it only with
    -- window transparency (Pitfall 4). Warn once that the pane stays solid otherwise.
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
