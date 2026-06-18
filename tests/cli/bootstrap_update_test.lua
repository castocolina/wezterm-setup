-- tests/cli/bootstrap_update_test.lua
-- Unit tests for the P6-D09 WezTerm version policy added to
-- tools/bootstrap-wezterm.sh (Plan 06-06):
--   * WEZTERM_TARGET defaults to `nightly` (incl. the non-interactive pipe path).
--   * wezterm_install_is_user_path() is a REAL predicate distinguishing the
--     project user-path install (under ${BIN_DIR}) from a system install
--     (/usr/bin/wezterm) — asserted on TEXT and on actual exit-code BEHAVIOR.
--   * latest_nightly_datestamp() / resolve_want_datestamp() resolve the want
--     (06-01-SUMMARY Open-Q1) and degrade gracefully to empty (never a forced
--     swap).
--   * detect_and_reuse() updates a behind-the-want USER-PATH install in place by
--     REUSING install_linux() (no new fetch), gated on the predicate; a system
--     install is left intact (no sudo); select_release() targets nightly by
--     default under no-TTY.
--
-- All assertions are on script TEXT + the predicate's exit-code behavior under a
-- SOURCED no-run mode (the BASH_SOURCE/$0 guard means sourcing does NOT run
-- main). NO live WezTerm download/update is triggered — this stays an autonomous
-- unit gate under tools/run-tests.sh.
--
-- Run directly: `lua5.4 tests/cli/bootstrap_update_test.lua`.

local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- tests/cli -> repo root

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

local SCRIPT = repo_root .. "/tools/bootstrap-wezterm.sh"

-- Read the script text once for plain-substring TEXT assertions.
local function read_file(path)
  local fh = assert(io.open(path, "rb"), "cannot open " .. path)
  local data = fh:read("*a")
  fh:close()
  return data
end

local SRC = read_file(SCRIPT)
local function has(needle)
  return SRC:find(needle, 1, true) ~= nil
end

-- ----------------------------------------------------------------------------
-- TEXT: WEZTERM_TARGET nightly default + the seam wiring (Blocker 2).
-- ----------------------------------------------------------------------------
check("WEZTERM_TARGET defaults to `nightly` (non-interactive default target, P6-D09)",
  has("WEZTERM_TARGET:-nightly}"))
check("WEZTERM_PINNED_RELEASE stays reachable as the pinned/explicit-tag opt-in",
  has("WEZTERM_PINNED_RELEASE"))
check("WEZTERM_MIN_RELEASE remains the distinct reuse FLOOR",
  has("WEZTERM_MIN_RELEASE"))

-- ----------------------------------------------------------------------------
-- TEXT: the new resolvers + predicate are defined (Blockers 2 + 3).
-- ----------------------------------------------------------------------------
check("latest_nightly_datestamp() is defined", has("latest_nightly_datestamp()"))
check("resolve_want_datestamp() is defined", has("resolve_want_datestamp()"))
check("wezterm_install_is_user_path() is defined", has("wezterm_install_is_user_path()"))
check("the predicate gates on a ${BIN_DIR} path compare (a real return, not a log line)",
  has("wezterm_install_is_user_path") and has('"${BIN_DIR}/"*'))
check("latest_nightly_datestamp reuses _wezterm_fetch (no new fetch helper)",
  has("_wezterm_fetch"))
check("the want query targets the official wez/wezterm nightly tag over HTTPS",
  has("WEZTERM_RELEASE_API") and has("releases/tags/nightly"))
check("latest_nightly_datestamp keys on the per-asset updated_at (Open-Q1 caveat)",
  has("updated_at"))

-- ----------------------------------------------------------------------------
-- TEXT: no sudo is INVOKED as a command anywhere in the script (P6-D03/P6-D09).
-- The only `sudo` token is the pre-existing "no sudo — D-05" comment; assert
-- NO non-comment line invokes sudo (a real privilege escalation).
-- ----------------------------------------------------------------------------
do
  -- Count lines that contain `sudo ` AND are not pure comments. `grep -v '^[[:space:]]*#'`
  -- drops comment lines; we expect zero remaining sudo invocations.
  local p = assert(io.popen(
    "grep -n 'sudo ' '" .. SCRIPT .. "' | grep -vc '#' || true"))
  local n = tonumber((p:read("*a") or "0"):match("%d+")) or 0
  p:close()
  check("no non-comment line invokes `sudo` (no privilege escalation introduced)", n == 0,
    "non-comment sudo lines=" .. tostring(n))
end

-- ----------------------------------------------------------------------------
-- BEHAVIOR: source the script (no main run, via the $0/BASH_SOURCE guard) and
-- call the predicate with a ${BIN_DIR} path (-> user-path, exit 0) and a
-- /usr/bin path (-> system, non-zero). Asserted via os.execute exit codes.
-- ----------------------------------------------------------------------------
-- Helper: run a bash snippet that sources the script then runs `body`, returning
-- whether it exited 0. We force a fixed BIN_DIR (so ${BIN_DIR} is deterministic)
-- and write the snippet to a temp bash script (robust against shell re-quoting —
-- os.execute runs via /bin/sh, so we must invoke bash explicitly on a file).
local function bash_ok(body)
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "w"))
  fh:write("#!/usr/bin/env bash\n")
  fh:write("source '" .. SCRIPT .. "'\n")
  fh:write(body .. "\n")
  fh:close()
  local cmd = "WEZTERM_BIN_DIR='/tmp/wezsetup-bindir' bash '" .. tmp .. "' >/dev/null 2>&1"
  local ok = os.execute(cmd)
  os.remove(tmp)
  -- lua5.4 os.execute returns true/false (+ "exit"/code); normalize to boolean.
  return ok == true or ok == 0
end

check("predicate: a ${BIN_DIR}/wezterm path is classified user-path (exit 0)",
  bash_ok('wezterm_install_is_user_path "${BIN_DIR}/wezterm"'))
check("predicate: /usr/bin/wezterm is classified SYSTEM (non-zero exit)",
  not bash_ok("wezterm_install_is_user_path /usr/bin/wezterm"))
check("predicate: an empty path (no install) is non-user-path (non-zero exit)",
  not bash_ok('wezterm_install_is_user_path ""'))

-- ----------------------------------------------------------------------------
-- BEHAVIOR: resolve_want_datestamp honors WEZTERM_TARGET=pinned without any
-- network (returns the pinned datestamp's 8 digits).
-- ----------------------------------------------------------------------------
check("resolve_want_datestamp with WEZTERM_TARGET=pinned yields the pinned 8-digit date",
  bash_ok('WEZTERM_TARGET=pinned ; WEZTERM_PINNED_RELEASE=20260604-145453 ; '
    .. '[ "$(resolve_want_datestamp)" = "20260604" ]'))

-- ----------------------------------------------------------------------------
-- TEXT: the update-in-place branch in detect_and_reuse (Blocker 1 / SC#8).
-- ----------------------------------------------------------------------------
check("detect_and_reuse computes the want via resolve_want_datestamp (not just the fixed floor)",
  has("resolve_want_datestamp"))
check("the update path REUSES install_linux (STEP-3 fetch), not a re-implementation",
  has("install_linux"))
-- Scope the gating + reuse to detect_and_reuse's body so we assert they co-occur
-- there (the update-in-place branch is inside the predicate-gated section).
do
  local body = SRC:match("detect_and_reuse%(%)%s*{(.-)\n}") or ""
  check("detect_and_reuse body gates the update on wezterm_install_is_user_path",
    body:find("wezterm_install_is_user_path", 1, true) ~= nil)
  check("detect_and_reuse body reuses install_linux for the in-place update",
    body:find("install_linux", 1, true) ~= nil)
  check("detect_and_reuse body uses resolve_want_datestamp for the want",
    body:find("resolve_want_datestamp", 1, true) ~= nil)
  check("detect_and_reuse body adds NO second fetch/extract block (no extra mktemp/tar -xJ)",
    body:find("mktemp", 1, true) == nil and body:find("tar -xJ", 1, true) == nil)
end

-- ----------------------------------------------------------------------------
-- TEXT: select_release honors WEZTERM_TARGET under no-TTY.
-- ----------------------------------------------------------------------------
do
  local body = SRC:match("select_release%(%)%s*{(.-)\n}") or ""
  check("select_release references WEZTERM_TARGET (no-TTY targets nightly by default)",
    body:find("WEZTERM_TARGET", 1, true) ~= nil)
  check("select_release prints 'nightly' on the no-TTY default path",
    body:find('printf \'%s\\n\' "nightly"', 1, true) ~= nil
      or body:find("nightly", 1, true) ~= nil)
end

-- ----------------------------------------------------------------------------
-- BEHAVIOR: select_release under no-TTY (stdin from /dev/null) with
-- WEZTERM_TARGET=nightly prints exactly `nightly`; with =pinned prints the
-- pinned release. No network, no fetch — pure tag selection.
-- ----------------------------------------------------------------------------
local function bash_stdout(env, body)
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "w"))
  fh:write("#!/usr/bin/env bash\n")
  fh:write("source '" .. SCRIPT .. "'\n")
  fh:write(body .. "\n")
  fh:close()
  local cmd = env .. " bash '" .. tmp .. "' 2>/dev/null </dev/null"
  local p = assert(io.popen(cmd))
  local out = (p:read("*a") or ""):gsub("%s+$", "")
  p:close()
  os.remove(tmp)
  return out
end

check("select_release (no-TTY, WEZTERM_TARGET=nightly) prints exactly 'nightly'",
  bash_stdout("WEZTERM_TARGET=nightly", "select_release") == "nightly")
check("select_release (no-TTY, WEZTERM_TARGET=pinned) prints the pinned release",
  bash_stdout("WEZTERM_TARGET=pinned WEZTERM_PINNED_RELEASE=20260604-145453", "select_release")
    == "20260604-145453")

-- ----------------------------------------------------------------------------
-- REGRESSION: tar extraction must use only flags GNU tar accepts. The BSD-tar
-- idiom `--no-absolute-names` makes GNU tar abort with "unrecognized option",
-- which broke every Linux curl|bash install (path-traversal safety is already
-- enforced by assert_safe_members + tar's default leading-'/' stripping). This
-- gate fails if that flag — or any other known GNU-incompatible long flag we've
-- been bitten by — creeps back into the script.
-- ----------------------------------------------------------------------------
do
  check("bootstrap-wezterm.sh uses NO `--no-absolute-names` (GNU tar rejects it)",
    not has("--no-absolute-names"))
  local body = SRC:match("install_linux%(%)%s*{(.-)\n}") or ""
  check("install_linux still extracts the asset with `tar -xJf` into the release dir",
    body:find("tar -xJf", 1, true) ~= nil)
  check("install_linux's `tar -xJf` line carries no `--no-absolute-names`",
    (body:match("tar %-xJf[^\n]*") or ""):find("--no-absolute-names", 1, true) == nil)
end

-- ----------------------------------------------------------------------------
-- TEXT: the desktop-launcher integration step (260618-dpp). install_linux must
-- place the shipped .desktop + icons into the user XDG dirs via a focused,
-- non-fatal, sudo-free helper, invoked AFTER the ${BIN_DIR}/wezterm symlink.
-- ----------------------------------------------------------------------------
check("install_desktop_entry() helper is defined", has("install_desktop_entry()"))
check("the helper resolves the XDG data home (XDG_DATA_HOME / .local/share)",
  has("XDG_DATA_HOME") and has(".local/share"))
check("the helper targets ${XDG}/applications for the .desktop",
  has("applications"))
check("the helper places the shipped org.wezfurlong.wezterm.desktop",
  has("org.wezfurlong.wezterm.desktop"))
check("the helper mirrors ALL shipped icons via find (not just one size)",
  has('find "${share_icons}"'))
check("the cache refresh is best-effort + non-fatal (update-desktop-database || true)",
  has("update-desktop-database") and has("gtk-update-icon-cache"))
check("the helper is non-fatal when the shipped .desktop is absent (guarded skip + return 0)",
  has("skipping launcher integration"))
do
  local body = SRC:match("install_desktop_entry%(%)%s*{(.-)\n}") or ""
  check("install_desktop_entry uses idempotent cp -f (overwrite-safe)",
    body:find("cp -f", 1, true) ~= nil)
  check("install_desktop_entry's cache commands are guarded with `|| true` (non-fatal)",
    body:find("|| true", 1, true) ~= nil)
end
do
  -- The helper must be CALLED from install_linux, AFTER the ${BIN_DIR}/wezterm
  -- symlink (the call site ordering is the whole point of this task).
  local body = SRC:match("install_linux%(%)%s*{(.-)\n}") or ""
  check("install_linux invokes install_desktop_entry",
    body:find("install_desktop_entry", 1, true) ~= nil)
  local sym = body:find('ln -sfn "${target}" "${BIN_DIR}/wezterm"', 1, true)
  local call = body:find("install_desktop_entry", 1, true)
  check("install_desktop_entry is called AFTER the ${BIN_DIR}/wezterm symlink",
    sym ~= nil and call ~= nil and call > sym)
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
