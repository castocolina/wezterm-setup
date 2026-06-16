-- Fixture tests for cli/spec.lua — the single source of truth for the `wez`
-- command tree (D-16). These assert the Phase 6.2 surface (G-1 icon attribute,
-- G-2a/G-2b color split + follow-pane opt-in) is REGISTERED in the parser, so
-- completion + `wez keys` pick it up automatically.
-- Run from the repo root: `lua5.4 cli/spec_test.lua`

local spec = require("cli.spec")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else
    fail = fail + 1
    io.stderr:write("FAIL: " .. name .. "\n")
  end
end

-- Protected parse helper: pparse returns (ok, result|errmsg) WITHOUT exiting the
-- process on a parse error, so we can assert both acceptance AND rejection.
local function pparse(argv)
  local parser = spec.build_parser()
  return parser:pparse(argv)
end

-- ── icon subcommand (D-01/D-03): tab + pane ────────────────────────────────
local ok1, r1 = pparse({ "pane", "icon", "python" })
check("pane icon subcommand registered", ok1 and r1.command == "pane" and r1.pane_cmd == "icon")
check("pane icon positional lands in value", ok1 and r1.value == "python")

local ok2, r2 = pparse({ "tab", "icon", "node" })
check("tab icon subcommand registered", ok2 and r2.command == "tab" and r2.tab_cmd == "icon")
check("tab icon positional lands in value", ok2 and r2.value == "node")

-- icon positional is optional (empty / reset clears) — args("?")
local ok3 = pparse({ "pane", "icon" })
check("pane icon accepts no positional (optional)", ok3 == true)

-- ── --icon convenience option on `title` ONLY (D-01) ───────────────────────
local ok4, r4 = pparse({ "tab", "title", "api", "--icon", "node" })
check("--icon registered on tab title", ok4 and r4.tab_cmd == "title" and r4.icon == "node")

local ok5, r5 = pparse({ "pane", "title", "api", "--icon", "python" })
check("--icon registered on pane title", ok5 and r5.pane_cmd == "title" and r5.icon == "python")

-- color does NOT carry --icon (D-01): parsing must FAIL (pparse -> ok=false)
local ok6 = pparse({ "tab", "color", "blue", "--icon", "node" })
check("--icon REJECTED on tab color (not registered there)", ok6 == false)
local ok7 = pparse({ "pane", "color", "navy", "--icon", "x" })
check("--icon REJECTED on pane color (not registered there)", ok7 == false)

-- ── --follow-pane-color flag on `tab color` ONLY (D-09) ────────────────────
local ok8, r8 = pparse({ "tab", "color", "blue", "--follow-pane-color" })
check("--follow-pane-color registered on tab color", ok8 and r8.tab_cmd == "color" and r8.follow_pane_color == true)

-- default OFF: absent the flag, follow_pane_color is falsy
local ok9, r9 = pparse({ "tab", "color", "blue" })
check("--follow-pane-color default OFF", ok9 and not r9.follow_pane_color)

-- --follow-pane-color is NOT on pane color (D-09 tab-only)
local ok10 = pparse({ "pane", "color", "navy", "--follow-pane-color" })
check("--follow-pane-color REJECTED on pane color (tab-only)", ok10 == false)

io.write(string.format("\nspec_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
