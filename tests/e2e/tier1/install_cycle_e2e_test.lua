-- tests/e2e/tier1/install_cycle_e2e_test.lua
--
-- Tier 1 (deterministic subcommand layer) — the INSTALL-CYCLE contracts per PRD
-- Appendix A.1: seed-scenes (copy-if-absent), install-state (fresh + explicit
-- --force reinstall), uninstall (binary-present exit 0 + the dist/wez-fallback
-- exit-0 path), and update (the OFFLINE pure comparator + a bounded,
-- reachability-gated live smoke).
--
-- ISOLATION (T-06.6-06): every assertion touches ONLY scratch dirs — a scratch
-- WEZTERM_SETUP_DIR for seed-scenes, a scratch WEZTERM_CONFIG_FILE and a redirected
-- scratch HOME for install-state/uninstall, and a scratch WEZ_BIN_DIR for the
-- binary location. The user's real ~/.config/wezterm/wezterm.lua and installed wez
-- binary are NEVER touched.
--
-- WAVE-CONTRACT NOTE (traceability): this is now Wave 3 (POST-cherry-pick 7e72bf5,
-- Plan 04). The two contracts Plan 02 staged as "today's behavior" have been FLIPPED
-- by Plan 04 to their PRD A.1 END-STATE form now that 7e72bf5 + setup.sh's resolver
-- have landed:
--   (a) `uninstall` with no `wez` on PATH but the repo-local `tools/../dist/wez`
--       present -> exit 0 via the dist/wez fallback (7e72bf5, bug 2): it delegates to
--       the dev build and removes the managed block. (The GENUINELY-absent case — all
--       three fallbacks miss -> idempotent exit-0 warn — is covered by the unit test
--       tests/cli/uninstall_idempotent_test.lua, which stages an isolated copy with no
--       sibling dist/wez.) Plan 04 OWNS the dedicated post-resolver Tier 1 assertion in
--       tests/e2e/tier1/install_resolver_e2e_test.lua.
--   (b) the no-flag `--force`-DEFAULT reinstall (exit 0 with no flag) — driven through
--       setup.sh's resolve_install_state_args (7e72bf5, bug 1) — is asserted in the
--       Plan-04-owned install_resolver_e2e_test.lua. This file still asserts the
--       EXPLICIT `--force` reinstall (exit 0) as the install-state baseline.
--
-- Run directly:  WEZ_BIN=./dist/wez lua5.4 tests/e2e/tier1/install_cycle_e2e_test.lua

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
local WEZ = h.WEZ

-- Resolve an ABSOLUTE repo root so the env-prefixed runs (which set HOME / a scratch
-- CWD-independent setup dir) still find the in-repo scenes/ and the dist launcher.
local ABS_REPO = (run_capture("cd " .. shquote(repo_root) .. " && pwd")):gsub("%s+$", "")
if ABS_REPO == "" then ABS_REPO = repo_root end

-- An ABSOLUTE launcher path for the env-prefixed runs. The harness WEZ is often the
-- relative `./dist/wez` (make e2e / WEZ_BIN=./dist/wez), which breaks the instant a
-- run is prefixed with HOME=… or runs from a different CWD. Resolve a relative WEZ
-- against ABS_REPO; an absolute WEZ (or a bare `wez` on PATH) passes through.
local ABS_WEZ = WEZ
if ABS_WEZ:sub(1, 1) == "." then
  ABS_WEZ = (ABS_REPO .. "/" .. ABS_WEZ):gsub("/%./", "/")
end

-- Small FS helpers (read bytes / file presence) for the byte-identical re-run check.
local function read_bytes(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local data = fh:read("*a")
  fh:close()
  return data
end
local function file_exists(path)
  local fh = io.open(path, "rb")
  if fh then fh:close(); return true end
  return false
end
local function rmrf(dir)
  os.execute("rm -rf " .. shquote(dir))
end

-- ===========================================================================
-- seed-scenes: copy-if-absent into a scratch WEZTERM_SETUP_DIR, then a byte-
-- identical re-run (keep-existing). The in-repo scenes/ is the seed source.
-- ===========================================================================
do
  local setup = scratch_dir("e2e-seed")
  local src = ABS_REPO .. "/scenes"
  local env = "WEZTERM_SETUP_DIR=" .. shquote(setup)
    .. " WEZ_SEED_SRC_DIR=" .. shquote(src) .. " "

  local out1, exit1 = run_capture_all(env .. shquote(WEZ) .. " seed-scenes")
  check("`seed-scenes` first run (exit 0)", exit1 == 0, "exit=" .. tostring(exit1) .. " out=" .. out1)

  local scenes = setup .. "/scenes"
  local recipes = { "ai", "dev", "docker" }
  for _, name in ipairs(recipes) do
    check("seed-scenes copied " .. name .. ".toml", file_exists(scenes .. "/" .. name .. ".toml"))
  end

  -- Capture bytes, re-run, assert byte-identical (copy-if-absent keeps existing).
  local before = read_bytes(scenes .. "/dev.toml")
  local out2, exit2 = run_capture_all(env .. shquote(WEZ) .. " seed-scenes")
  check("`seed-scenes` re-run (exit 0)", exit2 == 0, "exit=" .. tostring(exit2) .. " out=" .. out2)
  local after = read_bytes(scenes .. "/dev.toml")
  check("seed-scenes re-run keeps dev.toml byte-identical (copy-if-absent)",
    before ~= nil and before == after)
  check("seed-scenes re-run reports 'kept existing' (not re-seeded)",
    out2:find("kept existing scene recipe: dev", 1, true) ~= nil, out2)

  rmrf(setup)
end

-- ===========================================================================
-- install-state: ISOLATE the config target via WEZTERM_CONFIG_FILE (the seam
-- config_path() honors) under a scratch HOME — never the user's real wezterm.lua.
-- Fresh install -> exit 0 + one managed block; explicit --force reinstall -> exit 0
-- + exactly one block. A no-flag/no-TTY reinstall returns exit 3 today (D-03); the
-- no-flag-default exit 0 is a Plan 04 contract, NOT asserted here.
-- ===========================================================================
do
  local home = scratch_dir("e2e-install")
  local cfg = home .. "/wezterm.lua"
  -- Seed a minimal valid config so injection has a `return` to wrap.
  local seed = io.open(cfg, "wb")
  seed:write("return {}\n")
  seed:close()

  local env = "HOME=" .. shquote(home)
    .. " WEZTERM_CONFIG_FILE=" .. shquote(cfg) .. " "

  -- Fresh install (stdin redirected from /dev/null so the no-TTY path is taken,
  -- but the block is ABSENT so it installs cleanly -> exit 0).
  local out1, exit1 = run_capture_all(env .. shquote(WEZ) .. " install-state < /dev/null")
  check("`install-state` fresh (exit 0)", exit1 == 0, "exit=" .. tostring(exit1) .. " out=" .. out1)
  local cfg_text = read_bytes(cfg) or ""
  local _, blocks = cfg_text:gsub(">>> wezterm%-setup managed block >>>", "")
  check("install-state fresh injects exactly one managed block", blocks == 1,
    "block-count=" .. tostring(blocks))

  -- Explicit --force reinstall over the present block -> exit 0, still exactly one.
  local out2, exit2 = run_capture_all(env .. shquote(WEZ) .. " install-state --force < /dev/null")
  check("`install-state --force` reinstall (exit 0)", exit2 == 0,
    "exit=" .. tostring(exit2) .. " out=" .. out2)
  local cfg_text2 = read_bytes(cfg) or ""
  local _, blocks2 = cfg_text2:gsub(">>> wezterm%-setup managed block >>>", "")
  check("install-state --force keeps exactly one managed block", blocks2 == 1,
    "block-count=" .. tostring(blocks2))

  -- A present block + no flag + no TTY returns NON-ZERO today (exit 3, D-03 never
  -- silently overwrite). Documenting the Wave-2 contract; the no-flag-default exit 0
  -- is verified in Plan 04 after setup.sh's resolver lands.
  local _, exit3 = run_capture_all(env .. shquote(WEZ) .. " install-state < /dev/null")
  check("install-state no-flag/no-TTY reinstall is non-zero today (D-03; exit 0 default is Plan 04)",
    exit3 ~= 0, "exit=" .. tostring(exit3))

  rmrf(home)
end

-- ===========================================================================
-- uninstall: driven through tools/uninstall.sh with a scratch WEZ_BIN_DIR + a
-- redirected scratch HOME so neither the user's config nor the installed binary is
-- touched. Two PRD A.1 rows (POST-7e72bf5, Plan 04):
--   (a) binary PRESENT (on PATH / WEZ_BIN_DIR)  -> exit 0 AND the managed block +
--       binary are removed.
--   (b) no `wez` on PATH or at WEZ_BIN_DIR, but the repo-local `tools/../dist/wez`
--       dev build is present -> exit 0 via the dist/wez fallback (7e72bf5, bug 2):
--       uninstall.sh delegates to the dev build and the managed block is removed.
-- The front door (`wez uninstall`) self-deletes $HOME/.local/bin/wez LAST (D-10), so
-- we stage the dummy binary there to make the removal observable in case (a).
-- ===========================================================================
do
  -- (a) binary PRESENT.
  local home = scratch_dir("e2e-uninstall")
  local bindir = home .. "/.local/bin"
  os.execute("mkdir -p " .. shquote(bindir))
  -- A dummy `wez` that delegates to the real launcher so `wez uninstall --yes` runs
  -- the engine. Staged at $HOME/.local/bin/wez (the front door's self-delete target).
  local dummy = bindir .. "/wez"
  local fh = io.open(dummy, "wb")
  fh:write("#!/usr/bin/env bash\nexec " .. shquote(ABS_REPO .. "/dist/wez") .. " \"$@\"\n")
  fh:close()
  os.execute("chmod +x " .. shquote(dummy))

  -- Stage a managed-block config under the scratch HOME (isolated via WEZTERM_CONFIG_FILE).
  local cfgdir = home .. "/.config/wezterm"
  os.execute("mkdir -p " .. shquote(cfgdir))
  local cfg = cfgdir .. "/wezterm.lua"
  local cfh = io.open(cfg, "wb")
  cfh:write("return {}\n")
  cfh:close()
  run_capture_all("HOME=" .. shquote(home)
    .. " WEZTERM_CONFIG_FILE=" .. shquote(cfg)
    .. " " .. shquote(dummy) .. " install-state --force < /dev/null")
  local before = read_bytes(cfg) or ""
  local _, blocks_before = before:gsub(">>> wezterm%-setup managed block >>>", "")

  -- IMPORTANT: clear WEZ_BIN for this run. The harness exports WEZ_BIN=./dist/wez
  -- (a RELATIVE path) which would otherwise leak into the front door's
  -- resolve_cli_path ($WEZ_BIN wins) and make the D-10 self-delete target the wrong
  -- (non-existent) relative path. With WEZ_BIN unset, cli_path falls back to
  -- $HOME/.local/bin/wez — the dummy we staged — so the self-delete is observable.
  local out_p, exit_p = run_capture_all(
    "env -u WEZ_BIN HOME=" .. shquote(home)
      .. " PATH=" .. shquote(bindir) .. ":/usr/bin:/bin"
      .. " WEZ_BIN_DIR=" .. shquote(bindir)
      .. " WEZTERM_CONFIG_FILE=" .. shquote(cfg)
      .. " bash " .. shquote(ABS_REPO .. "/tools/uninstall.sh"))
  check("uninstall (binary PRESENT) staged one block before the run", blocks_before == 1,
    "block-count=" .. tostring(blocks_before))
  check("`uninstall` with the binary present (exit 0)", exit_p == 0,
    "exit=" .. tostring(exit_p) .. " out=" .. out_p)
  local after = read_bytes(cfg) or ""
  local _, blocks_after = after:gsub(">>> wezterm%-setup managed block >>>", "")
  check("uninstall (binary present) removed the managed block", blocks_after == 0,
    "block-count=" .. tostring(blocks_after))
  check("uninstall (binary present) removed the $HOME/.local/bin/wez binary (D-10 self-delete)",
    not file_exists(dummy))

  rmrf(home)

  -- (b) no `wez` on PATH and none at the scratch WEZ_BIN_DIR, but the repo-local
  -- `tools/../dist/wez` dev build IS present -> the dist/wez fallback (7e72bf5, bug 2)
  -- delegates removal to the dev build (exit 0 + managed block removed). Stage a
  -- managed-block config so the removal is observable. WEZ_BIN is unset (env -i) so
  -- the front door's resolve_cli_path does not pick up a relative ./dist/wez.
  local home2 = scratch_dir("e2e-uninstall-absent")
  local emptybin = home2 .. "/emptybin"
  os.execute("mkdir -p " .. shquote(emptybin))
  local cfg2dir = home2 .. "/.config/wezterm"
  os.execute("mkdir -p " .. shquote(cfg2dir))
  local cfg2 = cfg2dir .. "/wezterm.lua"
  do
    local c2 = io.open(cfg2, "wb"); c2:write("return {}\n"); c2:close()
  end
  -- Stage one managed block via the repo dev build (under the scratch HOME/config).
  run_capture_all("env -u WEZ_BIN HOME=" .. shquote(home2)
    .. " WEZTERM_CONFIG_FILE=" .. shquote(cfg2)
    .. " " .. shquote(ABS_REPO .. "/dist/wez") .. " install-state --force < /dev/null")
  local before2 = read_bytes(cfg2) or ""
  local _, blocks_before2 = before2:gsub(">>> wezterm%-setup managed block >>>", "")
  -- env -i scrubs PATH so the host `wez` cannot be found; restore a minimal PATH.
  -- No `wez` on PATH and an EMPTY WEZ_BIN_DIR -> uninstall.sh falls through to the
  -- repo-local `tools/../dist/wez` (the third fallback that 7e72bf5 added).
  local out_a, exit_a = run_capture_all(
    "env -i HOME=" .. shquote(home2)
      .. " PATH=/usr/bin:/bin"
      .. " WEZ_BIN_DIR=" .. shquote(emptybin)
      .. " WEZTERM_CONFIG_FILE=" .. shquote(cfg2)
      .. " bash " .. shquote(ABS_REPO .. "/tools/uninstall.sh"))
  check("uninstall (no PATH/bindir wez) staged one block before the run", blocks_before2 == 1,
    "block-count=" .. tostring(blocks_before2))
  check("`uninstall` via the dist/wez fallback -> exit 0 (7e72bf5, Plan 04 post-resolver)",
    exit_a == 0, "exit=" .. tostring(exit_a) .. " out=" .. out_a)
  check("uninstall (dist/wez fallback) logs `using repo-local dev build`",
    out_a:find("using repo-local dev build", 1, true) ~= nil, out_a)
  local after2 = read_bytes(cfg2) or ""
  local _, blocks_after2 = after2:gsub(">>> wezterm%-setup managed block >>>", "")
  check("uninstall (dist/wez fallback) removed the managed block", blocks_after2 == 0,
    "block-count=" .. tostring(blocks_after2))

  rmrf(home2)
end

-- ===========================================================================
-- update: assert the PURE comparator OFFLINE via a child lua5.4 -e (no ungated
-- network call). decide_wez_update is a string/numeric compare only.
--   * decide_wez_update(M.VERSION, "", "user")       == "current"     (no published
--                                                       release / already-latest no-op)
--   * decide_wez_update(M.VERSION, "v9.9.9", "system") == "system-skip" (P6-D09 guard
--                                                       wins FIRST, before any compare)
-- THEN an OPTIONAL live `wez update` smoke gated behind a bounded reachability probe;
-- on probe failure soft_skip LOUDLY (never a silent pass, never a hang).
-- ===========================================================================
do
  local body =
    "package.path=" .. string.format("%q", repo_root .. "/?.lua;" .. repo_root .. "/cli/vendor/?.lua;")
      .. "..package.path;"
      .. "local u=require('cli.commands.update');"
      .. "local sp=require('cli.spec');"
      .. "io.write('CURRENT='..u.decide_wez_update(sp.VERSION,'','user')..'\\n');"
      .. "io.write('SYSSKIP='..u.decide_wez_update(sp.VERSION,'v9.9.9','system')..'\\n');"
  local out, exit = run_capture_all("lua5.4 -e " .. shquote(body))
  check("update comparator child ran (exit 0)", exit == 0, "exit=" .. tostring(exit) .. " out=" .. out)
  check("decide_wez_update(no published release) -> 'current'",
    out:find("CURRENT=current", 1, true) ~= nil, out)
  check("decide_wez_update(system install) -> 'system-skip' (P6-D09 guard wins first)",
    out:find("SYSSKIP=system-skip", 1, true) ~= nil, out)

  -- Optional live smoke: bounded reachability probe; only on success do we drive a
  -- live `wez update`, asserting exit 0 + a known no-op/up-to-date message token. On
  -- a failed probe (offline box / CI without egress) soft_skip LOUDLY.
  local _, reachable = run_capture("curl -fsS --max-time 3 https://api.github.com")
  if reachable == 0 then
    -- Run in an isolated scratch HOME with WEZ_RELEASE_TAG empty so the wez half is a
    -- clean no-op; the WezTerm half is a system install (system-skip) on this host, so
    -- the command reports a non-destructive no-op and exits 0 WITHOUT delegating to a
    -- real installer (no fetch/place/self-replace can run).
    local home = scratch_dir("e2e-update")
    local out_u, exit_u = run_capture_all(
      "env -u WEZ_BIN HOME=" .. shquote(home) .. " WEZ_RELEASE_TAG= "
        .. shquote(ABS_WEZ) .. " update")
    check("live `wez update` smoke (reachable) -> exit 0", exit_u == 0,
      "exit=" .. tostring(exit_u) .. " out=" .. out_u)
    check("live `wez update` smoke -> a no-op / up-to-date / system-skip message",
      out_u:find("nothing to do", 1, true) ~= nil
        or out_u:find("leaving it untouched", 1, true) ~= nil
        or out_u:find("current", 1, true) ~= nil, out_u)
    rmrf(home)
  else
    print("  skip - live `wez update` smoke  (api.github.com not reachable within 3s; "
      .. "offline box / no egress — comparator asserted offline above)")
  end
end

os.exit(h.footer())
