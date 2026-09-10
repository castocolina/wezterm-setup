-- tests/e2e/lib/gui.lua
--
-- Real on-screen isolated WezTerm GUI session for Tier 3 Firing (Phase 06.9).
-- Sibling to mux.lua: mux drives a headless mux-server; this module drives a
-- forced-XWayland GUI window that loads the REAL shipped product config so
-- fired chords exercise the actual curated bindings.
--
-- Focus pipeline (TOCTOU narrowed, not eliminated):
--   1. M.verify_focus chains activation + confirmation in ONE process.
--   2. M.fire_chord then fires a SEPARATE `xdotool key --clearmodifiers`.
--   3. M.check_focus_unchanged is a bare getactivewindow AFTER the fire.
-- A host where the canary keystroke does not mutate pane text self-skips
-- via M.probe rather than printing a false LIVE-ASSERTED.

do
  local src = debug.getinfo(1, "S").source:gsub("^@", "")
  local libdir = src:match("^(.*)/") or "."
  local repo = libdir .. "/../../.."
  package.path = table.concat({
    libdir .. "/?.lua",
    repo .. "/?.lua",
    repo .. "/cli/vendor/?.lua",
    package.path,
  }, ";")
end

local harness = require("harness")
local mux = require("mux")

local shquote = harness.shquote
local run_capture = harness.run_capture

local M = {}

local function popen_line(cmd)
  local p = io.popen(cmd .. " 2>/dev/null", "r")
  if not p then return "" end
  local out = p:read("*l") or ""
  p:close()
  return out
end

local function nap(secs)
  os.execute("sleep " .. tostring(secs))
end

local function search_class_ids(class)
  local out = run_capture("xdotool search --class " .. shquote(class))
  local ids = {}
  for id in (out or ""):gmatch("%S+") do
    ids[#ids + 1] = id
  end
  return ids
end

local function last_nonempty_line(s)
  local last = ""
  for line in (s or ""):gmatch("[^\n]+") do
    if line:match("%S") then last = line:match("%S+") or line end
  end
  return last
end

function M.spin(tag, opts)
  opts = opts or {}
  if not opts.repo_root or opts.repo_root == "" then
    error("gui.spin requires opts.repo_root")
  end

  local repo = popen_line("readlink -f " .. shquote(opts.repo_root))
  if repo == "" then repo = opts.repo_root end

  local dir = harness.scratch_dir(tag)
  local launch = dir .. "/launch"
  local suffix = dir:match("(%d+%-%d+)$") or tostring(os.time())
  local class = "wez-e2e-fire-" .. tostring(tag) .. "-" .. suffix

  os.execute("mkdir -p " .. shquote(dir .. "/home") .. " " .. shquote(dir .. "/runtime")
    .. " " .. shquote(dir .. "/cfg") .. " " .. shquote(launch))
  os.execute("chmod 700 " .. shquote(dir .. "/runtime"))
  -- WezTerm dotted require() looks in $XDG_CONFIG_HOME/wezterm/, not the
  -- config-file directory. Keep the plan-specified cfg/wezterm-setup link AND
  -- the path that actually resolves.
  os.execute("mkdir -p " .. shquote(dir .. "/cfg/wezterm"))
  os.execute("ln -sfn " .. shquote(repo .. "/config/wezterm-setup")
    .. " " .. shquote(dir .. "/cfg/wezterm-setup"))
  os.execute("ln -sfn " .. shquote(repo .. "/config/wezterm-setup")
    .. " " .. shquote(dir .. "/cfg/wezterm/wezterm-setup"))

  local extra = opts.extra_config_lines or {}
  if type(extra) == "string" then extra = { extra } end

  local cfg = {
    "local wezterm = require 'wezterm'",
    "local config = wezterm.config_builder and wezterm.config_builder() or {}",
    "config.enable_wayland = false",
    "config.check_for_updates = false",
    "config.default_cwd = '" .. launch .. "'",
    "config.default_prog = { '/bin/sh' }",
    "config.initial_cols = 100",
    "config.initial_rows = 30",
  }
  for _, line in ipairs(extra) do
    cfg[#cfg + 1] = line
  end
  cfg[#cfg + 1] = "require('wezterm-setup').apply(config)"
  cfg[#cfg + 1] = "return config"
  cfg[#cfg + 1] = ""

  local fh = assert(io.open(dir .. "/cfg/wezterm.lua", "wb"))
  fh:write(table.concat(cfg, "\n"))
  fh:close()

  local env = mux.env_prefix(dir)
  local pidfile = dir .. "/gui.pid"
  local logfile = dir .. "/gui.log"
  os.execute(string.format(
    "%s wezterm --config-file %s start --always-new-process --class %s --cwd %s --position 0,0 >%s 2>&1 & echo $! > %s",
    env,
    shquote(dir .. "/cfg/wezterm.lua"),
    shquote(class),
    shquote(launch),
    shquote(logfile),
    shquote(pidfile)))

  local session = {
    dir = dir,
    launch_dir = launch,
    env = env,
    class = class,
    window_id = nil,
    pid = nil,
    first_pane_id = nil,
    live = false,
  }

  local ok = mux.poll_until(session, function()
    local panes = mux.cli_list(session)
    local ids = search_class_ids(class)
    if #panes >= 1 and #ids == 1 then
      session.window_id = ids[1]
      return true, panes
    end
    return false, panes
  end, { attempts = 40, sleep = 0.25, label = "gui liveness (" .. tostring(tag) .. ")" })
  session.live = ok == true

  local pid = popen_line("cat " .. shquote(pidfile))
  session.pid = pid ~= "" and pid or nil

  local panes = mux.cli_list(session)
  session.first_pane_id = panes[1] and panes[1].pane_id or nil

  if not session.live then
    print("  WARN - gui did not become live; see " .. logfile)
  end
  return session
end

function M.verify_focus(session)
  if not session or not session.window_id then return false end
  local out = run_capture("xdotool windowactivate --sync "
    .. shquote(tostring(session.window_id)) .. " getactivewindow")
  return last_nonempty_line(out) == tostring(session.window_id)
end

function M.check_focus_unchanged(session)
  if not session or not session.window_id then return false end
  local out = run_capture("xdotool getactivewindow")
  return last_nonempty_line(out) == tostring(session.window_id)
end

function M.fire_chord(session, xdotool_key_string)
  if not M.verify_focus(session) then
    error("gui.fire_chord: pre-fire focus verification failed for window "
      .. tostring(session and session.window_id))
  end
  os.execute("xdotool key --clearmodifiers " .. shquote(tostring(xdotool_key_string)))
  if not M.check_focus_unchanged(session) then
    error("gui.fire_chord: focus changed during fire for window "
      .. tostring(session.window_id))
  end
end

function M.probe(repo_root)
  local session
  local ok, result = pcall(function()
    session = M.spin("probe", { repo_root = repo_root })
    if not (session.live and M.verify_focus(session)) then
      return false
    end
    -- Canary: focus-only success is not enough. On this Wayland/KWin host,
    -- XTEST and ydotool/uinput both fail to mutate WezTerm pane text even
    -- when X11 activation matches. Probe must observe a real mux effect.
    local pane = session.first_pane_id
    if not pane then return false end
    local before = mux.get_text(session, pane)
    M.fire_chord(session, "a")
    local changed = false
    mux.poll_until(session, function()
      local now = mux.get_text(session, pane)
      if now ~= before then
        changed = true
        return true, now
      end
      return false, now
    end, { attempts = 8, sleep = 0.15, label = "gui probe canary" })
    return changed
  end)
  if session then M.teardown(session) end
  return ok and result == true
end

function M.teardown(session)
  if not session then return end
  if session.pid then
    os.execute("kill " .. tostring(session.pid) .. " 2>/dev/null")
    nap(0.3)
    os.execute("kill -9 " .. tostring(session.pid) .. " 2>/dev/null")
  end
  if session.dir then
    os.execute("rm -rf " .. shquote(session.dir))
  end
end

return M
