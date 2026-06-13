-- wezterm-setup :: entry point
--
-- The AUGMENT entry point (D-17 / INST-01). The installer's sentinel block in
-- the user's wezterm.lua calls:
--
--     require('wezterm-setup').apply(config)
--
-- right before the user's `return config`. `apply` MUTATES the passed config
-- object (adds our keys, key_map_preference, disabled defaults, and cwd
-- behavior) and RETURNS the same object. It never constructs or overwrites a
-- fresh config -- user settings survive, ours add on top.
--
-- Why a parameter and not a named global: the user's config variable name
-- varies (`config`, `cfg`, ...). Taking it as the `apply(config)` argument and
-- mutating by reference sidesteps the name entirely.
-- See .tmp/probes/phase-1/03-config-var-name.md (verdict: holds).
--
-- R3 composable: this entry point requires one topic module per behavior
-- (keybindings, cwd) and merges their contributions into the user's config.
--
-- The module resolves under WezTerm (the `wezterm` global is present) for real
-- use, and is import-safe under plain lua5.4 for unit testing -- action
-- resolution is guarded so the absence of `wezterm` does not error.

local M = {}

-- Resolve our sibling modules (keybindings/cwd/format-tab-title) with DOTTED
-- module names so they load under every loader WITHOUT mutating package.path.
--
-- Why not bare `require("keybindings")`: under WezTerm only the config DIR
-- (~/.config/wezterm/) is on package.path, so a bare name resolves against the
-- config ROOT, not this `wezterm-setup/` subdir -> `module 'keybindings' not
-- found`, apply() throws, and WezTerm pops a config-error window beside the main
-- one (the original two-windows bug).
--
-- Why not derive our own dir via `debug.getinfo`: WezTerm's embedded Lua sandbox
-- does NOT expose the `debug` library (`debug` is nil), so that approach errors
-- at load with `attempt to index a nil value (global 'debug')`.
--
-- Dotted names sidestep both: `require("wezterm-setup.keybindings")` resolves to
-- `<config-dir>/wezterm-setup/keybindings.lua` via WezTerm's existing
-- `<config-dir>/?.lua` template -- no `debug`, no `wezterm` global, no
-- package.path mutation. The unit tests put the config ROOT (`config/`) on
-- package.path so the same dotted names resolve there too. (luastatic bundles
-- only cli/, never config/, so this layer always loads as plain files at runtime.)
local keybindings = require("wezterm-setup.keybindings")
local cwd = require("wezterm-setup.cwd")
local format_tab_title = require("wezterm-setup.format-tab-title")

-- Resolve our declarative action spec (from keybindings.lua) into a real
-- wezterm.action. Pure data in -> wezterm action out. When the `wezterm`
-- global is unavailable (unit tests under plain lua5.4) we keep the spec table
-- as-is so the key entry still carries shape for assertions.
local function resolve_action(wezterm, spec)
  if not (wezterm and wezterm.action) then
    return spec -- test environment: leave the declarative spec in place
  end
  local act = wezterm.action
  local t = spec.type
  if t == "ClearScreenAndScrollback" then
    return act.ClearScrollback("ScrollbackAndViewport")
  elseif t == "SpawnTab" then
    return act.SpawnTab(spec.arg)
  elseif t == "CloseCurrentTab" then
    return act.CloseCurrentTab({ confirm = spec.confirm and true or false })
  elseif t == "ActivateTabRelative" then
    return act.ActivateTabRelative(spec.arg)
  elseif t == "MoveTabRelative" then
    return act.MoveTabRelative(spec.arg)
  elseif t == "SplitHorizontal" then
    return act.SplitHorizontal({ domain = spec.arg })
  elseif t == "SplitVertical" then
    return act.SplitVertical({ domain = spec.arg })
  elseif t == "CloseCurrentPane" then
    return act.CloseCurrentPane({ confirm = spec.confirm and true or false })
  elseif t == "TogglePaneZoomState" then
    return act.TogglePaneZoomState
  elseif t == "ActivatePaneDirection" then
    return act.ActivatePaneDirection(spec.arg)
  elseif t == "IncreaseFontSize" then
    return act.IncreaseFontSize
  elseif t == "DecreaseFontSize" then
    return act.DecreaseFontSize
  elseif t == "ResetFontSize" then
    return act.ResetFontSize
  elseif t == "SendString" then
    return act.SendString(spec.arg)
  end
  -- Unknown spec: surface loudly rather than silently dropping a binding.
  error("wezterm-setup: unknown action spec type '" .. tostring(t) .. "'")
end

--- Augment the user's config with the wezterm-setup behavior set.
-- Mutates and returns the SAME `config` table (D-17, never replaces it).
-- @param config table  the user's WezTerm config object (any variable name)
-- @return table        the same config object, now augmented
function M.apply(config)
  assert(type(config) == "table", "wezterm-setup.apply: expected a config table")

  -- `wezterm` may be absent under unit tests; require defensively.
  local ok, wezterm = pcall(require, "wezterm")
  if not ok then
    wezterm = nil
  end

  -- 1. Key match preference: fire on the produced character (D-09).
  config.key_map_preference = keybindings.key_map_preference

  -- 2. Merge our key bindings WITHOUT discarding any user-defined ones (D-17 /
  --    T-03-01): append to the existing list rather than reassigning it.
  config.keys = config.keys or {}
  for _, b in ipairs(keybindings.keys) do
    table.insert(config.keys, {
      key = b.key,
      mods = b.mods,
      action = resolve_action(wezterm, b.action),
    })
  end

  -- 3. Explicitly disable each replaced WezTerm default (D-12) so exactly one
  --    binding maps to each action and `wez keys` stays truthful. Represented
  --    as key entries with a DisableDefaultAssignment action.
  local disable_action = (wezterm and wezterm.action)
      and wezterm.action.DisableDefaultAssignment
      or { type = "DisableDefaultAssignment" }
  for _, d in ipairs(keybindings.disabled_defaults) do
    table.insert(config.keys, {
      key = d.key,
      mods = d.mods,
      action = disable_action,
    })
  end

  -- 4. Apply cwd behavior (no-op augment; inheritance is WezTerm default).
  cwd.apply(config)

  -- 5. Register the tab-bar renderer that surfaces pane/tab identity
  --    (format-tab-title event reads WEZTERM_TAB_COLOR / WEZTERM_TAB_TITLE
  --    user vars set by `wez pane color`/`title`). AUGMENT (D-17).
  format_tab_title.apply(config)

  -- Return the SAME object we received (augment, never replace).
  return config
end

return M
