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

-- Close-tab must have a Ctrl+Shift+W fallback, not Super-only: many Linux WMs grab
-- the Super key (Pop!_OS/GNOME), so a SUPER-only close-tab is dead on Linux.
check(any(function(b)
  return action_type(b) == "CloseCurrentTab"
    and tostring(b.mods or ""):find("CTRL")
    and tostring(b.mods or ""):find("SHIFT")
    and tostring(b.key or ""):find("w", 1, true) ~= nil
end), "close tab has a Ctrl+Shift+W binding (Linux Super-grab fallback)")

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

-- 4c. Arrange keys (D-12): Alt+Shift+R = RotatePanes Clockwise,
-- Alt+Shift+E = RotatePanes CounterClockwise. The Alt+Shift+Z zoom toggle is retained.
check(any(function(b)
  return b.key == "mapped:r"
    and b.mods == "ALT|SHIFT"
    and action_type(b) == "RotatePanes"
    and b.action.arg == "Clockwise"
end), "Alt+Shift+R = RotatePanes Clockwise binding exists (D-12)")

check(any(function(b)
  return b.key == "mapped:e"
    and b.mods == "ALT|SHIFT"
    and action_type(b) == "RotatePanes"
    and b.action.arg == "CounterClockwise"
end), "Alt+Shift+E = RotatePanes CounterClockwise binding exists (D-12)")

check(any(function(b)
  return b.key == "mapped:z"
    and b.mods == "ALT|SHIFT"
    and action_type(b) == "TogglePaneZoomState"
end), "Alt+Shift+Z zoom toggle retained (D-12)")

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

-- 7. Hybrid modifier reachability (feat 07.1-keys-hybrid).
-- EVERY load-bearing action must be reachable from BOTH modifier families:
--   * at least one binding whose mods contain SUPER (Cmd family), AND
--   * at least one binding whose mods contain CTRL (Ctrl family).
-- macOS sometimes routes a Cmd combo to the shell / OS, and many Linux WMs grab
-- the Super key; shipping both families keeps every action reachable on both
-- platforms regardless of which modifier the environment intercepts.
local function mods_contains(b, token)
  return tostring(b.mods or ""):find(token, 1, true) ~= nil
end

-- For an ActivateTabRelative / RotatePanes / ActivatePaneDirection action we must
-- match on arg too, so "next tab" and "prev tab" are each independently checked.
local function reachable(label, pred)
  check(any(function(b) return pred(b) and mods_contains(b, "SUPER") end),
    label .. " reachable from Cmd family (SUPER)")
  check(any(function(b) return pred(b) and mods_contains(b, "CTRL") end),
    label .. " reachable from Ctrl family (CTRL)")
end

reachable("ClearScreenAndScrollback",
  function(b) return action_type(b) == "ClearScreenAndScrollback" end)
reachable("SpawnTab",
  function(b) return action_type(b) == "SpawnTab" end)
reachable("CloseCurrentTab",
  function(b) return action_type(b) == "CloseCurrentTab" end)
reachable("SplitHorizontal",
  function(b) return action_type(b) == "SplitHorizontal" end)
reachable("SplitVertical",
  function(b) return action_type(b) == "SplitVertical" end)
reachable("TogglePaneZoomState",
  function(b) return action_type(b) == "TogglePaneZoomState" end)
reachable("RotatePanes Clockwise",
  function(b) return action_type(b) == "RotatePanes" and b.action.arg == "Clockwise" end)
reachable("RotatePanes CounterClockwise",
  function(b) return action_type(b) == "RotatePanes" and b.action.arg == "CounterClockwise" end)
reachable("ActivateTabRelative next",
  function(b) return action_type(b) == "ActivateTabRelative" and b.action.arg == 1 end)
reachable("ActivateTabRelative prev",
  function(b) return action_type(b) == "ActivateTabRelative" and b.action.arg == -1 end)
reachable("IncreaseFontSize",
  function(b) return action_type(b) == "IncreaseFontSize" end)
reachable("DecreaseFontSize",
  function(b) return action_type(b) == "DecreaseFontSize" end)
reachable("ResetFontSize",
  function(b) return action_type(b) == "ResetFontSize" end)
reachable("ActivatePaneDirection Left",
  function(b) return action_type(b) == "ActivatePaneDirection" and b.action.arg == "Left" end)
reachable("ActivatePaneDirection Right",
  function(b) return action_type(b) == "ActivatePaneDirection" and b.action.arg == "Right" end)
reachable("ActivatePaneDirection Up",
  function(b) return action_type(b) == "ActivatePaneDirection" and b.action.arg == "Up" end)
reachable("ActivatePaneDirection Down",
  function(b) return action_type(b) == "ActivatePaneDirection" and b.action.arg == "Down" end)
-- Word navigation (SendString ESC b / ESC f) is a Ctrl-family default today; it
-- must also be reachable from the Cmd family.
reachable("word navigation left (ESC b)",
  function(b) return action_type(b) == "SendString" and b.action.arg == "\027b" end)
reachable("word navigation right (ESC f)",
  function(b) return action_type(b) == "SendString" and b.action.arg == "\027f" end)

-- 8. No DUPLICATE identical {key, mods} entries — that is a config error
-- (two rows fighting over the same chord). Allowed: same key+mods is NEVER
-- repeated; same action under DIFFERENT mods is the whole point of the hybrid.
local seen = {}
local dup_ok = true
for _, b in ipairs(kb.keys) do
  local sig = tostring(b.key) .. "\0" .. tostring(b.mods)
  if seen[sig] then
    io.stderr:write("FAIL: duplicate {key,mods} entry: " .. tostring(b.key)
      .. " / " .. tostring(b.mods) .. "\n")
    dup_ok = false
  end
  seen[sig] = true
end
check(dup_ok, "no duplicate identical {key, mods} bindings")

if failures > 0 then
  io.stderr:write(string.format("\n%d assertion(s) failed\n", failures))
  os.exit(1)
end
io.write("\nall keybindings assertions passed\n")
os.exit(0)
