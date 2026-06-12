-- wezterm-setup :: format-tab-title
--
-- The config-layer renderer for pane/tab identity (Phase 2). Holds the tab-bar
-- color-profile table and registers the `format-tab-title` event handler that
-- reads the focused pane's user vars:
--   WEZTERM_TAB_COLOR -> accent profile name (or raw hex) for the tab-bar segment
--   WEZTERM_TAB_TITLE -> custom title shown while that pane is focused
--
-- The `wez pane color`/`title` CLI (plans 02-03/02-04) emits those user vars via
-- OSC 1337 SetUserVar; this module is their consumer. Pane user vars override the
-- tab's own title (D-02 priority).
--
-- Pure helpers (resolve_profile / format_label / build_runs) take no dependency
-- on the `wezterm` global so they are unit-testable under plain lua5.4. M.apply
-- follows the AUGMENT contract (D-17): it registers the event and returns the
-- same config table, guarded so the absence of `wezterm` (unit tests) is safe.

local M = {}

-- Tab-bar accent pairs (background/foreground) per named profile. Ported verbatim
-- from the proven prototype (02-CONTEXT.md <code_context>).
M.color_profiles = {
  red    = { bg = "#5f1e1e", fg = "#f0c8c8" },
  orange = { bg = "#5f3a1e", fg = "#f0d8c8" },
  yellow = { bg = "#5f5f1e", fg = "#f0f0c8" },
  green  = { bg = "#1e5f2e", fg = "#c8f0d0" },
  teal   = { bg = "#1e4f4a", fg = "#c8f0e8" },
  cyan   = { bg = "#1e5f5f", fg = "#c8f0f0" },
  blue   = { bg = "#1e3a5f", fg = "#c8ddf0" },
  navy   = { bg = "#1a2040", fg = "#c8cce0" },
  purple = { bg = "#3f1e5f", fg = "#d8c8f0" },
  pink   = { bg = "#5f1e4a", fg = "#f0c8e0" },
}

M.DEFAULT_PROFILE = { bg = "#333333", fg = "#c0c0c0" }

--- Resolve a WEZTERM_TAB_COLOR value to a {bg,fg} accent pair.
-- nil/empty/unknown -> default; named profile -> its pair (case-insensitive);
-- raw hex (#rgb / #rrggbb, alpha already stripped upstream) -> {bg=hex, default fg}.
function M.resolve_profile(color_name)
  if not color_name or color_name == "" then
    return M.DEFAULT_PROFILE
  end
  local key = color_name:lower()
  local profile = M.color_profiles[key]
  if profile then
    return profile
  end
  if key:match("^#%x%x%x$") or key:match("^#%x%x%x%x%x%x$") then
    return { bg = key, fg = M.DEFAULT_PROFILE.fg }
  end
  return M.DEFAULT_PROFILE
end

--- Parse a stored `tab.tab_title` of the form "<color>:<title>" into (color, title).
-- Locked encoding (tab-title-format.md): split on the FIRST ":". Left is the color
-- (may be empty -> nil), right is the title (may be empty -> nil, may itself contain
-- ":"). A no-colon NON-EMPTY token is the color name with no title (bare-token-is-a-
-- color rule); resolve_profile maps an unknown color to the default downstream.
-- Pure: no `wezterm` dependency, unit-testable under plain lua5.4.
-- INVARIANT: this logic MUST stay in lockstep with the CLI-side parser
-- `M.parse_stored` in cli/commands/tab.lua (separate Lua bundle, same encoding) —
-- change both together.
function M.parse_tab_title(tab_title)
  if not tab_title or tab_title == "" then
    return nil, nil
  end
  local pos = tab_title:find(":", 1, true)
  if not pos then
    return tab_title, nil
  end
  local color = tab_title:sub(1, pos - 1)
  local title = tab_title:sub(pos + 1)
  if color == "" then color = nil end
  if title == "" then title = nil end
  return color, title
end

--- Build the tab label string: "<n>: <title> ", 1-based index, right-truncated
-- to max_width-4 (byte-based fallback; the live handler additionally applies
-- wezterm.truncate_right for proper column width).
function M.format_label(index, title, max_width)
  local label = tostring((index or 0) + 1) .. ": " .. (title or "") .. " "
  local limit = (max_width or 0) - 4
  if limit > 0 and #label > limit then
    label = label:sub(1, limit)
  end
  return label
end

--- Build the WezTerm format-runs table for a tab segment.
-- Active: profile bg, green indicator, bold, white label.
-- Inactive: profile bg + profile fg, no indicator.
function M.build_runs(is_active, profile, label)
  if is_active then
    return {
      { Background = { Color = profile.bg } },
      { Foreground = { Color = "#50fa7b" } },
      { Attribute = { Intensity = "Bold" } },
      { Text = " ●-> " },
      { Foreground = { Color = "#ffffff" } },
      { Text = label },
      { Attribute = { Intensity = "Normal" } },
    }
  end
  return {
    { Background = { Color = profile.bg } },
    { Foreground = { Color = profile.fg } },
    { Text = "  " .. label },
  }
end

--- Augment the user's config by registering the format-tab-title handler.
-- AUGMENT contract (D-17): mutate nothing on `config`, return the same table.
-- Import-safe: if `wezterm` is unavailable (unit tests), no-op and return config.
function M.apply(config)
  local ok, wezterm = pcall(require, "wezterm")
  if not ok or not wezterm then
    return config
  end

  wezterm.on("format-tab-title", function(tab, _tabs, _panes, _cfg, _hover, max_width)
    local uv = (tab.active_pane and tab.active_pane.user_vars) or {}
    local tabColor, tabTitle = M.parse_tab_title(tab.tab_title)

    -- accent: pane WEZTERM_TAB_COLOR > tab-prefix color > default (TAB-04)
    local accent_color = (uv.WEZTERM_TAB_COLOR ~= "" and uv.WEZTERM_TAB_COLOR) or tabColor
    local profile = M.resolve_profile(accent_color)

    -- title: pane WEZTERM_TAB_TITLE > tab-prefix title > active_pane.title > ""
    local title = uv.WEZTERM_TAB_TITLE
    if not title or title == "" then
      title = tabTitle
      if not title or title == "" then
        title = tab.active_pane and tab.active_pane.title or ""
      end
    end

    local label = M.format_label(tab.tab_index, title, max_width)
    label = wezterm.truncate_right(label, math.max(1, (max_width or 8) - 4))
    return M.build_runs(tab.is_active, profile, label)
  end)

  return config
end

return M
