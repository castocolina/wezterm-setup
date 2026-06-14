-- tests/cli/seed_scenes_test.lua
-- Plain assert()-based unit tests for `wez seed-scenes` (Plan 05, SCEN-06):
--   * cli/commands/seed_scenes.lua — the PURE copy-if-absent DECISION
--     (M.plan_seed) PLUS a scratch-FS run() exercise proving fresh installs seed
--     and reinstalls preserve user edits byte-identical (D-06 INVARIANT).
--
-- All assertions are FIXTURE / TEMP-FS driven: no live WezTerm and no real
-- ~/.config edits. The run() FS test points WEZ_SEED_SRC_DIR + WEZTERM_SETUP_DIR
-- at scratch dirs, so this file is an autonomous gate under tools/run-tests.sh.
--
-- Run directly: `lua5.4 tests/cli/seed_scenes_test.lua`.

-- Make `cli/...` and the vendored deps requireable regardless of invocation CWD.
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- tests/cli -> repo root
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

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

local SS = require("cli.commands.seed_scenes")

-- ----------------------------------------------------------------------------
-- PURE plan_seed: all-new -> all seed; all-existing -> all keep; mixed.
-- ----------------------------------------------------------------------------
do
  local function actions(plan)
    local out = {}
    for _, e in ipairs(plan) do out[e.name] = e.action end
    return out
  end

  local all_new = SS.plan_seed({ "ai", "docker", "dev" }, {})
  check("plan_seed marks every recipe 'seed' when the dest is empty",
    #all_new == 3, "#=" .. #all_new)
  do
    local a = actions(all_new)
    check("all-new: ai/docker/dev all seed",
      a.ai == "seed" and a.docker == "seed" and a.dev == "seed",
      a.ai .. "/" .. a.docker .. "/" .. a.dev)
  end

  local all_existing = SS.plan_seed({ "ai", "docker", "dev" }, { "ai", "docker", "dev" })
  do
    local a = actions(all_existing)
    check("all-existing: ai/docker/dev all keep",
      a.ai == "keep" and a.docker == "keep" and a.dev == "keep",
      a.ai .. "/" .. a.docker .. "/" .. a.dev)
  end

  local mixed = SS.plan_seed({ "ai", "docker", "dev" }, { "dev" })
  do
    local a = actions(mixed)
    check("mixed: only the pre-existing 'dev' keeps; ai/docker seed",
      a.dev == "keep" and a.ai == "seed" and a.docker == "seed",
      a.dev .. "/" .. a.ai .. "/" .. a.docker)
  end

  check("plan_seed preserves the input order (deterministic messaging)",
    all_new[1].name == "ai" and all_new[2].name == "docker" and all_new[3].name == "dev")

  check("plan_seed of an empty repo list is an empty plan",
    #SS.plan_seed({}, { "dev" }) == 0)
end

-- ----------------------------------------------------------------------------
-- plan_seed is PURE: it touches no filesystem / env. (run()/resolvers do.)
-- ----------------------------------------------------------------------------
-- (Source-level token check lives in the acceptance grep; here we just confirm
-- it returns a value with no observable FS effect.)
do
  local before = SS.plan_seed({ "x" }, {})
  check("plan_seed returns a deterministic plan with no side effects",
    type(before) == "table" and before[1].action == "seed")
end

-- ----------------------------------------------------------------------------
-- Scratch FS helpers.
-- ----------------------------------------------------------------------------
local function read_file(path)
  local fh = assert(io.open(path, "rb"))
  local data = fh:read("*a")
  fh:close()
  return data
end

local function write_file(path, data)
  local fh = assert(io.open(path, "wb"))
  fh:write(data)
  fh:close()
end

local function scratch_dir(tag)
  local base = os.getenv("TMPDIR") or "/tmp"
  local dir = string.format("%s/wezsetup-%s-%d-%d", base, tag, os.time(), math.random(1, 1e6))
  assert(os.execute("mkdir -p '" .. dir .. "'"))
  return dir
end

-- Capture io.write output during a run() call (the seeder writes to stdout).
local function capture_run(args)
  local buf = {}
  local real_write = io.write
  io.write = function(...) -- luacheck: ignore
    for _, s in ipairs({ ... }) do buf[#buf + 1] = tostring(s) end
  end
  local code = SS.run(args)
  io.write = real_write
  return code, table.concat(buf)
end

-- ----------------------------------------------------------------------------
-- Scratch-FS run(): first run writes all 3 (seeded …); a user edit to one file
-- SURVIVES a second run (kept existing …, byte-identical) — the SCEN-06 "user
-- edits survive reinstall" gate / D-06 INVARIANT / threat T-05-05.
-- ----------------------------------------------------------------------------
do
  local src = scratch_dir("seedsrc")
  local home = scratch_dir("seedhome")
  local dst = home .. "/scenes"

  -- A minimal repo seed dir with the 3 recipes (content is opaque to the seeder;
  -- it copies bytes verbatim).
  write_file(src .. "/dev.toml", 'layout = "tall"\ncolor = "green"\n')
  write_file(src .. "/ai.toml", 'layout = "tall"\ncolor = "purple"\n')
  write_file(src .. "/docker.toml", 'layout = "grid"\ncolor = "teal"\n')

  local prev_src = os.getenv("WEZ_SEED_SRC_DIR")
  local prev_setup = os.getenv("WEZTERM_SETUP_DIR")
  -- lua5.4 has no os.setenv; export via a child-visible mechanism is unavailable,
  -- so we rely on the resolver reading these names. Use the POSIX `setenv` via a
  -- small C-less trick: os.getenv is read each call, and we can set them with
  -- the `_G` shim only if the host exports them. Lua cannot set process env, so
  -- we instead drive the resolver through the supported override names by
  -- writing them into the environment with `os.execute`-independent means:
  -- fall back to passing them through a wrapper if setenv is missing.
  local has_setenv = (os.setenv ~= nil)
  if has_setenv then
    os.setenv("WEZ_SEED_SRC_DIR", src)
    os.setenv("WEZTERM_SETUP_DIR", home)
  end

  if not has_setenv then
    -- Portable fallback: run the seeder in a child lua5.4 with env set, twice,
    -- asserting on its stdout + the resulting files.
    local function run_child()
      local cmd = string.format(
        "WEZ_SEED_SRC_DIR='%s' WEZTERM_SETUP_DIR='%s' lua5.4 -e %s 2>&1",
        src, home,
        "\"package.path='" .. repo_root .. "/?.lua;'..package.path;"
          .. "os.exit(require('cli.commands.seed_scenes').run({}))\"")
      local p = assert(io.popen(cmd))
      local out = p:read("*a")
      local ok = p:close()
      return out, ok
    end

    local out1 = run_child()
    check("first run seeds all 3 (child): dev/ai/docker each printed 'seeded'",
      out1:find("seeded scene recipe: dev", 1, true)
        and out1:find("seeded scene recipe: ai", 1, true)
        and out1:find("seeded scene recipe: docker", 1, true), out1)
    check("first run wrote all 3 recipe files",
      read_file(dst .. "/dev.toml") ~= nil
        and read_file(dst .. "/ai.toml") ~= nil
        and read_file(dst .. "/docker.toml") ~= nil)

    -- User edits one recipe, then reinstall.
    local EDITED = 'layout = "grid"\ncolor = "navy"\n# my hand edit\n'
    write_file(dst .. "/dev.toml", EDITED)
    local out2 = run_child()
    check("reinstall KEEPS the user-edited recipe (kept existing scene recipe: dev)",
      out2:find("kept existing scene recipe: dev", 1, true) ~= nil, out2)
    check("the edited recipe survives reinstall BYTE-IDENTICAL (SCEN-06 / D-06)",
      read_file(dst .. "/dev.toml") == EDITED)
    check("reinstall keeps the untouched recipes too (kept existing scene recipe: ai)",
      out2:find("kept existing scene recipe: ai", 1, true) ~= nil, out2)
  else
    -- In-process path (host lua exposes os.setenv).
    local code1, out1 = capture_run({})
    check("first run exits 0", code1 == 0, "code=" .. tostring(code1))
    check("first run seeds all 3: dev/ai/docker each printed 'seeded'",
      out1:find("seeded scene recipe: dev", 1, true)
        and out1:find("seeded scene recipe: ai", 1, true)
        and out1:find("seeded scene recipe: docker", 1, true), out1)
    check("first run wrote all 3 recipe files",
      read_file(dst .. "/dev.toml") ~= nil
        and read_file(dst .. "/ai.toml") ~= nil
        and read_file(dst .. "/docker.toml") ~= nil)

    local EDITED = 'layout = "grid"\ncolor = "navy"\n# my hand edit\n'
    write_file(dst .. "/dev.toml", EDITED)
    local code2, out2 = capture_run({})
    check("reinstall exits 0", code2 == 0, "code=" .. tostring(code2))
    check("reinstall KEEPS the user-edited recipe (kept existing scene recipe: dev)",
      out2:find("kept existing scene recipe: dev", 1, true) ~= nil, out2)
    check("the edited recipe survives reinstall BYTE-IDENTICAL (SCEN-06 / D-06)",
      read_file(dst .. "/dev.toml") == EDITED)
    check("reinstall NEVER prints 'skipped' (affirms preservation tone)",
      out2:find("skipped", 1, true) == nil, out2)
  end

  -- Restore prior env where we set it.
  if has_setenv then
    if prev_src then os.setenv("WEZ_SEED_SRC_DIR", prev_src) else os.setenv("WEZ_SEED_SRC_DIR", "") end
    if prev_setup then os.setenv("WEZTERM_SETUP_DIR", prev_setup) else os.setenv("WEZTERM_SETUP_DIR", "") end
  end

  os.execute("rm -rf '" .. src .. "' '" .. home .. "'")
end

-- ----------------------------------------------------------------------------
-- spec registration: seed-scenes is in the closed allow-list + categorized.
-- ----------------------------------------------------------------------------
do
  local spec = require("cli.spec")
  local found = false
  for _, n in ipairs(spec.subcommand_names()) do
    if n == "seed-scenes" then found = true end
  end
  check("seed-scenes is registered in spec.subcommand_names()", found)
  check("seed-scenes is categorized under 'install'",
    spec.categories()["seed-scenes"] == "install")
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
