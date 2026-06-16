-- tests/integration/scene_cwd_integration_test.lua
--
-- LIVE e2e for the clean-pane spawn-with-cwd contract (D-08, SCEN-04). Proves
-- that a pane spawned with `wezterm cli spawn --cwd <dir>` actually OPENS in that
-- dir — by reading the pane's cwd back out of `wezterm cli list --format json`
-- and asserting the path matches the target. This is the read-back round-trip
-- the maintainer asked for: not "we passed --cwd" but "the mux confirms the pane
-- landed there", which is what makes the clean pane (no visible `cd` line) real.
--
-- GUARDED: like every file under tests/integration/, this runs only when
-- WEZTERM_INTEGRATION=1 (tools/run-tests.sh). It ALSO self-skips (exit 0) when a
-- live WezTerm mux is not reachable — so a developer who exports the flag on a
-- headless box, or CI without a GUI socket, still gets a green, non-flaky run.
-- The skip is explicit and logged, never a silent pass.
--
-- Run directly:
--   WEZTERM_INTEGRATION=1 lua5.4 tests/integration/scene_cwd_integration_test.lua

local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- tests/integration -> repo root

package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

-- ---------------------------------------------------------------------------
-- tiny harness
-- ---------------------------------------------------------------------------
local passed, failed = 0, 0
local function check(label, ok, detail)
  if ok then
    passed = passed + 1
    print(string.format("  ok   - %s", label))
  else
    failed = failed + 1
    print(string.format("  FAIL - %s%s", label, detail and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local function shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function run_capture(cmd)
  local p = io.popen(cmd .. " 2>/dev/null", "r")
  if not p then return "", 1 end
  local out = p:read("*a") or ""
  local ok, _, code = p:close()
  local exit = code or (ok and 0 or 1)
  return out, exit
end

-- ---------------------------------------------------------------------------
-- SKIP GATE 1: integration flag. Mirrors the existing integration test's
-- contract — without WEZTERM_INTEGRATION=1 this file is a clean no-op exit 0.
-- (run-tests.sh already only DISCOVERS it under the flag; this guard makes a
-- direct `lua5.4 …` invocation skip cleanly too, which the plan's verify line
-- asserts.)
-- ---------------------------------------------------------------------------
if os.getenv("WEZTERM_INTEGRATION") ~= "1" then
  print("scene_cwd_integration_test: SKIP (WEZTERM_INTEGRATION != 1)")
  os.exit(0)
end

-- ---------------------------------------------------------------------------
-- SKIP GATE 2: a live mux must answer `wezterm cli list`. On a headless box /
-- no GUI socket this is unreachable; skip cleanly rather than fail.
-- ---------------------------------------------------------------------------
local list_out, list_exit = run_capture("wezterm cli list --format json")
if list_exit ~= 0 or not list_out:find("pane_id", 1, true) then
  print("scene_cwd_integration_test: SKIP (no live WezTerm mux reachable)")
  os.exit(0)
end

-- ---------------------------------------------------------------------------
-- LIVE PATH. A real mux is present.
-- ---------------------------------------------------------------------------
local dkjson = require("dkjson")

-- Decode the `file://<host>/<path>` (or `file:///<path>`) cwd URI the mux
-- reports into a bare filesystem path, URL-decoding %XX escapes. The host half
-- (OSC 7 vs OS read, per the Phase 0 cwd decision) is irrelevant to D-08 — only
-- the path must match the target.
local function cwd_uri_to_path(uri)
  if type(uri) ~= "string" then return nil end
  -- strip the scheme + authority: file://HOST  or  file://  -> leave the path.
  local path = uri:gsub("^file://[^/]*", "")
  -- URL-decode %XX.
  path = path:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  -- normalise a single trailing slash off (mux often reports a trailing /).
  if #path > 1 then path = path:gsub("/+$", "") end
  return path
end

-- Read the live topology and find a pane by id.
local function list_panes()
  local out, ex = run_capture("wezterm cli list --format json")
  if ex ~= 0 then return nil end
  local data = dkjson.decode(out)
  if type(data) ~= "table" then return nil end
  return data
end

local function find_pane(panes, pid)
  for _, p in ipairs(panes or {}) do
    if tonumber(p.pane_id) == tonumber(pid) then return p end
  end
  return nil
end

-- A real, existing target dir to spawn into (use the repo root's resolved
-- absolute path — guaranteed to exist on the live box running this).
local target, t_ex = run_capture("cd " .. shquote(repo_root) .. " && pwd -P")
target = (target or ""):gsub("%s+$", "")
check("resolved a real absolute target dir for --cwd", t_ex == 0 and target ~= "" and target:sub(1, 1) == "/", target)

-- Spawn a NEW pane (new tab in the current window) directly in <target> via the
-- EXACT clean-pane idiom cli/commands/scene.lua uses (spawn --cwd <resolved>).
local spawn_out, spawn_ex = run_capture("wezterm cli spawn --cwd " .. shquote(target))
local new_pid = (spawn_out or ""):match("%d+")
check("spawn --cwd printed a numeric pane id", spawn_ex == 0 and new_pid ~= nil,
  "exit=" .. tostring(spawn_ex) .. " out=" .. tostring(spawn_out))

if new_pid then
  -- Read the spawned pane back out of the mux and assert its cwd path == target.
  local panes = list_panes()
  local pane = find_pane(panes, new_pid)
  check("spawned pane id appears in `cli list` topology", pane ~= nil, "pid=" .. tostring(new_pid))

  if pane then
    local got = cwd_uri_to_path(pane.cwd)
    check("read-back pane cwd matches the spawn --cwd target (D-08 clean pane)",
      got == target, "got=" .. tostring(got) .. " uri=" .. tostring(pane.cwd) .. " want=" .. tostring(target))
  end

  -- Clean up the pane we created so the maintainer's session is left as found.
  run_capture("wezterm cli kill-pane --pane-id " .. shquote(new_pid))
end

-- ---------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
