-- cli/commands/update.lua
--
-- The `wez update` subcommand (INST-09). A self-update front door so users (and
-- the installer's update-in-place path) refresh through ONE trusted flow instead
-- of re-pasting the remote URL.
--
-- D-01 / P6-D11 BOUNDARY (CRITICAL): this is a THIN Lua command. The ONLY logic
-- that lives in Lua is the version-comparison DECISION. ALL fetch / unpack /
-- binary-self-replace is DELEGATED to the SAME shared launcher (tools/install.sh,
-- Plan 04) the `curl|bash` one-liner uses — a single entry point, no divergent
-- second update path. This module NEVER downloads, verifies, places, or writes a
-- binary itself; it decides, then shells out to the launcher.
--
-- Warning 4 (DO NOT conflate) — TWO DISTINCT freshness comparators, because they
-- compare different things:
--   (i)  M.decide_wez_update(have, latest, kind)      — the `wez` BINARY half.
--        A SEMVER / release-tag compare of M.VERSION (e.g. "0.1.0") against the
--        latest published `wez` RELEASE tag (e.g. "v0.2.0"). NOT a datestamp.
--   (ii) M.decide_wezterm_update(have, want, kind)    — the WezTerm EMULATOR half.
--        The 8-digit YYYYMMDD datestamp compare (numeric `>=`, the SAME semantics
--        as bootstrap-wezterm.sh's wezterm_datestamp_ge); the `want` is resolved
--        by 06-06 (resolve_want_datestamp / latest-nightly, Plan 01 query).
-- Both comparators are PURE (string/numeric compare only — no FS, no shell, no
-- network) so each is an autonomous, fixture-testable gate (mirrors plan_seed /
-- install_state.decide).
--
-- Self-replace safety (RESEARCH Pattern 4): a running `wez`/`wezterm` cannot be
-- overwritten in place. The swap (download to a temp file in the SAME dir as the
-- live binary, chmod +x, atomic `mv -f` over it — rename(2) keeps the old inode
-- alive for the running process, never rm-then-write / ETXTBSY) is performed in
-- the launcher GLUE, NOT here.
--
-- P6-D09 system-install guard: update-in-place applies ONLY to the project-
-- managed user-path install (~/.local/bin). The install kind is resolved by
-- CALLING 06-06's reusable wezterm_install_is_user_path() predicate (NOT a
-- re-mirror of detect_and_reuse:83). A `wez`/`wezterm` outside ~/.local (e.g. the
-- verified apt /usr/bin/wezterm-nightly, root-owned) is NEVER sudo'd / overwritten:
-- both comparators return "system-skip" and run() messages + leaves it intact.
--
-- Every path/arg reaching a shell goes through install_state.shquote (CR-02).
-- Never elevates privileges (no privilege escalation anywhere in this module).
-- Completion (D-16): `update` is registered in cli/spec.lua's three places so
-- `wez update` tab-completes with no completions.lua edit.

local install_state = require("cli.commands.install_state")
local spec = require("cli.spec")

local M = {}

-- ---------------------------------------------------------------------------
-- PURE comparators (Warning 4 — kept DISTINCT, no FS / shell / network)
-- ---------------------------------------------------------------------------

-- Parse a semver / release tag ("v0.2.0" | "0.2.0") into {major, minor, patch}
-- numeric fields. A leading `v` is tolerated; missing fields default to 0. PURE.
local function parse_semver(s)
  s = tostring(s or ""):gsub("^[vV]", "")
  local major = tonumber(s:match("^(%d+)")) or 0
  local minor = tonumber(s:match("^%d+%.(%d+)")) or 0
  local patch = tonumber(s:match("^%d+%.%d+%.(%d+)")) or 0
  return major, minor, patch
end

-- semver_ge(a, b) -> boolean: a >= b by NUMERIC per-field compare (so 0.10.0 >
-- 0.9.0, which a lexical compare gets wrong). PURE.
local function semver_ge(a, b)
  local amaj, amin, apat = parse_semver(a)
  local bmaj, bmin, bpat = parse_semver(b)
  if amaj ~= bmaj then return amaj > bmaj end
  if amin ~= bmin then return amin > bmin end
  if apat ~= bpat then return apat > bpat end
  return true -- equal
end

-- M.decide_wez_update(have_version, latest_version, install_kind)
--   -> "update" | "current" | "system-skip"
-- The `wez` BINARY freshness. SEMVER/tag compare of `have_version` (the binary's
-- M.VERSION) against `latest_version` (the latest published `wez` release tag).
--   * install_kind == "system"      -> "system-skip" (checked FIRST, P6-D09)
--   * empty/nil latest_version      -> "current" (no published wez release yet,
--                                      Open Q3 — a clean no-op for the wez half)
--   * have >= latest (semver)       -> "current" (equal or newer; never a downgrade)
--   * strictly-newer latest         -> "update"
-- PURE: semver parse + numeric compare only — NOT a YYYYMMDD datestamp.
function M.decide_wez_update(have_version, latest_version, install_kind)
  if install_kind == "system" then
    return "system-skip"
  end
  if latest_version == nil or latest_version == "" then
    return "current" -- no published release to compare against (Open Q3)
  end
  if semver_ge(have_version, latest_version) then
    return "current"
  end
  return "update"
end

-- Numeric 8-digit YYYYMMDD compare: have >= want (the SAME semantics as
-- bootstrap-wezterm.sh wezterm_datestamp_ge). An empty/unparseable side is NOT a
-- valid stamp. PURE.
local function datestamp_to_num(s)
  local d = tostring(s or ""):match("(%d%d%d%d%d%d%d%d)")
  return d and tonumber(d) or nil
end

-- M.decide_wezterm_update(have_datestamp, want_datestamp, install_kind)
--   -> "update" | "current" | "system-skip"
-- The WezTerm EMULATOR freshness. 8-digit YYYYMMDD numeric `>=` compare of the
-- installed datestamp against the latest-nightly want (06-06 resolver).
--   * install_kind == "system"      -> "system-skip" (checked FIRST, P6-D09)
--   * empty/unparseable want        -> "current" (degraded latest-nightly fetch:
--                                      a garbage "newer?" signal NEVER forces a
--                                      swap — T-06-05-04 / T-06-06-01)
--   * empty/unparseable have        -> "update" (installed treated as BELOW;
--                                      matches detect_and_reuse:76-78)
--   * have >= want                  -> "current"
--   * strictly-newer want           -> "update"
-- PURE: 8-digit numeric compare only — NOT a semver.
function M.decide_wezterm_update(have_datestamp, want_datestamp, install_kind)
  if install_kind == "system" then
    return "system-skip"
  end
  local want = datestamp_to_num(want_datestamp)
  if not want then
    return "current" -- degraded/garbage want -> never a forced swap
  end
  local have = datestamp_to_num(have_datestamp)
  if not have then
    return "update" -- unparseable installed -> below want
  end
  if have >= want then
    return "current"
  end
  return "update"
end

-- ---------------------------------------------------------------------------
-- IO seams — resolve the live wez binary, the shared launcher, and the bootstrap
-- predicate/resolver. All shell-bound paths go through install_state.shquote.
-- ---------------------------------------------------------------------------

-- repo_root() — the wezterm-setup tree that ships tools/install.sh +
-- tools/bootstrap-wezterm.sh. Honors a WEZ_REPO_DIR override (the managed-install
-- / test seam), else resolves relative to THIS running script:
-- cli/commands/update.lua -> repo root.
-- KNOWN GAP (follow-up, tracked in .planning/MACOS-PARITY-AND-FOLLOWUPS.md §A): inside
-- the shipped luastatic bundle there is NO on-disk source tree, so WEZ_REPO_DIR must
-- be exported for `wez update` to find install.sh + bootstrap-wezterm.sh — but the
-- installer (tools/setup.sh) does NOT yet set it, nor does it place those scripts in
-- a stable managed location. Until that is wired (alongside cutting the first vN.N.N
-- release, Open Q3), `wez update`'s live delegation only works from a checkout /
-- with WEZ_REPO_DIR set. The pure decision logic + system-install guard below are
-- unaffected and fully tested.
local function repo_root()
  local override = os.getenv("WEZ_REPO_DIR")
  if override and override ~= "" then return override end
  local src = debug.getinfo(1, "S").source
  local this = src:match("^@(.*)$") or src
  local dir = this:match("^(.*)/cli/commands/[^/]+$")
  if dir then return dir end
  return "." -- fallback: source invocation from the repo root
end

-- launcher_path() — the SHARED launcher `wez update` re-invokes: the SAME
-- tools/install.sh the `curl|bash` one-liner runs (single entry point, P6-D11).
-- Overridable via WEZ_LAUNCHER (test seam), else <repo>/tools/install.sh.
local function launcher_path()
  local override = os.getenv("WEZ_LAUNCHER")
  if override and override ~= "" then return override end
  return repo_root() .. "/tools/install.sh"
end

-- popen_line(cmd) -> first trimmed stdout line | "". Reads ONE value from a
-- shelled-out command (used to invoke the bootstrap predicate / resolver). The
-- command is built ONLY from shquote'd paths (CR-02).
local function popen_line(cmd)
  local p = io.popen(cmd .. " 2>/dev/null")
  if not p then return "" end
  local out = p:read("*a") or ""
  p:close()
  return (out:gsub("%s+$", ""):match("([^\n]*)") or "")
end

-- run_status(cmd) -> boolean: true iff the command exits 0. For the predicate
-- (`wezterm_install_is_user_path`) which signals via exit status, not stdout.
local function run_status(cmd)
  local ok = os.execute(cmd .. " >/dev/null 2>&1")
  return ok == true or ok == 0
end

-- resolve_install_kind(wez_path) -> "user-path" | "system". CALLS 06-06's
-- reusable wezterm_install_is_user_path() predicate by sourcing bootstrap-wezterm
-- .sh and invoking it (NOT a re-mirror of detect_and_reuse:83). The active
-- binary is user-path iff the predicate returns 0.
local function resolve_install_kind(wez_path)
  local boot = repo_root() .. "/tools/bootstrap-wezterm.sh"
  local cmd = ". " .. install_state.shquote(boot)
    .. " >/dev/null 2>&1; wezterm_install_is_user_path "
    .. install_state.shquote(wez_path or "")
  if run_status(cmd) then return "user-path" end
  return "system"
end

-- resolve_want_datestamp() -> the latest-nightly want datestamp (06-06 resolver),
-- "" on a degraded/failed fetch (graceful degradation — never a forced swap).
local function resolve_want_datestamp()
  local boot = repo_root() .. "/tools/bootstrap-wezterm.sh"
  local cmd = ". " .. install_state.shquote(boot)
    .. " >/dev/null 2>&1; resolve_want_datestamp"
  return popen_line(cmd)
end

-- wezterm_version_string() -> the active `wezterm --version` line (or "").
local function wezterm_version_string()
  return popen_line("wezterm --version")
end

-- wezterm_path() -> the resolved active wezterm path (or "").
local function wezterm_path()
  return popen_line("command -v wezterm")
end

-- datestamp_of(version_string) -> the leading 8-digit YYYYMMDD, or "".
local function datestamp_of(version_string)
  return (tostring(version_string or ""):match("(%d%d%d%d%d%d%d%d)") or "")
end

-- latest_wez_release_tag() -> the latest published `wez` release tag, or "".
-- Honors WEZ_RELEASE_TAG (the same seam build.sh/publish.sh use). Until the first
-- v* tag is cut (Open Q3) there is no published release to compare against, so an
-- empty value -> the wez half is a clean no-op ("no published wez release yet").
local function latest_wez_release_tag()
  return os.getenv("WEZ_RELEASE_TAG") or ""
end

-- ---------------------------------------------------------------------------
-- run() — wire the pure decisions to the shared launcher (delegate-only)
-- ---------------------------------------------------------------------------

-- run(args) -> exit code. Resolves the install kind via 06-06's predicate, reads
-- the wez semver + WezTerm datestamp inputs, applies BOTH comparators, and:
--   * EITHER "system-skip" -> message naming the system install; never touch it.
--   * BOTH "current"       -> clear combined no-op; return 0.
--   * EITHER "update" (user-path) -> DELEGATE to the shared launcher (install.sh,
--                            the SAME entry point the one-liner uses) and surface
--                            its exit code. No fetch/place/self-replace in Lua.
function M.run(args)
  args = args or {}

  local wez_loc = wezterm_path()
  local install_kind = resolve_install_kind(wez_loc)

  -- wez BINARY half (semver).
  local have_version = spec.VERSION
  local latest_version = latest_wez_release_tag()
  local wez_decision = M.decide_wez_update(have_version, latest_version, install_kind)

  -- WezTerm EMULATOR half (datestamp).
  local wt_version = wezterm_version_string()
  local have_datestamp = datestamp_of(wt_version)
  local want_datestamp = resolve_want_datestamp()
  local wt_decision = M.decide_wezterm_update(have_datestamp, want_datestamp, install_kind)

  -- Report a system install (never modified, P6-D09).
  if wez_decision == "system-skip" or wt_decision == "system-skip" then
    local where = (wez_loc ~= "" and wez_loc) or "the active install"
    io.write("wez update: WezTerm/wez at " .. where
      .. " is a system install (outside ~/.local/bin) — leaving it untouched (no sudo, P6-D09)\n")
    -- Both halves resolve to the same kind here, so a system install means there
    -- is nothing this command may safely update — a clean, non-destructive exit.
    return 0
  end

  -- Both already current -> clear combined no-op.
  if wez_decision == "current" and wt_decision == "current" then
    local wez_note = (latest_version ~= "" and latest_version)
      or (tostring(have_version) .. " (no published wez release yet)")
    local wt_note = (have_datestamp ~= "" and have_datestamp) or "unknown"
    io.write("wez update: wez " .. wez_note .. " and WezTerm " .. wt_note
      .. " are both current — nothing to do\n")
    return 0
  end

  -- EITHER half wants an update (user-path) -> DELEGATE to the shared launcher.
  -- The launcher (setup.sh STEP 2 runs 06-06's WezTerm update-in-place; STEP 3
  -- refreshes the wez binary via the atomic temp-same-dir `mv -f` swap, Pattern 4
  -- — in the GLUE, not here). We re-implement NO download/verify/place.
  local launcher = launcher_path()
  if wez_decision == "update" then
    io.write("wez update: a newer wez release (" .. latest_version
      .. ") is available — updating via the shared installer\n")
  end
  if wt_decision == "update" then
    io.write("wez update: a newer WezTerm nightly (" .. want_datestamp
      .. ") is available — updating via the shared installer\n")
  end

  io.write("wez update: delegating to " .. launcher .. "\n")
  local ok, _, code = os.execute("bash " .. install_state.shquote(launcher))
  if ok == true or ok == 0 then
    return 0
  end
  -- os.execute returns (ok, "exit"|"signal", code) on Lua 5.4; surface code.
  return type(code) == "number" and code or 1
end

return M
