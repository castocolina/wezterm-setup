-- tests/e2e/tier2/scene_motd_race_e2e_test.lua
--
-- REGRESSION test for the scene-launch-motd-race debug session
-- (.planning/debug/resolved/scene-launch-motd-race.md): `wez scene new`/`scene
-- launch` fires the Phase B setup `printf` via `send-text` IMMEDIATELY after
-- Phase A creates a pane, with no wait for the pane's shell to actually be ready
-- to read stdin. On a shell whose startup takes long enough to print something
-- BEFORE it starts reading input (an MOTD banner, slow rc files), the injected
-- setup line lands as literal, unexecuted text instead of being consumed and
-- executed — reproduced live against a real bash+MOTD pane on Bazzite (see the
-- resolved debug session's Evidence section).
--
-- Tier 1/existing Tier 2 cases never caught this because their panes' shells
-- settle near-instantly (`/bin/sh` with no banner, no rc). This file
-- DETERMINISTICALLY manufactures the same race, portably and fast, by pointing
-- the mux's `default_prog` at a REAL interactive `bash --rcfile <slow-rcfile>`
-- -- i.e. bash's OWN startup does some work (sleeps, prints a fake "MOTD" banner)
-- BEFORE it ever presents its first readline prompt, exactly mirroring how a
-- real .bashrc-driven MOTD delays readiness, without depending on any
-- particular distro's actual MOTD content or timing.
--
-- WHY "ever observed", not "final state" (a design correction made while
-- writing this file — recorded here so it isn't rediscovered the hard way):
-- an earlier draft asserted the leak was gone from a SETTLED end-state
-- snapshot. That is unsound: this environment's bash, once it finally reaches
-- its first readline prompt, ends up consuming and executing the earlier-queued
-- setup line anyway (the kernel pty already delivered it as one completed
-- line), so the FINAL state looks clean whether scene.lua raced or not -- the
-- only observable difference is the DURATION of the transient window where the
-- literal, unexecuted `printf '...` text sits on screen before that delayed
-- execution happens. On unfixed code that window is as wide as the shell's
-- startup delay (~0.6s here); on fixed code send-text is never sent until the
-- shell is already at an active prompt, so the type -> execute -> self-erase
-- round trip completes far faster than this test's sampling interval and the
-- leak is never observed at all. So this test POLLS THROUGHOUT a bounded
-- window and asserts the leak text was NEVER visible in any sample, rather
-- than only checking the final snapshot.
--
-- ISOLATION (T-06.7-03, same as the sibling Tier 2 drivers): a FRESH, isolated
-- headless wezterm-mux-server under a scratch HOME/XDG_RUNTIME_DIR/
-- XDG_CONFIG_HOME/WEZTERM_CONFIG_FILE; the user's real ~/.config/wezterm and
-- running WezTerm GUI session are never touched.
--
-- Run directly:  WEZ_BIN=./dist/wez lua5.4 tests/e2e/tier2/scene_motd_race_e2e_test.lua

-- package.path bootstrap (three `..` -> repo root; identical to the sibling
-- Tier 2 drivers).
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

-- Absolute repo root / WEZ_BIN resolution (identical to the sibling drivers, so
-- a relative WEZ_BIN like ./dist/wez still resolves once this test cd's into a
-- scratch launch dir before invoking the launcher).
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
-- Whole-tier mux gate (D-03), same as the sibling Tier 2 drivers.
-- ===========================================================================
skip.require_tool(
  mux.probe,
  "tier2 scene-launch-motd-race regression",
  "wezterm-mux-server unavailable (headless mux not resolvable)")

-- A real interactive bash is required: this is the exact program the real bug
-- was reproduced against (see the debug session's Evidence), and `--rcfile`
-- needs bash specifically (not a generic /bin/sh). Loud-skip (not a silent
-- pass) if bash is absent.
local BASH_PATH = (h.run_capture("command -v bash")):gsub("%s+$", "")
if BASH_PATH == "" then
  print("tier2 scene-launch-motd-race regression: SKIPPED (reason=no bash on PATH)")
  os.exit(0)
end

-- The MOTD marker text the rcfile prints (kept for readability of failure
-- dumps; not itself asserted on -- see the file header note above).
local MOTD_MARKER = "FAKE-MOTD-BANNER-e2e-motd-race"
-- The wrapper rcfile's fixed startup delay -- the manufactured "MOTD takes this
-- long" window. Long enough to be comfortably observable by a 0.05s poll, short
-- enough to keep the whole test fast.
local RC_SLEEP_SECONDS = 0.6

-- ---------------------------------------------------------------------------
-- Write the slow-starting rcfile: sleep (simulating whatever startup work a
-- real shell's rc processing does BEFORE it starts reading stdin -- an MOTD
-- printer, slow rc files), then print the marker banner. `bash --rcfile
-- <this> -i` sources it BEFORE presenting its first readline prompt -- the
-- exact shape of a real .bashrc-driven MOTD delay.
-- ---------------------------------------------------------------------------
local function write_motd_rcfile(dir)
  local path = dir .. "/motd.rcfile"
  local fh = assert(io.open(path, "wb"))
  fh:write(table.concat({
    "sleep " .. tostring(RC_SLEEP_SECONDS),
    "printf '" .. MOTD_MARKER .. "\\n'",
    "",
  }, "\n"))
  fh:close()
  return path
end

-- ---------------------------------------------------------------------------
-- poll_for_leak(session, pid, attempts, interval) -> (leaked, sample, final)
--   leaked : true if the literal, unexecuted setup line was observed on ANY
--            sample during the window.
--   sample : the FIRST sample it was observed in (nil if never).
--   final  : the LAST sample taken (for the responsiveness/hang check).
-- Samples unconditionally for the full `attempts` budget (does NOT stop early
-- on an apparently-stable screen -- see the file header note on why "settled"
-- is not a safe stopping condition here).
-- ---------------------------------------------------------------------------
local function poll_for_leak(session, pid, attempts, interval)
  local leaked, sample, final = false, nil, nil
  for i = 1, attempts do
    local cur = mux.get_text(session, pid)
    final = cur
    if not leaked and (cur:find("printf '", 1, true) or cur:find("\\033", 1, true)) then
      leaked, sample = true, cur
    end
    os.execute("sleep " .. tostring(interval))
  end
  return leaked, sample, final
end

-- ---------------------------------------------------------------------------
-- run_case(): one fresh mux (default_prog = `bash --rcfile <slow rcfile> -i`),
-- an IMMEDIATE `wez scene new --layout tall --pane color=teal` (n=1 -> mode=
-- reuse, no Phase A spawn/split -- the reused pane IS the mux's first pane,
-- i.e. the one running the slow-starting bash), then the leak-window poll.
-- ---------------------------------------------------------------------------
local function run_case()
  print("== scene-launch-motd-race regression: reuse-mode build against a slow-starting shell ==")
  local wrapper_dir = h.scratch_dir("e2e-t2-motd-race-wrapper")
  local rcfile_path = write_motd_rcfile(wrapper_dir)

  local s = mux.spin("e2e-t2-motd-race",
    { default_prog_argv = { BASH_PATH, "--rcfile", rcfile_path, "-i" } })

  local ok_run, err = pcall(function()
    check("mux came up live with a starting pane (the slow-starting bash pane)",
      s.live and s.first_pane_id ~= nil, "live=" .. tostring(s.live))
    if not s.live or s.first_pane_id == nil then return end

    -- Drive the launcher UNDER TEST against THIS mux, IMMEDIATELY (no settle
    -- delay here -- that absence IS the race being tested; any waiting must come
    -- from inside scene.lua's own readiness gate). WEZTERM_PANE points at the
    -- bash pane (the mux's only pane -> mode=reuse, n=1 -> zero Phase A calls,
    -- so this exercises ONLY the Phase B readiness-gate + send-text path).
    local launch_cmd = string.format(
      "cd %s && %s WEZTERM_PANE=%d %s scene new --layout tall --pane %s",
      shquote(s.launch_dir), s.env, tonumber(s.first_pane_id),
      shquote(WEZ_ABS), shquote("color=teal"))
    local out, code = h.run_capture_all(launch_cmd)
    check("`scene new` exited 0 against the slow-starting pane (no hang/abort)", code == 0,
      "code=" .. tostring(code) .. " out=" .. tostring(out))

    -- Poll THROUGHOUT the race window (0.05s x 60 = 3s -- comfortably above the
    -- rcfile's fixed 0.6s delay AND the fix's own 2s internal readiness-poll
    -- cap), recording whether the literal unexecuted setup line was EVER
    -- visible. This is the driving assertion (see the file header note): a
    -- fixed build never shows it at all; a racy build shows it for
    -- (approximately) the rcfile's whole startup delay.
    local leaked, sample, final = poll_for_leak(s, s.first_pane_id, 60, 0.05)
    check("setup line was NEVER visible as literal unexecuted text during the race window",
      not leaked, "first_seen=" .. tostring(sample))

    -- RESPONSIVENESS / no-hang (D-04, mirrors the sibling drivers): a fresh
    -- probe pane's marker round-trips, proving the readiness-gate poll bound
    -- did not wedge the live session.
    local probe_pid = mux.spawn_pane(s)
    local marker = string.format("ZZ%d_%dZZ", os.time(), math.random(100000, 999999))
    if probe_pid then mux.send_marker(s, probe_pid, marker) end
    local alive = probe_pid ~= nil and mux.poll_until(s, function()
      return mux.get_text(s, probe_pid):find(marker, 1, true) ~= nil
    end, { attempts = 20, sleep = 0.25, label = "motd-race marker echo" })
    check("live session is responsive after the race (marker round-trips, no hang) (D-04)",
      alive == true, "probe_pid=" .. tostring(probe_pid) .. " last_pane_text=" .. tostring(final))
  end)

  mux.teardown(s)
  os.execute("rm -rf " .. shquote(wrapper_dir))
  if not ok_run then
    check("case ran without an unhandled error", false, tostring(err))
  end
end

run_case()

os.exit(h.footer())
