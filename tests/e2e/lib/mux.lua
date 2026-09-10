-- tests/e2e/lib/mux.lua
--
-- Headless wezterm-mux-server LIFECYCLE helper for the Tier 2 live-mux battery
-- (Phase 06.7). This is the SINGLE home for the "spin a fresh, isolated, headless
-- multiplexer, drive it, tear it down" incantation so every Tier 2 case file
-- (reuse-mode here in Plan 01; new-tab mode in Plan 02) consumes it WITHOUT
-- re-rolling the daemonize/socket-isolation/poll plumbing (D-03).
--
-- WHY THIS EXISTS (no in-repo analog — PATTERNS "No Analog Found"): the Tier 1
-- files are deterministic + headless and never spin their own mux. Tier 2 covers
-- the RUNNING-APPLICATION layer unit tests cannot see, which requires a live mux.
-- The exact daemonize flags + socket-isolation mechanism are this module's owned
-- discretion; the CONTRACT the case files depend on is "fresh, isolated, torn
-- down, with zero residue".
--
-- ISOLATION (threat T-06.7-03): each session points a SCRATCH HOME /
-- XDG_RUNTIME_DIR / XDG_CONFIG_HOME / WEZTERM_CONFIG_FILE at a per-case scratch
-- dir, so the mux's unix socket lives under that scratch dir and the user's REAL
-- ~/.config/wezterm and running WezTerm GUI session are NEVER touched. Every
-- `wezterm cli` call is built with the session env prefix so it targets THIS mux,
-- never the user's live session.
--
-- PURITY-ISH (mirrors harness.lua): this is a TEST utility, so it legitimately
-- shells out via harness.run_capture / os.execute and touches the scratch FS. It
-- sets NO global process env (it builds a per-command env PREFIX string instead),
-- and defines NO scene/color/title logic — this is lifecycle plumbing only.
--
-- T-06.7-01: every interpolated scratch path / pane id flows through harness
-- shquote (string paths) or an integer-coercion guard (pane ids); no scratch path
-- is ever concatenated unescaped into a command line.
-- T-06.7-04: `wezterm cli list --format json` output is decoded via the vendored
-- dkjson decoder (cli.lib.shell.decode_json), never load()/eval'd.

local harness = require("harness")
local shell = require("cli.lib.shell")

local shquote = harness.shquote
local run_capture = harness.run_capture
local decode_json = shell.decode_json

local M = {}

-- ---------------------------------------------------------------------------
-- Read one trimmed line of command output ("" on failure). Local io.popen is
-- acceptable here (this IS the test-utility layer), but the heavier capture paths
-- reuse harness.run_capture so the exit-capture idiom stays single-sourced.
-- ---------------------------------------------------------------------------
local function popen_line(cmd)
  local p = io.popen(cmd .. " 2>/dev/null", "r")
  if not p then return "" end
  local out = p:read("*l") or ""
  p:close()
  return out
end

-- Bounded fractional sleep between poll attempts (GNU + BSD `sleep` both accept a
-- decimal). Kept tiny + logged by the callers so an intermittent hang stays loud.
local function nap(secs)
  os.execute("sleep " .. tostring(secs))
end

-- ---------------------------------------------------------------------------
-- M.resolve_mux_server() -> absolute path to a runnable wezterm-mux-server, or nil.
--
-- FIRST try `command -v wezterm-mux-server` (it is on PATH on a packaged Linux
-- install). If absent, resolve it as a SIBLING next to the REAL `wezterm` binary:
-- on this project's box `wezterm` on PATH is a symlink into the nightly bundle
-- whose siblings (wezterm-mux-server / wezterm-gui / strip-ansi-escapes) are NOT
-- on PATH. This mirrors the bundle-siblings concept in tests/e2e/platform.lua. nil
-- when neither resolves.
-- ---------------------------------------------------------------------------
function M.resolve_mux_server()
  -- 1. Directly on PATH.
  local direct = popen_line("command -v wezterm-mux-server")
  if direct ~= "" then return direct end

  -- 2. Sibling of the resolved `wezterm` binary (readlink -f to follow the symlink
  --    into the bundle, then look in the same dir).
  local wez = popen_line("command -v wezterm")
  if wez == "" then return nil end
  local real = popen_line("readlink -f " .. shquote(wez))
  if real == "" then real = wez end
  local dir = real:match("^(.*)/[^/]+$")
  if not dir then return nil end
  local cand = dir .. "/wezterm-mux-server"
  -- Confirm it is executable (test -x) before returning.
  local probe = popen_line("test -x " .. shquote(cand) .. " && echo yes")
  if probe == "yes" then return cand end
  return nil
end

-- ---------------------------------------------------------------------------
-- M.probe() -> boolean: true when BOTH a `wezterm` is on PATH AND
-- resolve_mux_server() is non-nil. This is the predicate the case files pass to
-- skip.require_tool (the D-03 mux gate). Returns false (never errors) on a host
-- with neither.
-- ---------------------------------------------------------------------------
function M.probe()
  local wez = popen_line("command -v wezterm")
  if wez == "" then return false end
  return M.resolve_mux_server() ~= nil
end

-- ---------------------------------------------------------------------------
-- Build the per-session env PREFIX string (no global env mutation). Every
-- `wezterm`/`wez` invocation against this session is prefixed with it so it
-- targets THIS scratch mux and NEVER the user's real session (T-06.7-03). Each
-- value is shquoted (T-06.7-01).
-- ---------------------------------------------------------------------------
function M.env_prefix(dir)
  return table.concat({
    "HOME=" .. shquote(dir .. "/home"),
    "XDG_RUNTIME_DIR=" .. shquote(dir .. "/runtime"),
    "XDG_CONFIG_HOME=" .. shquote(dir .. "/cfg"),
    "WEZTERM_CONFIG_FILE=" .. shquote(dir .. "/cfg/wezterm.lua"),
  }, " ")
end

-- ---------------------------------------------------------------------------
-- M.spin(tag, opts) -> a session handle table:
--   { dir, launch_dir, env, pid, first_pane_id, live }
--
-- Allocates a per-case scratch dir (harness.scratch_dir), writes a MINIMAL scratch
-- WezTerm config that (a) disables the user config by living at a scratch
-- WEZTERM_CONFIG_FILE, (b) sets default_prog (a plain `/bin/sh` unless
-- opts.default_prog_argv overrides it), and (c) sets default_cwd to the scratch
-- LAUNCH dir so the mux's FIRST pane (the reuse precondition's single pane) opens
-- in the launch dir (D-08(cwd)). It then starts `wezterm-mux-server` in the
-- BACKGROUND (not --daemonize, so we capture the PID for a deterministic kill at
-- teardown — D-03 / T-06.7-02), polls `wezterm cli list` until at least one pane
-- exists (liveness, bounded), and records the first pane id (the WEZTERM_PANE the
-- reuse case drives).
--
-- opts.default_prog_argv (optional): an array of argv strings overriding the
-- pane's default program (e.g. a wrapper script that sleeps + prints a banner
-- before exec'ing an interactive shell, simulating a slow/MOTD-delayed shell
-- startup — see tests/e2e/tier2/scene_motd_race_e2e_test.lua). Each entry is
-- rendered as a single-quoted Lua string literal with embedded quotes escaped, so
-- an arbitrary caller-supplied path still produces syntactically-valid Lua.
--
-- INCANTATION NOTE (Claude's discretion, D-03): background launch + PID-file kill
-- is used instead of --daemonize + a server-side shutdown because this wezterm
-- build exposes no `cli kill-server`; killing the captured PID + rmrf of the
-- scratch dir (whose XDG_RUNTIME_DIR holds the only socket) is the deterministic,
-- residue-free teardown.
-- ---------------------------------------------------------------------------
function M.spin(tag, opts)
  opts = opts or {}
  local mux = M.resolve_mux_server()
  local dir = harness.scratch_dir(tag)
  local launch = dir .. "/launch"
  os.execute("mkdir -p " .. shquote(dir .. "/home") .. " " .. shquote(dir .. "/runtime")
    .. " " .. shquote(dir .. "/cfg") .. " " .. shquote(launch))
  -- XDG_RUNTIME_DIR must be 0700 or wezterm refuses to use it for the socket.
  os.execute("chmod 700 " .. shquote(dir .. "/runtime"))

  -- default_prog argv -> a Lua table literal, each entry single-quoted with `'`
  -- and `\` escaped (Lua string literals support `\'` regardless of the outer
  -- quote character), so a caller-supplied wrapper-script path can never break
  -- out of the generated config.
  local prog_argv = opts.default_prog_argv or { "/bin/sh" }
  local prog_items = {}
  for _, p in ipairs(prog_argv) do
    prog_items[#prog_items + 1] = "'"
      .. tostring(p):gsub("\\", "\\\\"):gsub("'", "\\'")
      .. "'"
  end

  -- Minimal scratch config. default_cwd is the launch dir so the FIRST (reused)
  -- pane already satisfies the D-08 cwd contract. front_end='Software' + no
  -- wayland keeps it headless-safe. The launch path is interpolated as a quoted
  -- Lua string literal; scratch dirs are mktemp-style (no quotes), so a plain
  -- single-quote wrap is safe.
  local cfg = table.concat({
    "return {",
    "  default_prog = { " .. table.concat(prog_items, ", ") .. " },",
    "  default_cwd = '" .. launch .. "',",
    "  check_for_updates = false,",
    "  enable_wayland = false,",
    "  front_end = 'Software',",
    "}",
    "",
  }, "\n")
  local fh = assert(io.open(dir .. "/cfg/wezterm.lua", "wb"))
  fh:write(cfg)
  fh:close()

  local env = M.env_prefix(dir)

  -- Background launch; capture the bg PID into a pid file (the `& echo $!` runs in
  -- the same /bin/sh -c that backgrounded the server).
  local pidfile = dir .. "/mux.pid"
  local logfile = dir .. "/mux.log"
  os.execute(string.format(
    "%s %s >%s 2>&1 & echo $! > %s",
    env, shquote(mux), shquote(logfile), shquote(pidfile)))

  local session = { dir = dir, launch_dir = launch, env = env, live = false }

  -- Liveness poll: bounded, loud on every retry (D-02). Wait for >=1 pane.
  local ok = M.poll_until(session, function()
    local panes = M.cli_list(session)
    return (#panes >= 1), panes
  end, { attempts = 40, sleep = 0.25, label = "mux liveness (" .. tostring(tag) .. ")" })
  session.live = ok

  -- Read the captured PID (after liveness so the file is written).
  local pid = popen_line("cat " .. shquote(pidfile))
  session.pid = pid ~= "" and pid or nil

  -- First pane id = the single pane of the single-pane tab (the reuse precondition
  -- WEZTERM_PANE). nil if the mux never came up.
  local panes = M.cli_list(session)
  session.first_pane_id = panes[1] and panes[1].pane_id or nil

  if not ok then
    print("  WARN - mux did not become live; see " .. logfile)
  end
  return session
end

-- ---------------------------------------------------------------------------
-- M.poll_until(session, predicate_fn, opts) -> (ok, last_value)
--
-- The D-02 deterministic state-poller. Re-evaluates predicate_fn (which runs a
-- `wezterm cli` read against the session env) on a BOUNDED loop until it returns
-- truthy or the attempt budget elapses. Logs EVERY retry LOUDLY so an intermittent
-- real hang stays visible, never masked (D-02). opts: { attempts=N, sleep=secs,
-- label=str }. Defaults: 40 attempts x 0.25s (~10s ceiling).
-- ---------------------------------------------------------------------------
function M.poll_until(session, predicate_fn, opts)
  opts = opts or {}
  local attempts = opts.attempts or 40
  local sleep = opts.sleep or 0.25
  local label = opts.label or "poll"
  local last
  for i = 1, attempts do
    local ok, val = predicate_fn()
    last = val
    if ok then return true, val end
    print(string.format("  retry - %s (attempt %d/%d)", label, i, attempts))
    nap(sleep)
  end
  return false, last
end

-- ---------------------------------------------------------------------------
-- M.cli_list(session) -> array of { pane_id, tab_id, cwd, user_vars, window_id,
-- is_active, is_zoomed, size = { rows, cols } } decoded from
-- `wezterm cli list --format json` run against the session env. Reuses
-- cli.lib.shell.decode_json (T-06.7-04: never eval). Returns {} on no-session /
-- decode failure so callers (e.g. the liveness poll) can branch.
-- size is nil-tolerant: if a future build omits `size`, callers see nil.
-- user_vars stays nil-tolerant (absent on this build).
-- ---------------------------------------------------------------------------
function M.cli_list(session)
  local out, code = run_capture(session.env .. " wezterm cli list --format json")
  if code ~= 0 or not out or out == "" then return {} end
  local data = decode_json(out)
  if type(data) ~= "table" then return {} end
  local panes = {}
  for _, e in ipairs(data) do
    if type(e) == "table" then
      panes[#panes + 1] = {
        pane_id = e.pane_id,
        tab_id = e.tab_id,
        cwd = e.cwd,
        user_vars = e.user_vars,
        window_id = e.window_id,
        is_active = e.is_active,
        is_zoomed = e.is_zoomed,
        size = e.size and { rows = e.size.rows, cols = e.size.cols } or nil,
      }
    end
  end
  return panes
end

-- ---------------------------------------------------------------------------
-- M.active_pane(panes) -> the first entry with is_active == true, or nil.
-- Pure function over an already-fetched panes array; no mux call.
-- is_active is per-tab (the active pane of THAT tab), not window-level focus:
-- a 3-tab session of 1-pane tabs has three is_active=true rows. Within one
-- tab that has 2+ panes, exactly one row is is_active.
-- ---------------------------------------------------------------------------
function M.active_pane(panes)
  for _, p in ipairs(panes or {}) do
    if p.is_active == true then
      return p
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- M.activate_tab(session, tab_id) wraps `wezterm cli activate-tab --tab-id`.
-- ---------------------------------------------------------------------------
function M.activate_tab(session, tab_id)
  os.execute(string.format(
    "%s wezterm cli activate-tab --tab-id %d",
    session.env, tonumber(tab_id) or -1))
end

-- ---------------------------------------------------------------------------
-- M.activate_pane(session, pane_id) wraps `wezterm cli activate-pane --pane-id`.
-- ---------------------------------------------------------------------------
function M.activate_pane(session, pane_id)
  os.execute(string.format(
    "%s wezterm cli activate-pane --pane-id %d",
    session.env, tonumber(pane_id) or -1))
end

-- ---------------------------------------------------------------------------
-- M.get_text(session, pane_id) -> the pane's visible text via
-- `wezterm cli get-text --pane-id <id>`.
-- ---------------------------------------------------------------------------
function M.get_text(session, pane_id)
  local out = run_capture(string.format(
    "%s wezterm cli get-text --pane-id %d", session.env, tonumber(pane_id) or -1))
  return out or ""
end

-- ---------------------------------------------------------------------------
-- M.send_marker(session, pane_id, marker) -> send `echo <marker>` (with a trailing
-- newline so the shell executes it) via `wezterm cli send-text --pane-id <id>
-- --no-paste` — the D-04 responsiveness probe driver. `marker` is a unique token
-- the caller generates; it is shquoted (T-06.7-01).
-- ---------------------------------------------------------------------------
function M.send_marker(session, pane_id, marker)
  local text = "echo " .. tostring(marker) .. "\n"
  os.execute(string.format(
    "%s wezterm cli send-text --pane-id %d --no-paste %s",
    session.env, tonumber(pane_id) or -1, shquote(text)))
end

-- Run a mux command that prints a new pane id on stdout (spawn / split-pane), read
-- the first token, and coerce it to an int before returning (mirrors scene.lua's
-- run_capture_pane_id idiom). Returns a number or nil.
local function capture_pane_id(cmd)
  local out = run_capture(cmd)
  local token = out and out:match("%S+")
  return token and tonumber(token) or nil
end

-- ---------------------------------------------------------------------------
-- M.spawn_pane(session) -> new pane id (a NEW TAB in window 0), opened in the
-- launch dir. Used to BUILD a precondition tab and as the recipe-agnostic
-- responsiveness probe pane.
-- ---------------------------------------------------------------------------
function M.spawn_pane(session)
  return capture_pane_id(string.format(
    "%s wezterm cli spawn --window-id 0 --cwd %s",
    session.env, shquote(session.launch_dir)))
end

-- ---------------------------------------------------------------------------
-- M.split_pane(session, pane_id, opts) -> new pane id splitting the given pane,
-- opened in the launch dir. Used to BUILD a multi-pane precondition tab
-- (e.g. the 2-pane tab the Plan 02 new-tab case needs).
--
-- opts (optional): { direction = "right"|"left"|"top"|"bottom" (default
-- "right"), percent = <int> (default 50) }. When omitted, behavior is
-- identical to the original `--right --percent 50` (existing callers unchanged).
-- ---------------------------------------------------------------------------
function M.split_pane(session, pane_id, opts)
  opts = opts or {}
  local flags = {
    right = "--right",
    left = "--left",
    top = "--top",
    bottom = "--bottom",
  }
  local dirflag = flags[opts.direction or "right"] or flags.right
  local percent = tonumber(opts.percent) or 50
  return capture_pane_id(string.format(
    "%s wezterm cli split-pane --pane-id %d %s --percent %d --cwd %s",
    session.env, tonumber(pane_id) or -1, dirflag, percent,
    shquote(session.launch_dir)))
end

-- ---------------------------------------------------------------------------
-- M.teardown(session) -> tear the mux down deterministically (T-06.7-02): kill the
-- captured server PID (idempotent — tolerant of an already-dead server), then rmrf
-- the scratch dir (which holds the only socket, so no residue survives). Safe to
-- call even if spin() never became live.
-- ---------------------------------------------------------------------------
function M.teardown(session)
  if not session then return end
  if session.pid then
    os.execute("kill " .. tostring(session.pid) .. " 2>/dev/null")
    -- Give it a brief moment to release the socket, then hard-kill if needed.
    nap(0.3)
    os.execute("kill -9 " .. tostring(session.pid) .. " 2>/dev/null")
  end
  if session.dir then
    os.execute("rm -rf " .. shquote(session.dir))
  end
end

return M
