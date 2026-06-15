-- tests/cli/publish_test.lua
-- Pins the publish-side ASSET-NAME CONTRACT for tools/publish.sh.
--
-- tools/publish.sh is shell glue with no Lua entry point, so (per the project's
-- "assert script TEXT" convention) this test reads the script via io.open and
-- asserts on its CONTENTS: the asset name is derived from platform_os/platform_arch
-- (never hardcoded os/arch literals) so a maintainer-published asset and a
-- CI-published asset never drift (P6-D08), and the upload names BOTH the asset and
-- its per-asset `<asset>.sha256` with `--clobber` (the same command CI uses).
--
-- Runnable directly: `lua5.4 tests/cli/publish_test.lua`. Exits non-zero on any
-- failed assertion so tools/run-tests.sh discovers + gates it.

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

-- Read tools/publish.sh as text.
local path = repo_root .. "/tools/publish.sh"
local fh = io.open(path, "r")
check("tools/publish.sh exists and is readable", fh ~= nil, path)
local src = fh and fh:read("*a") or ""
if fh then fh:close() end

-- Asset name is derived from platform_os/platform_arch (the byte-identical
-- contract to build.sh:104-106), not invented locally.
check("asset name uses platform_os", src:find("platform_os", 1, true) ~= nil)
check("asset name uses platform_arch", src:find("platform_arch", 1, true) ~= nil)
check("asset name follows the wez-<os>-<arch> shape",
  src:find('wez%-%${os}%-%${arch}') ~= nil,
  "expected literal wez-${os}-${arch}")

-- No hardcoded os/arch literals in the asset name (would drift from platform.sh).
do
  local literal = src:find("wez%-linux%-") or src:find("wez%-darwin%-")
    or src:find("wez%-macos%-") or src:find("wez%-x86_64") or src:find("wez%-aarch64")
  check("no hardcoded os/arch literals in the asset name", literal == nil,
    literal and "found a hardcoded wez-<os|arch> literal" or nil)
end

-- The upload names BOTH ${asset} and ${asset}.sha256 with --clobber — the same
-- contract release.yml must match (Pattern 6 same-contract rule).
check("upload names the asset", src:find('"%${asset}"') ~= nil)
check("upload names the per-asset .sha256", src:find('"%${asset}%.sha256"') ~= nil)
check("upload uses --clobber", src:find("%-%-clobber", 1) ~= nil)
check("upload uses gh release upload", src:find("gh release upload", 1, true) ~= nil)

-- Apple Silicon ad-hoc codesign is guarded by BOTH macos AND aarch64 (Pattern 7).
check("codesign branch present", src:find("codesign", 1, true) ~= nil)
check("codesign guarded by macos", src:find('"%${os}" = "macos"') ~= nil)
check("codesign guarded by aarch64", src:find('"%${arch}" = "aarch64"') ~= nil)

-- Portable checksum generation (macOS has no sha256sum).
check("portable checksum: sha256sum branch", src:find("sha256sum", 1, true) ~= nil)
check("portable checksum: shasum -a 256 fallback", src:find("shasum %-a 256") ~= nil)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
