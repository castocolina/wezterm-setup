-- tests/cli/build_dev_launcher_test.lua
-- Regression-guard for the macOS dev-launcher Lua-5.4-resolution fix (quick
-- 260623-gbk). tools/build.sh build_dev_launcher() used to emit a hardcoded
-- `exec lua5.4 ...` line. On macOS, Homebrew's `lua@5.4` is keg-only so `lua5.4`
-- is NOT on the default PATH -> the generated `dist/wez` died with
-- `exec: lua5.4: not found` (exit 127) and the build's own `wez version` smoke
-- test correctly aborted, breaking `make install`.
--
-- The fix resolves a Lua 5.4 interpreter at BUILD time (PATH `lua5.4` ->
-- `$(brew --prefix lua@5.4)/bin/lua5.4` -> a `lua` reporting 5.4) and BAKES the
-- resolved path into the generated launcher's `exec` line (like REPO_ROOT is
-- already baked). When no Lua 5.4 interpreter exists, the resolver fails loudly
-- (non-zero) so the build aborts rather than generating an inert launcher.
--
-- Mirrors tests/cli/build_channel_test.lua + tests/cli/setup_dev_test.lua:
-- assertions are on script TEXT (via has()/comment-filtered grep) + the
-- generated-launcher BEHAVIOR under a SOURCED no-run mode (the BASH_SOURCE/$0
-- guard means sourcing does NOT run main). NO luastatic build is triggered — this
-- stays an autonomous unit gate under run-tests.sh.
--
-- Run directly: `lua5.4 tests/cli/build_dev_launcher_test.lua`.

local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- tests/cli -> repo root

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

local SCRIPT = repo_root .. "/tools/build.sh"

local function read_file(path)
  local fh = assert(io.open(path, "rb"), "cannot open " .. path)
  local data = fh:read("*a")
  fh:close()
  return data
end

local SRC = read_file(SCRIPT)
local function has(needle)
  return SRC:find(needle, 1, true) ~= nil
end

-- ----------------------------------------------------------------------------
-- TEXT regression guard: NO bare `exec lua5.4 ` line survives (comment-filtered
-- grep so header prose mentioning `lua5.4` does not self-invalidate the gate).
-- Idiom copied from setup_dev_test.lua's bare-`lua` guard: no `-n` on the first
-- grep (it would prepend LINENUM: and defeat the `^[[:space:]]*#` comment anchor).
-- ----------------------------------------------------------------------------
do
  local p = assert(io.popen(
    "grep -E 'exec lua5\\.4 ' '" .. SCRIPT .. "' | grep -vc '^[[:space:]]*#' || true"))
  local n = tonumber((p:read("*a") or "0"):match("%d+")) or 0
  p:close()
  check("no non-comment line emits a bare `exec lua5.4 ` (resolved-interpreter regression guard)",
    n == 0, "non-comment bare-`exec lua5.4` lines=" .. tostring(n))
end

-- ----------------------------------------------------------------------------
-- TEXT presence: a dedicated resolver function is defined.
-- ----------------------------------------------------------------------------
check("build.sh defines a dedicated `resolve_dev_lua` resolver", has("resolve_dev_lua"))

-- ----------------------------------------------------------------------------
-- BEHAVIOR harness: source build.sh (no main run via the $0/BASH_SOURCE guard)
-- and run build_dev_launcher against a temp OUT, with a fake `lua5.4` shim on a
-- prepended PATH. Then read the generated launcher text. We need both the exit
-- code and the produced file, so the harness returns (ok, launcher_text).
-- ----------------------------------------------------------------------------
local function run_build_dev_launcher(extra_env, path_setup)
  local out_file = os.tmpname()
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "w"))
  fh:write("#!/usr/bin/env bash\n")
  fh:write("set -u\n")
  fh:write(path_setup .. "\n")
  -- build.sh REASSIGNS OUT/ENTRY/REPO_ROOT on source (lines ~60-69), so we must
  -- point OUT/ENTRY at our temp targets AFTER sourcing, not before. REPO_ROOT
  -- stays the real repo root (resolved from BASH_SOURCE) — the launcher bakes it.
  fh:write("source '" .. SCRIPT .. "'\n")
  fh:write("OUT='" .. out_file .. "'\n")
  fh:write("ENTRY='cli/wez.lua'\n")
  -- Run the launcher generator and propagate its exit code as the script's.
  fh:write("build_dev_launcher\n")
  fh:close()
  local cmd = (extra_env or "") .. " bash '" .. tmp .. "' >/dev/null 2>&1 </dev/null"
  local ok = os.execute(cmd)
  ok = (ok == true or ok == 0)
  local text = ""
  local ofh = io.open(out_file, "rb")
  if ofh then
    text = ofh:read("*a") or ""
    ofh:close()
  end
  os.remove(tmp)
  os.remove(out_file)
  return ok, text
end

-- Build a PATH-setup snippet that creates a tmp bin/ holding an executable
-- `lua5.4` shim reporting "Lua 5.4", prepends it onto PATH, and exports the shim
-- absolute path as SHIM_LUA for the assertions below. Returns (setup, shim_path).
local SHIM_DIR = os.tmpname()
os.remove(SHIM_DIR)
local SHIM_PATH = SHIM_DIR .. "/lua5.4"
local path_setup = table.concat({
  "rm -f '" .. SHIM_DIR .. "' 2>/dev/null || true",
  "mkdir -p '" .. SHIM_DIR .. "'",
  "printf '#!/usr/bin/env bash\\necho \"Lua 5.4\"\\n' > '" .. SHIM_PATH .. "'",
  "chmod +x '" .. SHIM_PATH .. "'",
  "export PATH='" .. SHIM_DIR .. ":'\"$PATH\"",
}, "\n")

do
  local ok, text = run_build_dev_launcher("", path_setup)
  check("build_dev_launcher succeeds (exit 0) with a `lua5.4` shim on PATH", ok,
    "ok=" .. tostring(ok))
  -- (a) the generated launcher does NOT exec a BARE `lua5.4` command name.
  local bare = text:find("exec lua5.4 ", 1, true) ~= nil
  check("generated launcher does NOT exec a bare `lua5.4` command name (resolved path baked instead)",
    not bare, "launcher exec line still bare")
  -- (b) the resolved interpreter token in the exec line is the shim's ABSOLUTE path.
  check("generated launcher execs the RESOLVED shim absolute path (" .. SHIM_PATH .. ")",
    text:find(SHIM_PATH, 1, true) ~= nil,
    "launcher=" .. text:gsub("%s+", " "))
  -- The exec line still passes the in-repo entry + runtime args (REPO_ROOT/ENTRY + $@).
  check("generated launcher still runs ${REPO_ROOT}/cli/wez.lua with \"$@\"",
    text:find("cli/wez.lua", 1, true) ~= nil and text:find('"$@"', 1, true) ~= nil)
  os.execute("rm -rf '" .. SHIM_DIR .. "' 2>/dev/null || true")
end

-- ----------------------------------------------------------------------------
-- BEHAVIOR (fail-loud): with PATH scrubbed of any lua5.4/lua AND brew, the
-- resolver (and thus build_dev_launcher) exits NON-ZERO — it must NOT silently
-- generate an inert launcher that would 127 at runtime.
-- ----------------------------------------------------------------------------
do
  -- A scrub dir symlinking ONLY the coreutils the heredoc needs (cat, chmod) so
  -- the failure is attributable to the missing Lua 5.4 interpreter, NOT to a
  -- missing `cat`/`chmod`. No lua5.4, no lua, no brew are reachable. PATH points
  -- ONLY at this scrub dir.
  local scrub_dir = os.tmpname()
  os.remove(scrub_dir)
  local scrub_setup = table.concat({
    "rm -f '" .. scrub_dir .. "' 2>/dev/null || true",
    "mkdir -p '" .. scrub_dir .. "'",
    -- Link the minimal coreutils the source + launcher generator + resolver
    -- legitimately need (dirname/pwd are used while SOURCING build.sh; cat/chmod
    -- by the heredoc; printf/command are bash builtins). Do NOT link
    -- lua/lua5.4/brew — that is the condition under test, so any failure is
    -- attributable to the missing Lua 5.4 interpreter, not a missing coreutil.
    "for b in cat chmod cp mkdir rm sed grep tr mktemp dirname pwd basename uname; do " ..
      "src=\"$(command -v \"$b\" 2>/dev/null || true)\"; " ..
      "[ -n \"$src\" ] && ln -sf \"$src\" '" .. scrub_dir .. "/'\"$b\"; done",
    "export PATH='" .. scrub_dir .. "'",
  }, "\n")
  local ok = run_build_dev_launcher("", scrub_setup)
  check("build_dev_launcher FAILS LOUD (non-zero) when no Lua 5.4 interpreter is resolvable",
    not ok, "ok=" .. tostring(ok))
  os.execute("rm -rf '" .. scrub_dir .. "' 2>/dev/null || true")
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
