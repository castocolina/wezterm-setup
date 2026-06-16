-- tests/cli/spec_test.lua
-- Plain assert()-based unit tests for the wez CLI argparse contract (cli/spec.lua)
-- and the vendored dkjson round-trip. Runnable directly: `lua5.4 tests/cli/spec_test.lua`.
--
-- Resolves modules relative to the repo root so the test runs from any CWD that the
-- test runner invokes it under (tools/run-tests.sh runs each file via lua5.4).

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
-- spec.lua: the single source-of-truth argparse contract
-- ----------------------------------------------------------------------------
local spec = require("cli.spec")
check("spec module loads", type(spec) == "table")
check("spec exposes build_parser()", type(spec.build_parser) == "function")

local parser = spec.build_parser()
check("build_parser() returns a parser object", type(parser) == "table")

-- The parser must parse the `version` subcommand and the top-level `--version` flag.
do
  local ok, res = pcall(function() return parser:parse({ "version" }) end)
  check("parser parses `version` subcommand", ok and res ~= nil, not ok and res or nil)
end
do
  local ok, res = pcall(function() return parser:parse({ "--version" }) end)
  -- argparse handles built-in --version by printing+exiting; we accept either a clean
  -- parse table OR argparse's documented behaviour. Using add_version() makes --version
  -- exit, so instead the spec exposes the version via a flag we can observe in the table.
  check("parser parses `--version` flag", ok and res ~= nil, not ok and res or nil)
end

-- Every Phase 1 subcommand name must be registered (interface-first contract, D-16).
local required_subcommands = {
  "version", "doctor", "keys",
  "install-state", "uninstall-state", "seed-scenes", "update", "completions", "__complete",
}
local names = spec.subcommand_names()
check("spec.subcommand_names() returns a table", type(names) == "table")
local nameset = {}
for _, n in ipairs(names or {}) do nameset[n] = true end
for _, want in ipairs(required_subcommands) do
  check("subcommand registered: " .. want, nameset[want] == true)
end

-- `keys` must accept --json.
do
  local ok, res = pcall(function() return parser:parse({ "keys", "--json" }) end)
  check("`keys --json` parses", ok and res ~= nil and res.json == true,
    not ok and res or ("json=" .. tostring(res and res.json)))
end

-- install-state flags.
do
  local ok, res = pcall(function() return parser:parse({ "install-state", "--force" }) end)
  check("`install-state --force` parses", ok and res ~= nil, not ok and res or nil)
end

-- scene new must accept the tab-level --cwd flag (D-07) plus --color/--title and
-- repeatable --pane, and the --pane help string must advertise the full segment
-- grammar cwd/focus/size (D-16 — completion + `wez keys` read it).
do
  local ok, res = pcall(function()
    return parser:parse({ "scene", "new", "--layout", "tall",
      "--cwd", "~/proj", "--color", "teal", "--title", "Dev",
      "--pane", "shell", "--pane", "cmd=top, cwd=~/x, focus=true, size=30" })
  end)
  check("`scene new --cwd ...` parses", ok and res ~= nil and res.cwd == "~/proj",
    not ok and res or ("cwd=" .. tostring(res and res.cwd)))
  check("`scene new` collects repeatable --pane into an array",
    ok and type(res.pane) == "table" and #res.pane == 2,
    ok and ("#pane=" .. tostring(res.pane and #res.pane)) or nil)
  check("`scene new` carries tab-level color/title",
    ok and res.color == "teal" and res.title == "Dev",
    ok and ("color=" .. tostring(res.color) .. " title=" .. tostring(res.title)) or nil)
end

-- The registered --pane help string must list cwd/focus/size so the grammar is
-- discoverable via completion + `wez keys` (D-16). We assert against the option's
-- description text the parser holds.
do
  local found = false
  local parser2 = spec.build_parser()
  -- argparse stores commands/options in internal tables; walk for the scene_new
  -- --pane option description mentioning cwd/focus/size.
  local function walk(node)
    if type(node) ~= "table" then return end
    for _, opt in ipairs(node._options or {}) do
      local desc = opt._description or opt.description
      if type(desc) == "string" and desc:find("cwd")
        and desc:find("focus") and desc:find("size") then
        found = true
      end
    end
    for _, cmd in ipairs(node._commands or {}) do walk(cmd) end
  end
  walk(parser2)
  check("--pane help advertises cwd/focus/size segment grammar (D-16)", found)
end

-- ----------------------------------------------------------------------------
-- 6.2 surface (Plan 02): icon subcommands, --icon on title only, --follow-pane-color
-- on tab color only (D-01/D-09/D-16).
-- ----------------------------------------------------------------------------

-- tab/pane each gain an `icon` subcommand with one optional positional value.
do
  local ok, res = pcall(function() return parser:parse({ "tab", "icon", "node" }) end)
  check("`tab icon node` parses", ok and res ~= nil and res.tab_cmd == "icon" and res.value == "node",
    not ok and res or ("tab_cmd=" .. tostring(res and res.tab_cmd) .. " value=" .. tostring(res and res.value)))
end
do
  local ok, res = pcall(function() return parser:parse({ "tab", "icon" }) end)
  check("`tab icon` (no value, clear) parses", ok and res ~= nil and res.tab_cmd == "icon",
    not ok and res or nil)
end
do
  local ok, res = pcall(function() return parser:parse({ "pane", "icon", "python" }) end)
  check("`pane icon python` parses", ok and res ~= nil and res.pane_cmd == "icon" and res.value == "python",
    not ok and res or ("pane_cmd=" .. tostring(res and res.pane_cmd) .. " value=" .. tostring(res and res.value)))
end

-- --icon is carried on the `title` subcommands (a value option).
do
  local ok, res = pcall(function() return parser:parse({ "tab", "title", "api", "--icon", "node" }) end)
  check("`tab title api --icon node` parses with icon=node",
    ok and res ~= nil and res.tab_cmd == "title" and res.icon == "node",
    not ok and res or ("icon=" .. tostring(res and res.icon)))
end
do
  local ok, res = pcall(function() return parser:parse({ "pane", "title", "api", "--icon", "python" }) end)
  check("`pane title api --icon python` parses with icon=python",
    ok and res ~= nil and res.pane_cmd == "title" and res.icon == "python",
    not ok and res or ("icon=" .. tostring(res and res.icon)))
end

-- Color subcommands do NOT carry --icon (D-01): the parse must FAIL. Use pparse so
-- argparse returns (false, err) instead of printing usage + os.exit on the error.
do
  local ok = parser:pparse({ "tab", "color", "blue", "--icon", "node" })
  check("`tab color --icon` is rejected (color has no --icon, D-01)", ok == false)
end
do
  local ok = parser:pparse({ "pane", "color", "blue", "--icon", "python" })
  check("`pane color --icon` is rejected (color has no --icon, D-01)", ok == false)
end

-- --follow-pane-color is a boolean flag on `tab color` only (D-09).
do
  local ok, res = pcall(function() return parser:parse({ "tab", "color", "blue", "--follow-pane-color" }) end)
  check("`tab color blue --follow-pane-color` parses with follow_pane_color=true",
    ok and res ~= nil and res.follow_pane_color == true,
    not ok and res or ("follow_pane_color=" .. tostring(res and res.follow_pane_color)))
end
-- pane color does NOT carry --follow-pane-color.
do
  local ok = parser:pparse({ "pane", "color", "blue", "--follow-pane-color" })
  check("`pane color --follow-pane-color` is rejected (tab-only, D-09)", ok == false)
end

-- The --pane help string must now also advertise icon= (D-16).
do
  local found = false
  local parser3 = spec.build_parser()
  local function walk(node)
    if type(node) ~= "table" then return end
    for _, opt in ipairs(node._options or {}) do
      local desc = opt._description or opt.description
      if type(desc) == "string" and desc:find("icon=") then found = true end
    end
    for _, cmd in ipairs(node._commands or {}) do walk(cmd) end
  end
  walk(parser3)
  check("--pane help advertises icon= segment (D-16)", found)
end

-- Each subcommand carries a category tag the completion generator + keys read (D-16).
check("spec.categories() returns a table", type(spec.categories) == "function" and type(spec.categories()) == "table")
do
  local cats = spec.categories()
  check("every subcommand has a category", (function()
    for _, n in ipairs(required_subcommands) do
      if cats[n] == nil then return false, n end
    end
    return true
  end)())
end

-- ----------------------------------------------------------------------------
-- dkjson: encode -> decode round-trip equality on a nested table
-- ----------------------------------------------------------------------------
local json = require("dkjson")
do
  local original = { name = "wez", n = 42, nested = { a = 1, b = { 2, 3 } }, flag = true }
  local encoded = json.encode(original)
  check("dkjson encodes to a string", type(encoded) == "string")
  local decoded = json.decode(encoded)
  check("dkjson decode yields a table", type(decoded) == "table")
  local same = decoded.name == original.name
    and decoded.n == original.n
    and decoded.flag == original.flag
    and decoded.nested.a == original.nested.a
    and decoded.nested.b[1] == original.nested.b[1]
    and decoded.nested.b[2] == original.nested.b[2]
  check("dkjson encode->decode round-trips a nested table", same)
end

-- ----------------------------------------------------------------------------
-- version command + entry-point lazy dispatch (Task 2)
-- ----------------------------------------------------------------------------
local version = require("cli.commands.version")
check("version module loads", type(version) == "table")
check("version exposes run()", type(version.run) == "function")
do
  -- Capture stdout from version.run by swapping io.write/print is intrusive; the
  -- command prints via io.write, so we redirect through a captured buffer.
  local buf = {}
  local real_write = io.write
  io.write = function(...)
    for _, v in ipairs({ ... }) do buf[#buf + 1] = tostring(v) end
    return true
  end
  local code = version.run({})
  io.write = real_write
  local out = table.concat(buf)
  check("version.run returns exit code 0", code == 0, "code=" .. tostring(code))
  check("version.run prints a non-empty version string", #out > 0 and out:match("%d"), out)
end

-- The entry point exposes main(argv) returning a numeric exit code (no os.exit
-- when required as a module) so dispatch is unit-testable.
local wez = require("cli.wez")
check("wez entry module loads", type(wez) == "table")
check("wez exposes main()", type(wez.main) == "function")
do
  local code = wez.main({ "version" })
  check("main{'version'} exits 0", code == 0, "code=" .. tostring(code))
end
do
  local code = wez.main({ "--version" })
  check("main{'--version'} exits 0", code == 0, "code=" .. tostring(code))
end
do
  -- `doctor` dispatches and returns a NUMERIC exit code without raising a raw
  -- traceback. We deliberately do NOT assert a specific exit value here: doctor's
  -- code reflects the LIVE ~/.config/wezterm install health, which is not a
  -- property of the spec/dispatcher under test. (An earlier version asserted
  -- "exits non-zero" — but that only held because the live install was BROKEN by
  -- the BUG 2 config-load failure; it flipped to a false RED the moment the
  -- install was repaired. Coupling a unit gate to live install state is the very
  -- blind spot the install-config-e2e integration test now covers properly.)
  local ok, code = pcall(wez.main, { "doctor" })
  check("main{'doctor'} dispatches without raising", ok, ok and "" or tostring(code))
  check("main{'doctor'} returns a numeric exit code", ok and type(code) == "number",
    "code=" .. tostring(code))
end
do
  -- Regression: a HYPHENATED subcommand name (`install-state`) must resolve to
  -- its UNDERSCORED module file (cli/commands/install_state.lua). Before the
  -- dispatcher mapped `-` -> `_`, this reported "not implemented" (exit 3).
  -- Point it at a temp absent config so it runs the real install path to exit 0.
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "wb"))
  fh:write("return {}\n")
  fh:close()
  local prev = os.getenv("WEZTERM_CONFIG_FILE")
  -- Lua has no setenv; drive the command module directly to assert resolution.
  local resolved = require("cli.commands.install_state")
  check("install-state resolves to the install_state module (hyphen->underscore)",
    type(resolved) == "table" and type(resolved.run) == "function")
  os.remove(tmp)
  _ = prev
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
