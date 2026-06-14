-- cli/spec.lua
--
-- SINGLE SOURCE OF TRUTH for the `wez` command tree (D-16).
--
-- This module builds and returns the argparse parser that the CLI entry point
-- (cli/wez.lua), the completion generator (`wez completions` / `wez __complete`,
-- Plan 07), and `wez keys` (Plan 05) all read. Registering the COMPLETE Phase 1
-- subcommand surface here means downstream plans implement only their own
-- cli/commands/<name>.lua module WITHOUT editing this file (interface-first).
--
-- Phase 1 surface registered below:
--   version                                          (Plan 01 - implemented)
--   doctor                                           (Plan 06)
--   keys           --json                            (Plan 05)
--   install-state  --force --restore --skip          (Plan 04)
--   uninstall-state --keep-config --keep-backup --keep-cli (Plan 06)
--   completions    <shell>                           (Plan 07)
--   __complete     <context>   (hidden)              (Plan 07)
--
-- The top-level `pane`/`tab`/`scene` namespaces (Phases 2-5, see README) are left
-- intentionally OPEN here: we do not register their internals, but the flat
-- subcommand layout does not paint them into a corner.
--
-- Security (T-01-02): the entry point dispatches by looking up the chosen command
-- name against the closed set registered here (allow-list). Never build a require
-- path directly from raw user input.

-- Resolve the vendored argparse relative to THIS file, so the module works both
-- from source (any CWD) and from inside the luastatic bundle (relative module
-- names per .planning/decisions/cli-language.md standalone-binary constraint).
local M = {}

-- The version string. The build/installer can stamp this; version.lua reads the
-- same constant so the spec and the command never drift.
M.VERSION = "0.1.0"

-- Category tags consumed by the completion generator (D-16) and `wez keys`.
-- Each registered subcommand MUST appear here.
local CATEGORIES = {
  ["version"] = "diagnostics",
  ["doctor"] = "diagnostics",
  ["keys"] = "diagnostics",
  ["install-state"] = "install",
  ["uninstall-state"] = "install",
  ["seed-scenes"] = "install",
  ["completions"] = "shell",
  ["pane"] = "identity",
  ["tab"] = "identity",
  ["scene"] = "scenes",
  ["__complete"] = "internal",
}

-- The ordered, canonical Phase 1 subcommand list (the closed allow-list).
local SUBCOMMANDS = {
  "version",
  "doctor",
  "keys",
  "install-state",
  "uninstall-state",
  "seed-scenes",
  "completions",
  "pane",
  "tab",
  "scene",
  "__complete",
}

-- Build a fresh argparse parser registering the full Phase 1 command tree.
-- Returns the configured parser. Callers parse process `arg` against it.
function M.build_parser()
  -- Require the vendored argparse by its in-tree module path so it resolves both
  -- from source (`./?.lua` -> cli/vendor/argparse.lua) and inside the luastatic
  -- bundle (module name cli.vendor.argparse). Fall back to the bare name in case
  -- a bundler flattened the vendored dir.
  local ok, argparse = pcall(require, "cli.vendor.argparse")
  if not ok then
    argparse = require("argparse")
  end

  local parser = argparse("wez", "wezterm-setup companion CLI")

  -- Record the chosen subcommand name into result.command so the dispatcher can
  -- look it up against the allow-list (SUBCOMMANDS) without guessing.
  parser:command_target("command")

  -- A bare `wez` (or `wez --version`) is valid: print usage / version instead of
  -- erroring on a missing command. The entry point (cli/wez.lua) decides what to
  -- do when result.command is nil.
  parser:require_command(false)

  -- Top-level --version: a plain flag (NOT argparse:add_version, which exits on
  -- parse). Keeping it a flag lets the entry point observe `result.version` and
  -- route to the version command, and lets tests parse `--version` to a table.
  parser:flag("--version", "Print the wez version and exit")

  -- version ---------------------------------------------------------------
  parser:command("version", "Print the wez version")

  -- doctor (Plan 06) ------------------------------------------------------
  parser:command("doctor", "Diagnose install state and config health")

  -- keys (Plan 05) --------------------------------------------------------
  local keys = parser:command("keys", "List active keybindings by category")
  keys:flag("--json", "Emit machine-readable JSON")

  -- install-state (Plan 04) ----------------------------------------------
  local install_state = parser:command("install-state", "Inspect / drive install state")
  install_state:flag("--force", "Overwrite an existing managed block")
  install_state:flag("--restore", "Restore the timestamped backup")
  install_state:flag("--skip", "Leave the existing block untouched")

  -- uninstall-state (Plan 06) --------------------------------------------
  local uninstall_state = parser:command("uninstall-state", "Inspect / drive uninstall state")
  uninstall_state:flag("--keep-config", "Preserve ~/.config/wezterm/wezterm-setup/")
  uninstall_state:flag("--keep-backup", "Preserve wezterm.lua.bak.* backups")
  uninstall_state:flag("--keep-cli", "Preserve the wez binary")

  -- seed-scenes (Plan 05) ------------------------------------------------
  -- Copy-if-absent install seeding of the example scene recipes (SCEN-06). No
  -- flags: all copy/keep decisions live in cli/commands/seed_scenes.lua (D-01).
  parser:command("seed-scenes", "Seed example scene recipes (copy-if-absent)")

  -- completions (Plan 07) ------------------------------------------------
  local completions = parser:command("completions", "Generate shell completions from this spec")
  completions:argument("shell", "Target shell (bash|zsh)"):args("?")

  -- pane (Phase 2: Pane Identity) -----------------------------------------
  -- `wez pane color <value> [--opacity]` / `wez pane color reset`.
  -- The nested subcommand name lands in result.pane_cmd; the top-level
  -- result.command stays "pane" so the dispatcher routes to cli/commands/pane.lua.
  local pane = parser:command("pane", "Pane identity: color and title")
  pane:command_target("pane_cmd")
  local pane_color = pane:command("color", "Set or reset this pane's background and tab accent color")
  pane_color:argument("value", "Color name, hex (#rgb / #rrggbb / #rrggbbaa), or 'reset'")
  pane_color:flag("--opacity", "Apply the color's alpha as pane opacity if supported")
  local pane_title = pane:command("title", "Set or clear this pane's custom tab title")
  pane_title:argument("words", "Title text, or an icon name + text, or empty / 'reset' to clear"):args("*")

  -- tab (Phase 3: Tab Identity) -------------------------------------------
  -- `wez tab color <value>` / `wez tab color reset`. The nested subcommand name
  -- lands in result.tab_cmd; result.command stays "tab" so the dispatcher routes
  -- to cli/commands/tab.lua. The `title` subcommand + `--title` flag land in 03-03.
  local tab = parser:command("tab", "Tab identity: accent color and title")
  tab:command_target("tab_cmd")
  local tab_color = tab:command("color", "Set or reset this tab's accent color")
  tab_color:argument("value", "Color name, hex (#rgb / #rrggbb), or 'reset'")
  -- --title takes a value (the title text), so it is an option, not a boolean
  -- flag — `wez tab color blue --title api` must land "api" in result.title.
  -- Asymmetry by design: the combined --title is a single string (tab.lua splits
  -- it via resolve_title_str), whereas standalone `tab title` below takes pre-split
  -- argv words (args("*"), resolved via resolve_title).
  tab_color:option("--title", "Also set the tab title (icon name + text allowed)")
  local tab_title = tab:command("title", "Set or clear this tab's title")
  tab_title:argument("words", "Title text, an icon name + text, or empty / 'reset' to clear"):args("*")

  -- scene (Phase 4: Ad-hoc Scenes) ----------------------------------------
  -- `wez scene new --layout <L> --pane '<spec>' [--pane ...] [--color] [--title]`.
  -- The nested subcommand name lands in result.scene_cmd; result.command stays
  -- "scene" so the dispatcher routes to cli/commands/scene.lua. This is the
  -- MINIMAL routing registration (04-02): full --layout/--pane candidate-value
  -- completions are 04-03's scope and intentionally NOT wired here.
  local scene = parser:command("scene", "Build an ad-hoc multi-pane scene")
  scene:command_target("scene_cmd")
  local scene_new = scene:command("new", "Build a multi-pane tab from a layout + pane specs")
  -- --layout: required, single value (validated against the 4-layout enum by
  -- cli/lib/scene.lua at run time).
  scene_new:option("--layout", "Layout: tall | tall:mirrored | grid | horizontal"):args(1)
  -- --pane: required (>=1, enforced in scene.lua for the exact UI-SPEC error),
  -- repeatable. count("*") makes argparse collect every occurrence into an array
  -- (result.pane). Each value is a --pane spec string (shell | bare cmd | k=v,...).
  scene_new:option("--pane", "A pane spec: 'shell' | '<cmd>' | 'cmd=..,color=..,title=..'"):args(1):count("*")
  -- --color / --title: optional tab-level identity for the whole scene (D-05).
  scene_new:option("--color", "Tab-level accent color for the scene"):args(1)
  scene_new:option("--title", "Tab-level title for the scene"):args(1)
  -- scene launch <name> (Plan 05-03, SCEN-03/04) — the saved-recipe front door.
  -- A sibling subcommand under `scene` (scene_cmd target already set above), so
  -- the completion generator's spec-walk picks `launch` up automatically (D-16).
  -- The single positional <name> is the recipe basename (without .toml).
  -- OPTIONAL (args "?"): a bare `wez scene launch` must reach M.run_launch so it
  -- emits the UI-SPEC usage copy + available-recipes hint (exit 2) itself, rather
  -- than argparse intercepting with a generic "missing argument 'name'" error.
  local scene_launch = scene:command("launch", "Launch a saved scene recipe by name")
  scene_launch:argument("name", "Recipe basename (without .toml) under the scenes dir"):args("?")

  -- __complete (hidden, Plan 07) -----------------------------------------
  -- Internal hook the shell completion functions call for dynamic values.
  local complete = parser:command("__complete", "Internal completion hook")
  complete._hidden = true
  complete:argument("context", "Completion context"):args("?")

  return parser
end

-- The closed allow-list of registered subcommand names (a fresh copy each call).
function M.subcommand_names()
  local out = {}
  for i, n in ipairs(SUBCOMMANDS) do
    out[i] = n
  end
  return out
end

-- name -> category map (a fresh copy each call).
function M.categories()
  local out = {}
  for k, v in pairs(CATEGORIES) do
    out[k] = v
  end
  return out
end

return M
