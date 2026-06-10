-- wezterm-setup :: keybindings
--
-- SINGLE SOURCE OF TRUTH for the wezterm-setup key table.
--
-- This module returns DATA (no side effects): the curated `mapped:` key table,
-- the `key_map_preference` value, and the list of WezTerm default actions we
-- explicitly disable. Both `init.lua`'s `apply()` (which merges this into the
-- user's config) and `wez keys` (Plan 05, which classifies the live effective
-- table against our declared set) consume this same source.
--
-- Design rules (Phase 1 Context, D-09..D-12):
--   D-09  `mapped:` bindings (trigger by produced character) + explicit
--         `key_map_preference = "Mapped"`, so the PRINTED key fires the action
--         across keyboard layouts (US-ANSI <-> ES), not a physical position.
--   D-10  Layout-stable keys only: letters, digits, named keys (arrows, Tab,
--         Enter, `+`/`-`). NEVER bracket/brace/slash/backslash/semicolon
--         (`[ ] { } / \ ;`) -- those shift or need AltGr on ES layouts.
--   D-11  Direct modifier combos, no leader/prefix. `Super+K` (Cmd+K on macOS)
--         clear is locked.
--   D-12  Every replaced WezTerm default is explicitly disabled (one action =
--         one binding) so `wez keys` classification stays truthful.
--
-- Cross-platform (FOUND-05, D-18): the ONLY platform delta is Cmd (macOS) vs
-- Super (Linux). Everything else is identical. Verified on Linux; macOS
-- re-verification deferred to the Mac pass.
--
-- README deviation note (D-10 enforcement): the README draft used
-- `Alt+Shift+\` (split horizontal) and `Alt+-` (split vertical). The backslash
-- chord is a FORBIDDEN punctuation key under D-10 and was replaced with the
-- layout-stable letter chords `Alt+Shift+H` / `Alt+Shift+V`. Font zoom keeps
-- `+`/`-`/`0` (named/digit keys, layout-stable and allowed by D-10).

local M = {}

-- The super-vs-cmd modifier difference is the ONLY cross-platform delta.
-- WezTerm maps `SUPER` to the Command key on macOS and the Super/Win key on
-- Linux, so a single `"SUPER"` token is already correct on both platforms.
-- We expose it as a named constant to document the FOUND-05 / D-18 intent and
-- to keep `wez keys` able to report the platform-appropriate label.
M.super_mod = "SUPER" -- = Cmd on macOS, Super on Linux (WezTerm-native mapping)

-- Helper: a `mapped:` binding fires on the produced CHARACTER (D-09).
local function mapped(key)
  return "mapped:" .. key
end

-- ---------------------------------------------------------------------------
-- Curated key table. Each entry: { key, mods, action } where `action` is a
-- declarative spec resolved into a real wezterm.action by init.lua's apply().
-- Keeping actions declarative here means this module has ZERO dependency on the
-- `wezterm` global, so it loads standalone under plain lua5.4 for testing.
--
-- FOUND-03 categories covered: tabs, panes, font zoom, word navigation.
-- ---------------------------------------------------------------------------
M.keys = {
  -- == Locked clear binding (FOUND-02, D-11) ==
  -- Clears the visible screen AND the scrollback in one chord.
  { key = mapped("k"), mods = M.super_mod, action = { type = "ClearScreenAndScrollback" } },

  -- == Tabs (FOUND-03) ==
  { key = mapped("t"), mods = "SUPER",            action = { type = "SpawnTab", arg = "CurrentPaneDomain" } }, -- new tab
  { key = mapped("w"), mods = "SUPER",            action = { type = "CloseCurrentTab", confirm = false } },     -- close tab
  { key = mapped("Tab"), mods = "CTRL",           action = { type = "ActivateTabRelative", arg = 1 } },         -- next tab
  { key = mapped("Tab"), mods = "CTRL|SHIFT",     action = { type = "ActivateTabRelative", arg = -1 } },        -- prev tab
  { key = mapped("PageUp"), mods = "CTRL|SHIFT",  action = { type = "MoveTabRelative", arg = -1 } },            -- move tab left
  { key = mapped("PageDown"), mods = "CTRL|SHIFT",action = { type = "MoveTabRelative", arg = 1 } },             -- move tab right

  -- == Panes (FOUND-03) ==
  -- Split chords use letters (H/V) instead of the README's backslash/`-` punctuation (D-10).
  { key = mapped("h"), mods = "ALT|SHIFT", action = { type = "SplitHorizontal", arg = "CurrentPaneDomain" } }, -- split horizontal
  { key = mapped("v"), mods = "ALT|SHIFT", action = { type = "SplitVertical", arg = "CurrentPaneDomain" } },   -- split vertical
  { key = mapped("x"), mods = "ALT|SHIFT", action = { type = "CloseCurrentPane", confirm = false } },          -- close pane
  { key = mapped("z"), mods = "ALT|SHIFT", action = { type = "TogglePaneZoomState" } },                        -- zoom toggle
  -- Directional pane navigation (arrow named keys are layout-stable, D-10).
  { key = mapped("LeftArrow"),  mods = "ALT", action = { type = "ActivatePaneDirection", arg = "Left" } },
  { key = mapped("RightArrow"), mods = "ALT", action = { type = "ActivatePaneDirection", arg = "Right" } },
  { key = mapped("UpArrow"),    mods = "ALT", action = { type = "ActivatePaneDirection", arg = "Up" } },
  { key = mapped("DownArrow"),  mods = "ALT", action = { type = "ActivatePaneDirection", arg = "Down" } },

  -- == Font zoom (FOUND-03) ==
  -- `+`/`-`/`0` are named/digit keys -> layout-stable and explicitly allowed (D-10).
  { key = mapped("+"), mods = "SUPER", action = { type = "IncreaseFontSize" } },
  { key = mapped("-"), mods = "SUPER", action = { type = "DecreaseFontSize" } },
  { key = mapped("0"), mods = "SUPER", action = { type = "ResetFontSize" } },

  -- == Word navigation (FOUND-03) ==
  -- Emit the standard word-wise cursor escapes; arrow named keys (D-10).
  { key = mapped("LeftArrow"),  mods = "CTRL", action = { type = "SendString", arg = "\027b" } }, -- word left  (ESC b)
  { key = mapped("RightArrow"), mods = "CTRL", action = { type = "SendString", arg = "\027f" } }, -- word right (ESC f)
}

-- ---------------------------------------------------------------------------
-- Disabled WezTerm defaults (D-12). Each replaced default is turned into a
-- `DisableDefaultAssignment` so exactly one binding maps to each action and
-- `wez keys` (Plan 05) reports a truthful classification. Listed as DATA
-- (key + mods); init.lua resolves these into disabling key entries.
-- ---------------------------------------------------------------------------
M.disabled_defaults = {
  { key = "k", mods = "SUPER" },        -- default ClearScrollback (we re-bind to clear screen + scrollback)
  { key = "t", mods = "SUPER" },        -- default SpawnTab variant
  { key = "w", mods = "SUPER" },        -- default CloseCurrentTab variant
  { key = "Tab", mods = "CTRL" },       -- default ActivateTabRelative(1)
  { key = "Tab", mods = "CTRL|SHIFT" }, -- default ActivateTabRelative(-1)
  { key = "+", mods = "SUPER" },        -- default IncreaseFontSize
  { key = "-", mods = "SUPER" },        -- default DecreaseFontSize
  { key = "0", mods = "SUPER" },        -- default ResetFontSize
}

-- D-09: the printed key fires the action; report this preference so WezTerm
-- matches by produced character, not physical position.
M.key_map_preference = "Mapped"

return M
