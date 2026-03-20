local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Window chrome
config.window_decorations = "TITLE | RESIZE"
config.use_fancy_tab_bar = false
config.tab_max_width = 32

-- macOS: treat Option as Alt for keybindings, not compose
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Color profiles for tabs (name → {bg, fg})
-- These are referenced by WEZTERM_TAB_COLOR user variable
local color_profiles = {
  red    = { bg = '#5f1e1e', fg = '#f0c8c8' },
  orange = { bg = '#5f3a1e', fg = '#f0d8c8' },
  yellow = { bg = '#5f5f1e', fg = '#f0f0c8' },
  green  = { bg = '#1e5f2e', fg = '#c8f0d0' },
  teal   = { bg = '#1e4f4a', fg = '#c8f0e8' },
  cyan   = { bg = '#1e5f5f', fg = '#c8f0f0' },
  blue   = { bg = '#1e3a5f', fg = '#c8ddf0' },
  navy   = { bg = '#1a2040', fg = '#c8cce0' },
  purple = { bg = '#3f1e5f', fg = '#d8c8f0' },
  pink   = { bg = '#5f1e4a', fg = '#f0c8e0' },
}
local default_colors = { bg = '#333333', fg = '#c0c0c0' }

-- Fallback tab title from pane info
local function get_tab_title(tab)
  local title = tab.tab_title
  if title and #title > 0 then return title end
  return tab.active_pane.title
end

-- Render tab titles using per-tab user variables:
--   WEZTERM_TAB_COLOR → color profile name
--   WEZTERM_TAB_TITLE → custom label (may include emoji)
wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local user_vars = tab.active_pane.user_vars
  local color_name = user_vars.WEZTERM_TAB_COLOR
  local custom_title = user_vars.WEZTERM_TAB_TITLE

  local profile = (color_name and color_profiles[color_name]) or default_colors
  local bg = profile.bg
  local fg = profile.fg

  if tab.is_active then
    fg = '#ffffff'
  elseif hover then
    fg = '#e0e0e0'
  end

  local title = (custom_title and custom_title ~= '') and custom_title or get_tab_title(tab)
  local index = tab.tab_index + 1
  local label = tostring(index) .. ': ' .. title .. ' '
  label = wezterm.truncate_right(label, max_width - 4)

  if tab.is_active then
    return {
      { Background = { Color = bg } },
      { Foreground = { Color = '#50fa7b' } },
      { Attribute = { Intensity = 'Bold' } },
      { Text = '● ' },
      { Foreground = { Color = '#ffffff' } },
      { Text = label },
      { Attribute = { Intensity = 'Normal' } },
    }
  else
    return {
      { Background = { Color = bg } },
      { Foreground = { Color = fg } },
      { Text = '  ' .. label },
    }
  end
end)

local act = wezterm.action
config.keys = {}

-- Alt+Arrow word navigation (cross-platform)
table.insert(config.keys, { key = 'LeftArrow',  mods = 'ALT', action = act.SendKey { key = 'b', mods = 'ALT' } })
table.insert(config.keys, { key = 'RightArrow', mods = 'ALT', action = act.SendKey { key = 'f', mods = 'ALT' } })

-- Pane splitting
table.insert(config.keys, { key = '|', mods = 'ALT',        action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } })
table.insert(config.keys, { key = '-', mods = 'ALT',        action = act.SplitVertical   { domain = 'CurrentPaneDomain' } })

-- Pane management
table.insert(config.keys, { key = 'z', mods = 'CTRL|SHIFT', action = act.TogglePaneZoomState })
table.insert(config.keys, { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentPane { confirm = true } })

-- Tab cycling
table.insert(config.keys, { key = 'Tab', mods = 'CTRL',       action = act.ActivateTabRelative(1) })
table.insert(config.keys, { key = 'Tab', mods = 'CTRL|SHIFT',  action = act.ActivateTabRelative(-1) })

return config
