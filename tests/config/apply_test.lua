-- tests/config/apply_test.lua
--
-- Asserts the augment entry point contract (Plan 01-03 Task 2, D-17):
--   * apply(config) returns the SAME table it received (mutated, not replaced)
--   * that table now carries key_map_preference == "Mapped"
--   * that table now has a non-empty `keys` field
--   * a user-defined field set before apply() survives (non-destructive augment)
--   * a user-defined key binding present before apply() survives (T-03-01)
--
-- Runs under plain lua5.4: there is no `wezterm` global, so init.lua keeps the
-- declarative action specs in place. The subdir entry resolves `require("init")`;
-- the config ROOT entry resolves init.lua's DOTTED sibling requires
-- (`require("wezterm-setup.keybindings")` etc.), mirroring how WezTerm's
-- `<config-dir>/?.lua` template resolves them in a real session.

local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/../../config/wezterm-setup/?.lua;"
  .. here .. "/../../config/?.lua;" .. package.path

local wezterm_setup = require("init")

local failures = 0
local function check(cond, msg)
  if not cond then
    io.stderr:write("FAIL: " .. msg .. "\n")
    failures = failures + 1
  else
    io.write("ok: " .. msg .. "\n")
  end
end

-- A plain stub config table standing in for wezterm.config_builder()'s output,
-- carrying a pre-existing user setting and a user-defined key binding.
local config = {
  font = "user-chose-this",
  keys = {
    { key = "mapped:q", mods = "SUPER", action = "user-defined-action" },
  },
}

local returned = wezterm_setup.apply(config)

-- 1. Same table (identity) -> augment, not replace (D-17).
check(returned == config, "apply returns the SAME table it received (identity)")

-- 2. key_map_preference now set.
check(returned.key_map_preference == "Mapped", "config.key_map_preference == 'Mapped'")

-- 3. keys field present and non-empty.
check(type(returned.keys) == "table" and #returned.keys > 0, "config.keys is present and non-empty")

-- 4. The user's pre-existing non-key field survived untouched.
check(returned.font == "user-chose-this", "pre-existing user field (font) preserved")

-- 5. The user's pre-existing key binding survived (T-03-01: append, not reassign).
local user_key_present = false
for _, b in ipairs(returned.keys) do
  if b.key == "mapped:q" and b.mods == "SUPER" and b.action == "user-defined-action" then
    user_key_present = true
    break
  end
end
check(user_key_present, "pre-existing user key binding preserved (append, not reassign)")

-- 5b. General/terminal options: scrollback buffer raised to 50000 (AUGMENT, D-17).
check(returned.scrollback_lines == 50000, "config.scrollback_lines == 50000")

-- 6. RotatePanes spec reached the merged key table (D-12). Under plain lua5.4 there is no
--    `wezterm` global, so resolve_action leaves the declarative spec in place — the Alt+Shift+R
--    Clockwise entry must be present with its spec intact.
local rotate_present = false
for _, b in ipairs(returned.keys) do
  if b.key == "mapped:r" and b.mods == "ALT|SHIFT"
      and type(b.action) == "table" and b.action.type == "RotatePanes"
      and b.action.arg == "Clockwise" then
    rotate_present = true
    break
  end
end
check(rotate_present, "RotatePanes Alt+Shift+R spec merged into config.keys (D-12)")

-- 7. resolve_action maps a RotatePanes spec to a real wezterm action when `wezterm` is present
--    (Pitfall 3 lockstep: the closed switch must NOT error() on RotatePanes). We exercise the
--    SAME init.lua under a wezterm stub via package.preload to prove the arm exists.
package.loaded["init"] = nil
package.loaded["wezterm-setup.keybindings"] = nil
package.loaded["wezterm-setup.cwd"] = nil
package.loaded["wezterm-setup.format-tab-title"] = nil
package.preload["wezterm"] = function()
  return {
    action = {
      RotatePanes = function(arg) return { __action = "RotatePanes", arg = arg } end,
      ClearScrollback = function(a) return { __action = "ClearScrollback", arg = a } end,
      SpawnTab = function(a) return { __action = "SpawnTab", arg = a } end,
      CloseCurrentTab = function(a) return { __action = "CloseCurrentTab", arg = a } end,
      ActivateTabRelative = function(a) return { __action = "ActivateTabRelative", arg = a } end,
      MoveTabRelative = function(a) return { __action = "MoveTabRelative", arg = a } end,
      SplitHorizontal = function(a) return { __action = "SplitHorizontal", arg = a } end,
      SplitVertical = function(a) return { __action = "SplitVertical", arg = a } end,
      CloseCurrentPane = function(a) return { __action = "CloseCurrentPane", arg = a } end,
      TogglePaneZoomState = { __action = "TogglePaneZoomState" },
      ActivatePaneDirection = function(a) return { __action = "ActivatePaneDirection", arg = a } end,
      IncreaseFontSize = { __action = "IncreaseFontSize" },
      DecreaseFontSize = { __action = "DecreaseFontSize" },
      ResetFontSize = { __action = "ResetFontSize" },
      SendString = function(a) return { __action = "SendString", arg = a } end,
      DisableDefaultAssignment = { __action = "DisableDefaultAssignment" },
    },
    on = function() end,
    truncate_right = function(s, n) return s:sub(1, n) end,
  }
end

local ok_stub, stubbed = pcall(require, "init")
check(ok_stub, "init.lua loads under a wezterm stub without error (Pitfall 3 lockstep)")
if ok_stub then
  local cfg2 = { keys = {} }
  local ok_apply = pcall(stubbed.apply, cfg2)
  check(ok_apply, "apply() runs under wezterm stub without resolve_action error()")
  local resolved_rotate = false
  for _, b in ipairs(cfg2.keys) do
    if b.key == "mapped:r" and type(b.action) == "table" and b.action.__action == "RotatePanes"
        and b.action.arg == "Clockwise" then
      resolved_rotate = true
      break
    end
  end
  check(resolved_rotate, "resolve_action maps RotatePanes spec to wezterm.action.RotatePanes (D-12)")
end

if failures > 0 then
  io.stderr:write(string.format("\n%d assertion(s) failed\n", failures))
  os.exit(1)
end
io.write("\nall apply assertions passed\n")
os.exit(0)
