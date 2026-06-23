-- tests/cli/scene_styling_printf_test.lua
-- Plain assert()-based unit tests for the Phase B styling-delivery chunker
-- (cli/commands/scene.lua M.build_styling_printf_lines).
--
-- BUG (07.1-scene-leak): Phase B used to concatenate ALL of a pane's styling
-- escapes into ONE giant octal `printf '...'` line typed into the freshly-spawned
-- interactive shell via `wezterm cli send-text --no-paste`. For the `ai` scene
-- that single line is ~1100-1130 bytes; live on macOS the long line leaked the
-- literal `printf '...'` into the pane and could strand zsh at `quote>` when the
-- closing quote + newline of the >1KB line was lost. The fix emits EACH escape as
-- its OWN short `printf '<octal>'` line so no single typed line can overflow.
--
-- PURE: build_styling_printf_lines takes the list of escape strings and returns
-- the list of `printf '...'\n` lines — no io/os/mux — so the chunking rule is
-- unit-testable without a live session.
--
-- Run directly: `lua5.4 tests/cli/scene_styling_printf_test.lua`.

-- Make `cli/...` and the vendored deps requireable regardless of invocation CWD.
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- tests/cli -> repo root
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local scene = require("cli.commands.scene")

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

-- Octal-encode a byte string the SAME way the implementation does, so the tests
-- describe the expected payload independent of the production code path.
local function octal_of(s)
  return (s:gsub(".", function(c)
    return string.format("\\%03o", string.byte(c))
  end))
end

-- Decode a single `printf '\nnn\nnn...'\n` line back to its raw bytes so we can
-- prove byte-equivalence vs. the old single-line approach (round-trip).
local function decode_printf_line(line)
  -- Strip the leading `printf '` and the trailing `'\n`.
  local body = line:match("^printf '(.*)'\n$")
  assert(body ~= nil, "line is not a printf '...'\\n line: " .. tostring(line))
  -- Each token is a backslash + exactly 3 octal digits.
  return (body:gsub("\\(%d%d%d)", function(o)
    return string.char(tonumber(o, 8))
  end))
end

-- A representative `ai`-scene-shaped escape list: several OSC sequences plus the
-- CLEAR_SCROLLBACK_AND_VIEWPORT the caller appends last. Use real OSC builders so
-- the bytes match what build_pane_escapes actually produces.
local panelib = require("cli.lib.color")
local CLEAR = "\27[2J\27[3J\27[H"
local escapes = {
  panelib.build_osc11("#161c17"),
  panelib.build_osc1337("WEZTERM_PANE_TITLE", "assistant working on a long descriptive title"),
  panelib.build_osc1337("WEZTERM_PANE_ICON", "robot"),
  panelib.build_osc1337("WEZTERM_PANE_COLOR", "purple"),
  panelib.build_osc1337("WEZTERM_TAB_COLOR", "purple"),
  panelib.build_osc1337("WEZTERM_TAB_FOLLOW_PANE", "1"),
  CLEAR,
}

-- ----------------------------------------------------------------------------
-- The helper must exist (RED first: it does not yet on current source).
-- ----------------------------------------------------------------------------
check("build_styling_printf_lines is exported", type(scene.build_styling_printf_lines) == "function")

if type(scene.build_styling_printf_lines) == "function" then
  local lines = scene.build_styling_printf_lines(escapes)

  -- (a) MULTIPLE printf lines — one per escape — NOT a single concatenated line.
  check("emits one printf line PER escape (multiple lines, not one giant line)",
    #lines == #escapes, "got " .. tostring(#lines) .. " lines for " .. tostring(#escapes) .. " escapes")

  -- Every line is a well-formed `printf '...'\n` line.
  do
    local all_ok = true
    for _, l in ipairs(lines) do
      if not l:match("^printf '[\\%d]*'\n$") then all_ok = false end
    end
    check("every emitted line is a well-formed printf '<octal>'\\n line", all_ok)
  end

  -- (b) NO single emitted line exceeds a safe bound (< 512 bytes). The old
  -- single-line `ai` payload was ~1100+ bytes — the very fragility this fixes.
  do
    local longest = 0
    for _, l in ipairs(lines) do
      if #l > longest then longest = #l end
    end
    check("no single emitted line exceeds 512 bytes (>1KB single-line fragility fixed)",
      longest < 512, "longest line = " .. tostring(longest) .. " bytes")
  end

  -- (c) Round-trip byte-equivalence: the concatenated decoded payload of all the
  -- chunked lines equals the original escapes concatenated (SAME OSC bytes, just
  -- split across lines).
  do
    local decoded = {}
    for _, l in ipairs(lines) do
      decoded[#decoded + 1] = decode_printf_line(l)
    end
    local got = table.concat(decoded)
    local want = table.concat(escapes)
    check("round-trip: chunked lines decode to the SAME bytes as the old single line",
      got == want, "decoded " .. tostring(#got) .. " bytes, expected " .. tostring(#want))
  end

  -- Each chunk's octal must match exactly the octal-encoding of its escape (the
  -- octal idiom is unchanged — \%03o per byte).
  do
    local all_ok = true
    for i, esc in ipairs(escapes) do
      local want = "printf '" .. octal_of(esc) .. "'\n"
      if lines[i] ~= want then all_ok = false end
    end
    check("each chunk octal-encodes exactly its own escape (idiom unchanged)", all_ok)
  end

  -- An empty escape list yields no lines (caller only invokes this when there is
  -- styling to emit, but the helper must be total).
  check("empty escapes -> no printf lines", #scene.build_styling_printf_lines({}) == 0)
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
