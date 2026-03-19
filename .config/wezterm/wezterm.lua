local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Window chrome
config.window_decorations = "TITLE | RESIZE"
config.use_fancy_tab_bar = false

-- Color profiles for tabs (name → {bg, fg})
-- These are referenced by WEZTERM_TAB_COLOR user variable
local color_profiles = {
  blue   = { bg = '#1e3a5f', fg = '#c8ddf0' },
  red    = { bg = '#5f1e1e', fg = '#f0c8c8' },
  green  = { bg = '#1e5f2e', fg = '#c8f0d0' },
  yellow = { bg = '#5f5f1e', fg = '#f0f0c8' },
  purple = { bg = '#3f1e5f', fg = '#d8c8f0' },
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
  local formatted = ' ' .. tostring(index) .. ': ' .. title .. ' '
  formatted = wezterm.truncate_right(formatted, max_width - 2)

  return {
    { Background = { Color = bg } },
    { Foreground = { Color = fg } },
    { Text = formatted },
  }
end)

-- Helper: spawn a new tab that sets WEZTERM_TAB_COLOR via OSC 1337
-- The escape sequence is processed by WezTerm's terminal emulator,
-- then the shell starts via exec $SHELL.
local function spawn_color_tab(color)
  return wezterm.action.SpawnCommandInNewTab {
    args = {
      'bash', '-c',
      string.format(
        'printf "\\033]1337;SetUserVar=%%s=%%s\\007" WEZTERM_TAB_COLOR '
        .. '"$(echo -n %s | base64)" && exec "$SHELL"',
        color
      ),
    },
  }
end

-- Ctrl+Shift+1..5 → spawn tab with color
local color_order = { 'blue', 'red', 'green', 'yellow', 'purple' }
config.keys = {}
for i, color in ipairs(color_order) do
  table.insert(config.keys, {
    key = tostring(i),
    mods = 'CTRL|SHIFT',
    action = spawn_color_tab(color),
  })
end

return config
