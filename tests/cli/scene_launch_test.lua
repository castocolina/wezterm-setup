-- tests/cli/scene_launch_test.lua
-- Plain assert()-based unit tests for `wez scene launch <name>` (Plan 05-03,
-- SCEN-03/SCEN-04):
--   * cli/commands/scene.lua M.run_launch — the IO-shell front door that resolves
--     the scenes dir, guards the name, reads <name>.toml, hands the raw string to
--     the PURE cli/lib/recipe.lua, and delegates to the SAME M.run_new the
--     `scene new` path uses (one materialization code path).
--
-- The four UI-SPEC error paths are asserted by exit code + exact stderr copy
-- WITHOUT a live mux (every error exits before any mux call — validate-before-emit,
-- so a bad launch builds ZERO panes). The SCEN-04 delegation is proven by stubbing
-- M.run_new and asserting the captured args equal the recipe's mapped args.
--
-- run_launch resolves the scenes dir via M.scenes_dir(), which reads
-- WEZTERM_SETUP_DIR from the process env. lua5.4 has no os.setenv, so the
-- env-dependent error paths run in a child `lua5.4 -e` with the env set (the same
-- portable pattern as seed_scenes_test.lua). The delegation test stubs run_new
-- in-process and points the resolver at a scratch dir via the child env too.
--
-- Run directly: `lua5.4 tests/cli/scene_launch_test.lua`.

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

-- ----------------------------------------------------------------------------
-- Scratch FS helpers.
-- ----------------------------------------------------------------------------
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

-- Run `wez scene launch <name>` in a child lua5.4 with WEZTERM_SETUP_DIR pointed
-- at `setup` (so M.scenes_dir() resolves to <setup>/scenes). Returns
-- (exit_code, combined_stderr_stdout). The child stubs nothing — it exercises the
-- real run_launch error paths. A nil name is passed as the empty string sentinel
-- so the "no name" path is reachable from the child.
local function run_launch_child(setup, name)
  local namelit = name == nil and "nil" or string.format("%q", name)
  local body = string.format(
    "package.path=%q..package.path;"
      .. "local s=require('cli.commands.scene');"
      .. "os.exit(s.run_launch({name=%s}))",
    repo_root .. "/?.lua;" .. repo_root .. "/cli/vendor/?.lua;",
    namelit)
  local cmd = string.format(
    "WEZTERM_SETUP_DIR=%q lua5.4 -e %q 2>&1",
    setup, body)
  local p = assert(io.popen(cmd))
  local out = p:read("*a") or ""
  local _, _, code = p:close()
  return code, out
end

-- ----------------------------------------------------------------------------
-- Error path 1: no name given, NO recipes present -> exit 2 + usage error +
-- the no-recipes guidance line (UI-SPEC rows 119/120).
-- ----------------------------------------------------------------------------
do
  local home = scratch_dir("launch-empty")
  os.execute("mkdir -p '" .. home .. "/scenes'")
  local code, out = run_launch_child(home, nil)
  check("no-name + empty dir -> exit 2", code == 2, "code=" .. tostring(code))
  check("no-name -> usage error copy",
    out:find("error: wez scene launch requires a recipe name (got none)", 1, true) ~= nil, out)
  -- I-1: the usage error is the ONLY `error:` line; the no-recipes case appends
  -- the seed-hint guidance, NOT a second `error: no scene recipes found` line.
  check("no-name + empty dir -> seed-scenes guidance line (I-3 actionable copy)",
    out:find("  run: wez seed-scenes to restore the seeded examples (ai, docker, dev)", 1, true) ~= nil, out)
  do
    local _, n = out:gsub("error:", "")
    check("no-name + empty dir -> exactly ONE `error:` token (I-1, no double prefix)", n == 1,
      "error-count=" .. tostring(n) .. " out=" .. out)
  end
  os.execute("rm -rf '" .. home .. "'")
end

-- ----------------------------------------------------------------------------
-- Error path 2: a NAME given but NO recipes present -> exit 2 + no-recipes
-- guidance (UI-SPEC row 120/121).
-- ----------------------------------------------------------------------------
do
  local home = scratch_dir("launch-empty2")
  os.execute("mkdir -p '" .. home .. "/scenes'")
  local code, out = run_launch_child(home, "dev")
  check("named launch + empty dir -> exit 2", code == 2, "code=" .. tostring(code))
  -- Name-given: the missing recipes ARE the primary failure, so it leads with
  -- the `error: no scene recipes found` line + the seed-scenes guidance (I-3).
  check("named launch + empty dir -> no-recipes error + seed-scenes guidance",
    out:find("error: no scene recipes found in ~/.config/wezterm/wezterm-setup/scenes/", 1, true)
      and out:find("  run: wez seed-scenes to restore the seeded examples (ai, docker, dev)", 1, true), out)
end

-- ----------------------------------------------------------------------------
-- Error path 3: unknown name with a SEEDED dir -> exit 1 + not-found error +
-- the available-recipes hint block listing the seeded names SORTED (UI-SPEC
-- rows 121/122).
-- ----------------------------------------------------------------------------
do
  local home = scratch_dir("launch-seeded")
  local scenes = home .. "/scenes"
  os.execute("mkdir -p '" .. scenes .. "'")
  -- Seed two valid recipes so the hint lists them sorted (ai before dev).
  write_file(scenes .. "/dev.toml", 'layout = "tall"\ncolor = "green"\n[[panes]]\ncommand = "shell"\n[[panes]]\ncommand = "shell"\n')
  write_file(scenes .. "/ai.toml", 'layout = "tall"\ncolor = "purple"\n[[panes]]\ncommand = "shell"\n[[panes]]\ncommand = "shell"\n')

  local code, out = run_launch_child(home, "nope")
  check("unknown name -> exit 1", code == 1, "code=" .. tostring(code))
  check("unknown name -> not-found error copy",
    out:find("error: no scene recipe named 'nope' in ~/.config/wezterm/wezterm-setup/scenes/", 1, true) ~= nil, out)
  check("unknown name -> available-recipes hint header",
    out:find("available recipes:", 1, true) ~= nil, out)
  check("unknown name -> hint lists the seeded names SORTED (ai before dev)",
    out:find("  %- ai\n.-  %- dev\n") ~= nil, out)
  check("unknown name -> hint try-line uses the first sorted name",
    out:find("try: wez scene launch ai", 1, true) ~= nil, out)
  os.execute("rm -rf '" .. home .. "'")
end

-- ----------------------------------------------------------------------------
-- Error path 4: malformed .toml -> exit 1 + recipe-is-invalid (with '<name>'
-- framing) + a `could not parse TOML at line` reason, building ZERO panes
-- (UI-SPEC row 123).
-- ----------------------------------------------------------------------------
do
  local home = scratch_dir("launch-bad")
  local scenes = home .. "/scenes"
  os.execute("mkdir -p '" .. scenes .. "'")
  -- An unterminated string forces tinytoml to raise with a line number.
  write_file(scenes .. "/broken.toml", 'layout = "tall"\ncolor = "green\n[[panes]]\n')

  local code, out = run_launch_child(home, "broken")
  check("malformed recipe -> exit 1", code == 1, "code=" .. tostring(code))
  check("malformed recipe -> recipe-is-invalid copy with '<name>' framing",
    out:find("error: scene recipe 'broken' is invalid:", 1, true) ~= nil, out)
  check("malformed recipe -> the reason names the parse failure (line N)",
    out:find("could not parse TOML at line", 1, true) ~= nil, out)
  os.execute("rm -rf '" .. home .. "'")
end

-- ----------------------------------------------------------------------------
-- Path-traversal guard: a name with a separator/`..` is rejected (exit 1)
-- BEFORE any io.open (T-05-08). guard_name runs pre-I/O.
-- ----------------------------------------------------------------------------
do
  local home = scratch_dir("launch-guard")
  local scenes = home .. "/scenes"
  os.execute("mkdir -p '" .. scenes .. "'")
  write_file(scenes .. "/dev.toml", 'layout = "tall"\n[[panes]]\ncommand = "shell"\n')

  local code, out = run_launch_child(home, "../etc/passwd")
  check("path-traversal name -> exit 1 (guarded before io.open)", code == 1, "code=" .. tostring(code))
  check("path-traversal name -> guard error copy",
    out:find("invalid scene name", 1, true) ~= nil, out)
  os.execute("rm -rf '" .. home .. "'")
end

-- ----------------------------------------------------------------------------
-- SCEN-04 DELEGATION: run_launch maps the recipe and calls M.run_new with the
-- mapped args (ONE code path) — proven by stubbing run_new to CAPTURE its args.
-- The recipe is the `dev` seed shape (layout="tall", color="green", 2 shell
-- panes), so the captured args must equal recipe.lua's mapping of it.
-- ----------------------------------------------------------------------------
do
  local home = scratch_dir("launch-deleg")
  local scenes = home .. "/scenes"
  os.execute("mkdir -p '" .. scenes .. "'")
  write_file(scenes .. "/dev.toml",
    'layout = "tall"\ncolor = "green"\n[[panes]]\ncommand = "shell"\n[[panes]]\ncommand = "shell"\n')

  -- Run in a child so WEZTERM_SETUP_DIR resolves; the child stubs run_new to
  -- print the captured args in a parseable form, then exit 0.
  local body = string.format(
    "package.path=%q..package.path;"
      .. "local s=require('cli.commands.scene');"
      .. "local captured;"
      .. "s.run_new=function(a) captured=a; return 0 end;"  -- monkeypatch the seam
      .. "local code=s.run_launch({name='dev'});"
      .. "assert(captured~=nil, 'run_new was not called');"
      .. "io.write('LAYOUT='..tostring(captured.layout)..'\\n');"
      .. "io.write('COLOR='..tostring(captured.color)..'\\n');"
      .. "io.write('PANES='..table.concat(captured.pane or {}, '|')..'\\n');"
      .. "os.exit(code)",
    repo_root .. "/?.lua;" .. repo_root .. "/cli/vendor/?.lua;")
  local cmd = string.format("WEZTERM_SETUP_DIR=%q lua5.4 -e %q 2>&1", home, body)
  local p = assert(io.popen(cmd))
  local out = p:read("*a") or ""
  local _, _, code = p:close()

  check("delegation: run_launch returns run_new's code (0)", code == 0, "code=" .. tostring(code) .. " out=" .. out)
  check("delegation: run_new received layout='tall' (mapped from the recipe)",
    out:find("LAYOUT=tall", 1, true) ~= nil, out)
  check("delegation: run_new received color='green'",
    out:find("COLOR=green", 1, true) ~= nil, out)
  check("delegation: run_new received the 2 mapped shell pane specs (single code path)",
    out:find("PANES=shell|shell", 1, true) ~= nil, out)
  os.execute("rm -rf '" .. home .. "'")
end

-- ----------------------------------------------------------------------------
-- spec registration: `scene launch` is a sibling subcommand under `scene`.
-- ----------------------------------------------------------------------------
do
  local spec = require("cli.spec")
  local parser = spec.build_parser()
  local found = false
  for _, c in ipairs(parser._commands) do
    if c._name == "scene" then
      for _, sc in ipairs(c._commands) do
        if sc._name == "launch" then found = true end
      end
    end
  end
  check("scene launch is registered under the scene command in spec.lua", found)
end

-- ----------------------------------------------------------------------------
-- REGRESSION (05-VERIFICATION gap 1): a bare `wez scene launch` (no positional)
-- must PARSE successfully so M.run_launch owns the no-name UI-SPEC copy. The
-- positional is args("?") (optional); if it regresses to args(1), argparse
-- intercepts with a generic "missing argument 'name'" and the UI-SPEC usage copy
-- becomes unreachable. Parse in a child because argparse calls os.exit on error.
-- ----------------------------------------------------------------------------
do
  local body = string.format(
    "package.path=%q..package.path;"
      .. "local ok,res=pcall(function() return require('cli.spec').build_parser():parse({'scene','launch'}) end);"
      .. "if not ok then io.stderr:write('PARSE_ERR '..tostring(res)); os.exit(3) end;"
      .. "io.write('PARSE_OK name='..tostring(res.name))",
    repo_root .. "/?.lua;" .. repo_root .. "/cli/vendor/?.lua;")
  local p = assert(io.popen(string.format("lua5.4 -e %q 2>&1", body)))
  local out = p:read("*a") or ""
  local _, _, code = p:close()
  check("bare `scene launch` parses (optional positional, no argparse interception)",
    code == 0 and out:find("PARSE_OK", 1, true) ~= nil, "code=" .. tostring(code) .. " out=" .. out)
  check("bare `scene launch` yields no name (run_launch then emits the usage copy)",
    out:find("name=nil", 1, true) ~= nil, out)
end

-- ----------------------------------------------------------------------------
-- REGRESSION (05-VERIFICATION gap 2): an invalid layout/color recipe must NOT
-- double the `error:` token. The reused validate_layout/validate_color strings
-- already carry `error:`; run_launch strips it so the line reads
-- `error: scene recipe '<name>' is invalid: <enum wording>` with ONE prefix.
-- ----------------------------------------------------------------------------
do
  local home = scratch_dir("launch-badlayout")
  os.execute("mkdir -p '" .. home .. "/scenes'")
  write_file(home .. "/scenes/broken.toml", 'layout = "boguslayout"\n[[panes]]\ncommand = "shell"\n')
  local code, out = run_launch_child(home, "broken")
  check("invalid layout -> exit 1", code == 1, "code=" .. tostring(code))
  check("invalid layout -> single `error:` prefix (no `invalid: error:` double)",
    out:find("invalid: error:", 1, true) == nil, out)
  check("invalid layout -> reuses the exact validator enum wording",
    out:find("error: scene recipe 'broken' is invalid: unknown layout 'boguslayout'", 1, true) ~= nil, out)
  os.execute("rm -rf '" .. home .. "'")
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
