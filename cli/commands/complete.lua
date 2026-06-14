-- cli/commands/complete.lua
--
-- The HIDDEN `wez __complete <context>` subcommand (D-16). The subcommand is
-- ALREADY registered in cli/spec.lua by Plan 01 (marked `_hidden`) — this module
-- ONLY implements the behavior; it does NOT edit the spec.
--
-- Purpose: the generated zsh/bash completion scripts (cli/commands/completions.lua)
-- never hardcode dynamic candidate lists. Instead, for any value that is computed
-- at completion time, the shell function shells out to `wez __complete <context>`
-- and consumes the newline-separated tokens it prints. This is the single
-- extension point for future phases: teaching `__complete` a NEW context (e.g.
-- `colors`, `scene-names`) makes that completion work WITHOUT regenerating or
-- editing the static completion scripts.
--
-- Phase 1 contexts are minimal but the dispatch structure is established:
--   subcommands  -> the visible (non-hidden) top-level subcommand names from spec
--
-- Security (T-07-02): candidates are PLAIN tokens drawn from the closed spec set;
-- this module emits no shell metacharacters, so the shell treats the output as
-- data during Tab expansion, never as code. Unknown contexts emit nothing and
-- still exit 0 — the hook must never become an error surface mid-expansion.

local spec = require("cli.spec")
-- The canonical color/icon tables live in the command module (single source of
-- truth, D-16) — completion derives candidates from them, never a second copy.
local pane = require("cli.commands.pane")
local tab = require("cli.commands.tab")
local title = require("cli.lib.title")
local scene = require("cli.lib.scene")
-- The COMMAND module (not the lib) owns the SINGLE recipe-listing provider
-- M.list_recipe_names + M.scenes_dir (05-03) that the launch error hint uses.
-- scene-names reuses it so completion can never advertise a recipe set that
-- differs from what launch resolves (Pitfall 6 / single source — D-16).
local scene_cmd = require("cli.commands.scene")

local M = {}

-- Hidden / internal subcommands that must NOT be advertised as user-facing
-- completion candidates. `__complete` itself is the obvious one.
local HIDDEN = {
  ["__complete"] = true,
}

-- Return the list of visible (non-hidden) subcommand names from the spec. This is
-- the SAME closed set the dispatcher allow-lists, minus the internal hooks — so
-- the candidates are always in sync with the real command tree (D-16).
local function visible_subcommands()
  local out = {}
  for _, n in ipairs(spec.subcommand_names()) do
    if not HIDDEN[n] then out[#out + 1] = n end
  end
  return out
end

-- The closed context dispatch. Each entry returns a list of candidate tokens.
-- Future phases add entries here (colors, scene names, ...) without touching the
-- generated shell scripts.
-- `wez pane color <Tab>` candidates: the curated palette + the `reset` value.
local function pane_colors()
  local out = {}
  for _, n in ipairs(pane.COLOR_NAMES) do out[#out + 1] = n end
  out[#out + 1] = "reset"
  return out
end

-- `wez pane title <Tab>` candidates: the icon-name shortcut keys (sorted, stable).
local function pane_icons()
  local out = {}
  for name in pairs(pane.ICONS) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- `wez tab color <Tab>` candidates: the curated palette + the `reset` value.
local function tab_colors()
  local out = {}
  for _, n in ipairs(tab.COLOR_NAMES) do out[#out + 1] = n end
  out[#out + 1] = "reset"
  return out
end

-- `wez tab title <Tab>` candidates: the shared icon-name keys (sorted, stable),
-- sourced from cli/lib/title.lua — the SAME map pane-icons now uses (D-03).
local function tab_icons()
  local out = {}
  for name in pairs(title.ICONS) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- `wez scene new --layout <Tab>` candidates: the 4 closed layout names, in
-- display order, sourced from cli/lib/scene.lua's M.LAYOUTS (the SAME array
-- validate_layout checks against — D-16 single source of truth). No table.sort:
-- M.LAYOUTS is already in the intended display order (tall first).
local function scene_layouts()
  local out = {}
  for _, n in ipairs(scene.LAYOUTS) do out[#out + 1] = n end
  return out
end

-- `wez scene launch <Tab>` candidates: the recipe basenames (sorted, no .toml),
-- read DYNAMICALLY at completion time from the scenes dir via the SAME single
-- provider the launch error hint uses (scene.list_recipe_names(scene.scenes_dir())
-- — D-16 single source). No caching: adding/removing a recipe file changes the
-- set on the next Tab with NO regeneration (SCEN-05). A missing/empty dir yields
-- {} -> nothing emitted, exit 0 (the Tab-time-never-fails contract).
local function scene_names()
  return scene_cmd.list_recipe_names(scene_cmd.scenes_dir())
end

-- `wez scene new --color <Tab>` candidates: the scene accent palette in display
-- order, sourced from scene.COLOR_NAMES (the SAME array validate_color checks —
-- D-16 single source). No `reset`: `scene new` sets an accent at creation, there
-- is nothing to reset (unlike `pane/tab color reset`).
local function scene_colors()
  local out = {}
  for _, n in ipairs(scene.COLOR_NAMES) do out[#out + 1] = n end
  return out
end

local CONTEXTS = {
  subcommands = visible_subcommands,
  ["pane-colors"] = pane_colors,
  ["pane-icons"] = pane_icons,
  ["tab-colors"] = tab_colors,
  ["tab-icons"] = tab_icons,
  ["scene-layouts"] = scene_layouts,
  ["scene-colors"] = scene_colors,
  ["scene-names"] = scene_names,
}

-- run(args): print newline-separated candidates for args.context. Unknown context
-- prints nothing. Always returns 0 (a Tab-time hook must not fail the shell).
function M.run(args)
  args = args or {}
  local context = args.context
  if type(context) ~= "string" or context == "" then
    -- No context: nothing to complete. Clean no-op.
    return 0
  end

  local provider = CONTEXTS[context]
  if not provider then
    -- Unknown context: emit nothing, exit clean (closed dispatch).
    return 0
  end

  for _, token in ipairs(provider()) do
    -- Emit plain tokens only (T-07-02). spec names are a closed set of
    -- [%w_-] identifiers, so no quoting/escaping is required; we still avoid
    -- printing anything but the bare token + newline.
    io.write(tostring(token))
    io.write("\n")
  end
  return 0
end

return M
