-- tests/e2e/tier1/keys_siblings_e2e_test.lua
--
-- Tier 1 (deterministic subcommand layer) — the KEYS-SIBLINGS bundle-symlink
-- contract that `wez keys` depends on (PRD Appendix A.5 bundle-siblings parity row).
--
-- BACKGROUND: `wez keys` runs `wezterm show-keys --lua` (cli/commands/keys.lua),
-- and on macOS the `wezterm` binary re-execs the SIBLING `wezterm-gui` RELATIVE TO
-- its own resolved path. The WezTerm.app bundle keeps those siblings inside the
-- app, so the macOS installer must symlink ALL of them (`wezterm`, `wezterm-gui`,
-- `wezterm-mux-server`, `strip-ansi-escapes`) into ${BIN_DIR} or the re-exec fails
-- NotFound (Os code 2). On Linux these binaries ship on PATH already, so there is
-- no sibling-symlink step. The archived fix is 4c765e1 (Phase 7 / D-18, D-06).
--
-- TWO-LAYER STRUCTURE (OS-detect + loud skip-gate):
--   1. CROSS-PLATFORM (ALWAYS runs, green on Linux NOW): assert the sibling-bundle
--      REQUIREMENT itself — that tests/e2e/platform.lua's `bundle_siblings` parity
--      row names exactly the three macOS siblings `wez keys` needs (wezterm-gui,
--      wezterm-mux-server, strip-ansi-escapes) and that Linux needs none. This is
--      OS-independent to check (it asserts the data table, not a live install) and
--      is the single source of truth the macOS installer must honor.
--   2. macOS-SPECIFIC (PRESENT but skip.lua-GATED): the live-install symlink
--      contract. On non-macOS it emits a LOUD `SKIPPED (reason=…)` line (a loud
--      SKIP counts as PASS — make test / make e2e stay exit 0) and is shaped to
--      FIRE on macOS once Phase 7's `install_macos` lands. It asserts ONLY the
--      sibling-symlink contract — NOT the archived installer's fetch/extract
--      symbols (wezterm_macos_asset_url, ditto, 504b0304, WezTerm.app, cp -R),
--      which are Phase-7 surface that does not exist on this mainline.
--
-- Run directly:  WEZ_BIN=./dist/wez lua5.4 tests/e2e/tier1/keys_siblings_e2e_test.lua

-- package.path bootstrap (three `..` -> repo root; + harness lib + cli/vendor).
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../../.." -- tests/e2e/tier1 -> repo root (three ..)
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/tests/e2e/lib/?.lua",
  repo_root .. "/tests/e2e/?.lua", -- tests/e2e/platform.lua (the parity table)
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local h = require("harness")
local skip = require("skip")
local platform = require("platform")
local check = h.check

-- Resolve the runtime OS via the same detection platform.sh / platform.lua use.
local OS = platform.platform_os()

-- A set-membership helper over a parity-row list (order-independent).
local function has_value(list, want)
  for _, v in ipairs(list or {}) do
    if v == want then return true end
  end
  return false
end

-- ===========================================================================
-- (1) CROSS-PLATFORM — ALWAYS runs, green on Linux NOW. Assert the sibling-bundle
-- requirement via platform.lua's `bundle_siblings` parity row (the single source
-- of truth the macOS installer must honor). OS-independent: it asserts the data
-- table, not a live install.
-- ===========================================================================
local siblings = platform.expectations.bundle_siblings
check("platform.lua exposes the bundle_siblings parity row", siblings ~= nil)
check("bundle_siblings names wezterm-gui (the sibling `wezterm show-keys` re-execs)",
  has_value(siblings.mac, "wezterm-gui"))
check("bundle_siblings names wezterm-mux-server",
  has_value(siblings.mac, "wezterm-mux-server"))
check("bundle_siblings names strip-ansi-escapes",
  has_value(siblings.mac, "strip-ansi-escapes"))
check("bundle_siblings: Linux needs NO sibling symlinks (binaries on PATH already)",
  type(siblings.linux) == "table" and #siblings.linux == 0)
check("bundle_siblings row documents WHY the macOS delta is legitimate",
  type(siblings.note) == "string" and siblings.note:find("macOS", 1, true) ~= nil)

-- ===========================================================================
-- (2) macOS-SPECIFIC — skip.lua-GATED. On non-macOS this prints a loud
-- `SKIPPED (reason=…)` line and returns (counts as PASS). On macOS it FIRES the
-- live-install sibling-symlink contract (Phase 7, once install_macos lands).
--
-- require_tool exits 0 on skip, so we print the cross-platform footer tally FIRST
-- (the always-run assertions above must report before the gate's exit), then
-- gate. probe_fn returns true ONLY on macOS.
-- ===========================================================================

-- CR-01/WR-01: close the always-run cross-platform layer before the macOS gate.
-- finish_layer emits the tally, EXITS now if any cross-platform check failed (so
-- the skip.require_tool os.exit(0) on non-macOS below cannot mask a parity-row
-- regression — the false-green class), and resets so the macOS layer's footer
-- counts only itself.
h.finish_layer()

skip.require_tool(
  function() return OS == "macos" end,
  "keys-siblings macOS bundle-symlink contract",
  "macOS — deferred to Phase 7 / install_macos is a design-only stub (D-18, D-06)")

-- ---- macOS-only live assertions (reached ONLY when OS == macos) ----
-- Phase 7 wires install_macos to symlink the bundle siblings into ${BIN_DIR}.
-- When that lands, assert each sibling resolves on PATH so `wez keys` works. Until
-- then this branch is unreached on Linux (require_tool exited above) and is the
-- explicit FIRE target on macOS. We assert the live PATH resolution of each
-- sibling the parity row names — NOT the archived installer's fetch/extract
-- internals (those are Phase-7 surface, asserted by Phase 7's own bootstrap test).
local function on_path(bin)
  local p = io.popen("command -v " .. bin .. " 2>/dev/null", "r")
  if not p then return false end
  local out = (p:read("*l") or "")
  p:close()
  return out ~= ""
end

for _, sib in ipairs({ "wezterm", "wezterm-gui", "wezterm-mux-server", "strip-ansi-escapes" }) do
  check("macOS: bundle sibling `" .. sib .. "` resolves on PATH (installer symlinked it)",
    on_path(sib))
end

-- The cross-platform layer already passed (a FAIL would have exited above via
-- finish_layer), and the tally was reset, so this footer is the macOS layer's own
-- result and is the file's exit code.
os.exit(h.footer())
