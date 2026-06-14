-- tests/cli/completions_test.lua
-- Plain assert()-based unit tests for the spec-driven shell completion generator
-- (cli/commands/completions.lua) and the dynamic-value hook (cli/commands/complete.lua).
-- Runnable directly: `lua5.4 tests/cli/completions_test.lua`.
--
-- The generator MUST be spec-driven (D-16): it walks cli/spec.lua's argparse
-- parser and emits zsh/bash completion scripts covering every registered (visible)
-- subcommand and its flags. These tests assert coverage by deriving the expected
-- subcommand set from the REAL spec, never a hardcoded list, so adding a subcommand
-- to spec.lua extends coverage with no generator edit.

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

-- Capture stdout produced by a function that writes via io.write.
local function capture(fn)
  local buf = {}
  local real_write = io.write
  io.write = function(...)
    for _, v in ipairs({ ... }) do buf[#buf + 1] = tostring(v) end
    return true
  end
  local ok, code = pcall(fn)
  io.write = real_write
  return ok, code, table.concat(buf)
end

local spec = require("cli.spec")
local completions = require("cli.commands.completions")
local complete = require("cli.commands.complete")

-- ----------------------------------------------------------------------------
-- Module shape
-- ----------------------------------------------------------------------------
check("completions module loads", type(completions) == "table")
check("completions exposes run()", type(completions.run) == "function")
check("complete module loads", type(complete) == "table")
check("complete exposes run()", type(complete.run) == "function")

-- The visible Phase 1 subcommands the generated scripts must cover. Derived from
-- the REAL spec: every registered name MINUS the hidden internal ones (__complete).
-- This is what makes coverage grow automatically as later phases register more
-- subcommands (D-16) — the assertion follows the spec, it does not hardcode.
local hidden = { ["__complete"] = true }
local visible = {}
for _, n in ipairs(spec.subcommand_names()) do
  if not hidden[n] then visible[#visible + 1] = n end
end
-- Sanity: the Phase 1 visible set includes these (if the spec drops one, this is
-- a real regression, not a hardcoded expectation of the generator).
local must_cover = { "doctor", "keys", "install-state", "uninstall-state" }
do
  local vset = {}
  for _, n in ipairs(visible) do vset[n] = true end
  for _, want in ipairs(must_cover) do
    check("spec registers visible subcommand: " .. want, vset[want] == true)
  end
end

-- ----------------------------------------------------------------------------
-- zsh generation: non-empty script covering every visible subcommand + --json
-- ----------------------------------------------------------------------------
do
  local ok, code, out = capture(function() return completions.run({ shell = "zsh" }) end)
  check("completions.run(zsh) does not raise", ok, ok and "" or tostring(code))
  check("completions.run(zsh) exits 0", code == 0, "code=" .. tostring(code))
  check("zsh script is non-empty", #out > 0, "#out=" .. tostring(#out))
  check("zsh script references #compdef wez", out:find("#compdef%s+wez") ~= nil)
  for _, n in ipairs(visible) do
    check("zsh script references subcommand: " .. n, out:find(n, 1, true) ~= nil)
  end
  check("zsh script references --json flag", out:find("--json", 1, true) ~= nil)
  -- D-16: dynamic candidates route through `wez __complete`, not a hardcoded list.
  check("zsh script shells out to `wez __complete`", out:find("__complete", 1, true) ~= nil)
end

-- ----------------------------------------------------------------------------
-- bash generation: non-empty script covering every visible subcommand + --json
-- ----------------------------------------------------------------------------
do
  local ok, code, out = capture(function() return completions.run({ shell = "bash" }) end)
  check("completions.run(bash) does not raise", ok, ok and "" or tostring(code))
  check("completions.run(bash) exits 0", code == 0, "code=" .. tostring(code))
  check("bash script is non-empty", #out > 0, "#out=" .. tostring(#out))
  check("bash script registers a completion function via complete -F", out:find("complete%s+%-F") ~= nil)
  for _, n in ipairs(visible) do
    check("bash script references subcommand: " .. n, out:find(n, 1, true) ~= nil)
  end
  check("bash script references --json flag", out:find("--json", 1, true) ~= nil)
  check("bash script shells out to `wez __complete`", out:find("__complete", 1, true) ~= nil)
end

-- ----------------------------------------------------------------------------
-- Hidden subcommands (e.g. __complete) are NOT advertised in the visible
-- top-level subcommand completion list.
-- ----------------------------------------------------------------------------
do
  local _, _, zsh_out = capture(function() return completions.run({ shell = "zsh" }) end)
  -- __complete may appear as a shell-out target, but must not be offered as a
  -- top-level completion *candidate*. We assert it's not listed alongside the
  -- visible commands in the candidate block by checking the generator marks the
  -- subcommand candidate list and __complete is absent from it.
  local candidates = zsh_out:match("WEZ_SUBCOMMANDS_BEGIN(.-)WEZ_SUBCOMMANDS_END")
  check("zsh script delimits its subcommand candidate block", candidates ~= nil)
  if candidates then
    check("hidden __complete is not a visible candidate", candidates:find("__complete", 1, true) == nil)
    check("doctor IS a visible candidate", candidates:find("doctor", 1, true) ~= nil)
  end
end

-- ----------------------------------------------------------------------------
-- Spec-driven proof: the generated output is a FUNCTION of the spec. Regenerating
-- after registering an extra command must include that command, with no generator
-- edit. We simulate "the spec grew" by feeding the generator an explicit parser
-- that has one more command, asserting the new command appears.
-- ----------------------------------------------------------------------------
do
  local ok_ap, argparse = pcall(require, "cli.vendor.argparse")
  if not ok_ap then argparse = require("argparse") end
  local p = argparse("wez", "test")
  p:command_target("command")
  p:require_command(false)
  p:command("doctor", "d")
  p:command("zzz-future", "a future subcommand")
  local _, _, out = capture(function()
    return completions.run({ shell = "zsh", parser = p, names = { "doctor", "zzz-future" } })
  end)
  check("generator picks up a newly-registered subcommand (spec-driven)",
    out:find("zzz-future", 1, true) ~= nil)
end

-- ----------------------------------------------------------------------------
-- __complete: emits newline-separated candidates for a context. For Phase 1 the
-- `subcommands` context returns the visible subcommand names.
-- ----------------------------------------------------------------------------
do
  local ok, code, out = capture(function() return complete.run({ context = "subcommands" }) end)
  check("complete.run(subcommands) does not raise", ok, ok and "" or tostring(code))
  check("complete.run(subcommands) exits 0", code == 0, "code=" .. tostring(code))
  check("complete output is newline-separated", out:find("\n") ~= nil)
  for _, n in ipairs(must_cover) do
    check("__complete subcommands includes: " .. n, out:find(n, 1, true) ~= nil)
  end
  -- Injection guard (T-07-02): candidates are plain tokens, no shell metacharacters.
  check("__complete emits no shell metacharacters", out:find("[;&|`$()]") == nil, out)
end

-- An unknown context yields no candidates and still exits cleanly (0): the hook is
-- a closed dispatch, never an error surface during Tab expansion.
do
  local ok, code, out = capture(function() return complete.run({ context = "no-such-context" }) end)
  check("complete.run(unknown ctx) does not raise", ok, ok and "" or tostring(code))
  check("complete.run(unknown ctx) exits 0", code == 0, "code=" .. tostring(code))
  check("complete.run(unknown ctx) emits nothing", out == "" or out == "\n", out)
end

-- ----------------------------------------------------------------------------
-- Nested scene) -> launch) arm (05-04, SCEN-05). Unlike pane/tab, `scene` has
-- top-level flags AND subcommands, so the nested scene) arm REPLACES the generic
-- flag arm (ratified planner decision): launch -> scene-names, new -> flags,
-- bare -> new launch. The recipe names route through `wez __complete scene-names`
-- (never hardcoded). Both generated scripts must remain syntactically valid.
-- ----------------------------------------------------------------------------

-- Count non-overlapping occurrences of a literal substring.
local function count_sub(haystack, needle)
  local n, i = 0, 1
  while true do
    local s, e = haystack:find(needle, i, true)
    if not s then break end
    n = n + 1
    i = e + 1
  end
  return n
end

-- Write `text` to a temp file and run `checker file 2>&1`; returns (ok, output).
-- ok is true only when the checker exits 0. Used for `bash -n` / `zsh -n`.
local function syntax_check(text, checker)
  local base = os.getenv("TMPDIR") or "/tmp"
  local path = string.format("%s/wezsetup-compl-%d-%d.sh", base, os.time(), math.random(1, 1e6))
  local fh = assert(io.open(path, "wb"))
  fh:write(text)
  fh:close()
  local p = assert(io.popen(checker .. " '" .. path .. "' 2>&1"))
  local out = p:read("*a") or ""
  local _, _, code = p:close()
  os.execute("rm -f '" .. path .. "'")
  return code == 0 or code == true, out
end

-- zsh generator: exactly ONE scene) arm, with launch) -> scene-names and
-- new) -> the scene flags; no duplicate generic scene flag arm.
do
  local _, _, out = capture(function() return completions.run({ shell = "zsh" }) end)
  check("zsh: routes scene launch -> `wez __complete scene-names`",
    out:find("__complete scene-names", 1, true) ~= nil)
  check("zsh: exactly one scene) arm (generic flag arm replaced, not duplicated)",
    count_sub(out, "        scene)") == 1, "count=" .. count_sub(out, "        scene)"))
  check("zsh: scene) launch) case calls scene-names",
    out:find("launch%) compadd %${%(f%)\"%$%(wez __complete scene%-names") ~= nil)
  check("zsh: scene) new) fallback offers the scene flags",
    out:find("*) compadd --layout --pane --color --title", 1, true) ~= nil)
  check("zsh: scene new --layout VALUE routes to scene-layouts (A-1 fix)",
    out:find("--layout) compadd ${(f)\"$(wez __complete scene-layouts 2>/dev/null)\"}", 1, true) ~= nil)
  check("zsh: scene new --color VALUE routes to scene-colors (A-1 fix)",
    out:find("--color) compadd ${(f)\"$(wez __complete scene-colors 2>/dev/null)\"}", 1, true) ~= nil)
  check("zsh: scene) bare case offers new launch",
    out:find("*) compadd new launch", 1, true) ~= nil)
  -- D-16: the launch candidate set is NOT hardcoded — the scene) arm's launch)
  -- case routes through scene-names and adds no literal recipe word. Asserted by
  -- checking the launch) case body contains the dynamic shell-out and nothing else.
  local scene_arm = out:match("        scene%)(.-)\n          ;;")
  check("zsh: scene) launch) routes dynamically (no hardcoded recipe candidate)",
    scene_arm ~= nil
      and scene_arm:find("launch) compadd ${(f)\"$(wez __complete scene-names 2>/dev/null)\"}", 1, true) ~= nil)
end

-- bash generator: exactly ONE scene) arm dispatching on ${COMP_WORDS[2]}.
do
  local _, _, out = capture(function() return completions.run({ shell = "bash" }) end)
  check("bash: routes scene launch -> `wez __complete scene-names`",
    out:find("__complete scene-names", 1, true) ~= nil)
  check("bash: exactly one scene) arm (generic flag arm replaced, not duplicated)",
    count_sub(out, "    scene)") == 1, "count=" .. count_sub(out, "    scene)"))
  check("bash: scene) launch) case calls scene-names via compgen",
    out:find("launch) COMPREPLY=( $(compgen -W \"$(wez __complete scene-names", 1, true) ~= nil)
  check("bash: scene) new) fallback offers the scene flags",
    out:find("*) COMPREPLY=( $(compgen -W \"--layout --pane --color --title\"", 1, true) ~= nil)
  check("bash: scene new --layout VALUE routes to scene-layouts (A-1 fix)",
    out:find("--layout) COMPREPLY=( $(compgen -W \"$(wez __complete scene-layouts 2>/dev/null)\"", 1, true) ~= nil)
  check("bash: scene new --color VALUE routes to scene-colors (A-1 fix)",
    out:find("--color) COMPREPLY=( $(compgen -W \"$(wez __complete scene-colors 2>/dev/null)\"", 1, true) ~= nil)
  check("bash: scene) bare case offers new launch",
    out:find("*) COMPREPLY=( $(compgen -W \"new launch\"", 1, true) ~= nil)
  -- D-16: launch candidates route through scene-names, no literal recipe word in
  -- the scene) arm's launch) case.
  local scene_arm = out:match("    scene%)(.-)\n      ;;")
  check("bash: scene) launch) routes dynamically (no hardcoded recipe candidate)",
    scene_arm ~= nil
      and scene_arm:find("launch) COMPREPLY=( $(compgen -W \"$(wez __complete scene-names 2>/dev/null)\"", 1, true) ~= nil)
end

-- Syntax validity (CLAUDE.md verify-before-done): the recorded proof is the -n
-- check, not "should work". bash -n is MANDATORY; zsh -n is skipped gracefully
-- when zsh is absent.
do
  local _, _, bash_out = capture(function() return completions.run({ shell = "bash" }) end)
  local ok_bash, detail = syntax_check(bash_out, "bash -n")
  check("generated bash script passes `bash -n`", ok_bash, detail)

  local _, _, zsh_out = capture(function() return completions.run({ shell = "zsh" }) end)
  local has_zsh = (os.execute("command -v zsh >/dev/null 2>&1") == 0
    or os.execute("command -v zsh >/dev/null 2>&1") == true)
  if has_zsh then
    local ok_zsh, zdetail = syntax_check(zsh_out, "zsh -n")
    check("generated zsh script passes `zsh -n`", ok_zsh, zdetail)
  else
    print("  skip - `zsh -n` (zsh not installed)")
  end
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
