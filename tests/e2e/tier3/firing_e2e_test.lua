-- tests/e2e/tier3/firing_e2e_test.lua
--
-- Tier 3 (firing layer) — full PRD Appendix A.3 fire(B) matrix: focus-verify
-- then fire each curated chord against the REAL shipped product config.
--
-- On a host where OS-level injection cannot mutate a WezTerm pane (this
-- Wayland/KWin class: XTEST and ydotool/uinput both produce no mux effect),
-- gui.probe returns false and this file loud-SKIPs — never a false LIVE-ASSERTED.

local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../../.." -- tests/e2e/tier3 -> repo root (three ..)
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/tests/e2e/lib/?.lua",
  repo_root .. "/tests/e2e/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local h = require("harness")
local skip = require("skip")
local platform = require("platform")
local mux = require("mux")
local gui = require("gui")
local check = h.check

skip.require_env("WEZ_E2E_INPUT", "tier3 firing")
skip.require_tool(
  function() return gui.probe(repo_root) end,
  "tier3 firing — focus-verified OS input injection",
  "OS-level key injection cannot deliver a keystroke into a focus-verified forced-XWayland WezTerm window on this Wayland/KWin host (xdotool XTEST and ydotool/uinput both produce no mux effect)")

local chords = platform.expectations.fire_chords.linux

local POLL = { attempts = 40, sleep = 0.25 }

local function tab_ids_in_list_order(panes)
  -- R6 probe 01: `wezterm cli list --format json` array order matches
  -- left-to-right tab creation/UI position (spawn order: tab_id 0, then 1, then 2).
  local seen, ids = {}, {}
  for _, p in ipairs(panes) do
    local id = p.tab_id
    if id ~= nil and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = id
    end
  end
  return ids
end

local function tab_count(session)
  return #tab_ids_in_list_order(mux.cli_list(session))
end

local function panes_in_tab(panes, tab_id)
  local out = {}
  for _, p in ipairs(panes) do
    if p.tab_id == tab_id then
      out[#out + 1] = p
    end
  end
  return out
end

local function size_key(s)
  if not s then return "" end
  return tostring(s.rows) .. "x" .. tostring(s.cols)
end

local function sizes_by_pane_id(panes)
  local m = {}
  for _, p in ipairs(panes) do
    m[p.pane_id] = p.size
  end
  return m
end

local function pane_containing(session, needle)
  for _, p in ipairs(mux.cli_list(session)) do
    local t = mux.get_text(session, p.pane_id)
    if t:find(needle, 1, true) then
      return p
    end
  end
  return nil
end

local function wait_tabs(session, n, label)
  return mux.poll_until(session, function()
    local c = tab_count(session)
    return c == n, c
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = label })
end

local function wait_pane_n(session, n, label)
  return mux.poll_until(session, function()
    local c = #mux.cli_list(session)
    return c == n, c
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = label })
end

local function with_gui(tag, opts, body)
  opts = opts or {}
  opts.repo_root = opts.repo_root or repo_root
  local session
  local ok, err = pcall(function()
    session = gui.spin(tag, opts)
    check("gui session live (" .. tag .. ")", session.live == true)
    check("first_pane_id set (" .. tag .. ")", session.first_pane_id ~= nil)
    body(session)
  end)
  if session then gui.teardown(session) end
  if not ok then
    check("live firing section (" .. tag .. ")", false, tostring(err))
  end
end

-- ---------------------------------------------------------------------------
-- Plan 01 tracer (kept): ClearScreenAndScrollback + SpawnTab, one session.
-- ---------------------------------------------------------------------------
with_gui("firing", nil, function(session)
  local marker = "FIREMARKER" .. tostring(os.time()) .. tostring(math.random(1, 1e6))
  mux.send_marker(session, session.first_pane_id, marker)
  local present = mux.poll_until(session, function()
    local t = mux.get_text(session, session.first_pane_id)
    return t:find(marker, 1, true) ~= nil, t
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "marker present" })
  check("marker present before clear", present == true)

  gui.fire_chord(session, chords.ClearScreenAndScrollback)
  local gone = mux.poll_until(session, function()
    local t = mux.get_text(session, session.first_pane_id)
    return t:find(marker, 1, true) == nil, t
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "marker cleared" })
  check("ClearScreenAndScrollback removed marker", gone == true)

  local before = tab_count(session)
  gui.fire_chord(session, chords.SpawnTab)
  local grew = mux.poll_until(session, function()
    local n = tab_count(session)
    return n == before + 1, n
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "tab count +1" })
  check("SpawnTab increased tab count by 1", grew == true)
end)

-- ---------------------------------------------------------------------------
-- CloseCurrentTab
-- ---------------------------------------------------------------------------
with_gui("fire-closetab", nil, function(session)
  mux.spawn_pane(session)
  local ready = wait_tabs(session, 2, "2-tab precondition")
  check("CloseCurrentTab precondition: 2 tabs", ready == true)
  gui.fire_chord(session, chords.CloseCurrentTab)
  local dropped = mux.poll_until(session, function()
    local n = tab_count(session)
    return n == 1, n
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "tab count -1" })
  check("CloseCurrentTab: tab count decreased by 1", dropped == true)
end)

-- ---------------------------------------------------------------------------
-- ActivateTabRelative (next then prev, one session)
-- R6 probe 01: cli_list order is left-to-right UI order, but is_active is
-- per-tab (every 1-pane tab reports is_active=true), so window focus is
-- observed via get_text after a probe keystroke, not mux.active_pane.
-- ---------------------------------------------------------------------------
with_gui("fire-tabrel", nil, function(session)
  mux.spawn_pane(session)
  mux.spawn_pane(session)
  local ready = wait_tabs(session, 3, "3-tab precondition")
  check("ActivateTabRelative precondition: 3 tabs", ready == true)
  local ids = tab_ids_in_list_order(mux.cli_list(session))
  mux.activate_tab(session, ids[1])
  os.execute("sleep 0.25")

  gui.fire_chord(session, chords.ActivateTabRelative.next)
  gui.fire_chord(session, "q")
  local next_ok = mux.poll_until(session, function()
    local p = pane_containing(session, "q")
    return p ~= nil and p.tab_id == ids[2], p and p.tab_id
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "next tab got q" })
  check("ActivateTabRelative: next advanced to following tab", next_ok == true)

  gui.fire_chord(session, chords.ActivateTabRelative.prev)
  gui.fire_chord(session, "Q")
  local prev_ok = mux.poll_until(session, function()
    local p = pane_containing(session, "Q")
    return p ~= nil and p.tab_id == ids[1], p and p.tab_id
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "prev tab got Q" })
  check("ActivateTabRelative: prev returned to original tab", prev_ok == true)
end)

-- ---------------------------------------------------------------------------
-- MoveTabRelative (left then right, one session)
-- R6 probe 01: ordered tab_id list permutes with visual position.
-- ---------------------------------------------------------------------------
with_gui("fire-movetab", nil, function(session)
  mux.spawn_pane(session)
  mux.spawn_pane(session)
  local ready = wait_tabs(session, 3, "3-tab precondition")
  check("MoveTabRelative precondition: 3 tabs", ready == true)
  local ids = tab_ids_in_list_order(mux.cli_list(session))
  local moving = ids[2]
  mux.activate_tab(session, moving)
  os.execute("sleep 0.25")

  gui.fire_chord(session, chords.MoveTabRelative.left)
  local left_ok = mux.poll_until(session, function()
    local now = tab_ids_in_list_order(mux.cli_list(session))
    return now[1] == moving, now[1]
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "tab moved left" })
  check("MoveTabRelative: left decreased active tab list position by 1", left_ok == true)

  gui.fire_chord(session, chords.MoveTabRelative.right)
  local right_ok = mux.poll_until(session, function()
    local now = tab_ids_in_list_order(mux.cli_list(session))
    return now[2] == moving, now[2]
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "tab moved right" })
  check("MoveTabRelative: right restored original list position", right_ok == true)
end)

-- ---------------------------------------------------------------------------
-- SplitHorizontal
-- ---------------------------------------------------------------------------
with_gui("fire-splith", nil, function(session)
  local tab = mux.cli_list(session)[1].tab_id
  local before = mux.cli_list(session)[1].size
  gui.fire_chord(session, chords.SplitHorizontal)
  local ok = mux.poll_until(session, function()
    local in_tab = panes_in_tab(mux.cli_list(session), tab)
    if #in_tab ~= 2 then return false, #in_tab end
    local c1 = in_tab[1].size and in_tab[1].size.cols
    local c2 = in_tab[2].size and in_tab[2].size.cols
    if not (c1 and c2 and before and before.cols) then return false, "no cols" end
    local half = before.cols / 2
    local near_half = math.abs(c1 - half) <= (half * 0.4) and math.abs(c2 - half) <= (half * 0.4)
    return near_half, { c1, c2 }
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "h-split geometry" })
  check("SplitHorizontal: pane count +1 and cols roughly half", ok == true)
end)

-- ---------------------------------------------------------------------------
-- SplitVertical
-- ---------------------------------------------------------------------------
with_gui("fire-splitv", nil, function(session)
  local tab = mux.cli_list(session)[1].tab_id
  local before = mux.cli_list(session)[1].size
  gui.fire_chord(session, chords.SplitVertical)
  local ok = mux.poll_until(session, function()
    local in_tab = panes_in_tab(mux.cli_list(session), tab)
    if #in_tab ~= 2 then return false, #in_tab end
    local r1 = in_tab[1].size and in_tab[1].size.rows
    local r2 = in_tab[2].size and in_tab[2].size.rows
    if not (r1 and r2 and before and before.rows) then return false, "no rows" end
    local half = before.rows / 2
    local near_half = math.abs(r1 - half) <= (half * 0.4) and math.abs(r2 - half) <= (half * 0.4)
    return near_half, { r1, r2 }
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "v-split geometry" })
  check("SplitVertical: pane count +1 and rows roughly half", ok == true)
end)

-- ---------------------------------------------------------------------------
-- CloseCurrentPane
-- ---------------------------------------------------------------------------
with_gui("fire-closepane", nil, function(session)
  mux.split_pane(session, session.first_pane_id)
  local ready = wait_pane_n(session, 2, "2-pane precondition")
  check("CloseCurrentPane precondition: 2 panes", ready == true)
  gui.fire_chord(session, chords.CloseCurrentPane)
  local dropped = mux.poll_until(session, function()
    local n = #mux.cli_list(session)
    return n == 1, n
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "pane count -1" })
  check("CloseCurrentPane: pane count decreased by 1", dropped == true)
end)

-- ---------------------------------------------------------------------------
-- TogglePaneZoomState — real is_zoomed field, no proxy
-- ---------------------------------------------------------------------------
with_gui("fire-zoom", nil, function(session)
  mux.split_pane(session, session.first_pane_id, { percent = 30 })
  local ready = wait_pane_n(session, 2, "2-pane unequal split")
  check("TogglePaneZoomState precondition: 2 panes", ready == true)
  gui.fire_chord(session, chords.TogglePaneZoomState)
  local zoomed = mux.poll_until(session, function()
    local ap = mux.active_pane(mux.cli_list(session))
    return ap ~= nil and ap.is_zoomed == true, ap and ap.is_zoomed
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "is_zoomed" })
  check("TogglePaneZoomState: active pane is_zoomed == true", zoomed == true)
end)

local function rotation_shifted(before_panes, after_panes, dir)
  -- dir=1: each pane's previous size now belongs to the next pane in cli_list
  -- order (clockwise). dir=-1 is the opposite (counterclockwise).
  -- R6 probe 01: cli_list order correlates with UI position, so it is the
  -- rotation-order neighbor sequence.
  if #before_panes < 3 or #after_panes < 3 then return false end
  local ids = {}
  for _, p in ipairs(before_panes) do
    ids[#ids + 1] = p.pane_id
  end
  local b, a = sizes_by_pane_id(before_panes), sizes_by_pane_id(after_panes)
  local n = #ids
  for i = 1, n do
    local from = ids[i]
    local to = ids[((i - 1 + dir) % n) + 1]
    if size_key(a[to]) ~= size_key(b[from]) then
      return false
    end
  end
  return true
end

local function three_pane_unequal(session)
  local p1 = session.first_pane_id
  local p2 = mux.split_pane(session, p1, { direction = "right", percent = 30 })
  mux.split_pane(session, p2, { direction = "bottom", percent = 30 })
  return wait_pane_n(session, 3, "3-pane unequal")
end

-- ---------------------------------------------------------------------------
-- RotatePanes Clockwise
-- ---------------------------------------------------------------------------
with_gui("fire-rotcw", nil, function(session)
  local ready = three_pane_unequal(session)
  check("RotatePanes clockwise precondition: 3 panes", ready == true)
  local before = mux.cli_list(session)
  gui.fire_chord(session, chords.RotatePanes.clockwise)
  local ok = mux.poll_until(session, function()
    local after = mux.cli_list(session)
    return rotation_shifted(before, after, 1), after
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "clockwise permute" })
  check("RotatePanes: clockwise size map permuted to list-order neighbor", ok == true)
end)

-- ---------------------------------------------------------------------------
-- RotatePanes CounterClockwise (fresh session)
-- ---------------------------------------------------------------------------
with_gui("fire-rotccw", nil, function(session)
  local ready = three_pane_unequal(session)
  check("RotatePanes counterclockwise precondition: 3 panes", ready == true)
  local before = mux.cli_list(session)
  gui.fire_chord(session, chords.RotatePanes.counterclockwise)
  local ok = mux.poll_until(session, function()
    local after = mux.cli_list(session)
    return rotation_shifted(before, after, -1), after
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "ccw permute" })
  check("RotatePanes: counterclockwise size map permuted opposite direction", ok == true)
end)

-- ---------------------------------------------------------------------------
-- ActivatePaneDirection — ALL FOUR directions, two sessions (H then V)
-- ---------------------------------------------------------------------------
with_gui("fire-panedir-h", nil, function(session)
  local pid1 = session.first_pane_id
  local pid2 = mux.split_pane(session, pid1, { direction = "right" })
  local ready = wait_pane_n(session, 2, "horizontal 2-pane")
  check("ActivatePaneDirection H precondition: 2 panes", ready == true)
  mux.activate_pane(session, pid1)
  os.execute("sleep 0.25")

  gui.fire_chord(session, chords.ActivatePaneDirection.right)
  local right_ok = mux.poll_until(session, function()
    local ap = mux.active_pane(mux.cli_list(session))
    return ap ~= nil and ap.pane_id == pid2, ap and ap.pane_id
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "pane right" })
  check("ActivatePaneDirection Right: active pane is pid2", right_ok == true)

  gui.fire_chord(session, chords.ActivatePaneDirection.left)
  local left_ok = mux.poll_until(session, function()
    local ap = mux.active_pane(mux.cli_list(session))
    return ap ~= nil and ap.pane_id == pid1, ap and ap.pane_id
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "pane left" })
  check("ActivatePaneDirection Left: active pane reverted to pid1", left_ok == true)
end)

with_gui("fire-panedir-v", nil, function(session)
  local pid1 = session.first_pane_id
  local pid2 = mux.split_pane(session, pid1, { direction = "bottom" })
  local ready = wait_pane_n(session, 2, "vertical 2-pane")
  check("ActivatePaneDirection V precondition: 2 panes", ready == true)
  mux.activate_pane(session, pid1)
  os.execute("sleep 0.25")

  gui.fire_chord(session, chords.ActivatePaneDirection.down)
  local down_ok = mux.poll_until(session, function()
    local ap = mux.active_pane(mux.cli_list(session))
    return ap ~= nil and ap.pane_id == pid2, ap and ap.pane_id
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "pane down" })
  check("ActivatePaneDirection Down: active pane is pid2", down_ok == true)

  gui.fire_chord(session, chords.ActivatePaneDirection.up)
  local up_ok = mux.poll_until(session, function()
    local ap = mux.active_pane(mux.cli_list(session))
    return ap ~= nil and ap.pane_id == pid1, ap and ap.pane_id
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "pane up" })
  check("ActivatePaneDirection Up: active pane reverted to pid1", up_ok == true)
end)

-- ---------------------------------------------------------------------------
-- IncreaseFontSize / DecreaseFontSize / ResetFontSize (one session)
-- ---------------------------------------------------------------------------
with_gui("fire-fontsize", {
  extra_config_lines = {
    "config.adjust_window_size_when_changing_font_size = false",
  },
}, function(session)
  local baseline = mux.cli_list(session)[1].size
  check("FontSize baseline size present", baseline ~= nil and baseline.cols ~= nil)

  gui.fire_chord(session, chords.IncreaseFontSize)
  local inc = mux.poll_until(session, function()
    local s = mux.cli_list(session)[1].size
    return s and baseline and (s.cols < baseline.cols or s.rows < baseline.rows), s
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "font increase" })
  check("IncreaseFontSize: cols/rows decreased", inc == true)

  gui.fire_chord(session, chords.ResetFontSize)
  local reset = mux.poll_until(session, function()
    local s = mux.cli_list(session)[1].size
    return s and baseline and s.cols == baseline.cols and s.rows == baseline.rows, s
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "font reset" })
  check("ResetFontSize: cols/rows returned to baseline", reset == true)

  gui.fire_chord(session, chords.DecreaseFontSize)
  local dec = mux.poll_until(session, function()
    local s = mux.cli_list(session)[1].size
    return s and baseline and (s.cols > baseline.cols or s.rows > baseline.rows), s
  end, { attempts = POLL.attempts, sleep = POLL.sleep, label = "font decrease" })
  check("DecreaseFontSize: cols/rows increased beyond baseline", dec == true)
end)

os.exit(h.footer())
