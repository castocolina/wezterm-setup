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
--
-- Embraced WezTerm search defaults (item 8, 6.1): WezTerm ships
--   * `Ctrl+Shift+F` -> Search (scrollback search overlay), and
--   * `Ctrl+R` (inside CopyMode) -> CopyMode 'CycleMatchType' (cycle the match kind).
-- Both already fire today; we add NO binding for them — they are intentionally KEPT.
-- This relaxes the older "no less-style search overlays" philosophy rule: the
-- scrollback search overlay is now embraced rather than disabled, so we neither
-- rebind nor disable `Ctrl+Shift+F` / `Ctrl+R`. (No vi-modal bindings are added.)

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
  -- == Clear binding (FOUND-02, D-11) — DUAL chord for cross-platform sanity ==
  -- Clears the visible screen AND the scrollback in one chord.
  --   * Super+K (= Cmd+K on macOS): the conventional macOS clear chord.
  --   * Ctrl+Shift+K (both platforms): on Linux the Super/Win key is owned by the
  --     desktop/WM (e.g. Pop!_OS grabs Super+K and it never reaches WezTerm), so
  --     the terminal-standard Ctrl+Shift chord is the reliable Linux clear. It is
  --     also readline-safe (plain Ctrl+K is kill-line; the SHIFT lifts it clear of
  --     the shell) and layout-stable (letter key, D-10). Both fire the SAME action;
  --     `wez keys` lists both, which is truthful, not a conflict.
  --   * Both the lowercase `k` AND uppercase `K` Ctrl+Shift entries are declared:
  --     under `key_map_preference = "Mapped"` a Shift+letter produces the UPPERCASE
  --     char, so the chord that actually fires is `CTRL|SHIFT+K`; WezTerm's own
  --     defaults register both cases (e.g. `SHIFT|CTRL c` AND `SHIFT|CTRL C` for
  --     copy), and we mirror that so the binding fires regardless of how the
  --     produced character is reported.
  { key = mapped("k"), mods = M.super_mod,   action = { type = "ClearScreenAndScrollback" } },
  { key = mapped("k"), mods = "CTRL|SHIFT",  action = { type = "ClearScreenAndScrollback" } },
  { key = mapped("K"), mods = "CTRL|SHIFT",  action = { type = "ClearScreenAndScrollback" } },

  -- == Tabs (FOUND-03) ==
  { key = mapped("t"), mods = "SUPER",            action = { type = "SpawnTab", arg = "CurrentPaneDomain" } }, -- new tab (mac: Cmd+T)
  { key = mapped("w"), mods = "SUPER",            action = { type = "CloseCurrentTab", confirm = false } },     -- close tab (mac: Cmd+W)
  -- Linux fallback: many Linux WMs/DEs grab the Super key (e.g. Pop!_OS/GNOME bind
  -- Super+W/T to the shell), so a SUPER-only close-tab never reaches WezTerm. Ship a
  -- Ctrl+Shift+W variant too (mirrors the clear-screen dual binding above; lower +
  -- upper produced char, since Shift yields "W"). New-tab already has a working
  -- default Ctrl+Shift+T, so only close-tab needs the explicit Linux fallback.
  { key = mapped("w"), mods = "CTRL|SHIFT",       action = { type = "CloseCurrentTab", confirm = false } },     -- close tab (Linux)
  { key = mapped("W"), mods = "CTRL|SHIFT",       action = { type = "CloseCurrentTab", confirm = false } },     -- close tab (Linux, shifted char)
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
  -- == Arrange (D-12) ==
  -- RotatePanes presets join the Alt+Shift pane family ("R" for Rotate; "E" sits left of R
  -- for the counter direction). Each declarative RotatePanes spec MUST have a matching arm in
  -- init.lua resolve_action — the switch error()s on an unknown type, crashing config load
  -- (Pitfall 3). Add/remove both in lockstep. RotatePanes needs WezTerm >= 20220624.
  { key = mapped("r"), mods = "ALT|SHIFT", action = { type = "RotatePanes", arg = "Clockwise" } },        -- rotate panes clockwise
  { key = mapped("e"), mods = "ALT|SHIFT", action = { type = "RotatePanes", arg = "CounterClockwise" } }, -- rotate panes counter-clockwise
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
  -- D-12 truthfulness note: the Arrange chords Alt+Shift+R / Alt+Shift+E (RotatePanes)
  -- and the rest of the Alt+Shift pane family (H/V/X/Z) do NOT shadow a WezTerm default
  -- assignment (`wezterm show-keys` carries no ALT|SHIFT R/E/H/V/X/Z default), so they
  -- need NO DisableDefaultAssignment entry — one binding still maps to one action and
  -- `wez keys` stays truthful. The embraced search defaults (Ctrl+Shift+F / Ctrl+R) are
  -- deliberately KEPT, so they are likewise absent here.
}

-- D-09: the printed key fires the action; report this preference so WezTerm
-- matches by produced character, not physical position.
M.key_map_preference = "Mapped"

return M
