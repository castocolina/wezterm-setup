-- cli/commands/install_state.lua
--
-- The `wez install-state` subcommand (INST-01/02/03). The subcommand and its
-- flags (`--force`, `--restore`, `--skip`) are ALREADY registered in
-- cli/spec.lua by Plan 01 — this module ONLY implements the behavior; it does
-- NOT edit the spec (D-16).
--
-- Per D-01 ALL of the install-state decision logic lives here in Lua; the bash
-- installer (tools/setup.sh) is decision-free glue that just shells out to this
-- command and surfaces its exit code.
--
-- What it owns:
--   PARSE   — detect whether the user's wezterm.lua already carries our managed
--             block (state "absent"/"present") and extract a present block, using
--             the LOCKED sentinel markers below.
--   BACKUP  — copy wezterm.lua to wezterm.lua.bak.<UTC-timestamp> BEFORE any write
--             (INST-02).
--   INJECT  — insert EXACTLY ONE sentinel-bounded managed block that calls
--             `require('wezterm-setup').apply(config)` positioned so it runs
--             before the user's `return` (INST-01 / D-17). The write is done to a
--             TEMP file then atomically renamed over the target so an interrupted
--             write never corrupts the user's config (T-04-01).
--   DECIDE  — re-install dispatcher: a present block with an interactive TTY
--             prompts override/restore/skip; a present block with NO TTY returns
--             non-zero and instructs the user to re-run with an explicit flag
--             (D-03 / T-04-02 — never silently overwrite).
--
-- The PARSE / DECIDE / inject string-building helpers are PURE and fixture
-- testable with no filesystem (the autonomous gate, tests/cli/install_state_test
-- .lua). run() wires them to the real filesystem + TTY.
--
-- The CANONICAL sentinel markers (locked output of R6 probe
-- .tmp/probes/phase-1/04-sentinel-injection.md). Downstream plans (e.g. Plan 06
-- doctor / uninstall-state) reuse these EXACT strings — no variants.

local M = {}

M.OPEN_MARKER = "-- >>> wezterm-setup managed block >>>"
M.CLOSE_MARKER = "-- <<< wezterm-setup managed block <<<"

-- ---------------------------------------------------------------------------
-- PARSE
-- ---------------------------------------------------------------------------

-- parse(text) -> { state = "absent"|"present", block = <string|nil> }
-- "present" iff both markers appear in order. The extracted block is the lines
-- from the open marker through the close marker, inclusive.
function M.parse(text)
  text = tostring(text or "")
  local open_at = text:find(M.OPEN_MARKER, 1, true)
  local close_at = text:find(M.CLOSE_MARKER, 1, true)
  if not (open_at and close_at) or close_at < open_at then
    return { state = "absent" }
  end
  -- Extend to the end of the close-marker line so the block is whole.
  local line_end = text:find("\n", close_at, true)
  local block_end = line_end and (line_end - 1) or #text
  local block = text:sub(open_at, block_end)
  return { state = "present", block = block }
end

-- ---------------------------------------------------------------------------
-- timestamp / backup
-- ---------------------------------------------------------------------------

-- A filesystem-safe UTC timestamp: 2026-06-09T18-15-44Z (colons -> dashes so the
-- name is portable across filesystems).
local function utc_timestamp()
  return os.date("!%Y-%m-%dT%H-%M-%SZ")
end
M.utc_timestamp = utc_timestamp

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
  -- Capture BOTH return values: fh:write surfaces immediate write errors, and
  -- fh:close surfaces deferred/buffered-write errors (e.g. ENOSPC on flush). A
  -- backup/atomic_write that ignored these would report success on a truncated
  -- or empty write, defeating the backup-before-write safety property (CR-03).
  local wok, werr = fh:write(data)
  local cok, cerr = fh:close()
  if not wok then return nil, werr end
  if not cok then return nil, cerr end
  return true
end

-- backup(target) -> backup_path | nil, err
-- Copy `target` to `target..".bak."..<timestamp>` (INST-02). Taken BEFORE any
-- modification so the original is always recoverable.
function M.backup(target)
  local data, err = read_all(target)
  if not data then return nil, err end
  local bak = target .. ".bak." .. utc_timestamp()
  local ok, werr = write_all(bak, data)
  if not ok then return nil, werr end
  return bak
end

-- Single-quote a string for safe use as ONE /bin/sh argument. Every embedded
-- single quote is rewritten as '\'' so an attacker-influenced path containing a
-- quote (or any shell metacharacter) cannot break out of the quoting and inject
-- a command (CR-02). Exposed on M so sibling modules reuse the same quoter.
function M.shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- newest_backup(target) -> path | nil
-- Select the lexicographically-latest wezterm.lua.bak.<timestamp> beside target
-- (T-04-05: the ISO-ish timestamp makes lexicographic == chronological, so this
-- is the NEWEST backup, deterministically).
function M.newest_backup(target)
  local dir, base = target:match("^(.*)/([^/]+)$")
  if not dir then
    dir, base = ".", target
  end
  local prefix = base .. ".bak."
  local newest
  local p = io.popen("ls -1 -- " .. M.shquote(dir) .. " 2>/dev/null")
  if not p then return nil end
  for name in p:lines() do
    if name:sub(1, #prefix) == prefix then
      local full = dir .. "/" .. name
      if not newest or full > newest then
        newest = full
      end
    end
  end
  p:close()
  return newest
end

-- ---------------------------------------------------------------------------
-- atomic write (write-temp-then-rename)
-- ---------------------------------------------------------------------------

-- atomic_write(target, data) -> true | nil, err
-- Stage `data` to a sibling temp file, then os.rename it over `target`. rename(2)
-- is atomic within a filesystem, so a crash mid-write leaves `target` at its
-- previous content (the backup covers the prior step). Never a direct overwrite
-- of the live file (T-04-01).
function M.atomic_write(target, data)
  local tmp = target .. ".tmp." .. utc_timestamp() .. "." .. tostring(math.random(1, 1e6))
  local ok, err = write_all(tmp, data)
  if not ok then return nil, err end
  local rok, rerr = os.rename(tmp, target)
  if not rok then
    os.remove(tmp)
    return nil, rerr
  end
  return true
end

-- ---------------------------------------------------------------------------
-- managed-block construction + INJECT
-- ---------------------------------------------------------------------------

-- Build the managed block text. `var` is the name the user's config variable
-- carries on the final `return <var>` (default "config"). The block reuses that
-- identifier so apply() mutates the SAME table the chunk returns (probe 04).
function M.managed_block(var)
  var = var or "config"
  return table.concat({
    M.OPEN_MARKER,
    "require('wezterm-setup').apply(" .. var .. ")",
    M.CLOSE_MARKER,
  }, "\n")
end

-- Locate the final top-level `return <expr>` and return start/stop byte offsets
-- plus the returned expression. Scans from the end for the last line whose first
-- non-blank token is `return`.
local function find_final_return(text)
  local pos = #text
  while pos > 0 do
    -- Find the start of the line containing `pos`.
    local nl = text:sub(1, pos):find("\n[^\n]*$")
    local line_start = nl and (nl + 1) or 1
    local line = text:sub(line_start, pos)
    local expr = line:match("^%s*return%s+(.-)%s*$")
    if expr and expr ~= "" then
      return line_start, pos, expr
    end
    if line:match("%S") and not line:match("^%s*return%s*$") then
      -- A non-blank, non-return line below the return would mean the return is
      -- not the last statement; keep scanning upward regardless (we want the
      -- LAST return).
    end
    pos = line_start - 2 -- step above this line (skip the preceding "\n")
    if pos < 0 then break end
  end
  return nil
end

-- restore_original_text(text) -> original_text | nil, err
-- PURE inverse of inject_into_text: recover the user's PRE-injection config from
-- a file that already carries a managed block, so an override can re-inject from
-- the true original instead of a blindly-stripped fragment. Two shapes:
--   Shape A — the block sits before a `return <ident>`; removing the block
--             (markers inclusive, with its trailing newline) restores the original.
--   Shape B — the block CONTAINS the only top-level return; it is rebuilt back
--             into `return (<expr>)` by reading the captured expression from the
--             `local __wezterm_setup_config = (<expr>)` line, so the original
--             top-level return is recovered (never lost — the root cause of CR-01).
-- Returns nil+err when no well-formed managed block is present.
function M.restore_original_text(text)
  text = tostring(text or "")
  local open_at = text:find(M.OPEN_MARKER, 1, true)
  local close_at = text:find(M.CLOSE_MARKER, 1, true)
  if not (open_at and close_at) or close_at < open_at then
    return nil, "no managed block found"
  end
  -- `marker_stop` is the inclusive index of the last NON-newline byte of the
  -- close-marker line (the close marker itself). `line_nl` is the trailing
  -- newline after it, if any. Shape B replaced a `return <expr>` line, so its
  -- recovery must KEEP that trailing newline (it belongs to the user's line);
  -- Shape A's block was inserted WITH its own trailing newline, so excision
  -- drops it. Distinguishing the two keeps both round-trips byte-exact.
  local line_nl = text:find("\n", close_at, true)
  local marker_stop = line_nl and (line_nl - 1) or #text
  local block = text:sub(open_at, marker_stop)

  -- Shape B carries the wrapped expression on its `local <var> = (<expr>)` line,
  -- which inject_into_text wrote in a FIXED format: the known prefix
  -- "local <var> = (" then EXPR then a trailing ")" closing the whole line. We
  -- recover EXPR by stripping that exact known prefix and the single trailing
  -- ")" — NOT by `%b()` paren-balancing. `%b()` is byte-level and string/comment
  -- unaware, so an EXPR containing an unbalanced paren inside a Lua string or
  -- comment (e.g. `load_cfg("a)b")`, `require("x")() -- legacy (fallback)`) would
  -- mis-match, return nil, and silently fall through to the Shape-A branch —
  -- yielding a wrong-but-non-nil "" excision (the bug). Anchoring to the fixed
  -- wrapper structure recovers EXPR byte-exact regardless of paren content.
  local var = "__wezterm_setup_config"
  local prefix = "local " .. var .. " = ("
  -- Find the wrapper line within the block, bounded by its own newlines. The
  -- captured chunk is everything between the prefix's "(" and the line's final
  -- byte; the line always ends in the matching ")" inject_into_text appended.
  local wrap_body = block:match("\n" .. prefix:gsub("%W", "%%%1") .. "(.-)\n")
  local expr = wrap_body and wrap_body:match("^(.*)%)$")
  if expr then
    -- Replace the block (markers inclusive) with the recovered top-level return,
    -- KEEPING the trailing newline that belonged to the user's original return
    -- line, so the restored text is a byte-exact Shape-B config again.
    local head = text:sub(1, open_at - 1)
    local tail = text:sub(marker_stop + 1) -- starts at the trailing "\n" (if any)
    return head .. "return " .. expr .. tail
  end

  -- Shape A: the block is a pure insertion before a `return <ident>`; excising
  -- it (markers inclusive AND its trailing newline) yields the original.
  local strip_stop = line_nl or #text
  return text:sub(1, open_at - 1) .. text:sub(strip_stop + 1)
end

-- inject_into_text(text) -> new_text | nil, err
-- PURE: build the post-injection content from `text` in memory, with NO
-- filesystem effects. Locates the final top-level `return`, then either inserts
-- the managed block before a `return <ident>` (Shape A) or wraps a non-identifier
-- `return <expr>` (Shape B). Returns the rebuilt text or nil+err when there is no
-- top-level return to anchor against. Keeping this pure lets the override path
-- validate that re-injection SUCCEEDS before any byte is persisted (CR-01).
function M.inject_into_text(text)
  text = tostring(text or "")
  local line_start, line_stop, expr = find_final_return(text)
  if not line_start then
    return nil, "no top-level `return` found"
  end

  if expr:match("^[%a_][%w_]*$") then
    -- Shape A: `return <ident>` — insert the block before the return, reusing
    -- the identifier so apply() mutates the same returned table.
    local block = M.managed_block(expr)
    return text:sub(1, line_start - 1) .. block .. "\n" .. text:sub(line_start)
  end

  -- Shape B: `return <expr>` — wrap the expression in a local, augment it, and
  -- return the local. The managed block CONTAINS the only top-level return, so
  -- it must be built atomically with the strip (never persist a stripped file).
  local var = "__wezterm_setup_config"
  local wrap = table.concat({
    M.OPEN_MARKER,
    "local " .. var .. " = (" .. expr .. ")",
    "require('wezterm-setup').apply(" .. var .. ")",
    "return " .. var,
    M.CLOSE_MARKER,
  }, "\n")
  return text:sub(1, line_start - 1) .. wrap .. text:sub(line_stop + 1)
end

-- inject(target [, opts]) -> { ok = true } | { ok = false, err = ... }
-- Writes a timestamped backup, builds ONE managed block referencing the config
-- identifier from the user's final `return`, places it before that return
-- (Shape A) or wraps the returned expression (Shape B), and atomically writes
-- the result. opts.skip_backup is for callers that already backed up.
function M.inject(target, opts)
  opts = opts or {}
  local text, err = read_all(target)
  if not text then return { ok = false, err = err } end

  -- Build the final content FIRST so a failed inject never triggers a backup or
  -- a write of a half-applied file.
  local new_text, ierr = M.inject_into_text(text)
  if not new_text then
    return { ok = false, err = ierr .. " in " .. tostring(target) }
  end

  if not opts.skip_backup then
    local bak, berr = M.backup(target)
    if not bak then return { ok = false, err = berr } end
  end

  local ok, werr = M.atomic_write(target, new_text)
  if not ok then return { ok = false, err = werr } end
  return { ok = true }
end

-- ---------------------------------------------------------------------------
-- DECISION dispatcher (pure)
-- ---------------------------------------------------------------------------

-- decide(state, has_tty, flags) -> action, exit_code, message
--   state  : "absent" | "present"
--   has_tty: boolean (an interactive TTY is available for prompting)
--   flags  : { force=?, restore=?, skip=? }
--
-- Contract (D-03 / T-04-02):
--   absent                        -> "install", 0
--   present + --skip              -> "skip", 0       (no-op)
--   present + --force             -> "override", 0
--   present + --restore           -> "restore", 0
--   present + TTY (no flag)       -> "prompt", 0     (run() prompts interactively)
--   present + NO TTY (no flag)    -> "abort", non-zero, names the explicit flags
function M.decide(state, has_tty, flags)
  flags = flags or {}
  if state ~= "present" then
    return "install", 0
  end
  if flags.skip then
    return "skip", 0
  end
  if flags.force then
    return "override", 0
  end
  if flags.restore then
    return "restore", 0
  end
  if has_tty then
    return "prompt", 0
  end
  local msg = "wez install-state: a wezterm-setup managed block already exists and "
    .. "no interactive terminal is available. Re-run with one of:\n"
    .. "  --force    overwrite the existing managed block\n"
    .. "  --restore  reinstate the most recent timestamped backup\n"
    .. "  --skip     leave the existing block untouched"
  return "abort", 3, msg
end

-- ---------------------------------------------------------------------------
-- run() — wire the pure logic to the real filesystem + TTY
-- ---------------------------------------------------------------------------

-- Resolve the user's wezterm.lua. Honor WEZTERM_CONFIG_FILE for testing /
-- non-default layouts, else ~/.config/wezterm/wezterm.lua.
local function config_path()
  local explicit = os.getenv("WEZTERM_CONFIG_FILE")
  if explicit and explicit ~= "" then return explicit end
  local home = os.getenv("HOME") or ""
  return home .. "/.config/wezterm/wezterm.lua"
end

-- Detect an interactive TTY without assuming /proc (D-18). `test -t 0` over a
-- subshell is portable across Linux + macOS.
local function stdin_is_tty()
  local ok = os.execute("test -t 0")
  -- os.execute returns true/exit-0 on a TTY.
  return ok == true or ok == 0
end

-- Interactive prompt: override / restore / skip. Returns the chosen action.
local function prompt_choice()
  io.write("A wezterm-setup managed block already exists.\n")
  io.write("  [o] override   [r] restore backup   [s] skip\n")
  io.write("Choice [o/r/s]: ")
  io.flush()
  local line = io.read("*l") or ""
  local c = line:lower():sub(1, 1)
  if c == "o" then return "override"
  elseif c == "r" then return "restore"
  else return "skip" end
end

function M.run(args)
  args = args or {}
  local target = config_path()

  local text, rerr = read_all(target)
  if not text then
    io.stderr:write("wez install-state: cannot read " .. target .. ": " .. tostring(rerr) .. "\n")
    return 1
  end

  local parsed = M.parse(text)
  local flags = { force = args.force, restore = args.restore, skip = args.skip }
  local action, code, msg = M.decide(parsed.state, stdin_is_tty(), flags)

  if action == "prompt" then
    action = prompt_choice()
  end

  if action == "abort" then
    io.stderr:write((msg or "wez install-state: aborting") .. "\n")
    return code
  elseif action == "skip" then
    io.write("wez install-state: existing managed block left untouched (--skip)\n")
    return 0
  elseif action == "restore" then
    local bak = M.newest_backup(target)
    if not bak then
      io.stderr:write("wez install-state: no timestamped backup found to restore\n")
      return 1
    end
    local data = read_all(bak)
    if not data then
      io.stderr:write("wez install-state: could not read backup " .. bak .. "\n")
      return 1
    end
    local ok, werr = M.atomic_write(target, data)
    if not ok then
      io.stderr:write("wez install-state: restore failed: " .. tostring(werr) .. "\n")
      return 1
    end
    io.write("wez install-state: restored " .. bak .. "\n")
    return 0
  end

  -- action == "install" (absent) or "override" (present + --force/TTY override):
  -- both back up and inject a single block. For override we first strip the
  -- existing block so injection yields exactly ONE.
  if action == "override" then
    -- Recover the user's ORIGINAL pre-injection config, re-inject into it, and
    -- write EXACTLY ONCE — and only after the re-inject is known to succeed. The
    -- whole strip+reinject happens in memory, so the intermediate stripped state
    -- is never persisted. For a Shape-B config (whose managed block CONTAINS the
    -- only top-level `return`) we reconstruct `return <expr>` from the block, so
    -- the override never leaves the file return-less / broken on disk (CR-01).
    -- On ANY failure the original managed file is left byte-identical to before.
    local original, rerr = M.restore_original_text(text)
    if not original then
      -- No well-formed managed block (caller dispatched override defensively):
      -- treat the current text as the original and inject fresh.
      original = text
    end
    local final_text, ierr = M.inject_into_text(original)
    if not final_text then
      io.stderr:write(
        "wez install-state: override aborted; config left unchanged ("
        .. tostring(ierr or rerr) .. ")\n")
      return 1
    end

    -- Back up the CURRENT (managed) file, then write the final good content once.
    local bak, berr = M.backup(target)
    if not bak then
      io.stderr:write("wez install-state: backup failed: " .. tostring(berr) .. "\n")
      return 1
    end
    local ok, werr = M.atomic_write(target, final_text)
    if not ok then
      io.stderr:write("wez install-state: override write failed: " .. tostring(werr) .. "\n")
      return 1
    end
    io.write("wez install-state: managed block overridden\n")
    return 0
  end

  local res = M.inject(target)
  if not res.ok then
    io.stderr:write("wez install-state: inject failed: " .. tostring(res.err) .. "\n")
    return 1
  end
  io.write("wez install-state: managed block installed (timestamped backup written)\n")
  return 0
end

return M
