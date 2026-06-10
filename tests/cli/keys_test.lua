-- tests/cli/keys_test.lua
-- Plain assert()-based unit tests for `wez keys`:
--   * cli/lib/showkeys.lua   — parser for `wezterm show-keys --lua` (Task 1)
--   * cli/commands/keys.lua   — classify/group/render/--json (Task 2)
--
-- All assertions are FIXTURE-DRIVEN: no live WezTerm session is required, so this
-- file is an autonomous gate under tools/run-tests.sh. The live `./dist/wez keys`
-- checks (grouped output + `--json | jq`) are integration/manual checks (D-18) and
-- are NOT exercised here.
--
-- Run directly: `lua5.4 tests/cli/keys_test.lua`.

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
-- A representative `wezterm show-keys --lua` snippet captured by the R6 probe
-- (.tmp/probes/phase-1/05-show-keys-lua.md). It carries a few top-level `keys`
-- (the effective table) and a `key_tables` block with copy_mode + search_mode
-- entries that MUST be excluded (D-13).
-- ----------------------------------------------------------------------------
local SHOWKEYS_FIXTURE = [[
local wezterm = require 'wezterm'
local act = wezterm.action

return {
  keys = {
    { key = 'Tab', mods = 'CTRL', action = act.ActivateTabRelative(1) },
    { key = 'Tab', mods = 'SHIFT|CTRL', action = act.ActivateTabRelative(-1) },
    { key = 'Enter', mods = 'ALT', action = act.ToggleFullScreen },
    { key = 'k', mods = 'SUPER', action = act.ClearScrollback 'ScrollbackOnly' },
    { key = 't', mods = 'SUPER', action = act.SpawnTab 'CurrentPaneDomain' },
    { key = 'w', mods = 'SUPER', action = act.CloseCurrentTab{ confirm = true } },
    { key = '"', mods = 'ALT|CTRL', action = act.SplitVertical{ domain =  'CurrentPaneDomain' } },
  },

  key_tables = {
    copy_mode = {
      { key = 'Tab', mods = 'NONE', action = act.CopyMode 'MoveForwardWord' },
      { key = 'Escape', mods = 'NONE', action = act.CopyMode 'Close' },
    },
    search_mode = {
      { key = 'Enter', mods = 'NONE', action = act.CopyMode 'PriorMatch' },
    },
  },
}
]]

-- ============================================================================
-- Task 1 — cli/lib/showkeys.lua: parse the --lua form to {key, mods, action}
-- ============================================================================
local showkeys = require("cli.lib.showkeys")
check("showkeys module loads", type(showkeys) == "table")
check("showkeys exposes parse()", type(showkeys.parse) == "function")
check("showkeys exposes parse_baseline()", type(showkeys.parse_baseline) == "function")

local records = showkeys.parse(SHOWKEYS_FIXTURE)
check("parse returns a list", type(records) == "table")

-- The fixture has exactly 7 top-level `keys` entries; the 3 key_tables entries
-- (2 copy_mode + 1 search_mode) MUST be excluded (D-13).
check("parse yields exactly the 7 effective records (copy_mode/search_mode excluded)",
  #records == 7, "got " .. tostring(#records))

-- No parsed record may be a copy_mode/search_mode action.
do
  local leaked = false
  for _, r in ipairs(records) do
    if tostring(r.action):find("CopyMode") then leaked = true end
  end
  check("no copy_mode/search_mode action leaked into records", not leaked)
end

-- key/mods/action extracted correctly for a sample binding (`k` + SUPER).
do
  local found
  for _, r in ipairs(records) do
    if r.key == "k" and r.mods == "SUPER" then found = r end
  end
  check("sample binding k+SUPER is parsed", found ~= nil)
  check("sample binding action captured verbatim",
    found ~= nil and tostring(found.action):find("ClearScrollback") ~= nil,
    found and found.action or "nil")
end

-- The escaped double-quote key literal `'"'` unescapes to a single `"`.
do
  local found
  for _, r in ipairs(records) do
    if r.key == '"' then found = r end
  end
  check("escaped double-quote key literal unescaped to a single char", found ~= nil)
end

-- parse_baseline uses the same scanner: same fixture -> same record count.
do
  local base = showkeys.parse_baseline(SHOWKEYS_FIXTURE)
  check("parse_baseline yields the same 7 records on identical input",
    type(base) == "table" and #base == 7, "got " .. tostring(base and #base))
end

-- ============================================================================
-- Task 2 — cli/commands/keys.lua: classify (D-14), group, --json
-- ============================================================================
local keys = require("cli.commands.keys")
check("keys module loads", type(keys) == "table")
check("keys exposes run()", type(keys.run) == "function")
check("keys exposes classify() (pure, testable)", type(keys.classify) == "function")

-- Synthetic D-14 fixtures. `classify(effective, baseline, ours)` returns a list of
-- classified entries plus a list of conflicts, all derived deterministically.
-- A record key for matching is (key, mods).
local function rec(key, mods, action) return { key = key, mods = mods, action = action } end

-- effective ∩ baseline ∩ ours   -> "setup"
-- effective ∩ baseline, not ours -> "default"
-- effective, not baseline/ours   -> "user"
-- ours absent from effective     -> conflict (who-wins)
local effective = {
  rec("k", "SUPER", "act.ClearScreenAndScrollback"),  -- setup (ours wins, present in baseline too)
  rec("Tab", "CTRL", "act.ActivateTabRelative(1)"),   -- default (in baseline, not ours)
  rec("p", "CTRL", "act.SomeUserThing"),              -- user (not baseline, not ours)
}
local baseline = {
  rec("k", "SUPER", "act.ClearScrollback 'ScrollbackOnly'"),
  rec("Tab", "CTRL", "act.ActivateTabRelative(1)"),
}
local ours = {
  rec("k", "SUPER", "act.ClearScreenAndScrollback"),
  rec("zzz", "ALT", "act.SplitVertical"),  -- ours but ABSENT from effective -> conflict
}

local classified, conflicts = keys.classify(effective, baseline, ours)
check("classify returns (entries, conflicts)",
  type(classified) == "table" and type(conflicts) == "table")

local function label_of(list, key, mods)
  for _, e in ipairs(list) do
    if e.key == key and e.mods == mods then return e.label end
  end
  return nil
end

check("D-14 case 1: effective ∩ baseline ∩ ours -> 'setup'",
  label_of(classified, "k", "SUPER") == "setup", label_of(classified, "k", "SUPER"))
check("D-14 case 2: effective ∩ baseline, not ours -> 'default'",
  label_of(classified, "Tab", "CTRL") == "default", label_of(classified, "Tab", "CTRL"))
check("D-14 case 3: effective only -> 'user'",
  label_of(classified, "p", "CTRL") == "user", label_of(classified, "p", "CTRL"))

-- case 4: a binding of OURS absent from effective is flagged as a conflict.
do
  local flagged = false
  for _, c in ipairs(conflicts) do
    if c.key == "zzz" and c.mods == "ALT" then flagged = true end
  end
  check("D-14 case 4: ours absent from effective -> conflict/who-wins flagged", flagged)
end

-- --json output round-trips through dkjson (decode(encode(t)) preserves shape).
do
  local json = require("dkjson")
  local doc = keys.build_json(classified, conflicts)
  check("build_json returns a table", type(doc) == "table")
  local encoded = json.encode(doc)
  check("build_json encodes to a string", type(encoded) == "string")
  local decoded = json.decode(encoded)
  check("--json document round-trips through dkjson", type(decoded) == "table"
    and decoded.bindings ~= nil and decoded.conflicts ~= nil,
    encoded and (encoded:sub(1, 60)) or "nil")
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
