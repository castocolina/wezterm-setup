-- tests/cli/ci_macos_toolchain_test.lua
-- TEXT gate over the Phase 07-03 macOS CI legs (the supply-side fix set).
--
-- release.yml, ci-setup-toolchain.sh, and build.sh are shell/YAML glue with no Lua
-- entry point, so (per the project's "assert script TEXT" convention, the same
-- shape as publish_test.lua) this test reads each file via io.open and asserts on
-- its CONTENTS:
--
--   * release.yml restores the 3-leg strategy.matrix over ubuntu-latest /
--     macos-15-intel / macos-14, NEVER names the removed macos-13 runner, carries
--     an arm64-only in-build smoke (codesign --verify + dist/wez version on the
--     macos-14 leg), and keeps the workflow_dispatch dry-run trigger.
--   * ci-setup-toolchain.sh pins lua@5.4 (NOT bare `lua`, which is 5.5) — a
--     cross-file regression guard for 07-03 Task 1.
--   * build.sh ad-hoc codesigns the macOS build (`codesign --force --sign -`) —
--     the other half of the Task 1 cross-file guard.
--
-- Runnable directly: `lua5.4 tests/cli/ci_macos_toolchain_test.lua`. Exits
-- non-zero on any failed assertion so tools/run-tests.sh discovers + gates it.

-- Resolve the repo root from this file's location so it runs from any CWD.
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

local function read_file(rel)
  local path = repo_root .. "/" .. rel
  local fh = io.open(path, "r")
  check(rel .. " exists and is readable", fh ~= nil, path)
  local src = fh and fh:read("*a") or ""
  if fh then fh:close() end
  return src
end

-- ---------------------------------------------------------------------------
-- .github/workflows/release.yml — the restored 3-leg matrix.
-- ---------------------------------------------------------------------------
local wf = read_file(".github/workflows/release.yml")

-- All three runner labels appear.
check("release.yml names ubuntu-latest (linux-x86_64 leg)",
  wf:find("ubuntu-latest", 1, true) ~= nil)
check("release.yml names macos-15-intel (darwin-x86_64 leg)",
  wf:find("macos-15-intel", 1, true) ~= nil)
check("release.yml names macos-14 (darwin-aarch64 leg)",
  wf:find("macos-14", 1, true) ~= nil)

-- strategy.matrix is present (both the `strategy:` and `matrix:` keys).
check("release.yml has a strategy: key", wf:find("strategy:", 1, true) ~= nil)
check("release.yml has a matrix: key", wf:find("matrix:", 1, true) ~= nil)

-- The removed runner is NEVER named (Pitfall 7 — macos-13 was removed 2025-12-04).
check("release.yml never names the removed macos-13 runner",
  wf:find("macos-13", 1, true) == nil,
  "macos-13 was removed by GitHub; it must not appear")

-- runs-on consumes the matrix runner.
check("release.yml runs-on consumes matrix.runner",
  wf:find("matrix.runner", 1, true) ~= nil)

-- arm64-only in-build smoke: gated to the macos-14 leg, with codesign --verify
-- + the dist/wez version run.
check("release.yml has an arm64 smoke gated to macos-14",
  wf:find("matrix.runner == 'macos%-14'") ~= nil,
  "expected an if: matrix.runner == 'macos-14' guard")
check("release.yml arm64 smoke runs codesign --verify",
  wf:find("codesign %-%-verify") ~= nil)
check("release.yml arm64 smoke runs dist/wez version",
  wf:find("dist/wez version", 1, true) ~= nil)

-- workflow_dispatch dry-run trigger remains.
check("release.yml keeps the workflow_dispatch trigger (dry-run path)",
  wf:find("workflow_dispatch", 1, true) ~= nil)

-- ---------------------------------------------------------------------------
-- Cross-file regression guards for 07-03 Task 1 (the supply-side fixes the
-- matrix depends on).
-- ---------------------------------------------------------------------------
local toolchain = read_file("tools/ci-setup-toolchain.sh")
check("ci-setup-toolchain.sh pins lua@5.4 (keg-only, not bare lua=5.5)",
  toolchain:find("lua@5.4", 1, true) ~= nil)
check("ci-setup-toolchain.sh never does a bare `brew install lua ` (5.5)",
  toolchain:find("brew install lua ", 1, true) == nil,
  "a bare `brew install lua` would pull Homebrew Lua 5.5")
check("ci-setup-toolchain.sh persists the keg bin onto $GITHUB_PATH",
  toolchain:find("GITHUB_PATH", 1, true) ~= nil)

local build = read_file("tools/build.sh")
check("build.sh ad-hoc codesigns the macOS build",
  build:find("codesign %-%-force %-%-sign %-") ~= nil)
check("build.sh records a codesign --verify evidence line",
  build:find("codesign %-%-verify") ~= nil)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
