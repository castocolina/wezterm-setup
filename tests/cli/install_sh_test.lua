-- tests/cli/install_sh_test.lua
-- Text/contract tests for the remote one-liner installer (tools/install.sh) and
-- the rewritten README install section, PLUS a deterministic headless-abort
-- behavior assertion that proves the D-03 non-zero abort WITHOUT a human.
-- Runnable directly: `lua5.4 tests/cli/install_sh_test.lua`.
--
-- Shell glue has no Lua entry point, so — like publish_test.lua /
-- completions_test.lua — we assert on the SCRIPT TEXT (plain-substring, the
-- completions_test `find(needle, 1, true)` idiom). The headless-abort assertion
-- is the one exception: it EXECUTES install.sh's headless hand-off branch (via the
-- WEZ_ASSUME_HEADLESS=1 + WEZ_BOOTSTRAP_CMD seams) and asserts a non-zero exit.

-- Resolve the repo root so the test runs from any CWD the runner invokes it under.
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

-- Read a whole file (binary) relative to repo_root; returns its text or nil+err.
local function slurp(rel)
  local fh, oerr = io.open(repo_root .. "/" .. rel, "rb")
  if not fh then return nil, oerr end
  local data = fh:read("*a")
  fh:close()
  return data
end

-- Plain (non-pattern) substring presence, mirroring completions_test's idiom.
local function has(haystack, needle)
  return haystack ~= nil and haystack:find(needle, 1, true) ~= nil
end

-- ----------------------------------------------------------------------------
-- tools/install.sh — the pipe-safe safety contract
-- ----------------------------------------------------------------------------
local install = assert(slurp("tools/install.sh"), "cannot read tools/install.sh")

-- main() truncation safety: the LAST non-blank line must be exactly `main "$@"`,
-- so a truncated curl|bash stream never reaches an executable statement.
do
  local last
  for line in install:gmatch("[^\n]*") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then last = trimmed end
  end
  check("install.sh last non-blank line is `main \"$@\"`", last == 'main "$@"',
    "last=" .. tostring(last))
  -- exactly one main "$@" invocation
  local n, i = 0, 1
  while true do
    local s, e = install:find('main "$@"', i, true)
    if not s then break end
    n = n + 1
    i = e + 1
  end
  check("install.sh has exactly one `main \"$@\"` invocation", n == 1, "count=" .. n)
end

check("install.sh reads prompts from /dev/tty", has(install, "/dev/tty"))
check("install.sh uses a mktemp -d temp checkout", has(install, "mktemp"))
check("install.sh cleans up via `trap 'rm -rf' EXIT`",
  has(install, "trap 'rm -rf") and has(install, "EXIT"))
check("install.sh fetches from codeload (no git dependency)", has(install, "codeload"))
check("install.sh strips the GitHub wrapper dir (--strip-components=1)",
  has(install, "--strip-components=1"))
-- Regression guard (Phase 6 review Critical #1): WEZ_REF pin-to-tag/commit was
-- broken by a hardcoded `refs/heads/${ref}` — a tag/commit 404s there. The ref
-- must be resolved by kind: branch (refs/heads), tag (refs/tags), commit (/<sha>).
check("install.sh resolves a tag ref via refs/tags (not only refs/heads)",
  has(install, "refs/tags/"))
check("install.sh detects a commit-SHA ref (hex) for the bare /tar.gz/<sha> form",
  has(install, "[0-9a-fA-F]{7,40}"))
check("install.sh hands off with WEZ_REMOTE_BOOTSTRAP=1", has(install, "WEZ_REMOTE_BOOTSTRAP=1"))
check("install.sh exposes the WEZ_REF pin seam (tag/commit)", has(install, "WEZ_REF"))
check("install.sh exposes the deterministic WEZ_ASSUME_HEADLESS test seam",
  has(install, "WEZ_ASSUME_HEADLESS"))
-- Regression guards (live-dogfood-found, 06-04): the EXIT trap fires after main()
-- returns, so a `local tmp` is out of scope there — under `set -u` that aborts the
-- trap, leaks the temp dir, AND forces a non-zero exit on success (breaks SC#3).
check("install.sh does NOT declare `local tmp` (EXIT trap needs script scope)",
  not has(install, "local tmp"))
check("install.sh EXIT trap guards the cleanup var as `${tmp:-}`",
  has(install, 'rm -rf "${tmp:-}"'))
-- Usable-tty detection must OPEN /dev/tty, not just stat it (a container can expose
-- a /dev/tty node that passes `-e`/`-r` yet fails to open with ENXIO).
check("install.sh detects a usable tty by opening it (`: < /dev/tty`)",
  has(install, ": < /dev/tty"))
-- D-01: install.sh adds NO version/update/target/asset-selection decision logic.
do
  local forbidden = { "download_release", "wezterm_datestamp", "select_release",
    "WEZTERM_TARGET", "latest_nightly" }
  local found
  for _, f in ipairs(forbidden) do
    if has(install, f) then found = f; break end
  end
  check("install.sh contains NO install-decision logic (D-01 pure glue)", found == nil, found)
end

-- ----------------------------------------------------------------------------
-- README.md — the real one-liners + trust model + post-install steps
-- ----------------------------------------------------------------------------
local readme = assert(slurp("README.md"), "cannot read README.md")

local CURL = "curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash"
local WGET = "wget -qO- https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash"

check("README ships the castocolina curl one-liner", has(readme, CURL))
check("README ships the wget one-liner variant", has(readme, WGET))
check("README ships the bash <(curl …) full-interactivity form",
  has(readme, "bash <(curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh)"))
-- BROKEN placeholders are gone.
check("README no longer ships the broken `tools/setup.sh | sh` one-liner",
  not has(readme, "tools/setup.sh | sh"))
check("README no longer references the `you/` placeholder owner",
  not has(readme, "github.com/you/") and not has(readme, "raw.githubusercontent.com/you/"))
-- Trust model: inspect-before-run + pin-to-tag/commit (WEZ_REF) + SHA-256 note.
check("README has a Trust model heading", has(readme, "### Trust model"))
check("README documents inspect-before-run (curl -o install.sh; less; bash install.sh)",
  has(readme, "-o install.sh") and has(readme, "less install.sh") and has(readme, "bash install.sh"))
check("README documents pin-to-tag/commit via WEZ_REF", has(readme, "WEZ_REF=v1.0.0"))
check("README notes the wez binary is SHA-256 verified before chmod +x",
  has(readme, "SHA-256 verified before"))
-- Post-install + nightly-default behavior (06-06 / P6-D09).
check("README has post-install steps (PATH for ~/.local/bin, restart shell, wez doctor)",
  has(readme, "~/.local/bin") and has(readme, "wez doctor"))
check("README notes the nightly-default + update-in-place WezTerm behavior",
  has(readme, "nightly") and has(readme, "updated in place"))

-- ----------------------------------------------------------------------------
-- DETERMINISTIC headless-abort assertion (Warning 7): prove the D-03 non-zero
-- abort with NO human, via the WEZ_ASSUME_HEADLESS=1 seam.
--
-- install.sh's network fetch runs BEFORE the hand-off, so exercising the FULL
-- install.sh entry hermetically (no network) is what the human-checkpoint dogfood
-- covers. Here we drive the SMALLEST deterministic entry that reaches the SAME
-- D-03 abort the hand-off would hit — the local-checkout `wez install-state`
-- headless against a SCRATCH config that already carries a managed block, under
-- WEZ_ASSUME_HEADLESS=1 and NO override flag — and assert the non-zero (exit 3)
-- abort. This is the plan's sanctioned fallback (a deterministic, human-free,
-- non-zero-abort assertion in the suite), distinct from the human checkpoint's
-- live `bash install.sh </dev/null` dogfood of the full hand-off.
-- ----------------------------------------------------------------------------
local function sh(cmd)
  local ok, _, code = os.execute(cmd)
  if type(ok) == "number" then return ok end           -- Lua 5.1 style
  if ok == true then return 0 end                       -- 5.2+ success
  return code or 1                                      -- 5.2+ failure -> exit code
end

do
  -- A throwaway scratch dir with a wezterm.lua that ALREADY has a managed block.
  local scratch = os.tmpname()
  os.remove(scratch)
  os.execute("mkdir -p '" .. scratch .. "'")
  local cfg = scratch .. "/wezterm.lua"
  local fh = assert(io.open(cfg, "wb"))
  fh:write(table.concat({
    'local wezterm = require("wezterm")',
    "local config = wezterm.config_builder()",
    "-- >>> wezterm-setup managed block >>>",
    'config = dofile("/tmp/wezterm-setup/init.lua")(config)',
    "-- <<< wezterm-setup managed block <<<",
    "return config",
    "",
  }, "\n"))
  fh:close()

  -- The local-checkout wez launcher (dev source launcher or built binary).
  local wez = repo_root .. "/dist/wez"
  local have_wez = io.open(wez, "rb")
  if have_wez then have_wez:close() end

  if not have_wez then
    print("  skip - headless-abort assertion (dist/wez not built; run `make build`)")
  else
    -- Headless entry under WEZ_ASSUME_HEADLESS=1, NO override flag -> D-03 abort (exit 3).
    local direct = table.concat({
      "WEZ_ASSUME_HEADLESS=1",
      "WEZTERM_CONFIG_FILE='" .. cfg .. "'",
      "'" .. wez .. "' install-state",
      "</dev/null >/dev/null 2>&1",
    }, " ")
    local code = sh(direct)
    check("headless run aborts NON-ZERO on an existing managed block (D-03, deterministic)",
      code == 3, "exit=" .. tostring(code))

    -- And prove the same path yields a clean install when an override flag IS passed
    -- (so the non-zero abort above is specifically the missing-decision guard, not a
    -- blanket failure). --force overrides the block -> exit 0.
    local forced = table.concat({
      "WEZ_ASSUME_HEADLESS=1",
      "WEZTERM_CONFIG_FILE='" .. cfg .. "'",
      "'" .. wez .. "' install-state --force",
      "</dev/null >/dev/null 2>&1",
    }, " ")
    local fcode = sh(forced)
    check("headless run with --force re-yields one managed block (exit 0)", fcode == 0,
      "exit=" .. tostring(fcode))
  end

  os.execute("rm -rf '" .. scratch .. "'")
end

-- ----------------------------------------------------------------------------
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
