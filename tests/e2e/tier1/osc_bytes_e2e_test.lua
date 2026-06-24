-- tests/e2e/tier1/osc_bytes_e2e_test.lua
--
-- Tier 1 (deterministic subcommand layer) — EMITTED-OSC-BYTE well-formedness.
-- Per PRD Appendix A.1, this file locks the byte contract for the `wez pane/tab
-- color|title|icon` (+ reset/clear) subcommands: user-vars and the pane background
-- reach the terminal as PROGRAM OUTPUT (the subcommand's own stdout), and 06.7's
-- reuse-pane scene styling depends on EXACTLY these bytes. Getting the byte
-- contract right here de-risks 06.7.
--
-- Every assertion recomputes the EXPECTED bytes from the REAL emitter — never a
-- hardcoded literal — so the byte contract has ONE source of truth per concern:
--   * the OSC FRAME comes from cli/lib/color.lua
--     (build_osc11 `ESC ]11; hex ESC \`, build_reset_osc11 `ESC ]111 BEL`,
--      build_osc1337 `ESC ]1337;SetUserVar=<name>=<base64> BEL`, _base64), and
--   * the ICON GLYPH comes from cli/lib/title.lua M.resolve_icon (the name->glyph
--     map lives THERE, not in color.lua).
-- A color.lua or title.lua change that breaks the contract fails this test (T-06.6-10);
-- the base64-encoding of every user-var value is asserted (T-06.6-09: a control-byte
-- input cannot break out of the OSC frame).
--
-- OSC-on-stdout rows covered (A.1): pane color / pane color reset, pane title /
-- pane title clear, pane icon, tab color / tab color reset, tab icon.
--   * pane color is a DUAL write: OSC-11 background (MUTED_BG[name]) + OSC-1337
--     WEZTERM_PANE_COLOR user-var — both asserted (de-risks the 06.7 stdout mechanism).
--   * tab color emits NO OSC-11 (background is pane-only) — only WEZTERM_TAB_COLOR.
--   * the icon carrier is WEZTERM_TAB_ICON for BOTH pane icon AND tab icon
--     (there is NO WEZTERM_PANE_ICON); the pane-title carrier is WEZTERM_TAB_TITLE.
-- Tab title is DELIBERATELY NOT byte-asserted here: `wez tab title` writes via
-- `wezterm cli set-tab-title` (a subprocess, NOT OSC-on-stdout — confirmed in
-- tab.lua run_title), so its exit-code/output-shape contract belongs to Plan 02.
--
-- The pane/tab color emitters use build_osc1337 (NOT the octal build_user_var_octal —
-- that form is for pane-TARGETED send-text, not these stdout commands), so the
-- expected bytes are built via build_osc1337.
--
-- Run directly:  WEZ_BIN=./dist/wez lua5.4 tests/e2e/tier1/osc_bytes_e2e_test.lua

-- package.path bootstrap: this file is at tests/e2e/tier1/, THREE levels below the
-- repo root, so repo_root needs three `..`. Add tests/e2e/lib (the harness) so the
-- shared TAP-ish harness and the cli.lib.* modules resolve.
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../../.." -- tests/e2e/tier1 -> repo root (three ..)
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/tests/e2e/lib/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local h = require("harness")
local check = h.check
local run_capture = h.run_capture
local shquote = h.shquote
local WEZ = h.WEZ

-- The REAL emitter modules — the single sources of truth for the byte contract.
-- color.lua owns the OSC FRAME (prefix + terminator + base64); title.lua owns the
-- icon name->glyph resolution (color.lua has NO icon map). EXPECTED bytes are
-- recomputed from these on every assertion — never a hardcoded base64 or glyph.
local color = require("cli.lib.color")
local title = require("cli.lib.title")

local build_osc11 = color.build_osc11
local build_reset_osc11 = color.build_reset_osc11
local build_osc1337 = color.build_osc1337
local b64 = color._base64
local resolve_icon = title.resolve_icon

-- Literal substring presence: the captured stdout must CONTAIN the expected bytes
-- (find with plain=true — NOT a Lua pattern, so the OSC control bytes are matched
-- verbatim). Returns true when `expected` occurs anywhere in `captured`.
local function contains(captured, expected)
  return captured:find(expected, 1, true) ~= nil
end

-- Run `wez <subcmd>` capturing STDOUT ONLY (these commands write their OSC to their
-- own stdout) -> (captured_bytes, exit_code). stderr is discarded by run_capture.
local function run_wez(subcmd)
  return run_capture(shquote(WEZ) .. " " .. subcmd)
end

-- ---------------------------------------------------------------------------
-- pane color <name>: DUAL write — OSC-11 background (MUTED_BG[name]) + OSC-1337
-- WEZTERM_PANE_COLOR user-var (base64 of the NAME). Assert BOTH, plus the OSC-11
-- `\27]11;` prefix and the `\27\\` ST terminator explicitly (pane color only).
-- ---------------------------------------------------------------------------
do
  local out, code = run_wez("pane color cyan")
  check("`wez pane color cyan` exits 0", code == 0, "exit=" .. tostring(code))

  -- OSC-11 background: the muted hex is color.MUTED_BG.cyan (NOT the raw name) — the
  -- expected frame is recomputed from the real builder + the real muted-bg map.
  local expect_osc11 = build_osc11(color.MUTED_BG.cyan)
  check("`wez pane color cyan` emits OSC-11 background (build_osc11(MUTED_BG.cyan))",
    contains(out, expect_osc11), "missing OSC-11 frame")
  -- The OSC-11 prefix `\27]11;` and the ST terminator `\27\\` must BOTH be present.
  check("`wez pane color cyan` OSC-11 has `\\27]11;` prefix", contains(out, "\27]11;"))
  check("`wez pane color cyan` OSC-11 has `\\27\\\\` ST terminator", contains(out, "\27\\"))

  -- OSC-1337 WEZTERM_PANE_COLOR user-var: prefix + BEL + base64(name) — recompute.
  local expect_uv = build_osc1337("WEZTERM_PANE_COLOR", "cyan")
  check("`wez pane color cyan` emits OSC-1337 WEZTERM_PANE_COLOR (build_osc1337(\"cyan\"))",
    contains(out, expect_uv), "missing WEZTERM_PANE_COLOR user-var")
  check("`wez pane color cyan` OSC-1337 has `SetUserVar=WEZTERM_PANE_COLOR=` prefix",
    contains(out, "\27]1337;SetUserVar=WEZTERM_PANE_COLOR="))
  check("`wez pane color cyan` OSC-1337 base64 value == color._base64(\"cyan\")",
    contains(out, "WEZTERM_PANE_COLOR=" .. b64("cyan") .. "\7"), "base64/BEL mismatch")
end

-- ---------------------------------------------------------------------------
-- pane color reset: OSC-111 BEL-terminated reset (`\27]111\7`) + OSC-1337
-- WEZTERM_PANE_COLOR with an EMPTY payload (the accent clear).
-- ---------------------------------------------------------------------------
do
  local out, code = run_wez("pane color reset")
  check("`wez pane color reset` exits 0", code == 0, "exit=" .. tostring(code))

  check("`wez pane color reset` emits OSC-111 reset `\\27]111\\7`",
    contains(out, build_reset_osc11()), "missing OSC-111 reset")
  check("`wez pane color reset` OSC-111 bytes are exactly `\\27]111\\7`",
    contains(out, "\27]111\7"))
  -- The accent clear: WEZTERM_PANE_COLOR with the empty-string base64 payload.
  check("`wez pane color reset` emits empty WEZTERM_PANE_COLOR (build_osc1337(\"\"))",
    contains(out, build_osc1337("WEZTERM_PANE_COLOR", "")), "missing empty accent clear")
  check("`wez pane color reset` WEZTERM_PANE_COLOR= base64 == color._base64(\"\")",
    contains(out, "WEZTERM_PANE_COLOR=" .. b64("") .. "\7"))
end

-- ---------------------------------------------------------------------------
-- pane title <text>: OSC-1337 user-var on stdout. The pane-title carrier is
-- WEZTERM_TAB_TITLE (NOT a WEZTERM_PANE_TITLE) — base64 of the literal text.
-- ---------------------------------------------------------------------------
do
  local out, code = run_wez("pane title api")
  check("`wez pane title api` exits 0", code == 0, "exit=" .. tostring(code))

  check("`wez pane title api` emits OSC-1337 WEZTERM_TAB_TITLE (build_osc1337(\"api\"))",
    contains(out, build_osc1337("WEZTERM_TAB_TITLE", "api")), "missing WEZTERM_TAB_TITLE")
  check("`wez pane title api` OSC-1337 has `SetUserVar=WEZTERM_TAB_TITLE=` prefix",
    contains(out, "\27]1337;SetUserVar=WEZTERM_TAB_TITLE="))
  check("`wez pane title api` OSC-1337 base64 value == color._base64(\"api\")",
    contains(out, "WEZTERM_TAB_TITLE=" .. b64("api") .. "\7"), "base64/BEL mismatch")
end

-- pane title clear (reset): well-formed OSC-1337 WEZTERM_TAB_TITLE with the EMPTY
-- (cleared) base64 value — recompute color._base64("").
do
  local out, code = run_wez("pane title reset")
  check("`wez pane title reset` exits 0", code == 0, "exit=" .. tostring(code))

  check("`wez pane title reset` emits empty WEZTERM_TAB_TITLE (build_osc1337(\"\"))",
    contains(out, build_osc1337("WEZTERM_TAB_TITLE", "")), "missing cleared title")
  check("`wez pane title reset` WEZTERM_TAB_TITLE= base64 == color._base64(\"\")",
    contains(out, "WEZTERM_TAB_TITLE=" .. b64("") .. "\7"))
end

-- ---------------------------------------------------------------------------
-- pane icon <name>: OSC-1337 SetUserVar=WEZTERM_TAB_ICON= base64. The icon carrier
-- is WEZTERM_TAB_ICON (SHARED across pane + tab; there is NO WEZTERM_PANE_ICON).
-- The glyph MUST be resolved via title.resolve_icon("python") (the ICONS-map glyph),
-- THEN base64-encoded via color._base64 — never a hardcoded glyph or base64 literal.
-- ---------------------------------------------------------------------------
do
  local out, code = run_wez("pane icon python")
  check("`wez pane icon python` exits 0", code == 0, "exit=" .. tostring(code))

  -- Expected value chain: name -> glyph (title.resolve_icon) -> base64 (color._base64).
  local expect_icon = build_osc1337("WEZTERM_TAB_ICON", resolve_icon("python"))
  check("`wez pane icon python` emits OSC-1337 WEZTERM_TAB_ICON (resolve_icon->build_osc1337)",
    contains(out, expect_icon), "missing WEZTERM_TAB_ICON")
  check("`wez pane icon python` OSC-1337 has `SetUserVar=WEZTERM_TAB_ICON=` prefix",
    contains(out, "\27]1337;SetUserVar=WEZTERM_TAB_ICON="))
  check("`wez pane icon python` base64 == color._base64(title.resolve_icon(\"python\"))",
    contains(out, "WEZTERM_TAB_ICON=" .. b64(resolve_icon("python")) .. "\7"),
    "glyph->base64 chain mismatch")
end

-- ---------------------------------------------------------------------------
-- tab color <name> / reset: OSC-1337 SetUserVar=WEZTERM_TAB_COLOR= base64. NOTE:
-- `wez tab color` does NOT emit an OSC-11 background (that is pane-only) — assert
-- ONLY the WEZTERM_TAB_COLOR user-var (and its absence of OSC-11).
-- ---------------------------------------------------------------------------
do
  local out, code = run_wez("tab color cyan")
  check("`wez tab color cyan` exits 0", code == 0, "exit=" .. tostring(code))

  check("`wez tab color cyan` emits OSC-1337 WEZTERM_TAB_COLOR (build_osc1337(\"cyan\"))",
    contains(out, build_osc1337("WEZTERM_TAB_COLOR", "cyan")), "missing WEZTERM_TAB_COLOR")
  check("`wez tab color cyan` OSC-1337 has `SetUserVar=WEZTERM_TAB_COLOR=` prefix",
    contains(out, "\27]1337;SetUserVar=WEZTERM_TAB_COLOR="))
  check("`wez tab color cyan` OSC-1337 base64 value == color._base64(\"cyan\")",
    contains(out, "WEZTERM_TAB_COLOR=" .. b64("cyan") .. "\7"), "base64/BEL mismatch")
  -- tab color is user-var ONLY: no OSC-11 background frame on stdout (pane-only).
  check("`wez tab color cyan` emits NO OSC-11 background (`\\27]11;` absent)",
    not contains(out, "\27]11;"), "unexpected OSC-11 from tab color")
end

do
  local out, code = run_wez("tab color reset")
  check("`wez tab color reset` exits 0", code == 0, "exit=" .. tostring(code))

  check("`wez tab color reset` emits empty WEZTERM_TAB_COLOR (build_osc1337(\"\"))",
    contains(out, build_osc1337("WEZTERM_TAB_COLOR", "")), "missing cleared tab color")
  check("`wez tab color reset` WEZTERM_TAB_COLOR= base64 == color._base64(\"\")",
    contains(out, "WEZTERM_TAB_COLOR=" .. b64("") .. "\7"))
end

-- ---------------------------------------------------------------------------
-- tab icon <name>: OSC-1337 SetUserVar=WEZTERM_TAB_ICON= base64. SAME carrier AND
-- SAME resolution chain (resolve_icon -> _base64) as pane icon — never hardcoded.
-- ---------------------------------------------------------------------------
do
  local out, code = run_wez("tab icon python")
  check("`wez tab icon python` exits 0", code == 0, "exit=" .. tostring(code))

  local expect_icon = build_osc1337("WEZTERM_TAB_ICON", resolve_icon("python"))
  check("`wez tab icon python` emits OSC-1337 WEZTERM_TAB_ICON (resolve_icon->build_osc1337)",
    contains(out, expect_icon), "missing WEZTERM_TAB_ICON")
  check("`wez tab icon python` OSC-1337 has `SetUserVar=WEZTERM_TAB_ICON=` prefix",
    contains(out, "\27]1337;SetUserVar=WEZTERM_TAB_ICON="))
  check("`wez tab icon python` base64 == color._base64(title.resolve_icon(\"python\"))",
    contains(out, "WEZTERM_TAB_ICON=" .. b64(resolve_icon("python")) .. "\7"),
    "glyph->base64 chain mismatch")
end

os.exit(h.footer())
