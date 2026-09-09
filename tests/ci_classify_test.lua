-- tests/ci_classify_test.lua
--
-- Durable, make-test-discovered regression coverage for
-- tools/ci-classify-e2e-output.sh's full D-02 discrimination matrix (06.8,
-- cycle-2 MEDIUM-2: "no committed regression test discovered by `make test`").
-- Auto-discovered by tools/run-tests.sh with no registration step needed (tests/
-- + cli/ + config/ *_test.lua glob, confirmed by reading run-tests.sh — this file
-- is NOT named *_e2e_test.lua, so it is NOT excluded by that glob).
--
-- Follows tests/cli/bootstrap_update_test.lua's exact idiom: a check(label, ok,
-- detail) counter, a write_log(lines) helper writing a table of strings to an
-- os.tmpname() file (removed after use), and a classify_ok(path) helper running
-- tools/ci-classify-e2e-output.sh <path> via os.execute.
--
-- Run directly: `lua5.4 tests/ci_classify_test.lua`.

local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/.." -- tests/ -> repo root

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

local SCRIPT = repo_root .. "/tools/ci-classify-e2e-output.sh"

-- write_log(lines) -> path. Writes a table of strings, one line each, to an
-- os.tmpname() file. Caller is responsible for os.remove'ing it after use.
local function write_log(lines)
  local path = os.tmpname()
  local fh = assert(io.open(path, "wb"))
  for _, line in ipairs(lines) do
    fh:write(line, "\n")
  end
  fh:close()
  return path
end

-- classify_ok(path) -> boolean. Runs tools/ci-classify-e2e-output.sh <path> via
-- os.execute, with output explicitly redirected to /dev/null (cycle-3 HIGH-1):
-- without this redirect, the classify script's own ::error:: diagnostics for
-- these intentionally-malformed fixtures would print to make test's stdout,
-- which Task 1's own <verify> and Task 1's ci.yml step 3 (make test) run
-- unredirected — leaking fake "unexpected skip"/"missing live label" lines into
-- the very CI job log that would otherwise be scanned as a whole (the log Task 3
-- classifies is the DEDICATED e2e-output-log artifact, but this redirect is a
-- belt-and-braces first layer regardless). Only the exit code crosses out.
local function classify_ok(path)
  local cmd = string.format("%s %s >/dev/null 2>&1", SCRIPT, path)
  local ok = os.execute(cmd)
  -- lua5.4 os.execute returns true/false (+ "exit"/code); normalize to boolean.
  return ok == true or ok == 0
end

-- Shared label table — construct every fixture by slicing/extending this ONE
-- table, never re-typing the label strings a third time (the labels themselves
-- are Task 1 Part A's single source of truth, mirrored here only for fixture
-- construction).
local EXPECTED_SKIP = "keys-siblings macOS bundle-symlink contract"
local LIVE_LABELS = {
  "tier2 scene-launch-motd-race regression",
  "tier2 new-tab-mode scene live-mux",
  "tier2 reuse-mode scene live-mux",
  "tier3 show-keys registration",
}

local function live_line(label)
  return label .. ": LIVE-ASSERTED (some reason)"
end
local function skipped_line(label, reason)
  return label .. ": SKIPPED (reason=" .. (reason or "unavailable") .. ")"
end
local function expected_skip_line()
  return EXPECTED_SKIP .. ": SKIPPED (reason=macOS deferred to Phase 7)"
end

local function all_live_lines()
  local out = {}
  for _, l in ipairs(LIVE_LABELS) do
    out[#out + 1] = live_line(l)
  end
  return out
end

-- ----------------------------------------------------------------------------
-- Fixture 1: exactly-once expected skip + all 4 required lives -> PASS.
-- ----------------------------------------------------------------------------
do
  local lines = all_live_lines()
  lines[#lines + 1] = expected_skip_line()
  local path = write_log(lines)
  check("fixture 1 (pass: exactly-once expected skip + all 4 lives) classifies OK",
    classify_ok(path))
  os.remove(path)
end

-- ----------------------------------------------------------------------------
-- Fixture 2: one required live label replaced by an unexpected SKIPPED -> FAIL.
-- ----------------------------------------------------------------------------
do
  local lines = {}
  for i, l in ipairs(LIVE_LABELS) do
    if i == 2 then
      lines[#lines + 1] = skipped_line(l, "wezterm-mux-server unavailable")
    else
      lines[#lines + 1] = live_line(l)
    end
  end
  lines[#lines + 1] = expected_skip_line()
  local path = write_log(lines)
  check("fixture 2 (fail: missing a required live label) classifies FAIL",
    not classify_ok(path))
  os.remove(path)
end

-- ----------------------------------------------------------------------------
-- Fixture 3: all 4 lives present, PLUS an extra unexpected SKIPPED for an
-- ALREADY-live label — the real scene_motd_race dual-emit shape (cycle-2
-- MEDIUM-1) -> FAIL.
-- ----------------------------------------------------------------------------
do
  local lines = all_live_lines()
  -- Dual-emit: the FIRST live label also prints a separate SKIPPED line, the
  -- real shape scene_motd_race_e2e_test.lua produces when bash is absent.
  lines[#lines + 1] = skipped_line(LIVE_LABELS[1], "no bash on PATH")
  lines[#lines + 1] = expected_skip_line()
  local path = write_log(lines)
  check("fixture 3 (fail: extra unexpected skip alongside all-4-lives-present, dual-emit shape) classifies FAIL",
    not classify_ok(path))
  os.remove(path)
end

-- ----------------------------------------------------------------------------
-- Fixture 4: expected macOS self-skip line entirely absent -> FAIL (cycle-2
-- MEDIUM-3).
-- ----------------------------------------------------------------------------
do
  local lines = all_live_lines()
  -- No expected_skip_line() appended.
  local path = write_log(lines)
  check("fixture 4 (fail: expected self-skip absent) classifies FAIL",
    not classify_ok(path))
  os.remove(path)
end

-- ----------------------------------------------------------------------------
-- Fixture 5: expected macOS self-skip line appears TWICE -> FAIL (exactly-once,
-- not "at least once").
-- ----------------------------------------------------------------------------
do
  local lines = all_live_lines()
  lines[#lines + 1] = expected_skip_line()
  lines[#lines + 1] = expected_skip_line()
  local path = write_log(lines)
  check("fixture 5 (fail: expected self-skip duplicated) classifies FAIL",
    not classify_ok(path))
  os.remove(path)
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
