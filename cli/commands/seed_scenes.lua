-- cli/commands/seed_scenes.lua
--
-- The `wez seed-scenes` subcommand (SCEN-06). Copy-if-absent install seeding of
-- the three example scene recipes (ai, docker, dev) into the user's co-located
-- scenes dir `~/.config/wezterm/wezterm-setup/scenes/` (D-04).
--
-- Per D-01/D-07 ALL of the copy/keep decision logic lives here in Lua; the bash
-- installer (tools/setup.sh STEP 4b) is decision-free glue that just shells out
-- to this command. The seeder NEVER overwrites a user-edited recipe (D-06
-- INVARIANT / SCEN-06 "user edits survive reinstall" / threat T-05-05).
--
-- Pure-core / IO-shell split (mirrors install_state.lua):
--   M.plan_seed(repo_seed_names, existing_dest_names) -> { {name=, action=}, ... }
--     PURE list logic, no filesystem — the autonomous fixture-testable gate.
--   M.run(args) wires plan_seed to the real filesystem: it lists the repo seed
--     dir + dest dir, applies plan_seed, RE-CHECKS dest absence at write time
--     (TOCTOU guard, T-05-05) then copies the file bytes, emitting the EXACT
--     UI-SPEC messaging per recipe.
--
-- Every directory/path that reaches io.popen goes through install_state.shquote
-- (CR-02 single-quote escaper) so a scenes-dir path with a shell metacharacter
-- cannot break out (threat T-05-06). All writes target user paths, sudo-free
-- (threat T-05-07).

local install_state = require("cli.commands.install_state")

local M = {}

-- ---------------------------------------------------------------------------
-- PURE seeding DECISION
-- ---------------------------------------------------------------------------

-- plan_seed(repo_seed_names, existing_dest_names) -> { {name=, action="seed"|"keep"}, ... }
-- For each repo seed name, action="keep" when a recipe of that name already
-- exists in the destination (preserve the user's file — copy-if-absent), else
-- action="seed" (a fresh write). PURE: list logic only, no filesystem, so the
-- copy-if-absent contract is fixture-testable. The output order follows the
-- repo_seed_names order so messaging is deterministic.
function M.plan_seed(repo_seed_names, existing_dest_names)
  repo_seed_names = repo_seed_names or {}
  existing_dest_names = existing_dest_names or {}
  local present = {}
  for _, n in ipairs(existing_dest_names) do
    present[n] = true
  end
  local plan = {}
  for _, name in ipairs(repo_seed_names) do
    plan[#plan + 1] = { name = name, action = present[name] and "keep" or "seed" }
  end
  return plan
end

-- ---------------------------------------------------------------------------
-- filesystem helpers (mirror install_state read_all/write_all shapes, CR-03)
-- ---------------------------------------------------------------------------

local function read_all(path)
  local fh, err = io.open(path, "rb")
  if not fh then return nil, err end
  local data = fh:read("*a")
  fh:close()
  return data
end

local function write_all(path, data)
  local fh, err = io.open(path, "wb")
  if not fh then return nil, err end
  -- Capture BOTH return values: write surfaces immediate errors, close surfaces
  -- deferred/buffered-write errors (e.g. ENOSPC on flush) — a copy that ignored
  -- these would report success on a truncated write (CR-03).
  local wok, werr = fh:write(data)
  local cok, cerr = fh:close()
  if not wok then return nil, werr end
  if not cok then return nil, cerr end
  return true
end

-- file_exists(path) -> boolean. The TOCTOU re-check seam (T-05-05): run() asks
-- this again at write time so a recipe that appeared between the listing and the
-- write is still never overwritten.
local function file_exists(path)
  local fh = io.open(path, "rb")
  if fh then fh:close(); return true end
  return false
end

-- list_toml_basenames(dir) -> { <name-without-ext>, ... }
-- The shipped `newest_backup` io.popen("ls -1") idiom, filtered to `*.toml` and
-- mapped to basenames (no extension). The dir is shquote'd (T-05-06). A missing
-- dir yields an empty list (ls errors to /dev/null), so a fresh install with no
-- scenes dir simply seeds everything.
local function list_toml_basenames(dir)
  local names = {}
  local p = io.popen("ls -1 -- " .. install_state.shquote(dir) .. " 2>/dev/null")
  if not p then return names end
  for name in p:lines() do
    local base = name:match("^(.+)%.toml$")
    if base then names[#names + 1] = base end
  end
  p:close()
  return names
end

-- ---------------------------------------------------------------------------
-- environment seams (mirror uninstall_state.default_setup_dir precedence)
-- ---------------------------------------------------------------------------

-- dest_scenes_dir() — the user's co-located scenes dir (D-04). Honors the same
-- WEZTERM_SETUP_DIR override uninstall_state.default_setup_dir uses (the
-- dogfood/test seam), then WEZTERM_CONFIG_DIR, then XDG_CONFIG_HOME/wezterm,
-- then ~/.config/wezterm — always suffixed with /scenes.
local function dest_scenes_dir()
  local setup = os.getenv("WEZTERM_SETUP_DIR")
  if setup and setup ~= "" then return setup .. "/scenes" end
  local cfg = os.getenv("WEZTERM_CONFIG_DIR")
  if cfg and cfg ~= "" then return cfg .. "/wezterm-setup/scenes" end
  local xdg = os.getenv("XDG_CONFIG_HOME")
  if xdg and xdg ~= "" then return xdg .. "/wezterm/wezterm-setup/scenes" end
  local home = os.getenv("HOME") or ""
  return home .. "/.config/wezterm/wezterm-setup/scenes"
end

-- repo_seed_dir() — the in-repo `scenes/` dir the seeds are copied FROM. Honors
-- a WEZ_SEED_SRC_DIR override (tests point it at the in-repo scenes/), else
-- resolves relative to this running script: cli/commands/seed_scenes.lua ->
-- repo root -> scenes/. Inside the luastatic bundle WEZ_SEED_SRC_DIR is the
-- supported override (the installer sets it; see setup.sh STEP 4b context).
local function repo_seed_dir()
  local override = os.getenv("WEZ_SEED_SRC_DIR")
  if override and override ~= "" then return override end
  local src = debug.getinfo(1, "S").source
  local this = src:match("^@(.*)$") or src
  local dir = this:match("^(.*)/cli/commands/[^/]+$")
  if dir then return dir .. "/scenes" end
  -- Fallback: relative to CWD (source invocation from the repo root).
  return "scenes"
end

-- ---------------------------------------------------------------------------
-- run() — wire the pure plan_seed to the real filesystem
-- ---------------------------------------------------------------------------

-- run(args) -> exit code. Lists the repo seed dir + dest dir, applies plan_seed,
-- and for each "seed" action RE-CHECKS dest absence (TOCTOU) before copying the
-- bytes; emits `seeded scene recipe: <name>` (newly written) or `kept existing
-- scene recipe: <name>` (preserved) per the EXACT UI-SPEC copy — never "skipped".
-- Never overwrites an existing dest file. Returns 0 on success, 1 on a read/write
-- failure of a seed.
function M.run(args)
  args = args or {}
  local src_dir = repo_seed_dir()
  local dst_dir = dest_scenes_dir()

  local repo_names = list_toml_basenames(src_dir)
  table.sort(repo_names) -- deterministic messaging order
  local dest_names = list_toml_basenames(dst_dir)

  if #repo_names == 0 then
    io.stderr:write("wez seed-scenes: no seed recipes found in " .. src_dir .. "\n")
    return 1
  end

  -- Ensure the destination dir exists before any copy (mkdir -p is idempotent
  -- and creates no recipe files, so it cannot clobber).
  os.execute("mkdir -p " .. install_state.shquote(dst_dir))

  local plan = M.plan_seed(repo_names, dest_names)
  for _, entry in ipairs(plan) do
    local name = entry.name
    local dst_path = dst_dir .. "/" .. name .. ".toml"
    if entry.action == "keep" then
      io.write("kept existing scene recipe: " .. name .. "\n")
    else
      -- TOCTOU re-check: never overwrite a file that exists at write time, even
      -- if the listing said it was absent (T-05-05). Demote to "keep" messaging.
      if file_exists(dst_path) then
        io.write("kept existing scene recipe: " .. name .. "\n")
      else
        local data, rerr = read_all(src_dir .. "/" .. name .. ".toml")
        if not data then
          io.stderr:write("wez seed-scenes: cannot read seed " .. name
            .. ": " .. tostring(rerr) .. "\n")
          return 1
        end
        local ok, werr = write_all(dst_path, data)
        if not ok then
          io.stderr:write("wez seed-scenes: cannot write " .. name
            .. ": " .. tostring(werr) .. "\n")
          return 1
        end
        io.write("seeded scene recipe: " .. name .. "\n")
      end
    end
  end
  return 0
end

return M
