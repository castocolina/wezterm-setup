-- tests/e2e/tier1/install_resolver_e2e_test.lua
--
-- Tier 1 (deterministic subcommand layer) — the POST-7e72bf5 install-cycle
-- contracts that Plan 02 deliberately DEFERRED to Wave 3 because they cannot hold
-- until the install-cycle fix (7e72bf5) + setup.sh's resolve_install_state_args
-- resolver land. This file is OWNED by Plan 04: it asserts the two contracts that
-- only become TRUE after the resolver ships.
--
--   (a) NO-FLAG-DEFAULT non-interactive reinstall -> exit 0:
--       over an existing managed block, the non-interactive install-state path
--       driven THROUGH setup.sh's resolve_install_state_args (no explicit flag, no
--       TTY) resolves to --force and yields exit 0 + EXACTLY ONE managed block.
--       Pre-7e72bf5 this path returned exit 3 (D-03 never-silently-overwrite);
--       Plan 02's install_cycle file asserts only the EXPLICIT --force reinstall.
--
--   (b) dist/wez UNINSTALL FALLBACK -> exit 0:
--       with no `wez` on PATH and none at the scratch WEZ_BIN_DIR but the built
--       repo-local `tools/../dist/wez` present, tools/uninstall.sh falls through to
--       the dist/wez fallback (7e72bf5, bug 2), delegates removal to the dev build,
--       and exits 0 (the managed block is removed). Plan 02's install_cycle file
--       asserted the pre-7e72bf5 exit-1 "already gone" warn; THIS file asserts the
--       post-7e72bf5 exit-0 fallback.
--
-- ISOLATION (T-06.6-06): every assertion touches ONLY a scratch HOME + scratch
-- WEZTERM_CONFIG_FILE + scratch WEZ_BIN_DIR — exactly like install_cycle. The user's
-- real ~/.config/wezterm/wezterm.lua and installed wez binary are NEVER touched.
--
-- WEZ_BIN discipline (D-10 / Plan 02 SUMMARY): the harness exports WEZ_BIN=./dist/wez
-- (RELATIVE), which the front door's resolve_cli_path picks up FIRST and could
-- os.remove as the uninstall target. Every install-state/uninstall subprocess here
-- runs with `env -u WEZ_BIN` (or env -i, which has no WEZ_BIN) so the front door
-- falls back to a real, absolute path instead of a self-deleting relative one.
--
-- Run directly:  WEZ_BIN=./dist/wez lua5.4 tests/e2e/tier1/install_resolver_e2e_test.lua

-- package.path bootstrap (three `..` -> repo root; + harness lib + cli/vendor).
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../../.." -- tests/e2e/tier1 -> repo root (three ..)
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/tests/e2e/lib/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local h = require("harness")
local check = h.check
local run_capture = h.run_capture
local run_capture_all = h.run_capture_all
local shquote = h.shquote
local scratch_dir = h.scratch_dir

-- Resolve an ABSOLUTE repo root so the env-prefixed runs (which set a scratch HOME)
-- still find the in-repo tools/ + the dist launcher regardless of CWD.
local ABS_REPO = (run_capture("cd " .. shquote(repo_root) .. " && pwd")):gsub("%s+$", "")
if ABS_REPO == "" then ABS_REPO = repo_root end
local ABS_DIST_WEZ = ABS_REPO .. "/dist/wez"
local SETUP_SH = ABS_REPO .. "/tools/setup.sh"
local UNINSTALL_SH = ABS_REPO .. "/tools/uninstall.sh"

local function read_bytes(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local data = fh:read("*a")
  fh:close()
  return data
end
local function rmrf(dir)
  os.execute("rm -rf " .. shquote(dir))
end
local function count_blocks(text)
  local _, n = (text or ""):gsub(">>> wezterm%-setup managed block >>>", "")
  return n
end

-- ===========================================================================
-- (a) NO-FLAG-DEFAULT reinstall (exit 0) — driven through the resolver.
--   1. fresh install-state --force creates exactly one managed block.
--   2. source setup.sh's resolve_install_state_args (no explicit flag, nontty) to
--      get the args it would hand install-state -> must be `--force` (the safe
--      non-interactive default the resolver injects when the user passes no flag).
--   3. reinstall over the existing block with THOSE RESOLVED args -> exit 0 AND
--      still exactly one managed block (the no-op-safe reinstall that returned
--      exit 3 before 7e72bf5).
-- ===========================================================================
do
  local home = scratch_dir("e2e-resolver-reinstall")
  local cfgdir = home .. "/.config/wezterm"
  os.execute("mkdir -p " .. shquote(cfgdir))
  local cfg = cfgdir .. "/wezterm.lua"
  do
    local c = io.open(cfg, "wb"); c:write("return {}\n"); c:close()
  end

  -- 1. Fresh install -> one managed block.
  local out_fresh, exit_fresh = run_capture_all(
    "env -u WEZ_BIN HOME=" .. shquote(home)
      .. " WEZTERM_CONFIG_FILE=" .. shquote(cfg)
      .. " " .. shquote(ABS_DIST_WEZ) .. " install-state --force < /dev/null")
  check("resolver: fresh install-state --force (exit 0)", exit_fresh == 0,
    "exit=" .. tostring(exit_fresh) .. " out=" .. out_fresh)
  check("resolver: fresh install staged exactly one managed block",
    count_blocks(read_bytes(cfg)) == 1,
    "blocks=" .. tostring(count_blocks(read_bytes(cfg))))

  -- 2. Resolve the no-flag/no-TTY args via setup.sh's resolver (sourced under its
  --    BASH_SOURCE/$0 guard, so the installer body does NOT run). WEZ_INSTALL_STATE_MODE
  --    is cleared so the resolver's own --force default is what we observe.
  local resolved = (run_capture(
    "bash -c " .. shquote(
      "set -u; source " .. shquote(SETUP_SH)
        .. "; WEZ_INSTALL_STATE_MODE= resolve_install_state_args 0 nontty")
      .. " 2>/dev/null")):gsub("%s+$", "")
  check("resolver: no-flag + non-TTY resolves to --force (the injected default)",
    resolved == "--force", "resolved=[" .. resolved .. "]")

  -- 3. Reinstall over the existing block using the RESOLVED args (the no-flag
  --    default path) -> exit 0 + still exactly one managed block.
  local out_re, exit_re = run_capture_all(
    "env -u WEZ_BIN HOME=" .. shquote(home)
      .. " WEZTERM_CONFIG_FILE=" .. shquote(cfg)
      .. " " .. shquote(ABS_DIST_WEZ) .. " install-state " .. resolved .. " < /dev/null")
  check("resolver: no-flag-DEFAULT reinstall over an existing block -> exit 0 (post-7e72bf5)",
    exit_re == 0, "exit=" .. tostring(exit_re) .. " out=" .. out_re)
  check("resolver: no-flag-DEFAULT reinstall keeps exactly one managed block",
    count_blocks(read_bytes(cfg)) == 1,
    "blocks=" .. tostring(count_blocks(read_bytes(cfg))))

  rmrf(home)
end

-- ===========================================================================
-- (b) dist/wez UNINSTALL FALLBACK (exit 0) — no `wez` on PATH or at WEZ_BIN_DIR,
-- but the repo-local tools/../dist/wez dev build present. uninstall.sh's third
-- fallback (7e72bf5, bug 2) delegates removal to the dev build -> exit 0 + the
-- managed block removed. env -i scrubs PATH (and WEZ_BIN) so only the dist/wez
-- fallback can resolve.
-- ===========================================================================
do
  local home = scratch_dir("e2e-resolver-uninstall-fallback")
  local emptybin = home .. "/emptybin"
  os.execute("mkdir -p " .. shquote(emptybin))
  local cfgdir = home .. "/.config/wezterm"
  os.execute("mkdir -p " .. shquote(cfgdir))
  local cfg = cfgdir .. "/wezterm.lua"
  do
    local c = io.open(cfg, "wb"); c:write("return {}\n"); c:close()
  end

  -- Stage one managed block (via the repo dev build) so the fallback's removal is
  -- observable.
  run_capture_all("env -u WEZ_BIN HOME=" .. shquote(home)
    .. " WEZTERM_CONFIG_FILE=" .. shquote(cfg)
    .. " " .. shquote(ABS_DIST_WEZ) .. " install-state --force < /dev/null")
  check("fallback: staged one managed block before uninstall",
    count_blocks(read_bytes(cfg)) == 1,
    "blocks=" .. tostring(count_blocks(read_bytes(cfg))))

  -- No `wez` on PATH, empty WEZ_BIN_DIR -> uninstall.sh falls through to the
  -- repo-local tools/../dist/wez (the 7e72bf5 third fallback). env -i has no
  -- WEZ_BIN, so the front door cannot pick up a self-deleting relative path.
  local out_u, exit_u = run_capture_all(
    "env -i HOME=" .. shquote(home)
      .. " PATH=/usr/bin:/bin"
      .. " WEZ_BIN_DIR=" .. shquote(emptybin)
      .. " WEZTERM_CONFIG_FILE=" .. shquote(cfg)
      .. " bash " .. shquote(UNINSTALL_SH))
  check("fallback: dist/wez uninstall fallback -> exit 0 (post-7e72bf5)",
    exit_u == 0, "exit=" .. tostring(exit_u) .. " out=" .. out_u)
  check("fallback: uninstall logs `using repo-local dev build`",
    out_u:find("using repo-local dev build", 1, true) ~= nil, out_u)
  check("fallback: uninstall removed the managed block",
    count_blocks(read_bytes(cfg)) == 0,
    "blocks=" .. tostring(count_blocks(read_bytes(cfg))))

  rmrf(home)
end

os.exit(h.footer())
