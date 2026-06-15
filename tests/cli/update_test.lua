-- tests/cli/update_test.lua
-- Plain assert()-based unit tests for `wez update` (Plan 06-05, INST-09):
--   * cli/commands/update.lua — the TWO PURE freshness comparators (Warning 4,
--     NOT conflated): M.decide_wez_update (SEMVER/tag, the wez binary half) and
--     M.decide_wezterm_update (8-digit YYYYMMDD datestamp, the WezTerm emulator
--     half). Each returns exactly "update" | "current" | "system-skip".
--   * the module interface (M.decide_wez_update / M.decide_wezterm_update / M.run).
--   * the spec 3-place registration that makes `wez update` tab-complete (D-16).
--
-- All assertions are PURE-decision / fixture driven: no live wezterm, no real
-- download, no ~/.config edits (the KNOWN INTERIM: no v* wez release exists yet,
-- so a live fetch is impossible — the contract is tested, never an actual swap).
-- This file is an autonomous gate under tools/run-tests.sh.
--
-- Run directly: `lua5.4 tests/cli/update_test.lua`.

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

local U = require("cli.commands.update")

-- ----------------------------------------------------------------------------
-- Interface contract: the module exposes BOTH comparators + run().
-- ----------------------------------------------------------------------------
check("update module loads", type(U) == "table")
check("update exposes decide_wez_update()", type(U.decide_wez_update) == "function")
check("update exposes decide_wezterm_update()", type(U.decide_wezterm_update) == "function")
check("update exposes run()", type(U.run) == "function")

-- ----------------------------------------------------------------------------
-- decide_wez_update — SEMVER/tag (the wez BINARY half). NOT a datestamp.
-- ----------------------------------------------------------------------------
do
  -- A strictly-newer published release -> update.
  check("wez: newer latest release -> update",
    U.decide_wez_update("0.1.0", "0.2.0", "user-path") == "update")
  -- semver per-FIELD numeric, not lexical: 0.9.0 < 0.10.0.
  check("wez: 0.9.0 vs 0.10.0 is numeric per-field -> update",
    U.decide_wez_update("0.9.0", "0.10.0", "user-path") == "update")
  check("wez: patch bump 0.1.0 -> 0.1.1 -> update",
    U.decide_wez_update("0.1.0", "0.1.1", "user-path") == "update")

  -- have == latest -> current (no-op).
  check("wez: equal versions -> current",
    U.decide_wez_update("0.2.0", "0.2.0", "user-path") == "current")
  -- have NEWER than latest -> current (never a downgrade).
  check("wez: have newer than latest -> current",
    U.decide_wez_update("0.2.0", "0.1.0", "user-path") == "current")
  check("wez: have 0.10.0 vs latest 0.9.0 -> current (numeric, not lexical)",
    U.decide_wez_update("0.10.0", "0.9.0", "user-path") == "current")

  -- Leading `v` on either side is tolerated (release tags are `v0.1.0`).
  check("wez: tolerates a leading 'v' on the tag -> update",
    U.decide_wez_update("v0.1.0", "v0.2.0", "user-path") == "update")
  check("wez: mixed v-prefix equal -> current",
    U.decide_wez_update("0.2.0", "v0.2.0", "user-path") == "current")

  -- system install -> system-skip REGARDLESS of versions (checked FIRST, P6-D09).
  check("wez: system install -> system-skip even when newer exists",
    U.decide_wez_update("0.1.0", "0.2.0", "system") == "system-skip")
  check("wez: system install -> system-skip even when current",
    U.decide_wez_update("0.2.0", "0.2.0", "system") == "system-skip")

  -- No published release yet (Open Q3): empty/nil latest -> current (clean no-op
  -- for the wez half; "no published wez release yet" is reported by run()).
  check("wez: empty latest (no published release) -> current",
    U.decide_wez_update("0.1.0", "", "user-path") == "current")
  check("wez: nil latest (no published release) -> current",
    U.decide_wez_update("0.1.0", nil, "user-path") == "current")
end

-- ----------------------------------------------------------------------------
-- decide_wezterm_update — 8-digit YYYYMMDD datestamp (the WezTerm EMULATOR half).
-- Same numeric `>=` semantics as wezterm_datestamp_ge. NOT a semver.
-- ----------------------------------------------------------------------------
do
  -- newer want -> update.
  check("wezterm: newer nightly want -> update",
    U.decide_wezterm_update("20260601", "20260610", "user-path") == "update")
  -- have == want -> current.
  check("wezterm: have == want -> current",
    U.decide_wezterm_update("20260610", "20260610", "user-path") == "current")
  -- have > want -> current (never a downgrade).
  check("wezterm: have > want -> current",
    U.decide_wezterm_update("20260610", "20260601", "user-path") == "current")

  -- empty/unparseable have -> update (treated as below; matches detect_and_reuse:76-78).
  check("wezterm: empty have -> update (unparseable installed -> below)",
    U.decide_wezterm_update("", "20260610", "user-path") == "update")
  check("wezterm: nil have -> update",
    U.decide_wezterm_update(nil, "20260610", "user-path") == "update")

  -- empty want (degraded latest-nightly fetch) -> current: a garbage "newer?"
  -- signal NEVER forces a swap (T-06-05-04 / T-06-06-01 graceful degradation).
  check("wezterm: empty want (degraded fetch) -> current (no forced swap)",
    U.decide_wezterm_update("20260601", "", "user-path") == "current")
  check("wezterm: nil want (degraded fetch) -> current",
    U.decide_wezterm_update("20260601", nil, "user-path") == "current")

  -- system install -> system-skip REGARDLESS of datestamps (checked FIRST, P6-D09).
  check("wezterm: system install -> system-skip even when newer exists",
    U.decide_wezterm_update("20260601", "20260610", "system") == "system-skip")
  check("wezterm: system install -> system-skip even when current",
    U.decide_wezterm_update("20260610", "20260610", "system") == "system-skip")
end

-- ----------------------------------------------------------------------------
-- spec registration: `update` is in the closed allow-list + categorized (D-16).
-- ----------------------------------------------------------------------------
do
  local spec = require("cli.spec")
  local found = false
  for _, n in ipairs(spec.subcommand_names()) do
    if n == "update" then found = true end
  end
  check("update is registered in spec.subcommand_names()", found)
  check("update is categorized under 'install'",
    spec.categories()["update"] == "install")
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
