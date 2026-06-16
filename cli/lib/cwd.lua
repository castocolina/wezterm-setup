-- cli/lib/cwd.lua
--
-- The ONE pure resolver for the locked cwd grammar (D-01/D-07/D-08), shared by
-- both the `--cwd` CLI segment and the `.toml` `cwd` field (Wave 2/3 consumers).
--
-- The grammar (locked in 06.1-CONTEXT.md, NO new research): a cwd value is one of
--   literal absolute | ~-prefixed | $ENV-expanded | relative,
-- where `.` = the launch dir and `..` = dirname(launch dir). The resolved
-- absolute path is what later plans hand to `wezterm cli spawn --cwd <path>` so a
-- pane opens DIRECTLY in the target directory with NO visible `cd <path>` line
-- (D-08 clean pane).
--
-- SECURITY (RESEARCH Security Domain "cwd grammar shell evaluation", threat
-- T-06.1-03): shell command substitution ($(...) / backticks) is FORBIDDEN.
-- M.validate rejects it (validate-before-emit) and the resolver expands purely
-- in Lua — the value is NEVER handed to a shell here. An unset $ENV reference is
-- also rejected (never silently empty). Quoting the resolved STRING before
-- os.execute is the IO-shell's job (Plan 04, threat T-06.1-04).
--
-- PURE BY CONTRACT: no wezterm global, no os.getenv / os.execute, no io / no
-- filesystem access. The environment is an injected table supplied by the caller
-- (Plan 04's IO-shell passes a real env snapshot). This is what lets the full
-- suite run under plain `lua5.4`. (The acceptance grep enforces zero references
-- to those banned APIs.)

local M = {}

-- ---------------------------------------------------------------------------
-- private: dirname(path) — strip the trailing /component, mirroring doctor's
-- `match("^(.*)/[^/]+$")` style. "/home/u/proj" -> "/home/u"; a bare "/" or a
-- path with no slash collapses to "/" (the filesystem root) so ".." never
-- produces an empty string.
-- ---------------------------------------------------------------------------
local function dirname(path)
  local parent = path:match("^(.*)/[^/]+$")
  if parent == nil or parent == "" then
    return "/"
  end
  return parent
end

-- ---------------------------------------------------------------------------
-- private: does the value contain shell command substitution? `$(` or a
-- backtick. This is the security lock — such a value is rejected before emit
-- and never reaches a shell.
-- ---------------------------------------------------------------------------
local function has_command_substitution(value)
  return value:find("$(", 1, true) ~= nil or value:find("`", 1, true) ~= nil
end

-- ---------------------------------------------------------------------------
-- M.validate(value, env) -> (true, nil) | (false, errmsg).
-- Validate-before-emit: reject command substitution ($(...)/backticks) and any
-- $NAME prefix whose env[NAME] is unset. nil/empty (omitted -> launch dir) and
-- plain literal/relative/~ values validate true.
-- ---------------------------------------------------------------------------
function M.validate(value, env)
  env = env or {}
  if value == nil or value == "" then
    return true, nil -- omitted -> launch dir (D-07)
  end

  if has_command_substitution(value) then
    return false, string.format(
      "error: invalid cwd '%s' — command substitution is not allowed", value)
  end

  -- WR-02: reject the unsupported ${NAME} brace form up front. Only the bare
  -- $NAME form is expanded by resolve(); a braced reference like ${PWD}/x would
  -- otherwise slip past the unset-var check below AND fall through resolve() to
  -- the relative-path branch, producing a literal "launch/${PWD}/x" directory.
  -- Failing here makes the unsupported form visible instead of a broken path.
  if value:match("^%${") then
    return false, string.format(
      "error: invalid cwd '%s' — use $NAME (not ${NAME}); the brace form is not expanded", value)
  end

  -- A leading $NAME (not $(...), already rejected above) must be a set env var.
  local name = value:match("^%$([%w_]+)")
  if name then
    if env[name] == nil then
      return false, string.format(
        "error: invalid cwd '%s' — environment variable $%s is not set", value, name)
    end
  end

  -- A leading "~" expands to HOME; reject up front when HOME is unset so
  -- resolve() never concatenates a nil (validate-before-emit, mirrors $ENV).
  if value:sub(1, 1) == "~" and env.HOME == nil then
    return false, string.format(
      "error: invalid cwd '%s' — environment variable $HOME is not set", value)
  end

  return true, nil
end

-- ---------------------------------------------------------------------------
-- M.resolve(value, launch_dir, env) -> absolute path string.
-- Expands the locked grammar purely:
--   nil/""   -> launch_dir              (D-07 omitted -> launch dir)
--   "."      -> launch_dir              (. = launch dir)
--   ".."     -> dirname(launch_dir)     (.. = dirname launch dir)
--   "~"      -> env.HOME (+ remainder)
--   "$NAME…" -> env[NAME] (+ remainder)
--   "/…"     -> as-is                   (literal absolute)
--   else     -> launch_dir .. "/" .. value  (relative joined to launch dir)
-- Callers validate first (M.validate); resolve assumes a validated value.
-- ---------------------------------------------------------------------------
function M.resolve(value, launch_dir, env)
  env = env or {}

  if value == nil or value == "" or value == "." then
    return launch_dir
  end

  if value == ".." then
    return dirname(launch_dir)
  end

  -- Leading "~": HOME + remainder ("~" -> HOME, "~/x" -> HOME .. "/x").
  if value == "~" then
    return env.HOME
  end
  local home_rest = value:match("^~(/.*)$")
  if home_rest then
    return env.HOME .. home_rest
  end

  -- Leading "$NAME": env[NAME] + remainder.
  local name, rest = value:match("^%$([%w_]+)(.*)$")
  if name then
    return env[name] .. rest
  end

  -- Literal absolute path passes through unchanged.
  if value:sub(1, 1) == "/" then
    return value
  end

  -- Relative path joined to the launch dir.
  return launch_dir .. "/" .. value
end

return M
