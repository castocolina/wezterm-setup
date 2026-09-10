-- tests/e2e/tier4/visual_diff_e2e_test.lua
--
-- Tier 4 (visuals, deterministic half) — capture window-scoped screenshots of
-- four scenarios (dev/ai/docker/tabbar), RMSE-diff against committed per-OS
-- baselines, and promote EXACT prior-capture bytes on --approve.
--
-- Auto-discovered by tools/run-e2e.sh (`*_e2e_test.lua`). Without
-- WEZ_E2E_VISUAL=1 this file loud-SKIPs and captures nothing. Semantic/AI-vision
-- judgment of the same PNGs is Plan 05's e2e-visual-review skill (D-01: make e2e
-- never calls an external vision API).

local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../../.." -- tests/e2e/tier4 -> repo root (three ..)
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/tests/e2e/lib/?.lua",
  repo_root .. "/tests/e2e/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local h = require("harness")
local skip = require("skip")
local mux = require("mux")
local gui = require("gui")
local platform = require("platform")
local check = h.check
local shquote = h.shquote

local approve = false
local scenarios_csv = nil
for _, a in ipairs(arg or {}) do
  if a == "--approve" then
    approve = true
  else
    local csv = a:match("^--scenarios=(.*)$")
    if csv then scenarios_csv = csv end
  end
end

local DEFAULT_SCENARIOS = { "dev", "ai", "docker", "tabbar" }
local RECIPE = { dev = "dev", ai = "ai", docker = "docker", tabbar = "dev" }
local EXPECTED_PANES = { dev = 3, ai = 2, docker = 3, tabbar = 4 }

local function split_csv(s)
  local out = {}
  for part in string.gmatch(s or "", "[^,]+") do
    local t = part:match("^%s*(.-)%s*$")
    if t and t ~= "" then out[#out + 1] = t end
  end
  return out
end

local scenarios = scenarios_csv and split_csv(scenarios_csv) or DEFAULT_SCENARIOS

skip.require_env("WEZ_E2E_VISUAL", "tier4 visuals")

local ABS_REPO = (h.run_capture("cd " .. shquote(repo_root) .. " && pwd")):gsub("%s+$", "")
local DIFF_SH = ABS_REPO .. "/tools/e2e-visual-diff.sh"

local function file_exists(path)
  local fh = io.open(path, "rb")
  if not fh then return false end
  fh:close()
  return true
end

local function window_geometry(window_id)
  local out = h.run_capture("xdotool getwindowgeometry --shell "
    .. shquote(tostring(window_id)))
  local geo = {}
  for k, v in (out or ""):gmatch("(%w+)=(%-?%d+)") do
    geo[k] = tonumber(v)
  end
  if not geo.X or not geo.Y or not geo.WIDTH or not geo.HEIGHT then
    return nil
  end
  if geo.WIDTH <= 0 or geo.HEIGHT <= 0 then
    return nil
  end
  return geo
end

local function crop_to_window(full_path, dest_path, geo)
  local spec = string.format("%dx%d+%d+%d", geo.WIDTH, geo.HEIGHT, geo.X, geo.Y)
  local magick = (h.run_capture("command -v magick") or ""):match("%S") and "magick" or "convert"
  os.execute(string.format("%s %s -crop %s +repage %s",
    magick, shquote(full_path), spec, shquote(dest_path)))
  if not file_exists(dest_path) then return false end
  local dim = (h.run_capture("identify -format '%wx%h' " .. shquote(dest_path)) or ""):gsub("%s+$", "")
  return dim == string.format("%dx%d", geo.WIDTH, geo.HEIGHT)
end

local function capture_fullscreen(path)
  local tool = platform.detect_screenshot_tool()
  -- spectacle -a / gnome-screenshot -w follow native Wayland focus, which can
  -- diverge from the X11 window xdotool just verified. None of these tools
  -- accept an X11 window id. Fullscreen + crop to xdotool geometry is the
  -- window-scoped path that actually targets the test window.
  if tool == "spectacle" then
    os.execute("spectacle -b -f -n -d 400 -o " .. shquote(path))
  elseif tool == "grim" then
    -- grim <file> dumps the whole layout (all outputs). Focused-output
    -- heuristics only kick in with no file arg / some -o forms; we still crop.
    os.execute("grim " .. shquote(path))
  elseif tool == "gnome-screenshot" then
    os.execute("gnome-screenshot -f " .. shquote(path))
  else
    return false
  end
  return file_exists(path)
end

local function capture_active_window(session, path)
  if not session or not session.window_id then return false end
  local geo = window_geometry(session.window_id)
  if not geo then return false end
  local full = path .. ".full.png"
  if not capture_fullscreen(full) then
    os.execute("rm -f " .. shquote(full))
    return false
  end
  local ok = crop_to_window(full, path, geo)
  os.execute("rm -f " .. shquote(full))
  return ok
end

local function probe_render_sync()
  -- Analogous to gui.probe's keystroke canary: spin a throwaway GUI session,
  -- perform a real mux mutation, observe whether the GUI actually repaints.
  -- On this host, wezterm cli split-pane is mux-visible but the forced-XWayland
  -- window never redraws — a false LIVE-ASSERTED would ship identical
  -- "unsplit" baselines for every scenario.
  local session
  local tmp = (os.getenv("TMPDIR") or "/tmp") .. "/wez-e2e-probe-render"
  local ok, result = pcall(function()
    session = gui.spin("probe-render", { repo_root = ABS_REPO })
    if not (session.live and session.first_pane_id and session.window_id) then
      return false
    end
    if not gui.verify_focus(session) then
      return false
    end
    os.execute("mkdir -p " .. shquote(tmp))
    local before = tmp .. "/before.png"
    local after = tmp .. "/after.png"
    if not capture_active_window(session, before) then
      return false
    end
    h.run_capture_all(string.format(
      "%s wezterm cli split-pane --horizontal --pane-id %d",
      session.env, tonumber(session.first_pane_id)))
    local reached = mux.poll_until(session, function()
      local panes = mux.cli_list(session)
      return #panes == 2, panes
    end, { attempts = 40, sleep = 0.25, label = "probe-render mux 2 panes" })
    if not reached then
      return false
    end
    if not capture_active_window(session, after) then
      return false
    end
    local diff_out, diff_code = h.run_capture_all(
      shquote(DIFF_SH) .. " " .. shquote(after) .. " " .. shquote(before))
    print(string.format("  probe-render: mux_2_panes=%s diff=%s code=%s",
      tostring(reached), tostring(diff_out):gsub("%s+$", ""), tostring(diff_code)))
    if (diff_out or ""):match("cannot decode") or (diff_out or ""):match("dimension mismatch") then
      return false
    end
    return diff_code ~= 0
  end)
  if session then pcall(function() gui.teardown(session) end) end
  os.execute("rm -rf " .. shquote(tmp))
  return ok and result == true
end

skip.require_tool(
  function()
    -- Do NOT call gui.probe: that fires a canary keystroke. Plan 01 found OS
    -- injection cannot mutate WezTerm on this host; this driver never fires.
    -- Tools first (cheap, short-circuits); render-sync probe only if tools exist.
    local xdotool = h.run_capture("command -v xdotool")
    local cmp = h.run_capture("command -v compare")
    local ident = h.run_capture("command -v identify")
    local tools_ok = (xdotool or ""):match("%S")
      and platform.detect_screenshot_tool() ~= nil
      and (cmp or ""):match("%S")
      and (ident or ""):match("%S")
    return tools_ok and probe_render_sync()
  end,
  "tier4 visuals",
  "external wezterm cli mux mutations do not visually repaint the GUI window on this host")

local WEZ_ABS
do
  local w = h.WEZ
  if w:sub(1, 1) == "/" then
    WEZ_ABS = w
  elseif w:find("/") then
    WEZ_ABS = ABS_REPO .. "/" .. w:gsub("^%./", "")
  else
    local resolved = (h.run_capture("command -v " .. shquote(w))):gsub("%s+$", "")
    WEZ_ABS = resolved ~= "" and resolved or w
  end
end

local STABLE_DIR = (os.getenv("TMPDIR") or "/tmp") .. "/wez-e2e-visual-latest"
local MANIFEST = STABLE_DIR .. "/manifest.txt"
local OS_NAME = platform.platform_os()
local BASELINE_DIR = ABS_REPO .. "/tests/e2e/baselines/" .. OS_NAME
local MAX_AGE = tonumber(os.getenv("WEZ_E2E_VISUAL_MAX_AGE") or "") or 3600

local function sha256(path)
  local out = h.run_capture("sha256sum " .. shquote(path))
  return (out or ""):match("^(%S+)")
end

local function seed_recipe(setup, name)
  os.execute("mkdir -p " .. shquote(setup .. "/scenes"))
  os.execute(string.format("cp %s %s",
    shquote(ABS_REPO .. "/scenes/" .. name .. ".toml"),
    shquote(setup .. "/scenes/" .. name .. ".toml")))
end

local function launch_recipe(s, setup, recipe, pane_id)
  local launch_cmd = string.format(
    "cd %s && %s WEZTERM_PANE=%d WEZTERM_SETUP_DIR=%s %s scene launch %s",
    shquote(s.launch_dir), s.env, tonumber(pane_id),
    shquote(setup), shquote(WEZ_ABS), shquote(recipe))
  return h.run_capture_all(launch_cmd)
end

local function wait_settled(s, expected, label)
  local prev = nil
  return mux.poll_until(s, function()
    local panes = mux.cli_list(s)
    local n = #panes
    if n == expected and prev == n then
      return true, panes
    end
    prev = n
    return false, panes
  end, { attempts = 40, sleep = 0.25, label = label or ("settle " .. expected .. " panes") })
end

local function append_manifest(line)
  local fh = assert(io.open(MANIFEST, "a"))
  fh:write(line .. "\n")
  fh:close()
end

local function distinct_tab_count(panes)
  local seen, n = {}, 0
  for _, p in ipairs(panes or {}) do
    if p.tab_id ~= nil and not seen[p.tab_id] then
      seen[p.tab_id] = true
      n = n + 1
    end
  end
  return n
end

local function run_tabbar_setup(s, setup)
  -- Probe 03: spawn_pane opens a new tab whose pane is is_active=true (per-tab).
  -- Still activate_tab(tab1) so tab 1 is selected and tab 2 is inactive.
  local spawned = mux.spawn_pane(s)
  check("tabbar: spawn_pane returned a pane id", spawned ~= nil, "id=" .. tostring(spawned))
  local reached = wait_settled(s, EXPECTED_PANES.tabbar, "tabbar -> 4 panes")
  local panes = mux.cli_list(s)
  check("tabbar: 4 panes after spawn", reached and #panes == 4, "got=" .. tostring(#panes))

  local tab1_id, tab1_pane, tab2_pane
  for _, p in ipairs(panes) do
    if p.pane_id == s.first_pane_id then
      tab1_id = p.tab_id
      tab1_pane = p.pane_id
    end
  end
  for _, p in ipairs(panes) do
    if tab1_id ~= nil and p.tab_id ~= tab1_id then
      tab2_pane = p.pane_id
      break
    end
  end
  check("tabbar: both tabs resolved", tab1_pane ~= nil and tab2_pane ~= nil,
    "tab1_pane=" .. tostring(tab1_pane) .. " tab2_pane=" .. tostring(tab2_pane))

  if tab1_pane and tab2_pane then
    local title_cmd = function(pane)
      return string.format(
        "cd %s && %s WEZTERM_PANE=%d WEZTERM_SETUP_DIR=%s %s pane title %s",
        shquote(s.launch_dir), s.env, tonumber(pane),
        shquote(setup), shquote(WEZ_ABS), shquote("Same Title"))
    end
    h.run_capture_all(title_cmd(tab1_pane))
    h.run_capture_all(title_cmd(tab2_pane))
  end
  if tab1_id then mux.activate_tab(s, tab1_id) end
  return distinct_tab_count(mux.cli_list(s))
end

local function capture_scenario(name)
  local recipe = RECIPE[name]
  local expected = EXPECTED_PANES[name]
  check(name .. ": known scenario", recipe ~= nil and expected ~= nil, "name=" .. tostring(name))
  if not recipe then return end

  local s
  local png = STABLE_DIR .. "/" .. name .. ".png"
  local dim, verdict, baseline_or_none = "0x0", "NO BASELINE", "NONE"
  local tab_count = nil
  local ok_run, err = pcall(function()
    s = gui.spin("vis-" .. name, { repo_root = ABS_REPO })
    check(name .. ": gui came up live with a starting pane",
      s.live and s.first_pane_id ~= nil, "live=" .. tostring(s and s.live))
    if not s.live or s.first_pane_id == nil then error("gui not live") end

    local setup = s.dir .. "/setup"
    seed_recipe(setup, recipe)
    local out, code = launch_recipe(s, setup, recipe, s.first_pane_id)
    check(name .. ": scene launch exited 0", code == 0,
      "code=" .. tostring(code) .. " out=" .. tostring(out))

    local launch_expected = (name == "tabbar") and EXPECTED_PANES.dev or expected
    wait_settled(s, launch_expected, name .. " launch panes")
    if name == "tabbar" then
      tab_count = run_tabbar_setup(s, setup)
    end
    wait_settled(s, expected, name .. " pre-capture settle")

    if not gui.verify_focus(s) then
      error("verify_focus failed")
    end
    check(name .. ": verify_focus before capture", true, "focus")
    if not capture_active_window(s, png) then
      error("screenshot was not written: " .. png)
    end
    check(name .. ": screenshot written", true, png)
  end)
  pcall(function() gui.teardown(s) end)
  if not ok_run then
    check(name .. ": capture pcall", false, tostring(err))
    return
  end
  if not file_exists(png) then
    check(name .. ": png exists after teardown", false, png)
    return
  end

  dim = (h.run_capture("identify -format '%wx%h' " .. shquote(png)) or ""):gsub("%s+$", "")
  local baseline = BASELINE_DIR .. "/" .. name .. ".png"
  if file_exists(baseline) then
    local diff_out, diff_code = h.run_capture_all(
      shquote(DIFF_SH) .. " " .. shquote(png) .. " " .. shquote(baseline))
    verdict = (diff_code == 0) and "PASS" or "FAIL"
    baseline_or_none = baseline
    print(name .. " diff: " .. tostring(diff_out):gsub("%s+$", ""))
    check(name .. ": RMSE vs baseline " .. verdict, diff_code == 0, tostring(diff_out))
  else
    verdict = "NO BASELINE"
    baseline_or_none = "NONE"
  end

  append_manifest(table.concat({ name, png, dim, verdict, baseline_or_none }, "|"))
  print(string.format("%s: captured %s (%s) vs baseline: %s", name, png, dim, verdict))
  if name == "tabbar" then
    print("tabbar: 2 tabs (same-title + active/inactive)")
    check("tabbar live tab count is 2", tab_count == 2, "tabs=" .. tostring(tab_count))
  end
end

local function run_capture()
  os.execute("rm -rf " .. shquote(STABLE_DIR))
  os.execute("mkdir -p " .. shquote(STABLE_DIR))
  local fh = assert(io.open(MANIFEST, "w"))
  fh:write("RUN_ID=" .. tostring(os.time()) .. "\n")
  fh:close()
  for _, name in ipairs(scenarios) do
    capture_scenario(name)
  end
end

local function parse_manifest(path)
  local run_id, rows = nil, {}
  local fh = io.open(path, "r")
  if not fh then return nil, nil end
  for line in fh:lines() do
    local rid = line:match("^RUN_ID=(%d+)")
    if rid then
      run_id = tonumber(rid)
    else
      local sc, png, dim, verdict, base = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]*)$")
      if sc then
        rows[sc] = { png = png, dim = dim, verdict = verdict, baseline = base }
      end
    end
  end
  fh:close()
  return run_id, rows
end

local function run_approve()
  if not file_exists(MANIFEST) then
    io.stderr:write("no capture manifest found — run `make e2e-visual` first (without APPROVE), review the output, then approve.\n")
    os.exit(1)
  end
  local run_id, rows = parse_manifest(MANIFEST)
  if not run_id then
    io.stderr:write("stale capture manifest (captured missing RUN_ID, max age is "
      .. tostring(MAX_AGE) .. ") — re-run `make e2e-visual` first, then approve\n")
    os.exit(1)
  end
  local age = os.time() - run_id
  if age > MAX_AGE then
    io.stderr:write(string.format(
      "stale capture manifest (captured %d seconds ago, max age is %d) — re-run `make e2e-visual` first, then approve\n",
      age, MAX_AGE))
    os.exit(1)
  end

  os.execute("mkdir -p " .. shquote(BASELINE_DIR))
  local promoted = {}
  for _, name in ipairs(scenarios) do
    local row = rows[name]
    if not row then
      check("approve: " .. name .. " present in manifest", false, "missing")
    elseif not file_exists(row.png) then
      check("approve: " .. name .. " png exists", false, row.png)
    else
      local dest = BASELINE_DIR .. "/" .. name .. ".png"
      os.execute("cp " .. shquote(row.png) .. " " .. shquote(dest))
      local sum_a = sha256(row.png)
      local sum_b = sha256(dest)
      local ok = sum_a ~= nil and sum_a == sum_b
      check("approve: " .. name .. " byte-for-byte checksum", ok,
        "src=" .. tostring(sum_a) .. " dest=" .. tostring(sum_b))
      if ok then
        print(string.format("promoted %s -> %s sha256=%s", name, dest, sum_a))
        promoted[#promoted + 1] = name
      end
    end
  end
  print("promoted scenarios: " .. table.concat(promoted, ", "))
  print("remember to git add tests/e2e/baselines/" .. OS_NAME .. "/*.png")
end

if approve then
  run_approve()
else
  run_capture()
end

os.exit(h.footer())
