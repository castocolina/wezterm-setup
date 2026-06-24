-- tests/e2e/lib/skip.lua
--
-- Generalized self-skip gate for the E2E battery (Phase 06.6+).
--
-- This generalizes the TWO gates in keys_integration_test.lua 106-141 into a
-- reusable module so the permission/tool/mux-bound tiers (06.7-06.9) plug in
-- WITHOUT re-implementing the skip contract.
--
-- TIER 1 NEEDS NEITHER GATE: the deterministic subcommand tier (Plan 02/03) is
-- headless and always runs. The gate exists here so later tiers consume it:
--   * 06.9 plugs WEZ_E2E_INPUT=1 / WEZ_E2E_VISUAL=1 into require_env.
--   * 06.7 plugs a "mux reachable?" / "input tool present?" predicate into
--     require_tool.
--
-- THE LOUD-SKIP CONTRACT (CONTEXT: "self-skip must be loud and logged — never a
-- silent pass, never a hang"): a skip is ALWAYS printed and explained, never a
-- silent return. And on a host that DOES have the dependency, a skip is
-- IMPOSSIBLE to hide — require_tool prints a `LIVE-ASSERTED` marker when the
-- predicate is true, so a hollow/skipped pass on a capable host is detectable.
--
-- Three distinct mechanisms:
--   * require_env  — whole-tier env opt-in flag (absent => loud SKIP + exit 0).
--   * require_tool — whole-tier dependency predicate (absent => loud SKIPPED
--                    (reason=...) + exit 0; present => LIVE-ASSERTED + return).
--   * soft_skip    — per-ASSERTION graceful skip (no exit): the live host lacked
--                    the data to exercise THIS one check (e.g. no conflicts on a
--                    clean session). NOT a failure and NOT the whole-tier skip.

local M = {}

-- require_env(flag, label): whole-tier env opt-in. When the env var `flag` is not
-- exactly "1", print a loud SKIP line and exit 0 (a clean no-op). Generalizes
-- keys_integration_test.lua 109-112 (WEZTERM_INTEGRATION) so 06.9 plugs in
-- WEZ_E2E_INPUT / WEZ_E2E_VISUAL. Returns true when the flag IS set so a caller
-- can branch instead of relying on the exit.
function M.require_env(flag, label)
  if os.getenv(flag) ~= "1" then
    print(string.format("%s: SKIP (%s != 1)", tostring(label), tostring(flag)))
    os.exit(0)
  end
  return true
end

-- require_tool(probe_fn, label, reason): whole-tier dependency predicate.
-- probe_fn() returns truthy when the dependency (mux, input tool, permission) IS
-- present. FALSE => print a loud `SKIPPED (reason=...)` line and exit 0. TRUE =>
-- print a `LIVE-ASSERTED (...)` marker and RETURN true so the caller runs the
-- live assertions. Generalizes the display-capable predicate gate
-- (keys_integration_test.lua 121-141): a skip on a capable host is impossible to
-- hide because the LIVE-ASSERTED marker only prints when the host is capable.
function M.require_tool(probe_fn, label, reason)
  local ok = probe_fn and probe_fn() or false
  if not ok then
    print(string.format("%s: SKIPPED (reason=%s)", tostring(label), tostring(reason)))
    os.exit(0)
  end
  print(string.format("%s: LIVE-ASSERTED (%s)", tostring(label), tostring(reason)))
  return true
end

-- soft_skip(label, why): per-ASSERTION graceful skip WITHOUT exit. The live host
-- is capable but lacked the data to exercise this ONE check. Distinct from a
-- whole-tier skip — the file keeps running and the LIVE-ASSERTED marker (already
-- printed by require_tool) still stands. Lifted from keys_integration_test.lua
-- 71-73.
function M.soft_skip(label, why)
  print(string.format("  skip - %s  (%s)", tostring(label), tostring(why)))
end

return M
