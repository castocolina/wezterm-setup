-- tests/e2e/tier1/diagnostics_e2e_test.lua
--
-- Tier 1 (deterministic subcommand layer) — DIAGNOSTICS + COMPLETIONS + the
-- no-mux `scene new` validate-before-emit contract. Per PRD Appendix A.1, this
-- file locks the exit-code + output-shape contract for the read-only / pure-echo
-- subcommands so the next N runtime commits cannot silently regress them:
--
--   wez version            -> exit 0 AND prints the spec.VERSION string ("0.1.0")
--   wez doctor             -> exit 0 AND gate lines present ([PASS]/[FAIL] tokens)
--   wez keys               -> exit 0 AND non-empty
--   wez keys --json        -> exit 0 AND valid parseable JSON (dkjson; jq cross-check
--                             only when jq is present, else a loud soft_skip)
--   wez completions bash   -> exit 0 AND a non-empty bash completion script
--   wez completions zsh    -> exit 0 AND a non-empty zsh completion script
--   wez scene new (no mux) -> the validate-before-emit / usage path that returns
--                             BEFORE any mux call: zero --pane -> exit 2 + the exact
--                             UI-SPEC copy; bad --layout -> exit 2 + the layout-error
--                             copy. Driven via a child `lua5.4 -e` calling run_new
--                             directly (the same child-lua idiom scene_edge uses for
--                             run_launch), so NO `wezterm cli spawn/split-pane` runs.
--
-- CONTEXT CORRECTION (traceability, source-grounded against cli/commands/scene.lua
-- run_new): there is NO pure spec-echo happy path for `scene new`. After the Step-0
-- validate-before-emit block (scene.lua:259-327) run_new does LIVE mux materialization
-- (spawn/split-pane). So the only deterministic, headless Tier 1 contract for
-- `scene new` is the validate/usage path that returns before any mux call — this
-- supersedes CONTEXT.md line 66 / PRD A.1's "`wez scene new …` -> emits the expected
-- recipe/spec text (no mux needed)": the shipped run_new has no such pure echo branch.
--
-- The exit-code capture uses the harness io.popen + p:close() idiom (M.run_capture_all);
-- the env-/package.path-dependent `scene new` paths run in a child `lua5.4 -e`.
--
-- Run directly:  WEZ_BIN=./dist/wez lua5.4 tests/e2e/tier1/diagnostics_e2e_test.lua

-- package.path bootstrap: this file is at tests/e2e/tier1/, THREE levels below the
-- repo root, so repo_root needs three `..`. Add tests/e2e/lib (the harness) and
-- cli/vendor (dkjson + argparse) to the search path.
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
local run_capture_all = h.run_capture_all
local shquote = h.shquote
local WEZ = h.WEZ

-- spec.VERSION is the source of truth the version assertion compares against (so a
-- version bump cannot silently break the test by leaving a hardcoded "0.1.0").
local spec = require("cli.spec")
local SUBCOMMANDS = spec.subcommand_names()

-- A child `lua5.4 -e` that requires cli.commands.scene and os.exit(run_new{...}) so
-- the validate-before-emit paths run with NO mux (the same idiom scene_launch_test
-- uses for run_launch). Returns (exit_code, combined_stdout_stderr). The argstr is a
-- raw Lua table literal (e.g. "{pane={}}") spliced into the child body.
local function run_new_child(argstr)
  local body = string.format(
    "package.path=%q..package.path;"
      .. "local s=require('cli.commands.scene');"
      .. "os.exit(s.run_new(%s))",
    repo_root .. "/?.lua;" .. repo_root .. "/cli/vendor/?.lua;",
    argstr)
  local p = io.popen(string.format("lua5.4 -e %q 2>&1", body), "r")
  if not p then return 1, "" end
  local out = p:read("*a") or ""
  local ok, _, code = p:close()
  return (code or (ok and 0 or 1)), out
end

-- ---------------------------------------------------------------------------
-- wez version -> exit 0 AND output contains spec.VERSION (not a hardcoded literal).
-- ---------------------------------------------------------------------------
do
  local out, exit = run_capture_all(shquote(WEZ) .. " version")
  check("`wez version` ran (exit 0)", exit == 0, "exit=" .. tostring(exit))
  check("`wez version` prints spec.VERSION (" .. tostring(spec.VERSION) .. ")",
    out:find(tostring(spec.VERSION), 1, true) ~= nil, out)
end

-- ---------------------------------------------------------------------------
-- wez doctor -> exit 0 AND gate lines present (a known gate token).
-- ---------------------------------------------------------------------------
do
  local out, exit = run_capture_all(shquote(WEZ) .. " doctor")
  check("`wez doctor` ran (exit 0)", exit == 0,
    "exit=" .. tostring(exit) .. " out=" .. tostring(out))
  -- doctor prints each gate as `[PASS]`/`[FAIL]` (cli/commands/doctor.lua print_section).
  check("`wez doctor` prints gate lines ([PASS]/[FAIL])",
    out:find("[PASS]", 1, true) ~= nil or out:find("[FAIL]", 1, true) ~= nil, out)
end

-- ---------------------------------------------------------------------------
-- wez keys -> exit 0 AND non-empty.
-- ---------------------------------------------------------------------------
do
  local out, exit = run_capture_all(shquote(WEZ) .. " keys")
  check("`wez keys` ran (exit 0)", exit == 0, "exit=" .. tostring(exit))
  check("`wez keys` output is non-empty", out ~= nil and out:match("%S") ~= nil,
    "len=" .. tostring(#(out or "")))
end

-- ---------------------------------------------------------------------------
-- wez keys --json -> exit 0 AND dkjson.decode returns a table; optional jq cross-check.
-- ---------------------------------------------------------------------------
do
  local json_out, exit = run_capture(shquote(WEZ) .. " keys --json")
  if exit ~= 0 then
    local combined = run_capture_all(shquote(WEZ) .. " keys --json")
    check("`wez keys --json` ran (exit 0)", false,
      "exit=" .. tostring(exit) .. " out=" .. tostring(combined))
  else
    check("`wez keys --json` ran (exit 0)", true)
  end

  local ok_dk, dkjson = pcall(require, "dkjson")
  if ok_dk then
    local decoded = dkjson.decode(json_out)
    check("`wez keys --json` decodes to a table (dkjson)", type(decoded) == "table",
      (json_out or ""):sub(1, 200))
  else
    -- dkjson is vendored at cli/vendor/dkjson.lua; a missing require is a real
    -- failure, not a soft skip.
    check("dkjson is requireable (cli/vendor/dkjson.lua)", false, "require failed")
  end

  -- jq cross-check ONLY when jq is present (loud soft_skip otherwise — never a
  -- silent pass).
  local _, jq_present = run_capture("command -v jq")
  if jq_present == 0 then
    local _, jq_exit = run_capture(
      "printf %s " .. shquote(json_out) .. " | jq . > /dev/null")
    check("`wez keys --json` is jq-valid", jq_exit == 0, "jq exit=" .. tostring(jq_exit))
  else
    print("  skip - `wez keys --json` jq cross-check  (jq not present on PATH)")
  end
end

-- ---------------------------------------------------------------------------
-- wez completions bash|zsh -> exit 0 AND a non-empty script (known token).
-- ---------------------------------------------------------------------------
do
  local out, exit = run_capture_all(shquote(WEZ) .. " completions bash")
  check("`wez completions bash` ran (exit 0)", exit == 0, "exit=" .. tostring(exit))
  -- The generated bash script registers via `complete -F _wez wez`.
  check("`wez completions bash` is a non-empty bash completion script",
    out:find("complete -F _wez wez", 1, true) ~= nil, (out or ""):sub(1, 200))
end
do
  local out, exit = run_capture_all(shquote(WEZ) .. " completions zsh")
  check("`wez completions zsh` ran (exit 0)", exit == 0, "exit=" .. tostring(exit))
  -- The generated zsh script opens with `#compdef wez`.
  check("`wez completions zsh` is a non-empty zsh completion script",
    out:find("#compdef wez", 1, true) ~= nil, (out or ""):sub(1, 200))
end

-- ---------------------------------------------------------------------------
-- wez scene new NO-MUX contract: the validate-before-emit / usage paths that return
-- BEFORE any mux call (driven via child lua5.4 -e calling run_new directly).
-- ---------------------------------------------------------------------------
do
  -- Zero --pane (pane={}) -> exit 2 + the exact UI-SPEC copy.
  local code, out = run_new_child("{pane={}}")
  check("`scene new` with zero --pane -> exit 2 (no mux)", code == 2, "code=" .. tostring(code))
  check("`scene new` zero --pane -> exact UI-SPEC copy",
    out:find("error: wez scene new requires at least one --pane (got 0)", 1, true) ~= nil, out)
end
do
  -- Unknown --layout with a pane present -> exit 2 + the scenelib layout-error copy.
  local code, out = run_new_child("{layout='bogus', pane={'sh'}}")
  check("`scene new` with a bad --layout -> exit 2 (no mux)", code == 2, "code=" .. tostring(code))
  check("`scene new` bad --layout -> scenelib layout-error copy",
    out:find("error: unknown layout 'bogus'", 1, true) ~= nil, out)
end

-- ---------------------------------------------------------------------------
-- SUBCOMMANDS enumeration guard: every non-hidden, non-mux subcommand this file
-- exercises MUST be present in cli/spec.lua's closed allow-list, so a renamed or
-- removed subcommand fails loudly here (the "newly added/renamed subcommand is
-- detectable" contract).
-- ---------------------------------------------------------------------------
do
  local present = {}
  for _, name in ipairs(SUBCOMMANDS) do
    present[name] = true
  end
  -- The deterministic non-OSC subcommands asserted across this file + the
  -- install-cycle/scene-edge files (Task 2). pane/tab (OSC, Plan 03) and the hidden
  -- __complete are intentionally excluded.
  local exercised = {
    "version", "doctor", "keys", "completions",
    "scene", "seed-scenes", "install-state", "uninstall", "update",
  }
  for _, name in ipairs(exercised) do
    check("subcommand '" .. name .. "' is in the spec.lua allow-list",
      present[name] == true, "missing from SUBCOMMANDS")
  end
end

os.exit(h.footer())
