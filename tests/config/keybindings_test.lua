-- tests/config/keybindings_test.lua
--
-- Asserts the keybindings module contract (Plan 01-03 Task 1):
--   * key_map_preference == "Mapped" (D-09)
--   * every FOUND-03 category (tabs, panes, font zoom, word nav) has >= 1 binding
--   * the locked Super+K clear binding exists (FOUND-02)
--   * NO chord uses a forbidden punctuation key [ ] { } / \ ; (D-10)
--   * the disabled-defaults list is present and non-empty (D-12)
--
-- Runs under plain lua5.4 (no wezterm global) because the module is pure data.

-- Resolve the config dir relative to this test file so it runs from any cwd.
local here = arg[0]:match("^(.*)/[^/]*$") or "."
package.path = here .. "/../../config/wezterm-setup/?.lua;" .. package.path

local kb = require("keybindings")

local failures = 0
local function check(cond, msg)
  if not cond then
    io.stderr:write("FAIL: " .. msg .. "\n")
    failures = failures + 1
  else
    io.write("ok: " .. msg .. "\n")
  end
end

-- 1. key_map_preference
check(kb.key_map_preference == "Mapped", "key_map_preference == 'Mapped'")

-- 2. keys table present and non-empty
check(type(kb.keys) == "table" and #kb.keys > 0, "keys table is present and non-empty")

-- Helper: does any binding's action match a type or category predicate?
local function any(pred)
  for _, b in ipairs(kb.keys) do
    if pred(b) then return true end
  end
  return false
end

local function action_type(b)
  return b.action and b.action.type or ""
end

-- 3. FOUND-03 category coverage.
-- Tabs: spawn/close/activate/move tab actions.
check(any(function(b)
  local t = action_type(b)
  return t:find("Tab")
end), "category: tabs has at least one binding")

-- Panes: split/close/zoom/navigate pane actions.
check(any(function(b)
  local t = action_type(b)
  return t:find("Pane") or t:find("Split")
end), "category: panes has at least one binding")

-- Font zoom: increase/decrease/reset font size.
check(any(function(b)
  return action_type(b):find("FontSize")
end), "category: font zoom has at least one binding")

-- Word navigation: word-wise cursor movement (SendString of ESC b / ESC f).
check(any(function(b)
  return action_type(b) == "SendString"
    and b.action.arg ~= nil
    and (b.action.arg == "\027b" or b.action.arg == "\027f")
end), "category: word navigation has at least one binding")

-- 4. Locked clear binding: Super+K -> clear screen + scrollback.
check(any(function(b)
  return b.key == "mapped:k"
    and b.mods == "SUPER"
    and action_type(b) == "ClearScreenAndScrollback"
end), "locked Super+K clear binding exists")

-- 4b. Linux-friendly clear binding: Ctrl+Shift+K -> clear screen + scrollback.
-- On Linux the Super/Win key is owned by the desktop/WM, so the terminal-standard
-- Ctrl+Shift chord is the reliable clear there (and harmless on macOS).
check(any(function(b)
  return b.key == "mapped:k"
    and b.mods == "CTRL|SHIFT"
    and action_type(b) == "ClearScreenAndScrollback"
end), "Linux-friendly Ctrl+Shift+K clear binding exists")

-- 5. No forbidden punctuation keys (D-10): [ ] { } / \ ;
local forbidden = { ["["] = true, ["]"] = true, ["{"] = true, ["}"] = true,
                    ["/"] = true, ["\\"] = true, [";"] = true }
local function bare_key(k)
  -- strip a leading "mapped:" / "phys:" prefix to get the produced character
  return (k:gsub("^[%a]+:", ""))
end
local punctuation_ok = true
for _, b in ipairs(kb.keys) do
  if forbidden[bare_key(b.key)] then
    io.stderr:write("FAIL: forbidden punctuation key in binding: " .. b.key .. "\n")
    punctuation_ok = false
  end
end
check(punctuation_ok, "no binding uses a forbidden punctuation key (D-10)")

-- 6. Disabled-defaults list present and non-empty (D-12).
check(type(kb.disabled_defaults) == "table" and #kb.disabled_defaults > 0,
  "disabled_defaults list is present and non-empty")

if failures > 0 then
  io.stderr:write(string.format("\n%d assertion(s) failed\n", failures))
  os.exit(1)
end
io.write("\nall keybindings assertions passed\n")
os.exit(0)
