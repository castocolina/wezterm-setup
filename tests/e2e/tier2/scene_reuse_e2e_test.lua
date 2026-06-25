-- tests/e2e/tier2/scene_reuse_e2e_test.lua
--
-- Tier 2 (live-mux scene layer) — the REUSE-MODE scene driver. For each seeded
-- recipe (ai / dev / docker) it spins a FRESH, isolated, headless wezterm-mux-server
-- (tests/e2e/lib/mux.lua), drives the launcher UNDER TEST (`<WEZ_BIN> scene launch
-- <recipe>`) against that scratch mux with WEZTERM_PANE pointed at the mux's single
-- starting pane (the reuse precondition), polls to the expected state, and LIVE-
-- ASSERTS the six Tier 2 contracts (D-01..D-05, D-08(cwd)):
--
--   1. PANE-COUNT parity (D-01; PRD A.2): the reuse target tab holds EXACTLY the
--      recipe's pane count (ai=2, dev=3, docker=3) — no extra, no missing — AND no
--      other tab was created (reuse stays in place; residue guard).
--   2. CWD (D-08(cwd)): every pane in the target tab inherits the scratch launch dir.
--   3. USER-VARS: the styled panes carry the recipe's tab user vars when this
--      wezterm build surfaces user_vars in `cli list`; otherwise this is verified by
--      the no-leak interpreted-OSC proxy (the installed build returns no user_vars
--      via cli list, so the proxy stands — mechanism is the file's discretion).
--   4. NO-ESCAPE-LEAK (D-05): get-text of each styled pane contains NONE of the
--      leak signatures — literal `printf '`, the raw octal ESC run `\033`, or a
--      `quote>` shell continuation prompt. (A `claude: command not found` from a
--      missing recipe program is NOT a leak and is ignored.)
--   5. RESPONSIVENESS / no-hang (D-04): a unique marker echoed into a live shell
--      pane round-trips through get-text within a bounded poll; absence = hang = FAIL.
--   6. CLEANUP (D-03): every case tears its mux down (kill + rmrf) even if an
--      assertion threw, so the next case starts from zero residue.
--
-- WHY REUSE FIRST: reuse mode (single-pane tab -> launch in place) is the EXACT path
-- that produced the reported scene hang, so it is the priority and the proof that the
-- whole Tier 2 assertion machinery works. Plan 02 (new-tab mode) is a thin consumer
-- of the same mux helper.
--
-- ISOLATION (T-06.7-03): the mux + every `wezterm cli` call run under a scratch
-- HOME/XDG_RUNTIME_DIR/XDG_CONFIG_HOME/WEZTERM_CONFIG_FILE, and the recipe is seeded
-- into a scratch WEZTERM_SETUP_DIR/scenes — the user's real ~/.config/wezterm and
-- running WezTerm GUI session are NEVER touched.
--
-- Run directly:  WEZ_BIN=./dist/wez lua5.4 tests/e2e/tier2/scene_reuse_e2e_test.lua

-- package.path bootstrap (three `..` -> repo root; + harness/skip/mux lib +
-- tests/e2e (unused here but mirrors the tier convention) + cli/vendor for dkjson).
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
-- bare PATH name resolves via command -v).
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
-- Whole-tier mux gate (D-03). On a host with a resolvable headless mux this prints
-- LIVE-ASSERTED and runs the cases; otherwise it prints a loud SKIPPED line and
-- exits 0 — never a silent pass, never a hang. A hollow pass on a capable host is
-- impossible to hide (the LIVE-ASSERTED marker only prints when capable). No
-- always-run cross-platform block precedes the gate, so no pre-gate footer needed.
-- ===========================================================================
skip.require_tool(
  mux.probe,
  "tier2 reuse-mode scene live-mux",
  "wezterm-mux-server unavailable (headless mux not resolvable)")

-- Normalize a `cli list` cwd ("file://host/path/") to a bare absolute path for
-- comparison against the scratch launch dir (strip the file:// + optional host and
-- any trailing slash).
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

-- Count of DISTINCT tab ids present (the residue guard: reuse must stay in ONE tab).
local function distinct_tabs(panes)
  local seen, n = {}, 0
  for _, p in ipairs(panes) do
    if p.tab_id ~= nil and not seen[p.tab_id] then
      seen[p.tab_id] = true
      n = n + 1
    end
  end
  return n
end

-- ---------------------------------------------------------------------------
-- run_case(recipe, expected_panes): one fresh mux, one reuse launch, six checks.
-- ---------------------------------------------------------------------------
local function run_case(recipe, expected_panes)
  print(string.format("== reuse case: %s (expect %d panes) ==", recipe, expected_panes))
  local s = mux.spin("e2e-t2-reuse-" .. recipe)

  -- Everything from here runs inside a pcall so a thrown error still tears the mux
  -- down (D-03 / T-06.7-02 cleanup-on-failure).
  local ok_run, err = pcall(function()
    check(recipe .. ": mux came up live with a starting pane",
      s.live and s.first_pane_id ~= nil, "live=" .. tostring(s.live))
    if not s.live or s.first_pane_id == nil then return end

    -- Seed the recipe into a scratch WEZTERM_SETUP_DIR/scenes so `scene launch`
    -- resolves it without touching the user's installed scenes.
    local setup = s.dir .. "/setup"
    os.execute("mkdir -p " .. shquote(setup .. "/scenes"))
    os.execute(string.format("cp %s %s",
      shquote(ABS_REPO .. "/scenes/" .. recipe .. ".toml"),
      shquote(setup .. "/scenes/" .. recipe .. ".toml")))

    -- Drive the launcher UNDER TEST against THIS mux. The scratch env rides as a
    -- prefix so scene.lua's bare `wezterm cli` calls target this mux; WEZTERM_PANE
    -- is the mux's single starting pane (reuse precondition); we cd into the scratch
    -- launch dir so scene.lua's launch_dir ($PWD) resolves the panes' cwd to it.
    local launch_cmd = string.format(
      "cd %s && %s WEZTERM_PANE=%d WEZTERM_SETUP_DIR=%s %s scene launch %s",
      shquote(s.launch_dir), s.env, tonumber(s.first_pane_id),
      shquote(setup), shquote(WEZ_ABS), shquote(recipe))
    local out, code = h.run_capture_all(launch_cmd)
    check(recipe .. ": `scene launch` exited 0 (no hang/abort)", code == 0,
      "code=" .. tostring(code) .. " out=" .. tostring(out))

    -- The reuse target tab is the tab still holding the original (reused) pane.
    local target_tab
    for _, p in ipairs(mux.cli_list(s)) do
      if p.pane_id == s.first_pane_id then target_tab = p.tab_id end
    end
    check(recipe .. ": reused pane still present (target tab resolved)",
      target_tab ~= nil, "first_pane_id=" .. tostring(s.first_pane_id))
    if target_tab == nil then return end

    -- (D-02) Poll until the target tab holds exactly expected_panes before asserting.
    local reached = mux.poll_until(s, function()
      local tp = panes_in_tab(mux.cli_list(s), target_tab)
      return #tp == expected_panes, tp
    end, { attempts = 40, sleep = 0.25, label = recipe .. " -> " .. expected_panes .. " panes" })

    local panes = mux.cli_list(s)
    local tabpanes = panes_in_tab(panes, target_tab)

    -- (1) PANE-COUNT parity + residue guard.
    check(string.format("%s: reuse target tab has exactly %d panes (D-01)", recipe, expected_panes),
      reached and #tabpanes == expected_panes,
      "got=" .. tostring(#tabpanes))
    check(recipe .. ": reuse created NO new tab (residue guard)",
      distinct_tabs(panes) == 1, "tabs=" .. tostring(distinct_tabs(panes)))

    -- (2) CWD parity (D-08(cwd)): every pane in the target tab inherited the launch dir.
    local cwd_ok, bad = true, nil
    for _, p in ipairs(tabpanes) do
      if norm_cwd(p.cwd) ~= s.launch_dir then
        cwd_ok = false; bad = tostring(p.cwd); break
      end
    end
    check(recipe .. ": every reuse pane cwd == launch dir (D-08)", cwd_ok,
      "launch=" .. s.launch_dir .. " bad=" .. tostring(bad))

    -- (3) USER-VARS: assert the recipe carrier when the build surfaces user_vars;
    -- else the no-leak interpreted-OSC proxy below stands (this build returns none).
    local exposes_uv = false
    for _, p in ipairs(tabpanes) do
      if type(p.user_vars) == "table" and next(p.user_vars) ~= nil then exposes_uv = true end
    end
    if exposes_uv then
      local has_color = false
      for _, p in ipairs(tabpanes) do
        if type(p.user_vars) == "table" and p.user_vars.WEZTERM_TAB_COLOR ~= nil then
          has_color = true
        end
      end
      check(recipe .. ": styled panes carry WEZTERM_TAB_COLOR user var", has_color)
    else
      skip.soft_skip(recipe .. ": user-vars via `cli list`",
        "this wezterm build surfaces no user_vars in cli list; covered by the no-leak interpreted-OSC proxy")
    end

    -- (4) NO-ESCAPE-LEAK (D-05): no leaked emitter bytes in any styled pane.
    local leak_pane = nil
    for _, p in ipairs(tabpanes) do
      local t = mux.get_text(s, p.pane_id)
      if t:find("printf '", 1, true)      -- literal printf wrapper leaked
        or t:find("\\033", 1, true)        -- raw octal ESC run leaked (octal-run check)
        or t:find("quote>", 1, true) then  -- shell continuation prompt = broken quoting
        leak_pane = p.pane_id; break
      end
    end
    check(recipe .. ": no escape/printf/quote leak in any reuse pane (D-05)",
      leak_pane == nil, "leaking pane=" .. tostring(leak_pane))

    -- (5) RESPONSIVENESS / no-hang (D-04): a fresh shell pane echoes a unique marker.
    -- A dedicated shell pane is used (not the recipe's focused pane) because a
    -- recipe's focus pane may run an interactive program (e.g. `claude`, `$EDITOR`)
    -- that legitimately captures stdin, which is not a valid liveness signal; a
    -- freshly spawned shell pane proves the mux event loop is processing input->output.
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

  -- (6) CLEANUP (D-03) — ALWAYS, even on a thrown assertion error.
  mux.teardown(s)
  if not ok_run then
    check(recipe .. ": case ran without an unhandled error", false, tostring(err))
  end
end

run_case("ai", 2)
run_case("dev", 3)
run_case("docker", 3)

os.exit(h.footer())
