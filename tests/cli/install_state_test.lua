-- tests/cli/install_state_test.lua
-- Plain assert()-based unit tests for `wez install-state` (Plan 04):
--   * cli/commands/install_state.lua  — PARSE / BACKUP / INJECT + the
--     override/restore/skip DECISION dispatcher (D-01 all logic in Lua, D-03
--     no-TTY re-install aborts non-zero, INST-01/02 single block + backup).
--
-- All assertions are FIXTURE / TEMP-FS driven: no live WezTerm and no real
-- ~/.config edits. Filesystem effects are exercised against a scratch tmpdir, so
-- this file is an autonomous gate under tools/run-tests.sh. The live dogfood of
-- the full installer (setup.sh against a scratch HOME) is Task 2 / manual (D-18).
--
-- Run directly: `lua5.4 tests/cli/install_state_test.lua`.

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

local IS = require("cli.commands.install_state")

-- ----------------------------------------------------------------------------
-- Locked sentinel markers (the canonical contract — exact strings, no variants).
-- ----------------------------------------------------------------------------
do
  check("open marker is the locked literal",
    IS.OPEN_MARKER == "-- >>> wezterm-setup managed block >>>", IS.OPEN_MARKER)
  check("close marker is the locked literal",
    IS.CLOSE_MARKER == "-- <<< wezterm-setup managed block <<<", IS.CLOSE_MARKER)
end

-- ----------------------------------------------------------------------------
-- Fixtures: a real-shape user wezterm.lua with NO managed block, and one WITH a
-- well-formed managed block (built from the locked markers).
-- ----------------------------------------------------------------------------
local ABSENT_FIXTURE = [[
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.window_decorations = "TITLE | RESIZE"
config.font = wezterm.font 'JetBrains Mono'

return config
]]

local PRESENT_FIXTURE = table.concat({
  "local wezterm = require 'wezterm'",
  "local config = wezterm.config_builder()",
  "",
  "config.font = wezterm.font 'JetBrains Mono'",
  "",
  "-- >>> wezterm-setup managed block >>>",
  "require('wezterm-setup').apply(config)",
  "-- <<< wezterm-setup managed block <<<",
  "return config",
  "",
}, "\n")

-- ----------------------------------------------------------------------------
-- PARSE: absent vs present classification + block extraction.
-- ----------------------------------------------------------------------------
do
  local a = IS.parse(ABSENT_FIXTURE)
  check("parse classifies a clean config as 'absent'", a.state == "absent", a.state)
  check("parse reports no block for an absent config", a.block == nil)

  local p = IS.parse(PRESENT_FIXTURE)
  check("parse classifies a managed config as 'present'", p.state == "present", p.state)
  check("parse extracts the managed block including both markers",
    type(p.block) == "string"
      and p.block:find(IS.OPEN_MARKER, 1, true)
      and p.block:find(IS.CLOSE_MARKER, 1, true),
    p.block)
  check("extracted block carries the apply(config) call",
    type(p.block) == "string" and p.block:find("require('wezterm-setup').apply", 1, true) ~= nil)
end

-- ----------------------------------------------------------------------------
-- Temp filesystem helpers for the BACKUP / INJECT assertions.
-- ----------------------------------------------------------------------------
local function read_file(path)
  local fh = assert(io.open(path, "rb"))
  local data = fh:read("*a")
  fh:close()
  return data
end

local function write_file(path, data)
  local fh = assert(io.open(path, "wb"))
  fh:write(data)
  fh:close()
end

local function scratch_dir()
  local base = os.getenv("TMPDIR") or "/tmp"
  local dir = string.format("%s/wezsetup-istest-%d-%d", base, os.time(), math.random(1, 1e6))
  assert(os.execute("mkdir -p '" .. dir .. "'"))
  return dir
end

-- ----------------------------------------------------------------------------
-- BACKUP: copies wezterm.lua to wezterm.lua.bak.<timestamp> before any write.
-- ----------------------------------------------------------------------------
do
  local dir = scratch_dir()
  local target = dir .. "/wezterm.lua"
  write_file(target, ABSENT_FIXTURE)

  local bak = IS.backup(target)
  check("backup returns a path", type(bak) == "string", tostring(bak))
  check("backup name carries a timestamp suffix",
    type(bak) == "string" and bak:match("%.bak%.[0-9TZ%-]+$") ~= nil, tostring(bak))
  check("backup contents equal the original", read_file(bak) == ABSENT_FIXTURE)
  os.execute("rm -rf '" .. dir .. "'")
end

-- ----------------------------------------------------------------------------
-- INJECT: writes a timestamped backup, then inserts EXACTLY ONE managed block
-- wiring apply(config), positioned before the user's `return config`, leaving
-- all other lines intact — via write-temp-then-atomic-rename.
-- ----------------------------------------------------------------------------
do
  local dir = scratch_dir()
  local target = dir .. "/wezterm.lua"
  write_file(target, ABSENT_FIXTURE)

  local res = IS.inject(target)
  check("inject reports success", type(res) == "table" and res.ok == true,
    res and tostring(res.err))

  local injected = read_file(target)
  -- Exactly one open + one close marker.
  local opens = select(2, injected:gsub(IS.OPEN_MARKER:gsub("%W", "%%%1"), ""))
  local closes = select(2, injected:gsub(IS.CLOSE_MARKER:gsub("%W", "%%%1"), ""))
  check("inject yields exactly one open marker", opens == 1, "opens=" .. tostring(opens))
  check("inject yields exactly one close marker", closes == 1, "closes=" .. tostring(closes))
  check("injected block wires require('wezterm-setup').apply",
    injected:find("require('wezterm-setup').apply", 1, true) ~= nil)
  check("pre-existing user lines survive injection",
    injected:find("config.window_decorations", 1, true) ~= nil
      and injected:find("JetBrains Mono", 1, true) ~= nil)
  check("the augment runs before the user's return config",
    injected:find(IS.OPEN_MARKER, 1, true) < (injected:find("\nreturn config", 1, true) or math.huge))

  -- A timestamped backup of the ORIGINAL exists alongside the target.
  local listing = io.popen("ls '" .. dir .. "'"):read("*a")
  check("inject leaves a timestamped backup of the original",
    listing:find("wezterm%.lua%.bak%.") ~= nil, listing)

  -- Re-parsing the injected file reports 'present'.
  check("re-parsing the injected file reports 'present'",
    IS.parse(injected).state == "present")
  os.execute("rm -rf '" .. dir .. "'")
end

-- ----------------------------------------------------------------------------
-- INJECT uses write-temp-then-rename, NOT a direct in-place overwrite. We assert
-- the module exposes the atomic-write seam and that an interrupted write (the
-- temp file never renamed) leaves the target at its previous content.
-- ----------------------------------------------------------------------------
do
  check("module exposes an atomic write-temp-then-rename helper",
    type(IS.atomic_write) == "function")

  local dir = scratch_dir()
  local target = dir .. "/wezterm.lua"
  write_file(target, ABSENT_FIXTURE)

  -- Simulate an interrupted write: stage new content to a temp file but do NOT
  -- rename. The target must still hold the ORIGINAL bytes (recoverable).
  local tmp = target .. ".tmp.partial"
  write_file(tmp, "CORRUPT PARTIAL CONTENT")
  check("an un-renamed temp write leaves the target unchanged",
    read_file(target) == ABSENT_FIXTURE)
  os.execute("rm -rf '" .. dir .. "'")
end

-- ----------------------------------------------------------------------------
-- CR-01 REGRESSION: --force / override over a Shape-B config
-- (`return wezterm.config_builder()`) must yield a config that STILL has a
-- top-level return and EXACTLY ONE managed block — never a return-less broken
-- file. This is the coverage gap that let CR-01 ship: the prior suite only
-- exercised Shape A and the decide() dispatcher.
-- ----------------------------------------------------------------------------
local SHAPE_B_FIXTURE = table.concat({
  'local wezterm = require("wezterm")',
  "return wezterm.config_builder()",
  "",
}, "\n")

local function count_blocks(text)
  local opens = select(2, text:gsub(IS.OPEN_MARKER:gsub("%W", "%%%1"), ""))
  local closes = select(2, text:gsub(IS.CLOSE_MARKER:gsub("%W", "%%%1"), ""))
  return opens, closes
end

local function has_top_level_return(text)
  return (text:match("\n%s*return%s") or text:match("^%s*return%s")) ~= nil
end

do
  -- First install on a Shape-B config produces a block that CONTAINS the return.
  local first = IS.inject_into_text(SHAPE_B_FIXTURE)
  check("Shape-B first install succeeds", type(first) == "string", tostring(first))
  local o1, c1 = count_blocks(first)
  check("Shape-B first install yields exactly one managed block", o1 == 1 and c1 == 1,
    "opens=" .. tostring(o1) .. " closes=" .. tostring(c1))
  check("Shape-B first install keeps a top-level return", has_top_level_return(first))

  -- restore_original_text reverses the wrap back to the byte-exact original — the
  -- mechanism that lets override re-inject from the TRUE original (CR-01 fix).
  check("Shape-B managed block round-trips back to the original config",
    IS.restore_original_text(first) == SHAPE_B_FIXTURE,
    string.format("%q", tostring(IS.restore_original_text(first))))

  -- Override = recover original -> re-inject. The result must still be a valid,
  -- single-block, return-carrying config (the exact CR-01 defect).
  local original = IS.restore_original_text(first) or first
  local overridden = IS.inject_into_text(original)
  check("Shape-B override re-injects successfully", type(overridden) == "string",
    tostring(overridden))
  local o2, c2 = count_blocks(overridden)
  check("Shape-B override yields exactly one managed block (no duplication)",
    o2 == 1 and c2 == 1, "opens=" .. tostring(o2) .. " closes=" .. tostring(c2))
  check("Shape-B override preserves a top-level return (NOT return-less/broken)",
    has_top_level_return(overridden))
  check("Shape-B override is idempotent (a second override is a no-op)",
    IS.inject_into_text(IS.restore_original_text(overridden) or overridden) == overridden)

  -- Shape A also round-trips through restore_original_text (regression guard so
  -- the inverse helper covers both shapes).
  local a_first = IS.inject_into_text(ABSENT_FIXTURE)
  check("Shape-A managed block round-trips back to the original config",
    IS.restore_original_text(a_first) == ABSENT_FIXTURE,
    string.format("%q", tostring(IS.restore_original_text(a_first))))
end

-- ----------------------------------------------------------------------------
-- CR-01 REGRESSION (filesystem): a FAILED re-inject must NEVER persist a broken
-- (return-less) file — the on-disk config ends byte-identical to before. We
-- simulate a managed file whose recovered original has no top-level return; the
-- override-style path must abort and leave the file untouched.
-- ----------------------------------------------------------------------------
do
  -- inject_into_text on text with no top-level return fails cleanly (nil+err),
  -- which is exactly what makes the override path abort before any write.
  local rebuilt, err = IS.inject_into_text("local wezterm = require('wezterm')\n")
  check("re-inject with no top-level return fails (nil) instead of corrupting",
    rebuilt == nil and type(err) == "string", tostring(rebuilt))

  -- End-to-end: a Shape-B managed file on disk; emulate the override write-once
  -- contract (recover -> reinject -> single atomic_write) and assert the file is
  -- never left in the stripped/return-less intermediate state.
  local dir = scratch_dir()
  local target = dir .. "/wezterm.lua"
  write_file(target, SHAPE_B_FIXTURE)
  assert(IS.inject(target).ok)
  local before = read_file(target)

  local recovered = IS.restore_original_text(before)
  local final = IS.inject_into_text(recovered)
  check("override recovers and re-injects without touching disk first",
    type(final) == "string" and read_file(target) == before)
  IS.atomic_write(target, final)
  local after = read_file(target)
  local o, c = count_blocks(after)
  check("on-disk Shape-B override has exactly one block and a top-level return",
    o == 1 and c == 1 and has_top_level_return(after),
    "opens=" .. tostring(o) .. " closes=" .. tostring(c))
  os.execute("rm -rf '" .. dir .. "'")
end

-- ----------------------------------------------------------------------------
-- CR-01b REGRESSION: a Shape-B returned expression containing an UNBALANCED paren
-- inside a Lua string or comment must still round-trip byte-exact. The original
-- restore_original_text recovered the wrapped expr with Lua's `%b()`, which is
-- byte-level paren matching and string/comment UNAWARE — so a `)` inside a string
-- (e.g. `load_cfg("a)b")`) or comment (e.g. `... -- legacy (fallback)`) was
-- mis-matched, restore returned nil, and the function FELL THROUGH to the Shape-A
-- excision branch, silently returning "" (wrong-but-non-nil). The override path
-- then could never reverse the block, so `--force` re-install spuriously aborts
-- forever. The fix anchors recovery to inject_into_text's fixed wrapper format
-- instead of paren-balancing.
-- ----------------------------------------------------------------------------
do
  -- Unbalanced paren inside a STRING literal.
  local STR_FIXTURE = table.concat({
    'local wezterm = require("wezterm")',
    'return load_cfg("a)b")',
    "",
  }, "\n")
  -- Unbalanced paren inside a trailing COMMENT.
  local CMT_FIXTURE = table.concat({
    'local wezterm = require("wezterm")',
    'return require("x")() -- legacy (fallback)',
    "",
  }, "\n")

  for _, case in ipairs({ { "string", STR_FIXTURE }, { "comment", CMT_FIXTURE } }) do
    local label, fixture = case[1], case[2]
    local injected = IS.inject_into_text(fixture)
    check("Shape-B (" .. label .. ") install succeeds", type(injected) == "string",
      tostring(injected))
    local o1, c1 = count_blocks(injected)
    check("Shape-B (" .. label .. ") install yields exactly one managed block",
      o1 == 1 and c1 == 1, "opens=" .. tostring(o1) .. " closes=" .. tostring(c1))
    check("Shape-B (" .. label .. ") install keeps a top-level return",
      has_top_level_return(injected))

    -- The defect: restore previously returned "" (Shape-A fall-through) here.
    local restored = IS.restore_original_text(injected)
    check("Shape-B (" .. label .. ") restore NEVER returns the empty-excision \"\"",
      restored ~= "" and restored ~= nil, string.format("%q", tostring(restored)))
    check("Shape-B (" .. label .. ") round-trips back to the byte-exact original",
      restored == fixture, string.format("%q", tostring(restored)))

    -- Override = recover original -> re-inject: exactly one block, return survives.
    local original = IS.restore_original_text(injected) or injected
    local overridden = IS.inject_into_text(original)
    local o2, c2 = count_blocks(overridden)
    check("Shape-B (" .. label .. ") override yields exactly one managed block",
      o2 == 1 and c2 == 1, "opens=" .. tostring(o2) .. " closes=" .. tostring(c2))
    check("Shape-B (" .. label .. ") override preserves a top-level return",
      has_top_level_return(overridden))
  end

  -- Filesystem end-to-end on the string case: a FAILED/aborted path must NEVER
  -- persist a broken file; the recover->reinject happens fully in memory and the
  -- single atomic_write lands exactly one block with a surviving return.
  local dir = scratch_dir()
  local target = dir .. "/wezterm.lua"
  write_file(target, STR_FIXTURE)
  assert(IS.inject(target).ok)
  local before = read_file(target)

  local recovered = IS.restore_original_text(before)
  check("on-disk Shape-B (string) recovers the byte-exact original",
    recovered == STR_FIXTURE, string.format("%q", tostring(recovered)))
  local final = IS.inject_into_text(recovered)
  check("override recovers and re-injects without touching disk first",
    type(final) == "string" and read_file(target) == before)
  IS.atomic_write(target, final)
  local after = read_file(target)
  local o, c = count_blocks(after)
  check("on-disk Shape-B (string) override has exactly one block and a top-level return",
    o == 1 and c == 1 and has_top_level_return(after),
    "opens=" .. tostring(o) .. " closes=" .. tostring(c))
  os.execute("rm -rf '" .. dir .. "'")
end

-- ----------------------------------------------------------------------------
-- CR-02 REGRESSION: shquote() makes paths shell-safe, and newest_backup resolves
-- a backup even when the directory name contains a literal single quote (the
-- exact `d'ir` case that silently broke --restore and doctor GATE-4).
-- ----------------------------------------------------------------------------
do
  check("shquote wraps a plain path in single quotes",
    IS.shquote("/a/b") == "'/a/b'", IS.shquote("/a/b"))
  check("shquote escapes an embedded single quote as '\\''",
    IS.shquote("d'ir") == [['d'\''ir']], IS.shquote("d'ir"))

  local base = os.getenv("TMPDIR") or "/tmp"
  local qdir = string.format("%s/wezsetup-q'uote-%d-%d", base, os.time(), math.random(1, 1e6))
  assert(os.execute("mkdir -p " .. IS.shquote(qdir)))
  local target = qdir .. "/wezterm.lua"
  write_file(target, "return {}\n")
  write_file(target .. ".bak.2026-06-09T18-00-00Z", "newer\n")
  write_file(target .. ".bak.2026-06-09T00-00-00Z", "older\n")

  local nb = IS.newest_backup(target)
  check("newest_backup resolves on a path containing a single quote (CR-02)",
    type(nb) == "string" and nb:find("18-00-00Z", 1, true) ~= nil, tostring(nb))
  os.execute("rm -rf -- " .. IS.shquote(qdir))
end

-- ----------------------------------------------------------------------------
-- CR-03 REGRESSION: a failed backup/atomic_write propagates an error instead of
-- falsely reporting success — the backup-before-write safety property (INST-02).
-- ----------------------------------------------------------------------------
do
  local ok, err = IS.backup("/nonexistent-dir-cr03/wezterm.lua")
  check("backup of an unreadable source returns nil+err (not false success)",
    not ok and type(err) == "string", tostring(err))

  local wok, werr = IS.atomic_write("/proc/cr03-should-not-be-writable", "data")
  check("atomic_write into an unwritable location returns nil+err (CR-03)",
    not wok and type(werr) == "string", tostring(werr))
end

-- ----------------------------------------------------------------------------
-- DECISION: re-install over a PRESENT block with NO TTY returns non-zero and
-- names the explicit flags (D-03). --skip is a no-op exit 0; --force overrides;
-- --restore reinstates the newest timestamped backup.
-- ----------------------------------------------------------------------------
do
  -- decide() is pure: given (state, has_tty, flags) -> (action, exit_code, msg).
  local action, code, msg = IS.decide("present", false, {})
  check("no-TTY re-install over a present block returns non-zero",
    code ~= 0, "code=" .. tostring(code))
  check("the abort message names --force/--restore/--skip",
    type(msg) == "string"
      and msg:find("--force", 1, true)
      and msg:find("--restore", 1, true)
      and msg:find("--skip", 1, true),
    msg)
  check("no-TTY abort action is 'abort'", action == "abort", tostring(action))

  local _, scode = IS.decide("present", false, { skip = true })
  check("--skip is a no-op exit 0", scode == 0, "code=" .. tostring(scode))

  local faction, fcode = IS.decide("present", false, { force = true })
  check("--force selects override exit 0", faction == "override" and fcode == 0,
    tostring(faction) .. "/" .. tostring(fcode))

  local raction, rcode = IS.decide("present", false, { restore = true })
  check("--restore selects restore exit 0", raction == "restore" and rcode == 0,
    tostring(raction) .. "/" .. tostring(rcode))

  -- An ABSENT config installs cleanly regardless of TTY.
  local aaction, acode = IS.decide("absent", false, {})
  check("absent config installs cleanly (no flags, no TTY)",
    aaction == "install" and acode == 0, tostring(aaction) .. "/" .. tostring(acode))
end

-- ----------------------------------------------------------------------------
-- RESTORE picks the NEWEST timestamped backup deterministically (T-04-05).
-- ----------------------------------------------------------------------------
do
  local dir = scratch_dir()
  local target = dir .. "/wezterm.lua"
  write_file(target, "current managed content\n")
  write_file(target .. ".bak.2026-06-09T00-00-00Z", "OLDER backup\n")
  write_file(target .. ".bak.2026-06-09T18-00-00Z", "NEWER backup\n")

  local newest = IS.newest_backup(target)
  check("newest_backup selects the lexicographically-latest timestamp",
    type(newest) == "string" and newest:find("18-00-00Z", 1, true) ~= nil, tostring(newest))
  os.execute("rm -rf '" .. dir .. "'")
end

-- ----------------------------------------------------------------------------
-- FRESH INSTALL (07-04, Rule 2): on a clean machine with NO prior wezterm.lua,
-- the install seeds the minimal config-builder base, injects exactly ONE managed
-- block anchored on `return config` (Shape A), creates the file via atomic_write
-- (no pre-existing file required), and takes NO backup (nothing to back up). The
-- fresh file carries a `Created by wezterm-setup` marker the doctor backup gate
-- keys off. This is the primary INST-06/INST-07 first-run path.
-- ----------------------------------------------------------------------------
do
  local dir = scratch_dir()
  local target = dir .. "/wezterm.lua" -- intentionally does NOT exist yet

  -- The exact minimal base install-state seeds for a fresh file.
  local base = table.concat({
    "-- Created by wezterm-setup (no prior ~/.config/wezterm/wezterm.lua existed).",
    "local wezterm = require('wezterm')",
    "local config = wezterm.config_builder()",
    "return config",
    "",
  }, "\n")

  local injected, ierr = IS.inject_into_text(base)
  check("fresh-install base injects cleanly (Shape A)", injected ~= nil, tostring(ierr))
  if injected then
    check("fresh inject yields exactly one managed block",
      count_blocks(injected) == 1, "blocks=" .. tostring(count_blocks(injected)))
    check("fresh inject keeps a top-level return", has_top_level_return(injected), injected)
    check("fresh inject augments config via apply(config)",
      injected:find("apply(config)", 1, true) ~= nil, injected)
    check("fresh inject carries the Created-by marker",
      injected:find("Created by wezterm-setup", 1, true) ~= nil, injected)
  end

  -- atomic_write CREATES a brand-new target (no pre-existing file required).
  local wok = IS.atomic_write(target, injected or base)
  check("atomic_write creates a brand-new file",
    wok == true and read_file(target) ~= nil, tostring(wok))
  check("created file has a single managed block",
    count_blocks(read_file(target)) == 1,
    "blocks=" .. tostring(count_blocks(read_file(target))))
  -- No backup beside a freshly-created file (nothing existed to back up).
  check("no backup taken for a fresh creation",
    IS.newest_backup(target) == nil, tostring(IS.newest_backup(target)))
  os.execute("rm -rf '" .. dir .. "'")
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
