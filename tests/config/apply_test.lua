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

if failures > 0 then
  io.stderr:write(string.format("\n%d assertion(s) failed\n", failures))
  os.exit(1)
end
io.write("\nall apply assertions passed\n")
os.exit(0)
