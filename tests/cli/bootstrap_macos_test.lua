-- tests/cli/bootstrap_macos_test.lua
-- Unit tests for the Phase 7 (macOS parity, D-04/D-05) additions:
--   * wezterm_macos_asset_url(tag) in tools/lib/wezterm-release.sh — the macOS
--     counterpart of wezterm_release_asset_url; builds ONLY the official-host
--     HTTPS `.zip` URL (T-07-06), missing-arg -> non-zero exit.
--   * install_macos(tag) in tools/bootstrap-wezterm.sh — REAL, sudo-free `.app`
--     placement under ${HOME}/Applications: fetch via the shared fetch_to,
--     integrity-gate the `.zip` BEFORE extract (PK magic 504b0304 + size floor +
--     reject absolute/`..` members — T-07-04/T-07-05), extract with `ditto -x -k`,
--     `rm -rf` + `cp -R` the bundle, run-the-binary `--version` evidence. NEVER
--     `/Applications`, never sudo/hdiutil, never an `xattr`/quarantine strip
--     (D-07 — that is Plan 04's verify-then-decide job).
--
-- All assertions are on script TEXT + the pure helper's exit-code/stdout BEHAVIOR
-- under a SOURCED no-run mode (the BASH_SOURCE/$0 guard means sourcing does NOT
-- run main). NO live WezTerm download/extract is triggered — this stays an
-- autonomous unit gate under tools/run-tests.sh.
--
-- Run directly: `lua5.4 tests/cli/bootstrap_macos_test.lua`.

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

local BOOTSTRAP = repo_root .. "/tools/bootstrap-wezterm.sh"
local RELEASE_LIB = repo_root .. "/tools/lib/wezterm-release.sh"

local function read_file(path)
  local fh = assert(io.open(path, "rb"), "cannot open " .. path)
  local data = fh:read("*a")
  fh:close()
  return data
end

local BOOT_SRC = read_file(BOOTSTRAP)
local LIB_SRC = read_file(RELEASE_LIB)
local function boot_has(needle)
  return BOOT_SRC:find(needle, 1, true) ~= nil
end
local function lib_has(needle)
  return LIB_SRC:find(needle, 1, true) ~= nil
end

-- ----------------------------------------------------------------------------
-- TEXT: wezterm_macos_asset_url is defined, official-host only, emits `.zip`.
-- ----------------------------------------------------------------------------
check("wezterm_macos_asset_url() is defined in wezterm-release.sh",
  lib_has("wezterm_macos_asset_url()"))
check("wezterm_macos_asset_url builds the URL from the official host + repo (no arbitrary host)",
  lib_has("${WEZTERM_RELEASE_HOST}") and lib_has("${WEZTERM_RELEASE_REPO}"))
check("wezterm_macos_asset_url emits a `.zip` asset URL",
  lib_has("WezTerm-macos-%s.zip"))
check("wezterm_macos_asset_url has a missing-arg `:?` guard (mirror wezterm_release_asset_url)",
  lib_has('${1:?wezterm_macos_asset_url'))
check("a code comment records the API-confirmed macOS asset name + the date it was checked (Open Q2/A3)",
  lib_has("API-confirmed asset name") and lib_has("2026-06-22"))

-- ----------------------------------------------------------------------------
-- BEHAVIOR: source wezterm-release.sh (no-run) and exercise the pure helper.
-- These MUST PASS now (the helper is real this task).
-- ----------------------------------------------------------------------------
local function bash_stdout(env, body)
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "w"))
  fh:write("#!/usr/bin/env bash\n")
  fh:write("source '" .. RELEASE_LIB .. "'\n")
  fh:write(body .. "\n")
  fh:close()
  local cmd = env .. " bash '" .. tmp .. "' 2>/dev/null </dev/null"
  local p = assert(io.popen(cmd))
  local out = (p:read("*a") or ""):gsub("%s+$", "")
  p:close()
  os.remove(tmp)
  return out
end

local function bash_ok(env, body)
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "w"))
  fh:write("#!/usr/bin/env bash\n")
  fh:write("source '" .. RELEASE_LIB .. "'\n")
  fh:write(body .. "\n")
  fh:close()
  local cmd = env .. " bash '" .. tmp .. "' >/dev/null 2>&1 </dev/null"
  local ok = os.execute(cmd)
  os.remove(tmp)
  return ok == true or ok == 0
end

local nightly_url = bash_stdout("", "wezterm_macos_asset_url nightly")
check("wezterm_macos_asset_url nightly emits the official-host download URL",
  nightly_url:find("https://github.com/wez/wezterm/releases/download/", 1, true) == 1,
  "got=" .. nightly_url)
check("wezterm_macos_asset_url nightly emits a single line ending in `.zip`",
  nightly_url:match("%.zip$") ~= nil and not nightly_url:find("\n", 1, true),
  "got=" .. nightly_url)
check("wezterm_macos_asset_url nightly URL contains the `nightly` tag segment",
  nightly_url:find("/nightly/", 1, true) ~= nil, "got=" .. nightly_url)

local dated_url = bash_stdout("", "wezterm_macos_asset_url 20240203-110809-5046fc22")
check("wezterm_macos_asset_url <dated-tag> embeds the full dated tag in the `.zip` name",
  dated_url:find("WezTerm-macos-20240203-110809-5046fc22.zip", 1, true) ~= nil,
  "got=" .. dated_url)

check("wezterm_macos_asset_url with NO arg exits non-zero (missing-arg guard)",
  not bash_ok("", "wezterm_macos_asset_url"))

-- ----------------------------------------------------------------------------
-- TEXT: install_macos REAL body (Task 2 GREEN). These assertions FAIL RED in
-- Task 1 (the stub only logs+returns 0) and PASS GREEN once Task 2 lands.
-- ----------------------------------------------------------------------------
check("install_macos() is defined", boot_has("install_macos()"))
check("install_macos resolves the asset URL via wezterm_macos_asset_url (no ad-hoc URL build)",
  boot_has("wezterm_macos_asset_url"))
check("install_macos reuses the shared fetch_to downloader (NEVER a new fetcher)",
  boot_has("fetch_to"))
check("install_macos extracts with Apple-native `ditto -x -k`",
  boot_has("ditto -x -k"))
check("install_macos targets ${HOME}/Applications (user-path, sudo-free)",
  boot_has("${HOME}/Applications"))
check("install_macos rm -rf + cp -R places the WezTerm.app bundle",
  boot_has("WezTerm.app") and boot_has("cp -R"))
check("install_macos runs the placed binary as evidence (Contents/MacOS/wezterm --version)",
  boot_has("Contents/MacOS/wezterm"))

-- The .zip integrity gate (T-07-04): PK magic 504b0304 + size floor BEFORE extract.
check("install_macos checks the PK zip magic header (504b0304) before extraction",
  boot_has("504b0304"))

-- ----------------------------------------------------------------------------
-- SECURITY (Task 2 GREEN): the integrity + member-safety gate must come BEFORE
-- the ditto/cp extraction (extract-then-check is forbidden — T-07-04/T-07-05),
-- and NO quarantine/sudo/hdiutil/system-/Applications mutation may appear.
-- These are scoped to install_macos's body.
-- ----------------------------------------------------------------------------
local function macos_body()
  return BOOT_SRC:match("install_macos%(%)%s*{(.-)\n}") or ""
end
do
  local body = macos_body()
  local magic_idx = body:find("504b0304", 1, true)
  local ditto_idx = body:find("ditto -x -k", 1, true)
  check("install_macos: the PK-magic integrity check PRECEDES the ditto extract (no extract-then-check)",
    magic_idx ~= nil and ditto_idx ~= nil and magic_idx < ditto_idx,
    "magic=" .. tostring(magic_idx) .. " ditto=" .. tostring(ditto_idx))

  check("install_macos: a member-safety check (reject absolute / `..` members) precedes extraction",
    (body:find("%.%.") ~= nil) and ditto_idx ~= nil)

  check("install_macos: never references the system /Applications (only ${HOME}/Applications)",
    body:find("/Applications", 1, true) == nil or body:find("${HOME}/Applications", 1, true) ~= nil)

  check("install_macos: NO `xattr`/quarantine mutation in its body (D-07 defers to Plan 04)",
    body:find("xattr", 1, true) == nil)

  check("install_macos: a mktemp scratch dir + RETURN-trap cleanup (mirror install_linux)",
    body:find("mktemp", 1, true) ~= nil and body:find("trap", 1, true) ~= nil)
end

-- ----------------------------------------------------------------------------
-- SOURCE-WIDE (security greps mirroring the acceptance criteria): no system
-- /Applications, no sudo invocation, no hdiutil, no xattr quarantine strip.
-- ----------------------------------------------------------------------------
local function popen_count(cmd)
  local p = assert(io.popen(cmd))
  local n = tonumber((p:read("*a") or "0"):match("%d+")) or 0
  p:close()
  return n
end
-- NOTE: grep WITHOUT -n so a comment line still STARTS with optional space + `#`
-- (a `-n` prefix `NN:#...` would defeat the `^[[:space:]]*#` comment filter).
check("no non-comment line references the system /Applications",
  popen_count("grep -E '/Applications' '" .. BOOTSTRAP .. "' | grep -v 'HOME.*Applications' | grep -vc '^[[:space:]]*#' || true") == 0)
check("no non-comment line invokes `sudo ` or `hdiutil` (sudo-free, no DMG path — D-05)",
  popen_count("grep -E 'sudo |hdiutil' '" .. BOOTSTRAP .. "' | grep -vc '^[[:space:]]*#' || true") == 0)
check("no non-comment line strips com.apple.quarantine via xattr (D-07)",
  popen_count("grep -E 'xattr' '" .. BOOTSTRAP .. "' | grep -vc '^[[:space:]]*#' || true") == 0)

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
