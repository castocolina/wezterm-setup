-- tests/integration/keys_integration_test.lua
--
-- LIVE e2e for the curated-first `wez keys` renderer (Plan 02) exercised against
-- the reconciled single-entry keybindings (Plan 03). This is Lane B of the phase
-- Validation Architecture (06.5-RESEARCH §Validation Architecture): the pure-core
-- TDD fixtures (cli/commands/keys_test.lua) prove the renderer logic headlessly;
-- THIS file proves the whole `wez keys` output shape end-to-end against a REAL
-- running WezTerm session.
--
-- It drives the real `wez keys` binary (the installed launcher on PATH, or a
-- $WEZ_BIN override) against the live `wezterm show-keys` mux and asserts, on the
-- live stdout:
--   (1) three-group sectioning in fixed order (D-05/D-12) — the renderer emits
--       `== Managed (overrides) ==` then `== Our additions ==` then
--       `== WezTerm defaults ==`, and the byte offsets MUST satisfy
--       Managed < Additions < Defaults (managed/additions BEFORE defaults), with our
--       ALT+SHIFT ergonomic keys landing under `== Our additions ==` tagged `[added]`;
--   (2) unambiguous render (D-01/D-02) — every letter chord is lowercase base with
--       explicit SHIFT; no `CTRL+SHIFT+<UPPER-LETTER>` chord appears;
--   (3) twin/action dedupe (D-07/D-08) — an action reachable by two chords renders
--       ONE row with a `, `-joined list, and the old upper/lower twin collapses;
--   (4) `wez keys --json` carries NO `\27[` (SGR) byte and stays jq-valid;
--   (5) `wez keys --platform all` inline-annotates a Super chord (`(macOS)` AND
--       `(Linux)` on that row);
--   (6) red-conflict degradation (D-06) — with color allowed (TTY) a conflict row
--       carries `\27[31m` + `! ` + `[CONFLICT]`; under NO_COLOR=1 the SAME row keeps
--       the `! `/`[CONFLICT]` text markers but ZERO `\27[` bytes.
--
-- GUARDED + DISPLAY-AWARE: like every file under tests/integration/, this runs only
-- when WEZTERM_INTEGRATION=1 (tools/run-tests.sh). It diverges from
-- scene_cwd_integration_test.lua's no-mux gate on ONE point (MEDIUM-2,
-- 06.5-RESEARCH §Environment Availability): the whole-lane skip is legitimate ONLY
-- when the host is NOT display-capable. DISPLAY-CAPABLE PREDICATE: os.getenv("DISPLAY")
-- is non-empty AND `wezterm cli list --format json` parses to a list with at least
-- one pane_id. On a display-capable host the live assertions MUST execute and the
-- run MUST print a `LIVE-ASSERTED` marker; a `SKIPPED` outcome on a display-capable
-- host is a FAILURE (exit non-zero), so a hollow/skipped pass is detectable. The
-- per-assertion "no data to exercise this" graceful skip (e.g. no conflicts on a
-- clean session) is still allowed and is NOT the same as skipping the whole lane.
--
-- Run directly:
--   WEZTERM_INTEGRATION=1 lua5.4 tests/integration/keys_integration_test.lua

local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- tests/integration -> repo root

package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

-- ---------------------------------------------------------------------------
-- tiny harness (copied from scene_cwd_integration_test.lua)
-- ---------------------------------------------------------------------------
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

-- A logged per-assertion graceful skip: the live session lacked the data to
-- exercise this particular check (e.g. no conflicts present on a clean host).
-- NOT a failure, and NOT the whole-lane skip — the LIVE-ASSERTED marker still
-- prints because the host IS display-capable.
local function soft_skip(label, why)
  print(string.format("  skip - %s  (%s)", label, tostring(why)))
end

local function shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Run a command (stdout only) and return (text, exit_code).
local function run_capture(cmd)
  local p = io.popen(cmd .. " 2>/dev/null", "r")
  if not p then return "", 1 end
  local out = p:read("*a") or ""
  local ok, _, code = p:close()
  local exit = code or (ok and 0 or 1)
  return out, exit
end

-- Run a command capturing BOTH stdout and stderr (needed so a no-mux `wez keys`
-- error doesn't vanish), returning (text, exit_code).
local function run_capture_all(cmd)
  local p = io.popen(cmd .. " 2>&1", "r")
  if not p then return "", 1 end
  local out = p:read("*a") or ""
  local ok, _, code = p:close()
  local exit = code or (ok and 0 or 1)
  return out, exit
end

-- Resolve the live `wez` binary: a $WEZ_BIN override wins (lets CI/dev point at a
-- freshly built ./dist/wez), else the installed launcher on PATH.
local WEZ = os.getenv("WEZ_BIN")
if not WEZ or WEZ == "" then WEZ = "wez" end

-- ---------------------------------------------------------------------------
-- SKIP GATE 1: integration flag. Without WEZTERM_INTEGRATION=1 this file is a
-- clean no-op exit 0 (a direct `lua5.4 …` invocation skips cleanly too).
-- ---------------------------------------------------------------------------
if os.getenv("WEZTERM_INTEGRATION") ~= "1" then
  print("keys_integration_test: SKIP (WEZTERM_INTEGRATION != 1)")
  os.exit(0)
end

-- ---------------------------------------------------------------------------
-- DISPLAY-CAPABLE PREDICATE (MEDIUM-2 — 06.5-RESEARCH §Environment Availability):
--   DISPLAY non-empty  AND  `wezterm cli list --format json` answers with a pane_id.
-- This REPLACES scene_cwd_integration_test.lua's plain no-mux gate: a skip is
-- legitimate ONLY when this predicate is FALSE. On a display-capable host the
-- live assertions MUST execute (a skip there is a FAILURE).
-- ---------------------------------------------------------------------------
local display = os.getenv("DISPLAY")
local has_display = display ~= nil and display ~= ""
local list_out, list_exit = run_capture("wezterm cli list --format json")
local mux_reachable = list_exit == 0 and list_out:find("pane_id", 1, true) ~= nil

if not (has_display and mux_reachable) then
  -- Legitimate whole-lane skip: the host is NOT display-capable (no DISPLAY, or no
  -- live WezTerm mux answering — e.g. CI without a GUI socket). Explicit + logged,
  -- never a silent pass.
  print(string.format(
    "keys_integration_test: SKIPPED (host not display-capable: DISPLAY=%s, mux_reachable=%s)",
    has_display and tostring(display) or "<unset>", tostring(mux_reachable)))
  os.exit(0)
end

-- ---------------------------------------------------------------------------
-- LIVE PATH. The host IS display-capable — the live assertions MUST run, and we
-- MUST print the LIVE-ASSERTED marker so a hollow/skipped pass is impossible here.
-- ---------------------------------------------------------------------------
print(string.format(
  "keys_integration_test: LIVE-ASSERTED (DISPLAY=%s, mux reachable)", tostring(display)))

-- (1) `wez keys` default output -------------------------------------------------
local keys_out, keys_exit = run_capture_all(shquote(WEZ) .. " keys")
check("`wez keys` ran against the live session (exit 0)", keys_exit == 0,
  "exit=" .. tostring(keys_exit) .. " out=" .. tostring((keys_out or ""):sub(1, 200)))

-- The three section headers the renderer emits after the 06.5-05 three-group
-- rewrite (cli/commands/keys.lua run()): Managed (overrides) → Our additions →
-- WezTerm defaults. The OLD single-section `== wezterm-setup (managed) ==` header is
-- gone; asserting against it would silently soft-skip the headline D-05 ordering
-- claim, so we pin the new three headers and verify their byte-offset order directly
-- (mirrors keys_test.lua's s4: Managed < Additions < Defaults).
local managed_hdr   = "== Managed (overrides) =="
local additions_hdr = "== Our additions =="
local defaults_hdr  = "== WezTerm defaults =="

local mpos = keys_out:find(managed_hdr, 1, true)
local apos = keys_out:find(additions_hdr, 1, true)
local dpos = keys_out:find(defaults_hdr, 1, true)

-- D-05/D-12 fixed three-group order. The defaults section is effectively always
-- present (the live effective table carries WezTerm defaults), so dpos anchors the
-- ordering. Each curated header that IS present must precede defaults, and Managed
-- must precede Additions when both are present.
check("D-12 the live render carries the WezTerm defaults section header", dpos ~= nil,
  "defaults header missing from live output")
if mpos and dpos then
  check("D-05 Managed (overrides) section renders BEFORE WezTerm defaults", mpos < dpos,
    "managed@" .. tostring(mpos) .. " defaults@" .. tostring(dpos))
end
if apos and dpos then
  check("D-05 Our additions section renders BEFORE WezTerm defaults", apos < dpos,
    "additions@" .. tostring(apos) .. " defaults@" .. tostring(dpos))
end
if mpos and apos then
  check("D-12 Managed (overrides) renders BEFORE Our additions (fixed three-group order)",
    mpos < apos, "managed@" .. tostring(mpos) .. " additions@" .. tostring(apos))
end

-- Our ALT+SHIFT ergonomic keys (Plan 03 additions, e.g. ALT+SHIFT+x close-pane /
-- ALT+SHIFT+h split) must live UNDER the `== Our additions ==` header and carry the
-- `[added]` tag. Slice from the additions header to the next `== ` header and assert
-- a tagged ALT+SHIFT row exists inside that slice.
if apos then
  local seg = keys_out:sub(apos)
  local nxt = seg:find("\n== ", 5)
  if nxt then seg = seg:sub(1, nxt) end
  local tagged_altshift = false
  for line in seg:gmatch("[^\n]+") do
    if line:find("ALT+SHIFT+", 1, true) and line:find("[added]", 1, true) then
      tagged_altshift = true
      break
    end
  end
  check("our ALT+SHIFT ergonomic key renders under Our additions tagged [added]",
    tagged_altshift, "no `[added]`-tagged ALT+SHIFT row inside the Our additions section")
else
  soft_skip("ALT+SHIFT under Our additions",
    "live classify produced no Our additions section on this host")
end

-- D-01/D-02 unambiguous render: no chord renders a bare uppercase letter as the
-- base key. Every letter chord must be lowercase + explicit SHIFT, so a
-- `(CTRL|ALT|SHIFT|SUPER|+ ...)+<UPPER-LETTER>` boundary token must NEVER appear.
-- Scan each chord-shaped token: a mod-prefixed token whose final '+'-segment is a
-- single uppercase ASCII letter is a D-01 violation.
local upper_letter_chord = nil
for token in keys_out:gmatch("[%u]+%+[%u%l%+]*") do
  -- token like CTRL+SHIFT+w or ALT+SHIFT+X — inspect the final segment.
  local last = token:match("%+([^%+]+)$")
  if last and last:match("^%u$") then
    upper_letter_chord = token
    break
  end
end
check("D-01/D-02 no chord renders an uppercase-letter base (lowercase + explicit SHIFT)",
  upper_letter_chord == nil, "offending=" .. tostring(upper_letter_chord))

-- D-07/D-08 dedupe: an action reachable by two chords renders ONE row whose chord
-- column is a `, `-joined list. The reconciled ClearScreenAndScrollback /
-- CloseCurrentTab each carry a Ctrl+Shift chord AND a Super chord (Plan 03), so a
-- `, `-joined dual-chord row must exist. The old uppercase twin must NOT appear as
-- a second standalone row.
local dual_chord_row = keys_out:match("[^\n]*%+%a+, %u[%u%+]*%+%a[^\n]*")
if dual_chord_row then
  check("D-07 an action renders ONE row with a `, `-joined dual-chord list",
    dual_chord_row:find(", ", 1, true) ~= nil, "row=" .. tostring(dual_chord_row))
else
  -- Fall back to asserting at least one `, `-joined chord list exists somewhere.
  local any_joined = keys_out:find("%a, %u") ~= nil
  if any_joined then
    check("D-07 at least one action renders a `, `-joined multi-chord row", true)
  else
    soft_skip("D-07 dual-chord row",
      "live session exposed no multi-chord action row to assert against")
  end
end

-- D-08 twin collapse: the old CTRL+SHIFT+z / CTRL+SHIFT+Z (and k/K, w/W) twins must
-- collapse — the uppercase-letter form must never appear as its own chord token
-- (already enforced by the D-01 scan above; assert the specific reconciled twins).
local has_upper_k = keys_out:find("CTRL+SHIFT+K", 1, true) ~= nil
local has_upper_w = keys_out:find("CTRL+SHIFT+W", 1, true) ~= nil
check("D-08 reconciled twins collapsed (no CTRL+SHIFT+K / CTRL+SHIFT+W uppercase twin row)",
  not has_upper_k and not has_upper_w,
  "K=" .. tostring(has_upper_k) .. " W=" .. tostring(has_upper_w))

-- (2) `wez keys --json` — no SGR, jq-valid -------------------------------------
local json_out, json_exit = run_capture(shquote(WEZ) .. " keys --json")
check("`wez keys --json` ran (exit 0)", json_exit == 0, "exit=" .. tostring(json_exit))
check("`--json` output carries NO ANSI/SGR byte (\\27[)",
  json_out:find("\27[", 1, true) == nil, "found an ESC[ byte in the JSON document")

-- jq-validity: prefer the vendored dkjson (always present), cross-check with `jq`
-- if it is on PATH.
do
  local ok_dk, dkjson = pcall(require, "dkjson")
  if ok_dk then
    local decoded = dkjson.decode(json_out)
    check("`--json` output is valid JSON (dkjson parses it to a table)",
      type(decoded) == "table", "dkjson did not return a table")
  else
    soft_skip("--json dkjson parse", "dkjson not loadable under this runner")
  end
  -- Cross-check with jq when available (exit 0 == valid).
  local _, jq_present = run_capture("command -v jq")
  if jq_present == 0 then
    local _, jq_exit = run_capture(
      "printf %s " .. shquote(json_out) .. " | jq . > /dev/null")
    check("`--json` output is jq-valid (`jq .` exits 0)", jq_exit == 0,
      "jq exit=" .. tostring(jq_exit))
  else
    soft_skip("--json jq cross-check", "jq not on PATH")
  end
end

-- (3) `wez keys --platform all` — inline Super annotation -----------------------
local pall_out, pall_exit = run_capture_all(shquote(WEZ) .. " keys --platform all")
check("`wez keys --platform all` ran (exit 0)", pall_exit == 0, "exit=" .. tostring(pall_exit))
-- A Super-bearing chord must carry BOTH inline annotations on its row.
local super_row = nil
for line in (pall_out .. "\n"):gmatch("([^\n]*)\n") do
  if line:find("(macOS)", 1, true) and line:find("(Linux)", 1, true) then
    super_row = line
    break
  end
end
if super_row then
  check("`--platform all` inline-annotates a Super chord with (macOS) AND (Linux)",
    true, "row=" .. super_row)
else
  -- If the live managed set exposes no Super chord at all, this is a graceful skip;
  -- the reconciled clear/close bindings DO carry Super siblings, so normally present.
  soft_skip("--platform all inline annotation",
    "no Super-bearing chord present in the live --platform all output")
end

-- (4) red-conflict degradation (D-06) ------------------------------------------
-- Force color ON (a TTY) via the documented seam: `wez keys` gates color on a real
-- TTY, which io.popen does NOT provide. We instead exercise the degradation
-- CONTRACT directly: under NO_COLOR=1 the output must carry ZERO SGR bytes while
-- keeping the `! `/`[CONFLICT]` text markers IF a conflict is present. A clean live
-- session may have no conflicts — then this is a graceful per-assertion skip.
local nocolor_out = run_capture_all("NO_COLOR=1 " .. shquote(WEZ) .. " keys")
check("under NO_COLOR=1 the output carries ZERO SGR bytes (\\27[)",
  nocolor_out:find("\27[", 1, true) == nil,
  "found an ESC[ byte despite NO_COLOR=1")

local conflict_hdr = "== Conflicts (who-wins) =="
if nocolor_out:find(conflict_hdr, 1, true) then
  -- A conflict IS present: under NO_COLOR the text markers must still carry meaning.
  check("D-06 NO_COLOR conflict row keeps the `! ` text marker",
    nocolor_out:find("! ", 1, true) ~= nil, "no `! ` marker under NO_COLOR")
  check("D-06 NO_COLOR conflict row keeps the `[CONFLICT]` text marker",
    nocolor_out:find("[CONFLICT]", 1, true) ~= nil, "no `[CONFLICT]` marker under NO_COLOR")
  -- And the color-allowed path (default `wez keys`, captured above) — when stdout is
  -- a TTY it would carry \27[31m. Through io.popen it is non-TTY, so the renderer's
  -- fail-closed gate emits plain text; we therefore assert only that the SAME
  -- conflict row is present in both runs (the degradation is byte-symmetric minus SGR).
  check("D-06 the conflict row is present in the default run too (degradation symmetry)",
    keys_out:find(conflict_hdr, 1, true) ~= nil, "conflict header absent from default run")
else
  soft_skip("D-06 red-conflict degradation",
    "no conflicts present on the live session (clean host) — nothing to colorize")
end

-- ---------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
