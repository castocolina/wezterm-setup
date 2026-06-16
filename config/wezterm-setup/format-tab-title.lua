-- wezterm-setup :: format-tab-title
--
-- The config-layer renderer for pane/tab identity (Phase 2 / 6.2). Holds the tab-bar
-- color-profile table and registers the `format-tab-title` event handler that
-- reads the focused pane's user vars:
--   WEZTERM_TAB_COLOR       -> the tab's own accent (name or raw hex) — wins (D-08 step 1)
--   WEZTERM_PANE_COLOR      -> the active pane's accent, used only when following (D-07/D-08 step 2)
--   WEZTERM_TAB_FOLLOW_PANE -> "1" opts the tab into following the pane's accent (D-09, default OFF)
--   WEZTERM_TAB_ICON        -> glyph composed left of the title (one carrier, tab+pane, D-01/D-04)
--   WEZTERM_TAB_TITLE       -> custom title shown while that pane is focused (literal, D-05/D-06)
--
-- The `wez tab`/`pane` CLI emits those user vars via OSC 1337 SetUserVar; this module
-- is their consumer. Pane user vars override the tab's own title (D-02 priority). An
-- empty title self-labels by the launch-dir basename (D-11/D-13).
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
-- raw hex (#rgb / #rrggbb / #rrggbbaa) -> {bg=hex, default fg}.
-- D-09: an 8-digit #RRGGBBAA accent is ACCEPTED (alpha no longer stripped upstream)
-- so an IDE-inserted alpha never falls back to the default profile. Caveat (Pitfall 4):
-- WezTerm ignores the alpha channel except for selection_fg/selection_bg — the 8th hex
-- digit only RENDERS with window transparency; it is accepted/stored, not promised to paint.
-- A non-matching value (malformed/over-long hex, unknown name) falls back to the default
-- profile (T-06.1-12 tamper safety: only a name or a well-formed hex is honored).
function M.resolve_profile(color_name)
  if not color_name or color_name == "" then
    return M.DEFAULT_PROFILE
  end
  local key = color_name:lower()
  local profile = M.color_profiles[key]
  if profile then
    return profile
  end
  if key:match("^#%x%x%x$")
      or key:match("^#%x%x%x%x%x%x$")
      or key:match("^#%x%x%x%x%x%x%x%x$") then
    return { bg = key, fg = M.DEFAULT_PROFILE.fg }
  end
  return M.DEFAULT_PROFILE
end

--- Resolve the tab-bar accent from the active pane user vars by the D-08 three-step
-- precedence (pure; takes the user_vars table, returns a {bg,fg} via resolve_profile):
--   (1) the tab's OWN WEZTERM_TAB_COLOR, if non-empty, ALWAYS wins (D-08 step 1);
--   (2) else if WEZTERM_TAB_FOLLOW_PANE == "1" (the LOCKED opt-in carrier, W3) and the
--       active pane's WEZTERM_PANE_COLOR is non-empty, follow that pane accent (D-08 step 2);
--   (3) else neutral M.DEFAULT_PROFILE (D-08 step 3 / D-10 = WezTerm default, no sticky state).
-- D-09: follow-pane is OPT-IN — only the exact value "1" turns it ON; unset/empty/any
-- other value is OFF, so a pane color alone never bleeds into the tab. resolve_profile
-- (unchanged) keeps the malformed/over-long tamper fallback (T-06.2-06).
function M.resolve_accent(uv)
  uv = uv or {}
  local tab_color = uv.WEZTERM_TAB_COLOR
  if tab_color and tab_color ~= "" then
    return M.resolve_profile(tab_color)
  end
  local pane_color = uv.WEZTERM_PANE_COLOR
  if uv.WEZTERM_TAB_FOLLOW_PANE == "1" and pane_color and pane_color ~= "" then
    return M.resolve_profile(pane_color)
  end
  return M.DEFAULT_PROFILE
end

-- D-05/D-06: the legacy `<color>:<title>` parse_tab_title was REMOVED here. With the
-- icon as its own carrier (WEZTERM_TAB_ICON, D-01) and the accent on its own user var
-- (WEZTERM_TAB_COLOR / WEZTERM_PANE_COLOR, D-07), a stored title needs no prefix split:
-- a colon now carries no special meaning and a legacy "cyan:api" renders verbatim
-- (no doctor gate, no migration tracking — CONTEXT D-06).

--- Basename of a path string (last non-empty segment). Pure; trailing slashes
-- ignored. "/" -> "/", "" -> "/", nil -> "/".
-- INVARIANT (deliberate standalone-bundle duplicate): this is the SAME logic as
-- `M.basename` in cli/lib/title.lua:68-73. format-tab-title.lua loads inside WezTerm's
-- Lua (NOT the luastatic CLI bundle) and has no `cli/lib` require, so the helper is
-- duplicated here on purpose (the one justified reuse exception, per 06.2-PATTERNS.md).
-- Keep both copies in lockstep — change them together.
function M.basename(path)
  local stripped = tostring(path or ""):gsub("/+$", "")
  local base = stripped:match("[^/]+$") or stripped
  if base == "" then base = "/" end
  return base
end

--- Compose the displayed label text: icon left of the (literal) title, single space
-- between (D-04). Empty/nil icon -> title only. Empty/nil title with an icon -> icon
-- only (no trailing space). Empty both -> "". Pure, unit-testable under plain lua5.4.
function M.compose_label_text(icon, title)
  icon = icon or ""
  title = title or ""
  if icon == "" then
    return title
  end
  if title == "" then
    return icon
  end
  return icon .. " " .. title
end

--- Resolve the displayed text with the empty-title cwd fallback (D-11/D-13). A
-- non-empty title wins (D-11). An empty title falls back to the launch-dir basename;
-- with an icon present this yields "icon basename", icon-only fallback otherwise (D-13).
-- Pure: launch_dir is supplied by the caller (the handler sources it from the active
-- pane cwd / title). No `wezterm` dependency.
function M.title_with_fallback(title, icon, launch_dir)
  title = title or ""
  if title ~= "" then
    return M.compose_label_text(icon, title)
  end
  return M.compose_label_text(icon, M.basename(launch_dir))
end

--- Build the tab label string: "<n>: <title> ", 1-based index, right-truncated
-- to max_width-4 on a CODEPOINT boundary (the live handler additionally applies
-- wezterm.truncate_right for proper column width).
-- WR-03: the label now routinely begins with a multibyte icon glyph (D-04 composes
-- `icon .. " " .. title`). A byte-based `label:sub(1, limit)` could cut INSIDE a
-- UTF-8 sequence, emitting a bare continuation byte. Truncate on a codepoint
-- boundary via utf8.offset so a narrow tab never splits a glyph. The byte length
-- is still the fallback guard for any value utf8.len cannot measure (invalid UTF-8).
function M.format_label(index, title, max_width)
  local label = tostring((index or 0) + 1) .. ": " .. (title or "") .. " "
  local limit = (max_width or 0) - 4
  if limit > 0 then
    local cp_len = utf8.len(label)
    if cp_len and cp_len > limit then
      -- Cut just before the (limit+1)-th codepoint; offset returns the byte index
      -- of that codepoint's first byte, so sub(1, offset-1) keeps `limit` glyphs.
      local cut = utf8.offset(label, limit + 1)
      label = cut and label:sub(1, cut - 1) or label
    elseif not cp_len and #label > limit then
      -- Invalid UTF-8 (no codepoint count) — fall back to the byte truncation.
      label = label:sub(1, limit)
    end
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

    -- accent (D-08 three-step): tab's own WEZTERM_TAB_COLOR > followed pane
    -- WEZTERM_PANE_COLOR (when WEZTERM_TAB_FOLLOW_PANE == "1") > neutral default.
    local profile = M.resolve_accent(uv)

    -- icon carrier (D-01/D-04): one user var shared tab+pane, composed left of the title.
    local icon = uv.WEZTERM_TAB_ICON or ""

    -- title: pane WEZTERM_TAB_TITLE > explicit tab.tab_title > active_pane.title > ""
    -- (literal — no `<color>:` split anymore, D-05/D-06). tab.tab_title is what
    -- `wez tab title <text>` writes via set-tab-title; it sits ABOVE the inherited pane
    -- PROCESS title so an explicit tab title is honored, while the pane user var stays
    -- first so the active pane's own title still wins (active-pane precedence). launch_dir
    -- feeds the empty-title cwd fallback (D-11/D-13): active pane cwd if WezTerm exposes it.
    local title = uv.WEZTERM_TAB_TITLE
    if not title or title == "" then
      title = tab.tab_title
    end
    if not title or title == "" then
      title = tab.active_pane and tab.active_pane.title or ""
    end
    local launch_dir = (tab.active_pane and tab.active_pane.current_working_dir)
    if type(launch_dir) == "table" then
      launch_dir = launch_dir.file_path or launch_dir.path
    end
    if not launch_dir or launch_dir == "" then
      launch_dir = tab.active_pane and tab.active_pane.title or ""
    end

    -- compose displayed text: icon left of the title, with the empty-title cwd fallback.
    local display = M.title_with_fallback(title, icon, launch_dir)

    local label = M.format_label(tab.tab_index, display, max_width)
    label = wezterm.truncate_right(label, math.max(1, (max_width or 8) - 4))
    return M.build_runs(tab.is_active, profile, label)
  end)

  return config
end

return M
