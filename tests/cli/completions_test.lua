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
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
