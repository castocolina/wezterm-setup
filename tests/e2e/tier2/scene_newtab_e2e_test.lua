-- tests/e2e/tier2/scene_newtab_e2e_test.lua
--
-- Tier 2 (live-mux scene layer) — the NEW-TAB-MODE scene driver, the second half
-- of the PRD A.2 recipe x mode matrix (reuse mode ships in Plan 01's
-- scene_reuse_e2e_test.lua; this file ships new-tab mode). For each seeded recipe
-- (ai / dev / docker) it spins a FRESH, isolated, headless wezterm-mux-server
-- (tests/e2e/lib/mux.lua), BUILDS a >=2-pane originating tab (the new-tab
-- precondition: scene.decide_materialization sends a current tab that already has
-- >=2 panes to a NEW tab, never an in-place build), drives the launcher UNDER TEST
-- (`<WEZ_BIN> scene launch <recipe>`) against that scratch mux with WEZTERM_PANE
-- pointed at a pane IN the 2-pane tab, polls until a NEW tab carrying exactly the
-- recipe's pane count appears, and LIVE-ASSERTS the six Tier 2 contracts
-- (D-01..D-05, D-08(cwd)):
--
--   1. PANE-COUNT parity (D-01; PRD A.2): the NEW tab holds EXACTLY the recipe's
--      pane count (ai=2, dev=3, docker=3) — no extra, no missing.
--   2. ORIGINATING-TAB UNTOUCHED (residue guard): the 2-pane tab the launch fired
--      from still has EXACTLY 2 panes — new-tab mode must NOT build in place.
--   3. CWD (D-08(cwd)): every pane in the new tab inherits the scratch launch dir.
--   4. USER-VARS: the styled panes carry the recipe's tab user vars when this
--      wezterm build surfaces user_vars in `cli list`; otherwise this is verified by
--      the no-leak interpreted-OSC proxy (the installed build returns no user_vars
--      via cli list, so the proxy stands — mechanism mirrors the reuse driver).
--   5. NO-ESCAPE-LEAK (D-05): get-text of each styled pane contains NONE of the
--      leak signatures — literal `printf '`, the raw octal ESC run `\033`, or a
--      `quote>` shell continuation prompt. (A `claude: command not found` from a
--      missing recipe program is NOT a leak and is ignored.)
--   6. RESPONSIVENESS / no-hang (D-04): a unique marker echoed into a fresh shell
--      pane round-trips through get-text within a bounded poll; absence = hang = FAIL.
--   7. CLEANUP (D-03): every case tears its mux down (kill + rmrf) even if an
--      assertion threw, so the next case starts from zero residue.
--
-- NEW-TAB vs REUSE: this file is the DIRECT analog of scene_reuse_e2e_test.lua and
-- differs ONLY in (a) the precondition — it splits the mux's first pane once so the
-- originating tab has 2 panes — and (b) which tab is asserted — the NEW tab (a tab
-- id absent from the pre-launch topology) instead of the reused tab, plus the
-- originating-tab-untouched residue guard. It reuses tests/e2e/lib/mux.lua
-- WHOLESALE (no lifecycle code here) and does NOT reimplement materialization
-- selection — the >=2-pane precondition drives new-tab; the result is asserted.
--
-- ISOLATION (T-06.7-03): the mux + every `wezterm cli` call run under a scratch
-- HOME/XDG_RUNTIME_DIR/XDG_CONFIG_HOME/WEZTERM_CONFIG_FILE, and the recipe is seeded
-- into a scratch WEZTERM_SETUP_DIR/scenes — the user's real ~/.config/wezterm and
-- running WezTerm GUI session are NEVER touched.
--
-- Run directly:  WEZ_BIN=./dist/wez lua5.4 tests/e2e/tier2/scene_newtab_e2e_test.lua

-- package.path bootstrap (three `..` -> repo root; + harness/skip/mux lib +
-- tests/e2e + cli/vendor for dkjson). Identical to the reuse driver.
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../../.." -- tests/e2e/tier2 -> repo root (three ..)
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
local check = h.check
local shquote = h.shquote

-- Absolute repo root (the test cd's into a scratch launch dir before invoking the
-- launcher, so a relative WEZ_BIN like ./dist/wez must be made absolute first; a
-- bare PATH name resolves via command -v). Identical to the reuse driver.
local ABS_REPO = (h.run_capture("cd " .. shquote(repo_root) .. " && pwd")):gsub("%s+$", "")
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

-- ===========================================================================
-- Whole-tier mux gate (D-03). Same gate as the reuse driver: on a host with a
-- resolvable headless mux this prints LIVE-ASSERTED and runs the cases; otherwise
-- it prints a loud SKIPPED line and exits 0 — never a silent pass, never a hang.
-- ===========================================================================
skip.require_tool(
  mux.probe,
  "tier2 new-tab-mode scene live-mux",
  "wezterm-mux-server unavailable (headless mux not resolvable)")

-- Normalize a `cli list` cwd ("file://host/path/") to a bare absolute path for
-- comparison against the scratch launch dir.
local function norm_cwd(cwd)
  if type(cwd) ~= "string" then return nil end
  return (cwd:gsub("^file://[^/]*", ""):gsub("/+$", ""))
end

-- Panes belonging to a given tab id.
local function panes_in_tab(panes, tab_id)
  local out = {}
  for _, p in ipairs(panes) do
    if p.tab_id == tab_id then out[#out + 1] = p end
  end
  return out
end

-- Set of tab ids present in a pane list (the residue/new-tab topology helper).
local function tab_set(panes)
  local seen = {}
  for _, p in ipairs(panes) do
    if p.tab_id ~= nil then seen[p.tab_id] = true end
  end
  return seen
end

-- The single tab id present in `panes` that is NOT in `before` (nil if none / >1).
local function new_tab_id(before, panes)
  local found = nil
  for _, p in ipairs(panes) do
    if p.tab_id ~= nil and not before[p.tab_id] then
      if found ~= nil and found ~= p.tab_id then
        return nil -- ambiguous: more than one new tab appeared
      end
      found = p.tab_id
    end
  end
  return found
end

-- ---------------------------------------------------------------------------
-- run_case(recipe, expected_panes): one fresh mux, build a 2-pane originating
-- tab, one new-tab launch, the seven checks.
-- ---------------------------------------------------------------------------
local function run_case(recipe, expected_panes)
  print(string.format("== new-tab case: %s (expect %d panes) ==", recipe, expected_panes))
  local s = mux.spin("e2e-t2-newtab-" .. recipe)

  -- Everything from here runs inside a pcall so a thrown error still tears the mux
  -- down (D-03 / T-06.7-02 cleanup-on-failure).
  local ok_run, err = pcall(function()
    check(recipe .. ": mux came up live with a starting pane",
      s.live and s.first_pane_id ~= nil, "live=" .. tostring(s.live))
    if not s.live or s.first_pane_id == nil then return end

    -- PRECONDITION (new-tab): split the mux's first pane ONCE so its tab holds 2
    -- panes. scene.decide_materialization sends a current tab with >=2 panes to a
    -- NEW tab, so this 2-pane tab is the originating tab the launch must NOT touch.
    local second_pane_id = mux.split_pane(s, s.first_pane_id)
    check(recipe .. ": built a 2-pane originating tab (new-tab precondition)",
      second_pane_id ~= nil, "split returned nil")
    if second_pane_id == nil then return end

    -- Resolve the originating tab id (the tab holding the mux's first pane).
    local origin_tab
    for _, p in ipairs(mux.cli_list(s)) do
      if p.pane_id == s.first_pane_id then origin_tab = p.tab_id end
    end
    check(recipe .. ": originating tab resolved", origin_tab ~= nil,
      "first_pane_id=" .. tostring(s.first_pane_id))
    if origin_tab == nil then return end

    -- Confirm the originating tab really has 2 panes before launching.
    local before_panes = mux.cli_list(s)
    check(recipe .. ": originating tab has 2 panes pre-launch",
      #panes_in_tab(before_panes, origin_tab) == 2,
      "got=" .. tostring(#panes_in_tab(before_panes, origin_tab)))
    -- Snapshot the pre-launch tab topology so the NEW tab is identifiable.
    local before_tabs = tab_set(before_panes)

    -- Seed the recipe into a scratch WEZTERM_SETUP_DIR/scenes so `scene launch`
    -- resolves it without touching the user's installed scenes.
    local setup = s.dir .. "/setup"
    os.execute("mkdir -p " .. shquote(setup .. "/scenes"))
    os.execute(string.format("cp %s %s",
      shquote(ABS_REPO .. "/scenes/" .. recipe .. ".toml"),
      shquote(setup .. "/scenes/" .. recipe .. ".toml")))

    -- Drive the launcher UNDER TEST against THIS mux. WEZTERM_PANE points at a pane
    -- IN the 2-pane originating tab (the new-tab precondition); we cd into the
    -- scratch launch dir so scene.lua's launch_dir ($PWD) resolves the new tab's
    -- panes' cwd to it (D-08).
    local launch_cmd = string.format(
      "cd %s && %s WEZTERM_PANE=%d WEZTERM_SETUP_DIR=%s %s scene launch %s",
      shquote(s.launch_dir), s.env, tonumber(s.first_pane_id),
      shquote(setup), shquote(WEZ_ABS), shquote(recipe))
    local out, code = h.run_capture_all(launch_cmd)
    check(recipe .. ": `scene launch` exited 0 (no hang/abort)", code == 0,
      "code=" .. tostring(code) .. " out=" .. tostring(out))

    -- (D-02) Poll until a NEW tab (absent from the pre-launch topology) holds
    -- exactly expected_panes before asserting.
    local target_tab
    local reached = mux.poll_until(s, function()
      local panes = mux.cli_list(s)
      local nt = new_tab_id(before_tabs, panes)
      if nt == nil then return false, panes end
      local tp = panes_in_tab(panes, nt)
      if #tp == expected_panes then
        target_tab = nt
        return true, panes
      end
      return false, panes
    end, { attempts = 40, sleep = 0.25, label = recipe .. " -> new tab w/ " .. expected_panes .. " panes" })

    local panes = mux.cli_list(s)
    -- Re-resolve in case poll timed out (target_tab may still be nil).
    if target_tab == nil then target_tab = new_tab_id(before_tabs, panes) end
    local newpanes = target_tab and panes_in_tab(panes, target_tab) or {}

    -- (1) PANE-COUNT parity: the NEW tab has exactly expected_panes panes.
    check(string.format("%s: new tab has exactly %d panes (D-01)", recipe, expected_panes),
      reached and target_tab ~= nil and #newpanes == expected_panes,
      "target_tab=" .. tostring(target_tab) .. " got=" .. tostring(#newpanes))

    -- (2) ORIGINATING-TAB UNTOUCHED (residue guard): the 2-pane tab is unchanged.
    check(recipe .. ": originating tab still has exactly 2 panes (no in-place build)",
      #panes_in_tab(panes, origin_tab) == 2,
      "got=" .. tostring(#panes_in_tab(panes, origin_tab)))

    -- (3) CWD parity (D-08(cwd)): every pane in the NEW tab inherited the launch dir.
    local cwd_ok, bad = true, nil
    for _, p in ipairs(newpanes) do
      if norm_cwd(p.cwd) ~= s.launch_dir then
        cwd_ok = false; bad = tostring(p.cwd); break
      end
    end
    check(recipe .. ": every new-tab pane cwd == launch dir (D-08)", cwd_ok,
      "launch=" .. s.launch_dir .. " bad=" .. tostring(bad))

    -- (4) USER-VARS: assert the recipe carrier when the build surfaces user_vars;
    -- else the no-leak interpreted-OSC proxy below stands (this build returns none).
    local exposes_uv = false
    for _, p in ipairs(newpanes) do
      if type(p.user_vars) == "table" and next(p.user_vars) ~= nil then exposes_uv = true end
    end
    if exposes_uv then
      local has_color = false
      for _, p in ipairs(newpanes) do
        if type(p.user_vars) == "table" and p.user_vars.WEZTERM_TAB_COLOR ~= nil then
          has_color = true
        end
      end
      check(recipe .. ": styled new-tab panes carry WEZTERM_TAB_COLOR user var", has_color)
    else
      skip.soft_skip(recipe .. ": user-vars via `cli list`",
        "this wezterm build surfaces no user_vars in cli list; covered by the no-leak interpreted-OSC proxy")
    end

    -- (5) NO-ESCAPE-LEAK (D-05): no leaked emitter bytes in any new-tab pane.
    local leak_pane = nil
    for _, p in ipairs(newpanes) do
      local t = mux.get_text(s, p.pane_id)
      if t:find("printf '", 1, true)      -- literal printf wrapper leaked
        or t:find("\\033", 1, true)        -- raw octal ESC run leaked (octal-run check)
        or t:find("quote>", 1, true) then  -- shell continuation prompt = broken quoting
        leak_pane = p.pane_id; break
      end
    end
    check(recipe .. ": no escape/printf/quote leak in any new-tab pane (D-05)",
      leak_pane == nil, "leaking pane=" .. tostring(leak_pane))

    -- (6) RESPONSIVENESS / no-hang (D-04): a fresh shell pane echoes a unique marker.
    -- A dedicated shell pane is used (not the recipe's focused pane) because a
    -- recipe's focus pane may run an interactive program (e.g. `claude`, `$EDITOR`)
    -- that legitimately captures stdin, which is not a valid liveness signal.
    local probe_pid = mux.spawn_pane(s)
    local marker = string.format("ZZ%d_%dZZ", os.time(), math.random(100000, 999999))
    if probe_pid then
      mux.send_marker(s, probe_pid, marker)
    end
    local alive = probe_pid ~= nil and mux.poll_until(s, function()
      return mux.get_text(s, probe_pid):find(marker, 1, true) ~= nil
    end, { attempts = 20, sleep = 0.25, label = recipe .. " marker echo" })
    check(recipe .. ": live session is responsive (marker round-trips, no hang) (D-04)",
      alive == true, "probe_pid=" .. tostring(probe_pid))
  end)

  -- (7) CLEANUP (D-03) — ALWAYS, even on a thrown assertion error.
  mux.teardown(s)
  if not ok_run then
    check(recipe .. ": case ran without an unhandled error", false, tostring(err))
  end
end

run_case("ai", 2)
run_case("dev", 3)
run_case("docker", 3)

os.exit(h.footer())
