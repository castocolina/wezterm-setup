-- tests/integration/install_config_load_integration_test.lua
--
-- REGRESSION GUARD for the two install/config e2e bugs found during the first
-- real end-to-end install (.planning/debug/install-config-e2e.md). The existing
-- 154 unit tests passed while BOTH bugs were live, because none of them exercise
-- the install + config-load path the way WezTerm and a local `make install`
-- actually do. This integration test closes that blind spot.
--
-- It is an INTEGRATION test (lives under tests/integration/, runs only when
-- WEZTERM_INTEGRATION=1 via tools/run-tests.sh) because it shells out to a fresh
-- lua5.4 child and to tools/build.sh — heavier than the pure-fixture unit gates.
--
-- BUG 2 (config nested-require resolution):
--   The managed block injected into the user's wezterm.lua is just
--   `require('wezterm-setup').apply(config)` with NO package.path setup. Under
--   WezTerm's real resolution (only the config DIR on package.path) the entry
--   loads via the `?/init.lua` form, but config/wezterm-setup/init.lua's bare
--   `require("keybindings"/"cwd"/"format-tab-title")` then look in the config
--   ROOT, not the wezterm-setup/ subdir -> `module 'keybindings' not found` ->
--   apply() throws -> WezTerm shows a config-error window alongside the main one.
--   GUARD: stage the config tree the way setup.sh does, build the managed block
--   with install_state.inject_into_text (the REAL injected text), then in a FRESH
--   lua5.4 child with package.path = config-dir-only, run the managed block and
--   call apply on a stub config. Assert NO error.
--
-- BUG 1 (build.sh path order):
--   A LOCAL source build must never hit the network. On a box with lua5.4 but no
--   luastatic, build.sh used to attempt download_release() (placeholder remote
--   base) before the dev launcher. GUARD: run tools/build.sh with luastatic
--   forced absent and WEZ_REMOTE_BOOTSTRAP unset, pointing WEZ_RELEASE_BASE at an
--   unreachable host; assert the output never takes the release-download path and
--   that it produces a runnable dev launcher.
--
-- Run directly:  WEZTERM_INTEGRATION=1 lua5.4 tests/integration/install_config_load_integration_test.lua

local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- tests/integration -> repo root

package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local IS = require("cli.commands.install_state")

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

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Run a command, capture combined stdout+stderr and the exit status.
local function run_capture(cmd)
  local p = assert(io.popen(cmd .. " 2>&1", "r"))
  local out = p:read("*a") or ""
  local ok, _, code = p:close()
  -- Lua 5.4 io.popen close -> (ok, "exit", code)
  local exit = code or (ok and 0 or 1)
  return out, exit
end

local function mkdtemp()
  local out = run_capture("mktemp -d")
  return (out:gsub("%s+$", ""))
end

local function write_file(path, data)
  local fh = assert(io.open(path, "wb"))
  fh:write(data)
  fh:close()
end

local function rmrf(path)
  os.execute("rm -rf -- " .. shquote(path))
end

local function file_exists(path)
  local fh = io.open(path, "rb")
  if fh then fh:close(); return true end
  return false
end

-- ===========================================================================
-- BUG 2 GUARD — managed block loads under WezTerm-like resolution with no error
-- ===========================================================================
do
  local scratch = mkdtemp()
  -- 1. Stage the config tree exactly the way setup.sh STEP 4 does:
  --    config/wezterm-setup/  ->  <config-dir>/wezterm-setup/
  local config_dir = scratch .. "/wezterm"
  os.execute("mkdir -p " .. shquote(config_dir .. "/wezterm-setup"))
  os.execute("cp -R " .. shquote(repo_root .. "/config/wezterm-setup/.")
    .. " " .. shquote(config_dir .. "/wezterm-setup/"))

  -- 2. Build the REAL managed block the installer injects into a user's config
  --    (Shape A: `require('wezterm-setup').apply(config)`), via the SAME canonical
  --    builder the installer uses (M.managed_block), referencing the stub's `config`
  --    identifier. This is the exact line that was failing in production. We embed
  --    ONLY the managed block (not a whole synthetic wezterm.lua) so the child runs
  --    our stub config through the real require+apply, not a fixture's `return`.
  local injected = IS.managed_block("config")
  check("managed_block builds the injected block", injected ~= nil)
  check("managed block calls require('wezterm-setup')",
    injected and injected:find("require('wezterm-setup')", 1, true) ~= nil, "block content")
  -- Sanity: inject_into_text emits the SAME block when anchoring a `return config`
  -- (so this guard tracks the real injection path, not a drifted copy).
  do
    local whole = IS.inject_into_text("local config = {}\nreturn config\n") or ""
    check("inject_into_text emits the same managed block (Shape A)",
      whole:find(injected, 1, true) ~= nil, whole)
  end

  -- 3. Drive it in a FRESH lua5.4 child whose package.path mimics WezTerm: only
  --    the config DIR is on the path (the `?.lua` and `?/init.lua` forms), and
  --    NOTHING from the repo or this harness leaks in. The child runs the exact
  --    injected managed block against a stub `config` table and reports success
  --    only if require + apply both complete with no error.
  local driver = table.concat({
    "local cfgdir = arg[1]",
    -- Emulate WezTerm's embedded Lua sandbox: it does NOT expose the `debug`
    -- library. plain lua5.4 DOES, which is exactly why an earlier `debug.getinfo`
    -- self-bootstrap fix passed this test yet crashed live with
    -- `attempt to index a nil value (global 'debug')`. Niling it here makes the
    -- guard fail on any config-layer code that reaches for a WezTerm-absent global.
    "debug = nil",
    -- WezTerm-like resolution: config dir only, ?.lua then ?/init.lua.
    'package.path = cfgdir.."/?.lua;"..cfgdir.."/?/init.lua"',
    -- A stub config table standing in for wezterm.config_builder()'s output.
    "local config = { keys = {} }",
    -- The managed block (Shape A) refers to `config` and calls apply on it.
    "<<MANAGED_BLOCK>>",
    -- If we got here, require + apply both succeeded.
    'io.write("APPLY_OK\\n")',
    "assert(type(config.keys) == 'table', 'apply should have populated config.keys')",
    'io.write("KEYS_OK\\n")',
  }, "\n")
  -- Escape any `%` in the replacement (gsub treats `%` specially) and TRUNCATE
  -- the inner gsub to a single value with extra parens — otherwise its second
  -- return (the match count) leaks in as the outer gsub's `n` (max-replacements)
  -- argument and silently suppresses the substitution.
  local block_repl = (((injected or ""):gsub("%%", "%%%%")))
  driver = driver:gsub("<<MANAGED_BLOCK>>", block_repl)

  local driver_path = scratch .. "/driver.lua"
  write_file(driver_path, driver)

  local out, exit = run_capture(
    "lua5.4 " .. shquote(driver_path) .. " " .. shquote(config_dir))

  check("config load under WezTerm-like package.path exits 0 (no apply error)",
    exit == 0, "exit=" .. tostring(exit) .. " output=" .. out:gsub("%s+$", ""))
  check("apply() completed without throwing", out:find("APPLY_OK", 1, true) ~= nil, out)
  check("apply() populated config.keys", out:find("KEYS_OK", 1, true) ~= nil, out)
  check("no 'module not found' regression (BUG 2)",
    out:find("not found", 1, true) == nil, out)

  rmrf(scratch)
end

-- ===========================================================================
-- BUG 1 GUARD — a local source build never hits the network
-- ===========================================================================
do
  -- Run tools/build.sh in an environment where:
  --   * luastatic is forced ABSENT (empty PATH shim dir; lua5.4 re-exposed so the
  --     build's lua5.4-based smoke check still works),
  --   * WEZ_REMOTE_BOOTSTRAP is unset (local build, not the remote installer),
  --   * WEZ_RELEASE_BASE points at an unreachable host, so IF the script ever
  --     tried to download we would both see the release-download log line AND
  --     a failure — neither of which should happen on the local path.
  --
  -- Discover the real dir holding lua5.4 so we can keep it (and coreutils) on the
  -- shim PATH without leaking luastatic.
  local lua_dir = (run_capture("dirname \"$(command -v lua5.4)\""):gsub("%s+$", ""))
  local coreutils_dir = (run_capture("dirname \"$(command -v env)\""):gsub("%s+$", ""))

  -- Build a clean PATH that has lua5.4 + coreutils + a C compiler dir, but with
  -- luastatic guaranteed missing. (We do NOT add any dir that contains luastatic.)
  local shim_path = table.concat({ lua_dir, coreutils_dir, "/usr/bin", "/bin" }, ":")

  local env = table.concat({
    "PATH=" .. shquote(shim_path),
    "WEZ_RELEASE_BASE=" .. shquote("http://127.0.0.1:1/should-never-be-hit"),
    -- WEZ_REMOTE_BOOTSTRAP intentionally NOT set (defaults to local path).
  }, " ")

  -- Sanity: confirm luastatic is genuinely absent on the shim PATH; otherwise the
  -- guard would be vacuous (the build would take the luastatic path instead).
  local luastatic_check =
    run_capture("env -i " .. env .. " sh -c 'command -v luastatic >/dev/null 2>&1 && echo PRESENT || echo ABSENT'")
  check("luastatic is absent on the test PATH (guard is meaningful)",
    luastatic_check:find("ABSENT", 1, true) ~= nil, luastatic_check:gsub("%s+$", ""))

  local out, exit = run_capture(
    "env -i " .. env .. " " .. shquote(repo_root .. "/tools/build.sh"))

  check("local build.sh exits 0 with no luastatic and no remote bootstrap",
    exit == 0, "exit=" .. tostring(exit) .. " output=" .. out:gsub("%s+$", ""))
  check("local build NEVER takes the release-download path (BUG 1)",
    out:lower():find("release%-download") == nil, out:gsub("%s+$", ""))
  check("local build produces the dev source-launcher",
    out:lower():find("dev source%-launcher") ~= nil
      or out:lower():find("dev launcher") ~= nil, out:gsub("%s+$", ""))
  check("dev launcher artifact exists and is runnable",
    file_exists(repo_root .. "/dist/wez"), repo_root .. "/dist/wez")

  -- The just-built dev launcher should answer `version` cleanly (offline).
  local vout, vexit = run_capture(shquote(repo_root .. "/dist/wez") .. " version")
  check("dev launcher `wez version` exits 0 offline",
    vexit == 0, "exit=" .. tostring(vexit) .. " output=" .. vout:gsub("%s+$", ""))
end

-- ---------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
os.exit(0)
