-- tests/cli/setup_sh_test.lua
-- Text + behavior tests for tools/setup.sh's STEP 6 install-state delegation
-- (fix 07.1-install-cycle, bug 1).
--
-- The bug: `make install` over an EXISTING managed block failed with
--   `wez install-state: a wezterm-setup managed block already exists and no
--    interactive terminal is available. Re-run with --force/--restore/--skip`
--   make: *** [install] Error 3
-- because setup.sh's STEP 6 shelled out to `wez install-state "$@"` with NO flag,
-- and install-state cannot prompt without a TTY (D-03). That broke reinstalls /
-- `make uninstall setup build install`.
--
-- The fix (decision-free glue, D-01 preserved — setup.sh still makes NO sentinel
-- decision; it only chooses a SAFE NON-INTERACTIVE DEFAULT flag to hand the
-- binary): when stdin is NOT a TTY (`[ ! -t 0 ]`) AND the user passed no explicit
-- override flag, setup.sh passes a default mode to `wez install-state`. The
-- default is `--force` (install-state writes a timestamped backup before
-- overwriting, so it is safe and yields a correct current managed block). The
-- chosen default is overridable via `WEZ_INSTALL_STATE_MODE` for power users.
-- On a FRESH install (no block yet) install-state's own `absent -> install`
-- decision needs no flag, so the default is harmless either way; an explicit
-- user-supplied flag ("$@") always takes precedence over the default.
--
-- Asserted on the SCRIPT TEXT (mirroring setup_dev_test.lua / install_sh_test.lua
-- text idioms) PLUS a deterministic SOURCED behavior check of the default-mode
-- resolver (so the `--force` default + `WEZ_INSTALL_STATE_MODE` override + the
-- TTY/explicit-flag precedence are proven without a real terminal).
--
-- Run directly: `lua5.4 tests/cli/setup_sh_test.lua`.

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

local SCRIPT = repo_root .. "/tools/setup.sh"

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
-- TEXT: the non-interactive default is wired into STEP 6.
-- ----------------------------------------------------------------------------
check("setup.sh exposes the WEZ_INSTALL_STATE_MODE override seam",
  has("WEZ_INSTALL_STATE_MODE"))
check("setup.sh defaults the non-interactive install-state mode to --force",
  has("--force"))
-- The default only applies on a non-TTY: a `[ ! -t 0 ]` (or `! [ -t 0 ]`) guard
-- must gate the default so the interactive path is unchanged (still prompts).
check("setup.sh gates the default behind a non-TTY test (`! -t 0`)",
  has("! -t 0") or has("-t 0"))
-- The user's explicit "$@" override must still flow to install-state (precedence).
check("setup.sh still forwards the user's explicit flags (\"$@\") to install-state",
  has('"$@"'))
check("setup.sh still delegates to `wez install-state`", has("install-state"))

-- ----------------------------------------------------------------------------
-- BEHAVIOR: source setup.sh and drive the default-mode resolver directly. The
-- script must define a helper (`resolve_install_state_args`) that, given whether
-- explicit flags were supplied + whether stdin is a TTY, prints the args to pass
-- to `wez install-state`. We avoid running the full installer (it bootstraps
-- WezTerm + builds) by sourcing under a guard: setup.sh must NOT run its install
-- sequence when sourced (BASH_SOURCE/$0 guard), only define the helper.
--
-- Cases asserted:
--   * non-TTY + no explicit flags + no env   -> `--force` (the safe default)
--   * non-TTY + no explicit flags + env=--skip -> `--skip` (env override honored)
--   * any context + explicit user flags       -> echo the user flags verbatim
--   * TTY + no explicit flags                  -> NO default flag (interactive prompt)
-- ----------------------------------------------------------------------------
local function bash_capture(body)
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "w"))
  fh:write("#!/usr/bin/env bash\n")
  fh:write("set -u\n")
  fh:write("source '" .. SCRIPT .. "'\n")
  fh:write(body .. "\n")
  fh:close()
  local cmd = "bash '" .. tmp .. "' 2>/dev/null"
  local p = assert(io.popen(cmd))
  local out = (p:read("*a") or ""):gsub("%s+$", "")
  p:close()
  os.remove(tmp)
  return out
end

-- The sourcing guard must hold: sourcing setup.sh defines the helper without
-- running the installer (which would fail outside a real machine anyway).
check("setup.sh has the BASH_SOURCE/$0 sourcing guard (testable)",
  has('[ "${BASH_SOURCE[0]}" = "${0}" ]'))
check("setup.sh defines resolve_install_state_args (the default-mode resolver)",
  bash_capture("declare -F resolve_install_state_args >/dev/null && echo yes") == "yes")

-- non-TTY + no explicit flags + no env -> --force
check("resolver: non-TTY, no flags, no env -> --force (safe default)",
  bash_capture("WEZ_INSTALL_STATE_MODE= resolve_install_state_args 0 nontty") == "--force",
  bash_capture("WEZ_INSTALL_STATE_MODE= resolve_install_state_args 0 nontty"))

-- non-TTY + no explicit flags + env override -> the env value
check("resolver: non-TTY, no flags, env=--skip -> --skip (env override honored)",
  bash_capture("WEZ_INSTALL_STATE_MODE=--skip resolve_install_state_args 0 nontty") == "--skip",
  bash_capture("WEZ_INSTALL_STATE_MODE=--skip resolve_install_state_args 0 nontty"))

-- explicit user flags ALWAYS win (here on a non-TTY) -> verbatim passthrough
check("resolver: explicit user flag --restore wins over the default (passthrough)",
  bash_capture("resolve_install_state_args 1 nontty --restore") == "--restore",
  bash_capture("resolve_install_state_args 1 nontty --restore"))

-- TTY + no explicit flags -> NO default flag (let install-state prompt)
check("resolver: TTY, no flags -> empty (interactive prompt path unchanged)",
  bash_capture("resolve_install_state_args 0 tty") == "",
  "[" .. bash_capture("resolve_install_state_args 0 tty") .. "]")

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
