-- tests/cli/build_channel_test.lua
-- Regression-guard for the WEZ_CHANNEL release-channel selector added to
-- tools/build.sh download_release() (Plan 06.3-03):
--   * WEZ_CHANNEL defaults to `nightly` (incl. the non-interactive curl|bash
--     pipe path), REPLACING the hardcoded `WEZ_RELEASE_TAG=v0.1.0` channel pin
--     (D-08). WEZ_RELEASE_TAG survives ONLY as the explicit-pin escape hatch
--     (the `<vX.Y.Z>` third option, D-01).
--   * resolve_channel_tag() mirrors bootstrap-wezterm.sh's channel machinery
--     SHAPE (D-03): stable -> GitHub /releases/latest (prereleases excluded),
--     nightly -> the newest `nightly-*` prerelease, <vX.Y.Z> -> literal.
--   * A no-TTY pipe (`[ ! -t 0 ]`) resolves deterministically to nightly by
--     default and NEVER hangs (D-02), mirroring select_release().
--   * The verify-SHA-256-before-chmod checksum gate (P6-D08) is NOT bypassed by
--     the channel switch — the verify markers survive the edit unchanged.
--   * A degraded/empty API resolution FAILS LOUDLY (non-zero) and never silently
--     installs an unverified asset (T-06.3-03-03 fail-loud).
--
-- Mirrors tests/cli/bootstrap_update_test.lua: assertions are on script TEXT +
-- the resolver's exit-code/stdout BEHAVIOR under a SOURCED no-run mode (the
-- BASH_SOURCE/$0 guard means sourcing does NOT run main). NO live release
-- download is triggered — this stays an autonomous unit gate under run-tests.sh.
--
-- Run directly: `lua5.4 tests/cli/build_channel_test.lua`.

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
-- TEXT: WEZ_CHANNEL nightly default replaces the hardcoded v0.1.0 pin.
-- ----------------------------------------------------------------------------
check("WEZ_CHANNEL is introduced", has("WEZ_CHANNEL"))
check("WEZ_CHANNEL defaults to `nightly` (D-02/D-08 non-interactive default)",
  has("WEZ_CHANNEL:-nightly"))
check("the hardcoded `WEZ_RELEASE_TAG:-v0.1.0` channel pin is GONE (no longer the default)",
  not has("WEZ_RELEASE_TAG:-v0.1.0"))
check("WEZ_RELEASE_TAG survives only as the explicit-pin escape hatch (still referenced)",
  has("WEZ_RELEASE_TAG"))
check("WEZ_RELEASE_BASE is unchanged (releases host stays fixed)",
  has("WEZ_RELEASE_BASE"))

-- ----------------------------------------------------------------------------
-- TEXT: the resolver function + the three resolution arms (D-03).
-- ----------------------------------------------------------------------------
check("a resolve_channel_tag() resolver is defined", has("resolve_channel_tag()"))
check("stable arm -> GitHub /releases/latest (prereleases excluded, D-03)",
  has("releases/latest"))
check("nightly arm -> newest `nightly-*` prerelease (mirrors latest_nightly_datestamp shape)",
  has("nightly-"))
check("the resolver does NOT add a jq dependency (mirrors tr/grep -oE parse shape)",
  not has("jq "))
check("the API host is derived for the channel queries (api.github.com repos)",
  has("api.github.com") and has("releases"))

-- ----------------------------------------------------------------------------
-- TEXT: no-TTY determinism (D-02) — mirrors select_release().
-- ----------------------------------------------------------------------------
check("no-TTY branch present (`[ ! -t 0 ]`)", has("! -t 0"))
do
  -- Scope the no-TTY nightly default to the resolver/selector body.
  local body = SRC:match("resolve_channel_tag%(%)%s*{(.-)\n}") or ""
  check("resolve_channel_tag body references the no-TTY branch (deterministic, never hangs)",
    body:find("! -t 0", 1, true) ~= nil)
  check("resolve_channel_tag body resolves nightly by default on the no-TTY pipe",
    body:find("nightly", 1, true) ~= nil)
end

-- ----------------------------------------------------------------------------
-- TEXT: the channel switch does NOT bypass the verify-SHA-before-chmod gate
-- (P6-D08). The verify markers must SURVIVE the edit byte-identically.
-- ----------------------------------------------------------------------------
check("checksum verified marker survives (verify-before-chmod gate intact)",
  has("checksum verified"))
check("checksum mismatch abort survives (P6-D08)", has("checksum mismatch"))
check("the per-asset .sha256 fetch survives", has(".sha256"))
check("chmod +x still present (must occur only AFTER the verify compare)",
  has("chmod +x"))
do
  -- Assert ordering at the TEXT level: the `checksum verified` log precedes the
  -- final `chmod +x "${OUT}"` in download_release (verify-before-chmod, P6-D08).
  local body = SRC:match("download_release%(%)%s*{(.-)\n}") or ""
  local verify_at = body:find("checksum verified", 1, true)
  local chmod_at = body:find('chmod +x "${OUT}"', 1, true)
  check("download_release verifies the checksum BEFORE chmod +x (ordering preserved)",
    verify_at ~= nil and chmod_at ~= nil and verify_at < chmod_at)
end

-- ----------------------------------------------------------------------------
-- TEXT: fail-loud on a degraded/empty resolution (T-06.3-03-03). The resolver
-- must `return 1` on an empty/unparseable tag rather than fall through to an
-- empty/`latest` segment that would fetch an unverified or wrong asset.
-- ----------------------------------------------------------------------------
do
  local body = SRC:match("resolve_channel_tag%(%)%s*{(.-)\n}") or ""
  check("resolve_channel_tag fails loudly (return 1) on a degraded/empty resolution",
    body:find("return 1", 1, true) ~= nil)
end

-- ----------------------------------------------------------------------------
-- TEXT: the $0/BASH_SOURCE sourcing guard around main "$@" (so this test can
-- source build.sh and exercise the resolver without running a build).
-- ----------------------------------------------------------------------------
check("build.sh guards `main \"$@\"` behind a BASH_SOURCE/$0 sourcing guard",
  has("BASH_SOURCE[0]") and has('= "${0}"'))

-- ----------------------------------------------------------------------------
-- BEHAVIOR: source build.sh (no main run, via the $0/BASH_SOURCE guard) and
-- exercise resolve_channel_tag. Force a fake API host so NO real network call
-- is made (the literal arm needs no network; the no-TTY default needs none).
-- ----------------------------------------------------------------------------
local function bash_stdout(env, body)
  local tmp = os.tmpname()
  local fh = assert(io.open(tmp, "w"))
  fh:write("#!/usr/bin/env bash\n")
  fh:write("source '" .. SCRIPT .. "'\n")
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
  fh:write("source '" .. SCRIPT .. "'\n")
  fh:write(body .. "\n")
  fh:close()
  local cmd = env .. " bash '" .. tmp .. "' >/dev/null 2>&1 </dev/null"
  local ok = os.execute(cmd)
  os.remove(tmp)
  return ok == true or ok == 0
end

-- Literal arm: an explicit vX.Y.Z channel echoes verbatim, no network.
check("resolve_channel_tag (WEZ_CHANNEL=v9.9.9) echoes the literal tag verbatim",
  bash_stdout("WEZ_CHANNEL=v9.9.9", "resolve_channel_tag") == "v9.9.9")

-- Explicit-pin escape hatch: WEZ_RELEASE_TAG forces the literal channel.
check("WEZ_RELEASE_TAG=v0.1.0 (no WEZ_CHANNEL) still resolves to v0.1.0 (escape hatch)",
  bash_stdout("WEZ_RELEASE_TAG=v0.1.0", "resolve_channel_tag") == "v0.1.0")

-- No-TTY default: stdin from /dev/null + no channel -> deterministically nightly
-- resolution attempt. We force a bogus API host so the nightly lookup fails the
-- fetch and the resolver fails LOUDLY (non-zero) rather than hanging or silently
-- emitting an empty/`latest` tag.
check("resolve_channel_tag with an unreachable API on the nightly default fails loud (non-zero)",
  not bash_ok("WEZ_RELEASE_API=http://127.0.0.1:0", "resolve_channel_tag"))

-- ----------------------------------------------------------------------------
-- resolve_stable_date() — DISPLAY-ONLY stable release-date resolver folded into
-- the interactive picker label (Plan 06.3 quick 260618-evx). Stable date-parity
-- with nightly: "newest stable (v0.1.0 · 2026-06-15)".
-- ----------------------------------------------------------------------------

-- BEHAVIOR (stubbed fetch): resolve_stable_date echoes exactly the YYYY-MM-DD
-- prefix of published_at. _api_fetch is redefined AFTER the source so the body
-- shadows the real fetcher — NO network call is made. The JSON has no single
-- quotes, so single-quoting the env value is safe.
local SAMPLE = '{"tag_name": "v0.1.0", "published_at": "2026-06-15T13:56:59Z"}'
check("resolve_stable_date (stubbed /releases/latest JSON) echoes the YYYY-MM-DD prefix",
  bash_stdout("SAMPLE_JSON='" .. SAMPLE .. "'",
    "_api_fetch() { printf '%s' \"$SAMPLE_JSON\"; }; resolve_stable_date") == "2026-06-15")

-- BEHAVIOR (best-effort empty): a stubbed _api_fetch that echoes nothing /
-- returns 1 -> resolve_stable_date is non-zero AND its stdout is empty, proving
-- it never aborts and the picker can fall back to the tag-only label.
check("resolve_stable_date with an empty/failed fetch returns non-zero (best-effort, never aborts)",
  not bash_ok("", "_api_fetch() { return 1; }; resolve_stable_date"))
check("resolve_stable_date with an empty/failed fetch emits NOTHING on stdout",
  bash_stdout("", "_api_fetch() { return 1; }; resolve_stable_date") == "")

-- TEXT: the helper is defined.
check("resolve_stable_date() helper is defined", has("resolve_stable_date()"))

-- TEXT: resolve_stable_date reuses /releases/latest (no second/third endpoint).
do
  local body = SRC:match("resolve_stable_date%(%)%s*{(.-)\n}") or ""
  check("resolve_stable_date reuses /releases/latest (same endpoint as resolve_stable_tag)",
    body:find("releases/latest", 1, true) ~= nil)
  check("resolve_stable_date reuses _api_fetch (no third fetcher)",
    body:find("_api_fetch", 1, true) ~= nil)
  check("resolve_stable_date adds no jq dependency", body:find("jq ", 1, true) == nil)
  check("resolve_stable_date extracts published_at (not tag_name)",
    body:find("published_at", 1, true) ~= nil)
end

-- TEXT: the interactive resolver references resolve_stable_date and builds a
-- date-bearing stable label. Use the EXACT byte sequence emitted by build.sh
-- (the U+00B7 MIDDLE DOT separator is UTF-8) so has() substring matching lines up.
do
  local body = SRC:match("resolve_channel_tag%(%)%s*{(.-)\n}") or ""
  check("resolve_channel_tag references resolve_stable_date (interactive date capture)",
    body:find("resolve_stable_date", 1, true) ~= nil)
  check("the interactive stable label is date-augmented (newest stable (tag · date))",
    has("newest stable (${stable_tag} · ${stable_date})"))
  check("the tag-only stable label fallback survives (date-resolution failure path)",
    has("newest stable (${stable_tag})"))
end

-- TEXT (contract guard): resolve_stable_tag stays bare-tag-only — its body must
-- still echo the tag and must NOT contain published_at (the date logic lives
-- ONLY in resolve_stable_date), proving the download-feeding contract is intact.
do
  local body = SRC:match("resolve_stable_tag%(%)%s*{(.-)\n}") or ""
  check("resolve_stable_tag body still extracts tag_name", body:find("tag_name", 1, true) ~= nil)
  check("resolve_stable_tag body still echoes the bare tag (printf '%s\\n' \"${tag}\")",
    body:find('printf \'%s\\n\' "${tag}"', 1, true) ~= nil)
  check("resolve_stable_tag body has NO published_at (date logic is display-only, elsewhere)",
    body:find("published_at", 1, true) == nil)
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
