-- tests/cli/scene_spawn_prelude_test.lua
-- Plain assert()-based unit tests for the Phase A/B styling-delivery PRELUDE
-- (cli/commands/scene.lua M.build_pane_spawn_command).
--
-- BUG (07.1-scene-prelude): scene styling was delivered by TYPING a `printf
-- '<octal>'` line into each pane's freshly-spawned INTERACTIVE shell via
-- `wezterm cli send-text --no-paste`. Two prior attempts both failed live:
--   * one giant ~1.1KB printf  -> leaked the literal `printf '...'` / stranded
--     zsh at `quote>` (the `ai` scene).
--   * one printf PER escape (53a49cf, SUPERSEDED here) -> broke the single
--     self-erasing printf's clean-pane property; the pane showed a BLANK/FROZEN
--     screen (a hang).
-- Root cause of BOTH: the OSC bytes went through the interactive shell's LINE
-- EDITOR (zsh zle / bash readline), which is racy on a not-yet-ready shell.
--
-- THE PROPER FIX (this suite): emit the OSC bytes as the spawned program's
-- OUTPUT, BEFORE the interactive shell starts — never typed into a line editor.
-- The pane is spawned as `<shell> -c 'printf "<octal>"; exec "$SHELL" -l'`:
-- a NON-interactive shell runs `printf` (its stdout, parsed by the terminal),
-- then `exec`s the user's interactive LOGIN shell so the pane ends up a normal
-- working shell. No line-editor, no race, no hang, no leak.
--
-- PURE: build_pane_spawn_command takes the escape list (+ optional shell path)
-- and returns the PROG argv array `{shell, "-c", body}` — no io/os/mux — so the
-- prelude construction is unit-testable without a live session.
--
-- Run directly: `lua5.4 tests/cli/scene_spawn_prelude_test.lua`.

-- Make `cli/...` and the vendored deps requireable regardless of invocation CWD.
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- tests/cli -> repo root
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local scene = require("cli.commands.scene")
local panelib = require("cli.lib.color")

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

-- A representative `ai`-scene-shaped escape list: several OSC sequences plus the
-- CLEAR_SCROLLBACK_AND_VIEWPORT the caller appends last. Real OSC builders so the
-- bytes match what build_pane_escapes actually produces.
local CLEAR = "\27[2J\27[3J\27[H"
local escapes = {
  panelib.build_osc11("#161c17"),
  panelib.build_osc1337("WEZTERM_TAB_TITLE", "assistant working on a long descriptive title"),
  panelib.build_osc1337("WEZTERM_TAB_ICON", "robot"),
  panelib.build_osc1337("WEZTERM_PANE_COLOR", "purple"),
  panelib.build_osc1337("WEZTERM_TAB_COLOR", "purple"),
  panelib.build_osc1337("WEZTERM_TAB_FOLLOW_PANE", "1"),
  CLEAR,
}

-- ----------------------------------------------------------------------------
-- The helper must exist (RED first: it does not yet on current source).
-- ----------------------------------------------------------------------------
check("build_pane_spawn_command is exported", type(scene.build_pane_spawn_command) == "function")

if type(scene.build_pane_spawn_command) == "function" then
  local argv = scene.build_pane_spawn_command(escapes, "/bin/zsh")

  -- The argv is a 3-element PROG array: <shell> -c <body>.
  check("returns a 3-element argv {shell, '-c', body}",
    type(argv) == "table" and #argv == 3, "got " .. tostring(argv and #argv))
  check("argv[1] is the resolved shell (/bin/zsh)", argv and argv[1] == "/bin/zsh", tostring(argv and argv[1]))
  check("argv[2] is -c", argv and argv[2] == "-c", tostring(argv and argv[2]))

  local body = argv and argv[3] or ""

  -- (a) The OSC bytes are present as a SINGLE octal `printf '<octal>'` — the WHOLE
  -- escape payload concatenated (NOT chunked), emitted as program output.
  do
    local want_octal = octal_of(table.concat(escapes))
    check("(a) body emits ALL escapes as one octal printf '<octal>'",
      body:find("printf '" .. want_octal .. "'", 1, true) ~= nil,
      "body=" .. body:sub(1, 80) .. "...")
  end

  -- (b) The body ENDS by exec-ing an INTERACTIVE LOGIN shell, so the pane is a
  -- working shell (not a one-shot `printf` that exits and freezes the pane).
  do
    check("(b) body execs the interactive login shell after the printf",
      body:find('exec "$SHELL"', 1, true) ~= nil and body:find("-l", 1, true) ~= nil,
      body)
    -- The printf must come BEFORE the exec (emit OSC, THEN hand over to the shell).
    local pi = body:find("printf ", 1, true)
    local ei = body:find("exec ", 1, true)
    check("(b2) the printf precedes the exec (OSC emitted before the shell starts)",
      pi ~= nil and ei ~= nil and pi < ei, "printf@" .. tostring(pi) .. " exec@" .. tostring(ei))
  end

  -- (c) NO giant single send-text printf payload is produced HERE — the styling
  -- no longer goes through send-text. The superseded chunker must be GONE.
  check("(c) the superseded build_styling_printf_lines chunker is removed",
    scene.build_styling_printf_lines == nil)

  -- (d) The octal idiom is unchanged (\%03o per byte -> pure printable ASCII): no
  -- raw ESC (\27) survives in the body for a line editor to mangle.
  check("(d) no raw ESC byte in the body (pure printable octal)",
    body:find("\27", 1, true) == nil)

  -- (e) shell resolution: nil shell falls back to /bin/sh (a sane default that
  -- still `exec "$SHELL" -l`s the user's real login shell afterwards).
  do
    local argv2 = scene.build_pane_spawn_command(escapes, nil)
    check("(e) nil shell falls back to /bin/sh", argv2 and argv2[1] == "/bin/sh", tostring(argv2 and argv2[1]))
  end

  -- (f) An EMPTY escape list still yields a valid working-shell prelude (no printf
  -- needed, but the pane must still become an interactive shell — totality).
  do
    local argv3 = scene.build_pane_spawn_command({}, "/bin/zsh")
    check("(f) empty escapes still execs an interactive shell",
      argv3 and argv3[3] and argv3[3]:find('exec "$SHELL"', 1, true) ~= nil,
      argv3 and argv3[3])
  end
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
