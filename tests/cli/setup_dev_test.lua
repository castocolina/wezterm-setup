-- tests/cli/setup_dev_test.lua
-- Unit tests for tools/setup-dev.sh (Plan 07-01): the sudo-free DEV
-- compile-toolchain provisioner for an end-developer's own Mac (autonomy item
-- #1, distinct from tools/ci-setup-toolchain.sh which provisions a CI runner).
--
-- All assertions are on script TEXT + a SOURCED no-run behavior check (the
-- BASH_SOURCE/$0 guard means sourcing does NOT run main). NO brew/luarocks
-- install is triggered — this stays an autonomous unit gate under run-tests.sh.
--
-- Invariants asserted (Pitfall 1/2 + D-08 sudo-free):
--   * installs the keg-only `lua@5.4` formula, NOT the bare `lua` (= Lua 5.5).
--   * resolves the keg-only prefix via `brew --prefix lua@5.4` and prepends its
--     bin onto PATH (so `lua5.4` is findable for build.sh have_luastatic()).
--   * echoes the keg bin onto $GITHUB_PATH when set.
--   * detects Xcode CLT with xcode-select and INSTRUCTS (never auto-installs/sudos).
--   * fails loud if lua5.4 / luastatic are absent after install.
--   * has the sourcing guard (testability).
--   * no non-comment line invokes sudo (sudo-free invariant).
--
-- Run directly: `lua5.4 tests/cli/setup_dev_test.lua`.

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

local SCRIPT = repo_root .. "/tools/setup-dev.sh"

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
-- TEXT: keg-only lua@5.4 install + prefix resolution (Pitfall 1 + 2).
-- ----------------------------------------------------------------------------
check("installs the keg-only `lua@5.4` formula (brew install lua@5.4)",
  has("brew install lua@5.4"))
check("resolves the keg-only prefix via `brew --prefix lua@5.4` (Pitfall 2)",
  has("brew --prefix lua@5.4"))
check("prepends the keg bin onto PATH so lua5.4 is findable for build.sh",
  has('export PATH="${prefix}/bin:${PATH}"'))
check("installs luarocks", has("brew install luarocks"))
-- `--local` is load-bearing: a bare `luarocks install` targets the system tree
-- (/usr/local) and fails without write access, violating the sudo-free invariant.
check("installs luastatic via `luarocks install --local` (sudo-free, ~/.luarocks)",
  has("luarocks install --local luastatic"))
check("prepends ~/.luarocks/bin onto PATH so luastatic is findable",
  has('export PATH="${HOME}/.luarocks/bin:${PATH}"'))

-- ----------------------------------------------------------------------------
-- TEXT: $GITHUB_PATH persistence (so the keg bin survives onto a CI job PATH).
-- ----------------------------------------------------------------------------
check("echoes the keg bin onto $GITHUB_PATH when set",
  has("GITHUB_PATH"))

-- ----------------------------------------------------------------------------
-- TEXT: Xcode CLT detect-then-instruct (never auto-install / sudo).
-- ----------------------------------------------------------------------------
check("detects Xcode CLT via `xcode-select -p`", has("xcode-select -p"))
check("instructs the user to run `xcode-select --install` (one-time interactive)",
  has("xcode-select --install"))

-- ----------------------------------------------------------------------------
-- TEXT: fail-loud asserts on missing lua5.4 / luastatic after install.
-- ----------------------------------------------------------------------------
check("fail-loud assert references lua5.4 not on PATH", has("lua5.4 not on PATH"))
check("fail-loud assert references luastatic not on PATH", has("luastatic not on PATH"))

-- ----------------------------------------------------------------------------
-- TEXT: sourcing guard (the test can source the script without running main).
-- ----------------------------------------------------------------------------
check("has the BASH_SOURCE/$0 sourcing guard", has('[ "${BASH_SOURCE[0]}" = "${0}" ]'))

-- ----------------------------------------------------------------------------
-- REGRESSION (latent-bug guard, Pitfall 1): no line installs the BARE `lua`
-- formula (`brew install lua ` with a trailing space). That formula is now Lua
-- 5.5 and would silently link the build against the wrong interpreter. We assert
-- NO non-comment line invokes it.
-- ----------------------------------------------------------------------------
do
  -- NOTE: no `-n` on the first grep — `-n` prepends `LINENUM:` which would defeat
  -- the `^[[:space:]]*#` comment anchor on the second grep (a known idiom trap).
  local p = assert(io.popen(
    "grep -E 'brew install lua ' '" .. SCRIPT .. "' | grep -vc '^[[:space:]]*#' || true"))
  local n = tonumber((p:read("*a") or "0"):match("%d+")) or 0
  p:close()
  check("no non-comment line installs the BARE `lua` formula (Lua 5.5 regression guard)",
    n == 0, "non-comment bare-lua lines=" .. tostring(n))
end

-- ----------------------------------------------------------------------------
-- REGRESSION: sudo-free invariant — no non-comment line invokes `sudo`.
-- ----------------------------------------------------------------------------
do
  -- No `-n` (same anchor-trap reason as the bare-lua guard above).
  local p = assert(io.popen(
    "grep -E 'sudo ' '" .. SCRIPT .. "' | grep -vc '^[[:space:]]*#' || true"))
  local n = tonumber((p:read("*a") or "0"):match("%d+")) or 0
  p:close()
  check("no non-comment line invokes `sudo` (sudo-free invariant, D-08)", n == 0,
    "non-comment sudo lines=" .. tostring(n))
end

-- ----------------------------------------------------------------------------
-- BEHAVIOR: the script is sourceable (no main run via the $0/BASH_SOURCE guard)
-- and defines the expected functions. We source it under bash and assert the
-- functions are declared — proving the guard works and the shape is intact.
-- ----------------------------------------------------------------------------
local function bash_ok(body)
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "w"))
  fh:write("#!/usr/bin/env bash\n")
  fh:write("source '" .. SCRIPT .. "'\n")
  fh:write(body .. "\n")
  fh:close()
  local cmd = "bash '" .. tmp .. "' >/dev/null 2>&1"
  local ok = os.execute(cmd)
  os.remove(tmp)
  return ok == true or ok == 0
end

check("script sources cleanly without running main (sourcing guard holds)",
  bash_ok("true"))
check("defines install_macos (the verified macOS toolchain path)",
  bash_ok("declare -F install_macos >/dev/null"))
check("defines assert_and_capture (the fail-loud gate)",
  bash_ok("declare -F assert_and_capture >/dev/null"))
check("defines require_xcode_clt (the detect-then-instruct CLT helper)",
  bash_ok("declare -F require_xcode_clt >/dev/null"))

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
