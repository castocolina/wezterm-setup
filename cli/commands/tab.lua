-- cli/commands/tab.lua
--
-- The `wez tab` command module: tab-level accent color (and, in Plan 03-03,
-- title). Writes the proven "<color>:<title>" prefix to the tab's stored title
-- via `wezterm cli set-tab-title`; the Phase 3 formatter (format-tab-title.lua)
-- renders the accent + label from that stored string.
--
-- Pure helpers (validate_color / parse_stored / merge_title) take no dependency
-- on `wezterm` and perform no I/O, so they are unit-testable under plain lua5.4.
-- All subprocess calls are confined to the read/write sinks (D-05 seam).

local M = {}

-- Shared icon-name title resolver (D-03), consumed by both pane and tab.
local title = require("cli.lib.title")

-- The curated palette (D-01). pane.lua holds the canonical list; this is the
-- CLI-side validate set, intentionally duplicated like the config formatter's own
-- color_profiles copy — the two runtimes bundle separately.
M.COLOR_NAMES = { "red", "orange", "yellow", "green", "teal", "cyan", "blue", "navy", "purple", "pink" }

local NAME_SET = {}
for _, n in ipairs(M.COLOR_NAMES) do NAME_SET[n] = true end

--- Strip the alpha component from a 4- or 8-digit hex; 3/6-digit pass through.
function M.strip_alpha(hex)
  local digits = hex:match("^#(%x+)$")
  if not digits then return hex end
  if #digits == 8 then return "#" .. digits:sub(1, 6) end
  if #digits == 4 then return "#" .. digits:sub(1, 3) end
  return hex
end

--- Pure normalization (no membership validation): lowercase; "reset" passes
-- through; hex-shaped input has its alpha stripped; named input is lowercased.
function M.normalize_color(input)
  local low = tostring(input):lower()
  if low == "reset" then return "reset" end
  if low:match("^#%x+$") then
    return M.strip_alpha(low)
  end
  return low
end

local function unknown_color_error(original)
  return string.format(
    'unknown color "%s" — expected one of: %s, a hex value (#rgb / #rrggbb), or "reset"',
    tostring(original), table.concat(M.COLOR_NAMES, ", ")
  )
end

--- Validate-before-emit gate (D-06). Returns (true, normalized) or (false, error_string).
-- Accepts the 10 curated names (case-insensitive), a hex value (#rgb / #rrggbb,
-- alpha stripped), and the literal "reset". No opacity/OSC concerns here.
function M.validate_color(input)
  local norm = M.normalize_color(input)
  if norm == "reset" then
    return true, "reset"
  end
  if norm:sub(1, 1) == "#" then
    if norm:match("^#%x%x%x$") or norm:match("^#%x%x%x%x%x%x$") then
      return true, norm
    end
    return false, unknown_color_error(input)
  end
  if NAME_SET[norm] then
    return true, norm
  end
  return false, unknown_color_error(input)
end

--- Parse a stored tab title "<color>:<title>" into (color, title). Split on the
-- FIRST ":" (locked encoding, tab-title-format.md); empty sides -> nil; a no-colon
-- NON-EMPTY token is the color with no title (bare-token-is-a-color rule).
-- INVARIANT: this logic MUST stay in lockstep with the config-layer parser
-- `M.parse_tab_title` in config/wezterm-setup/format-tab-title.lua (separate Lua
-- bundle, same encoding) — change both together.
function M.parse_stored(s)
  if not s or s == "" then
    return nil, nil
  end
  local pos = s:find(":", 1, true)
  if not pos then
    return s, nil
  end
  local color = s:sub(1, pos - 1)
  local title = s:sub(pos + 1)
  if color == "" then color = nil end
  if title == "" then title = nil end
  return color, title
end

--- Read-modify-write builder. opts carries cur_color/cur_title plus exactly one
-- of set_color/set_title; the unset side is preserved. set_color="" means "clear
-- the color" (reset). The colon is ALWAYS present (D-02): result is
-- "<color>:<title>" with either side "" when nil.
function M.merge_title(opts)
  -- Note: locals are named *_part (not `title`) to avoid shadowing the
  -- module-level `local title = require("cli.lib.title")`.
  local color_part = opts.set_color ~= nil and opts.set_color or opts.cur_color
  local title_part = opts.set_title ~= nil and opts.set_title or opts.cur_title
  return (color_part or "") .. ":" .. (title_part or "")
end

-- ---------------------------------------------------------------------------
-- I/O layer (D-05 seam): the ONLY functions that shell out. The pure helpers
-- above stay subprocess-free so they remain unit-testable under plain lua5.4.
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
-- failure / no active entry, degrades to { tab_id = nil, tab_title = "" } so a
-- recolor still writes "<color>:" from an empty base.
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

--- Write the merged title via `wezterm cli set-tab-title`. `tab_id` is the D-05
-- seam (a future `--tab-id` target); nil omits the flag (active tab default).
-- Returns 0 on success, non-zero on failure.
function M.write_tab_title(str, tab_id)
  local cmd = "wezterm cli set-tab-title "
    .. (tab_id and ("--tab-id " .. tostring(tab_id) .. " ") or "")
    .. shquote(str)
  local ok = os.execute(cmd)
  return (ok == true or ok == 0) and 0 or 1
end

--- Handle `wez tab color <name|hex>` / `wez tab color reset`.
-- Validate-before-emit (D-06): an invalid color bails BEFORE any read or write.
-- Otherwise read-modify-write: parse the stored title, swap only the color
-- (or clear it on reset), write the merged "<color>:<title>" back.
function M.run_color(args)
  local ok, normalized = M.validate_color(args.value)
  if not ok then
    io.stderr:write("wez tab color: " .. normalized .. "\n")
    return 2
  end

  local cur = M.read_current_tab()
  local cur_color, cur_title = M.parse_stored(cur.tab_title)

  -- "" is the merge-time reset sentinel: merge_title emits ":<title>", and the
  -- next read's parse_stored turns a leading ":" back into a nil color.
  local set_color = (normalized == "reset") and "" or normalized
  local opts = { cur_color = cur_color, cur_title = cur_title, set_color = set_color }
  -- Combined form (TAB-03): `wez tab color <name> --title "<text>"` sets both
  -- halves in ONE write. The title flows through the shared icon resolver.
  if args.title ~= nil then
    opts.set_title = title.resolve_title_str(args.title)
  end
  local merged = M.merge_title(opts)

  return M.write_tab_title(merged, nil)
end

--- Handle `wez tab title <words...>` / `wez tab title reset` (TAB-03).
-- Read-modify-write: keep the existing color, set/clear the title (D-01/D-04).
-- An empty/reset resolution clears the title -> "<color>:".
function M.run_title(args)
  local resolved = title.resolve_title(args.words)
  local cur = M.read_current_tab()
  local cur_color, cur_title = M.parse_stored(cur.tab_title)
  local merged = M.merge_title({ cur_color = cur_color, cur_title = cur_title, set_title = resolved })
  return M.write_tab_title(merged, nil)
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
