-- tests/e2e/tier3/registration_e2e_test.lua
--
-- Tier 3 (registration layer) — the DETERMINISTIC "is every curated chord still
-- registered?" contract (PRD Appendix A.3 curated inventory; D-06/D-07/D-08).
--
-- BACKGROUND: a binding can silently DISAPPEAR from the effective key map (a
-- merge that drops a chord, a disabled-default that masks the wrong key) without
-- any error — the dead new-tab binding class. This tier parses the LIVE
-- `wezterm show-keys --lua` effective table via the string-only
-- cli/lib/showkeys.parse (NEVER load()/eval — T-06.7-10) and asserts that every
-- curated action still registers the chord FAMILIES it MUST have on the running
-- OS (tests/e2e/platform.lua's chord_families row, Plan 03 / D-06).
--
-- TWO-LAYER STRUCTURE (mirrors keys_siblings_e2e_test.lua):
--   1. CROSS-PLATFORM (ALWAYS runs, no live wezterm needed): assert the PRD A.3
--      curated list cross-checks against config/wezterm-setup/keybindings.lua's
--      M.keys (D-07) — a PRD action with NO binding is SURFACED as a FAIL, never
--      silently dropped — and that platform.chord_families covers every curated
--      action for the running OS.
--   2. LIVE-GATED: skip.require_tool gates on a runnable `wezterm`. On a capable
--      host it parses `wezterm show-keys --lua` and asserts, per curated action,
--      that EVERY platform-expected family registers. The SpawnTab CTRL-family
--      assertion is the dead-new-tab catch on Linux (the exact registration Plan
--      04's break harness drops). Without a runnable wezterm it loud-SKIPs.
--
-- LINUX CATCH-SCOPE (D-06): the test asserts only families that legitimately
-- register on the running OS, so on Linux it catches a dropped binding only in a
-- family that actually appears (SpawnTab via its CTRL-family Ctrl+Shift+T fold —
-- the managed SUPER+T is WM-shadowed and absent, so a SUPER+T loss is invisible
-- here; the CTRL-family loss IS caught). See platform.chord_families.note.
--
-- Run directly:  WEZ_BIN=./dist/wez lua5.4 tests/e2e/tier3/registration_e2e_test.lua

-- package.path bootstrap (three `..` -> repo root; + harness lib + e2e + cli/vendor
-- + repo root for the dotted cli.lib.showkeys / config.wezterm-setup.keybindings).
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../../.." -- tests/e2e/tier3 -> repo root (three ..)
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
local showkeys = require("cli.lib.showkeys")
local keybindings = require("config.wezterm-setup.keybindings")
local check = h.check

local OS = platform.platform_os()

-- The PRD Appendix A.3 curated action inventory, VERBATIM. Keyed by the WezTerm
-- action TYPE name as declared in keybindings.lua's `action.type` (D-07).
local CURATED = {
  "ClearScreenAndScrollback",
  "SpawnTab",
  "CloseCurrentTab",
  "ActivateTabRelative",
  "MoveTabRelative",
  "SplitHorizontal",
  "SplitVertical",
  "CloseCurrentPane",
  "TogglePaneZoomState",
  "RotatePanes",
  "ActivatePaneDirection",
  "IncreaseFontSize",
  "DecreaseFontSize",
  "ResetFontSize",
  "SendString",
}

-- Some curated actions resolve to a DIFFERENT live action name in the effective
-- table (init.lua resolve_action). ClearScreenAndScrollback is sugar over
-- WezTerm's native ClearScrollback (config/wezterm-setup/init.lua:63-64), so the
-- live records carry "ClearScrollback". Map curated name -> live match token; an
-- absent entry means the curated name matches verbatim.
local LIVE_MATCH = {
  ClearScreenAndScrollback = "ClearScrollback",
}

-- Membership over a families list (order-independent).
local function has_value(list, want)
  for _, v in ipairs(list or {}) do
    if v == want then return true end
  end
  return false
end

-- The chord FAMILIES a `mods` string belongs to (token containment, D-06):
-- contains SUPER -> Cmd-family; CTRL -> Ctrl-family; ALT -> Alt-family.
local function families_of(mods)
  local set = {}
  if mods:find("SUPER", 1, true) then set.SUPER = true end
  if mods:find("CTRL", 1, true) then set.CTRL = true end
  if mods:find("ALT", 1, true) then set.ALT = true end
  return set
end

-- ===========================================================================
-- (1) CROSS-PLATFORM — ALWAYS runs, deterministic, no live wezterm needed.
-- Cross-check the PRD A.3 curated list against keybindings.lua M.keys (D-07): a
-- curated action with no binding is a SURFACED FAIL, not a silent drop. Also
-- assert platform.chord_families covers every curated action for the running OS.
-- ===========================================================================

-- Collect the set of action TYPE names actually bound in keybindings.lua.
local bound = {}
for _, b in ipairs(keybindings.keys or {}) do
  if type(b.action) == "table" and b.action.type then
    bound[b.action.type] = true
  end
end

for _, action in ipairs(CURATED) do
  check("PRD A.3 curated action `" .. action .. "` is bound in keybindings.lua (D-07)",
    bound[action] == true,
    "PRD curated action " .. action .. " has no binding in keybindings.lua")
end

local cf = platform.expectations.chord_families
check("platform.lua exposes the chord_families expectation row (Plan 03)", cf ~= nil)
check("chord_families documents the SUPER/expected[os]/Linux-catch-scope rationale",
  cf ~= nil and type(cf.note) == "string" and cf.note:find("SUPER", 1, true) ~= nil)

local expected_os = cf and cf[OS] or nil
check("chord_families covers the running OS (`" .. OS .. "`)", expected_os ~= nil)
for _, action in ipairs(CURATED) do
  check("chord_families[" .. OS .. "] covers curated action `" .. action .. "`",
    expected_os ~= nil and type(expected_os[action]) == "table" and #expected_os[action] > 0)
end

-- Emit the cross-platform tally NOW so it reports BEFORE the gate's exit. Capture
-- it so a cross-platform FAIL still fails the file even if the live layer skips.
local xplat_rc = h.footer()

-- ===========================================================================
-- (2) LIVE-GATED — parse `wezterm show-keys --lua` and assert per-action families.
-- require_tool gates on a runnable wezterm: absent => loud SKIPPED + exit 0;
-- present => LIVE-ASSERTED marker (a hollow skip on a capable host is impossible
-- to hide). The captured text is reused so we do not shell show-keys twice.
-- ===========================================================================

local showkeys_text = nil
local function wezterm_runnable()
  if h.run_capture("command -v wezterm") == "" then return false end
  showkeys_text = h.run_capture("wezterm show-keys --lua")
  return type(showkeys_text) == "string" and showkeys_text:match("keys%s*=%s*{") ~= nil
end

-- The reason string is printed on BOTH the LIVE-ASSERTED and the SKIPPED line, so
-- keep it path-neutral: it names the dependency, reading sensibly either way.
skip.require_tool(
  wezterm_runnable,
  "tier3 show-keys registration",
  "needs a runnable `wezterm` on PATH for `wezterm show-keys --lua`")

-- ---- live assertions (reached ONLY when wezterm is runnable) ----
-- Parse the effective top-level keys array (modal key_tables excluded — D-08).
-- NEVER load()/eval the untrusted text: showkeys.parse is string-only (T-06.7-10).
local records, dropped = showkeys.parse(showkeys_text)
check("show-keys parsed into a non-empty effective key map", #records > 0,
  "0 records parsed from show-keys")
check("show-keys parse dropped NO record lines (parser-regression guard)", dropped == 0,
  "dropped=" .. tostring(dropped))

-- Bucket the registered families by curated action (substring match on the action
-- name / its live-resolved token). The action string is kept opaque — we only
-- test substring membership and the chord's mods, never execute it.
local registered = {}
for _, action in ipairs(CURATED) do
  registered[action] = {}
end
for _, rec in ipairs(records) do
  for _, action in ipairs(CURATED) do
    local token = LIVE_MATCH[action] or action
    if rec.action:find(token, 1, true) then
      for fam in pairs(families_of(rec.mods)) do
        registered[action][fam] = true
      end
    end
  end
end

-- For each curated action assert EVERY platform-expected family registers (D-06).
-- A missing expected family is a FAIL naming the action + the missing family.
-- SpawnTab's CTRL family on Linux is the dead-new-tab catch (the exact loss Plan
-- 04 injects): drop the Ctrl+Shift+T new-tab fold and this assertion FAILS.
for _, action in ipairs(CURATED) do
  local want = (expected_os and expected_os[action]) or {}
  for _, fam in ipairs(want) do
    check(string.format("registration: `%s` registers a %s-family chord (D-06)", action, fam),
      registered[action][fam] == true,
      string.format("expected %s-family chord for %s, found none in the live key map", fam, action))
  end
end

-- Belt-and-braces: the headline dead-new-tab catch made explicit, so a regression
-- on this box flips a NAMED assertion (this is the registration Plan 04 drops).
do
  local spawn_want = (expected_os and expected_os.SpawnTab) or {}
  if has_value(spawn_want, "CTRL") then
    check("dead-new-tab catch: SpawnTab registers a CTRL-family chord (Plan 04 break target)",
      registered.SpawnTab.CTRL == true,
      "no CTRL-family chord registers SpawnTab — the dead new-tab regression")
  else
    skip.soft_skip("SpawnTab CTRL-family catch",
      OS .. " does not expect a CTRL-family SpawnTab chord")
  end
end

-- A cross-platform FAIL must fail the file even when the live layer is green.
os.exit(h.footer() == 0 and xplat_rc or 1)
