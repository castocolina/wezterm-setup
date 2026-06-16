-- cli/commands/tab.lua
--
-- The `wez tab` command module: tab-level accent color + title.
--
-- 06.1-03 decouple (D-02/D-03/D-04): COLOR and TITLE are now two independent
-- channels — the legacy "<color>:<title>" set-tab-title encoding is GONE from the
-- steady state.
--   wez tab color <name|hex>   -> emit WEZTERM_TAB_COLOR via OSC 1337 SetUserVar to
--                                 the active pane's TTY (io.write, the SAME channel
--                                 `wez pane color` uses). Read by the config-layer
--                                 format-tab-title handler. NO title is touched.
--   wez tab title <text>       -> write PURE title text via `wezterm cli set-tab-title`
--                                 (no color prefix).
--   wez tab color <c> --title  -> two distinct writes: OSC color + pure-text title.
--
-- D-01 / `/reducing-entropy`: the palette + normalize/validate + base64 + OSC builders
-- are NOT defined here — they live ONCE in cli/lib/color.lua and are re-exported.
--
-- D-04 migration: parse_stored / merge_title survive ONLY as a one-time parse-and-warn
-- migration helper (and scene.lua still calls them until Plan 04 rewires it). They are
-- removed from this module's OWN steady-state write path — run_color/run_title never
-- emit the "<color>:<title>" prefix.
--
-- All subprocess calls are confined to the read/write sinks (D-05 seam).

local M = {}

-- The single shared color module (D-01): palette, validate (alpha-preserving, D-09),
-- and the OSC 1337 builder used for the WEZTERM_TAB_COLOR accent emit.
local color = require("cli.lib.color")

-- Shared icon-name title resolver (D-03), consumed by both pane and tab.
local title = require("cli.lib.title")

-- Public surface re-exported from the shared module (no local re-definition, D-01).
M.COLOR_NAMES = color.COLOR_NAMES
M.validate_color = color.validate_color
M.build_osc1337 = color.build_osc1337

--- Parse a stored tab title "<color>:<title>" into (color, title). MIGRATION-ONLY
-- (D-04): split on the FIRST ":"; empty sides -> nil; a no-colon NON-EMPTY token is
-- the color with no title. Retained because (a) `run_color` uses it to detect a
-- legacy-prefixed live tab and warn once, and (b) scene.lua still calls it until
-- Plan 04 rewires scene styling onto the OSC user-var path. NOT used by the
-- steady-state write path of this module.
-- INVARIANT: stays in lockstep with the config-layer parser `M.parse_tab_title` in
-- config/wezterm-setup/format-tab-title.lua (separate Lua bundle, same encoding).
function M.parse_stored(s)
  if not s or s == "" then
    return nil, nil
  end
  local pos = s:find(":", 1, true)
  if not pos then
    return s, nil
  end
  local color_part = s:sub(1, pos - 1)
  local title_part = s:sub(pos + 1)
  if color_part == "" then color_part = nil end
  if title_part == "" then title_part = nil end
  return color_part, title_part
end

--- MIGRATION-ONLY (D-04) read-modify-write builder for the legacy "<color>:<title>"
-- encoding. KEPT callable because scene.lua still depends on it until Plan 04; this
-- module no longer calls it from run_color/run_title (the encoding is dropped from
-- the steady state). opts carries cur_color/cur_title plus exactly one of
-- set_color/set_title; the unset side is preserved.
function M.merge_title(opts)
  local color_part = opts.set_color ~= nil and opts.set_color or opts.cur_color
  local title_part = opts.set_title ~= nil and opts.set_title or opts.cur_title
  return (color_part or "") .. ":" .. (title_part or "")
end

-- ---------------------------------------------------------------------------
-- I/O layer (D-05 seam): the ONLY functions that shell out / write escapes. The
-- pure helpers above stay subprocess-free so they remain unit-testable.
-- ---------------------------------------------------------------------------

-- Single-quote shell escaper (same proven helper as install_state.M.shquote,
-- CR-02): a single quote is rewritten as '\'' so a value containing a quote or
-- any shell metacharacter cannot break out of the quoting and inject a command.
local function shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Decode JSON with the vendored dkjson, resolving both from source (CWD on
-- package.path) and inside the luastatic bundle (module baked as cli.vendor.dkjson).
local function decode_json(text)
  local ok, dkjson = pcall(require, "cli.vendor.dkjson")
  if not ok then ok, dkjson = pcall(require, "dkjson") end
  if not ok or type(dkjson) ~= "table" then return nil end
  local data = dkjson.decode(text)
  return data
end

--- Read the active tab's id + stored title from `wezterm cli list --format json`.
-- Returns { tab_id = <id|nil>, tab_title = <string> }. On no session / decode
-- failure / no active entry, degrades to { tab_id = nil, tab_title = "" }.
function M.read_current_tab()
  local fh = io.popen("wezterm cli list --format json 2>/dev/null")
  if not fh then return { tab_id = nil, tab_title = "" } end
  local out = fh:read("*a")
  fh:close()
  if not out or out == "" then return { tab_id = nil, tab_title = "" } end
  local data = decode_json(out)
  if type(data) ~= "table" then return { tab_id = nil, tab_title = "" } end
  for _, entry in ipairs(data) do
    if type(entry) == "table" and entry.is_active == true then
      return { tab_id = entry.tab_id, tab_title = entry.tab_title or "" }
    end
  end
  return { tab_id = nil, tab_title = "" }
end

--- Write a PURE title string via `wezterm cli set-tab-title`. `tab_id` is the D-05
-- seam (a future `--tab-id` target); nil omits the flag (active tab default).
-- The value is shquote'd before os.execute (T-06.1-06). Returns 0 on success.
function M.write_tab_title(str, tab_id)
  local cmd = "wezterm cli set-tab-title "
    .. (tab_id and ("--tab-id " .. tostring(tab_id) .. " ") or "")
    .. shquote(str)
  local ok = os.execute(cmd)
  return (ok == true or ok == 0) and 0 or 1
end

-- The OSC write sink (D-05): the WEZTERM_TAB_COLOR accent is emitted to the active
-- pane's TTY via io.write, the SAME path `wez pane color` uses (the CLI runs inside
-- the target pane). A future pane-TARGETED write would use the printf-octal
-- send-text path (color.build_user_var_octal) instead.
local function emit(str)
  io.write(str)
end

-- One-time migration warn (D-04 / Open Q3): if the active tab still carries a legacy
-- "<color>:<title>" prefix, warn ONCE on the CLI side that the old encoding is being
-- migrated. The clean write path below never re-emits the prefix.
local function warn_legacy_prefix_once(stored)
  local cur_color, cur_title = M.parse_stored(stored)
  -- A legacy prefix is present when the stored title actually contained a colon
  -- (so both halves are meaningful, or one half plus a colon separator).
  if stored and stored ~= "" and stored:find(":", 1, true)
    and (cur_color ~= nil or cur_title ~= nil) then
    io.stderr:write(
      "wez tab color: migrating a legacy \"<color>:<title>\" tab title — "
      .. "the color now lives in WEZTERM_TAB_COLOR; the title is left as plain text\n")
  end
end

--- Handle `wez tab color <name|hex> [--title <text>]` / `wez tab color reset`.
-- Validate-before-emit (D-06/T-06.1-07): an invalid color bails BEFORE any write.
-- Decoupled (D-02/D-03/D-04): emits WEZTERM_TAB_COLOR via OSC (NO title prefix); a
-- `--title` flag additionally writes PURE title text via set-tab-title.
function M.run_color(args)
  local ok, normalized = M.validate_color(args.value)
  if not ok then
    io.stderr:write("wez tab color: " .. normalized .. "\n")
    return 2
  end

  -- Migration parse-and-warn (D-04): detect a legacy-prefixed live tab and warn once.
  local cur = M.read_current_tab()
  warn_legacy_prefix_once(cur.tab_title)

  -- The accent value is the name (or hex); "reset" clears it with an empty payload.
  local accent = (normalized == "reset") and "" or normalized
  emit(color.build_osc1337("WEZTERM_TAB_COLOR", accent))

  -- Combined form (TAB-03): `wez tab color <c> --title "<text>"` ALSO sets the title
  -- as PURE text in a second, independent write — no encoding.
  if args.title ~= nil then
    return M.write_tab_title(title.resolve_title_str(args.title), nil)
  end
  return 0
end

--- Handle `wez tab title <words...>` / `wez tab title reset` (TAB-03).
-- Writes PURE resolved title text via set-tab-title (D-01/D-04) — NO color prefix,
-- NO read-modify-write. An empty/reset resolution clears the title ("").
function M.run_title(args)
  local resolved = title.resolve_title(args.words)
  return M.write_tab_title(resolved, nil)
end

--- Command entry. Branches on the selected `tab` subcommand.
function M.run(args)
  local sub = args and args.tab_cmd
  if sub == "color" then
    return M.run_color(args)
  elseif sub == "title" then
    return M.run_title(args)
  end
  io.stderr:write("wez tab: expected a subcommand (color | title)\n")
  return 2
end

return M
