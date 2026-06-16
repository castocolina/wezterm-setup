-- cli/lib/scene.lua
--
-- Pure scene-building helpers for `wez scene new` (SCEN-02). This module is the
-- algorithmic core: layout split-sequencing, --pane spec parsing, layout/color
-- validation, materialization decision, and pane/tab-id validation.
--
-- PURE BY CONTRACT: no terminal multiplexer global, no process-spawning or
-- shell-out primitives, no filesystem/network access. Every input is a Lua value
-- supplied by the caller (04-02's live orchestrator owns the I/O trust boundary).
-- This is what lets the full suite run under plain `lua5.4` with no live session.
-- (The acceptance grep enforces zero literal references to those banned APIs.)
--
-- NOTE (D-07): auto pane-title resolution from a command is a LIVE-WRAPPER concern
-- (the title is SET via `wez pane title` after spawn — 04-02's job), so this module
-- deliberately does NOT require("cli.lib.title"). parse_pane_spec only carries the
-- raw title= value through; title resolution happens at spawn time downstream.

local M = {}

-- ---------------------------------------------------------------------------
-- private: round-half-up percent for an equal-share split.
-- `remaining` = panes still to be carved from the current target (incl. this one).
-- e.g. 100/4=25, 100/3=33.33->33, 100/2=50 (matches horizontal N=4 [25,33,50]).
-- (Extracted as the sole rounding site in the REFACTOR pass.)
-- ---------------------------------------------------------------------------
local function round_pct(remaining)
  return math.floor(100 / remaining + 0.5)
end

-- ---------------------------------------------------------------------------
-- private: split a --pane spec on top-level commas, then each segment on its
-- FIRST '=' into {key, value}. Values may contain spaces and further '='; only
-- the first '=' per segment separates key from value (so `cmd=tail -f x` keeps
-- the whole `tail -f x` as the value).
-- ---------------------------------------------------------------------------
local function split_kv_segments(spec)
  local function trim(s) return s and (s:match("^%s*(.-)%s*$")) or s end
  local segments = {}
  for segment in tostring(spec):gmatch("[^,]+") do
    -- Trim surrounding whitespace so the readable D-06 form with spaces after
    -- commas works verbatim: 'cmd=docker stats, color=teal, title=stats'.
    segment = trim(segment)
    local key, value = segment:match("^([^=]+)=(.*)$")
    if key then
      segments[#segments + 1] = { trim(key), trim(value) }
    else
      segments[#segments + 1] = { segment, nil }
    end
  end
  return segments
end

-- ---------------------------------------------------------------------------
-- M.plan_splits(layout, n) -> ordered array of split-step tables.
-- D-02 / UI-SPEC Layout Geometry Contract: each step is
--   { direction = "left"|"right"|"top"|"bottom", percent = <int>, target = <pane index> }
-- where `target` is the creation-order index of the pre-existing pane to split
-- (original pane = 0; each split creates the next index). N<=1 -> {} (no split,
-- D-10 reuse path). Equal-share invariant: percents use 100/(remaining incl. self).
-- ---------------------------------------------------------------------------
function M.plan_splits(layout, n)
  n = tonumber(n) or 0
  local steps = {}
  if n <= 1 then
    return steps
  end

  if layout == "tall" or layout == "tall:mirrored" then
    -- Step 1: main/stack boundary at a fixed 50% (NOT equal-share). UI-SPEC:
    -- `tall` keeps the MAIN pane on the LEFT, `tall:mirrored` on the RIGHT.
    -- wezterm `split-pane --<dir>` places the NEW (stack) pane on <dir>, leaving
    -- the original (main, pane 0) on the OPPOSITE side — so to keep main LEFT we
    -- send the first stack pane RIGHT, and vice versa (the directions are the
    -- inverse of the main pane's target side).
    local first_dir = (layout == "tall:mirrored") and "left" or "right"
    steps[#steps + 1] = { direction = first_dir, percent = 50, target = 0 }
    -- Stacking splits: split the MOST RECENTLY CREATED stack pane downward, each
    -- taking 100/(remaining) so all stacked panes end equal height.
    -- j-th stacking split (j=1..n-2): percent = round(100/(n-j)).
    local last = 1 -- pane created by step 1
    for j = 1, n - 2 do
      steps[#steps + 1] = { direction = "bottom", percent = round_pct(n - j), target = last }
      last = last + 1
    end
    return steps

  elseif layout == "horizontal" then
    -- N equal-width columns. Always split off the SMALLEST piece from the
    -- original un-split remainder (pane 0): percents [100/n, 100/(n-1), ..., 100/2].
    for j = 1, n - 1 do
      steps[#steps + 1] = { direction = "right", percent = round_pct(n - j + 1), target = 0 }
    end
    return steps

  elseif layout == "grid" then
    -- cols = ceil(sqrt(n)) columns, rows = ceil(n/cols) rows, row-major.
    local cols = math.ceil(math.sqrt(n))
    local rows = math.ceil(n / cols)
    -- Phase 1: create `rows` horizontal bands by splitting pane 0 downward,
    -- smallest-piece-off-the-original recursion (mirror of horizontal, --bottom).
    -- Band pane indices in creation order: band 0 = pane 0, band k = pane k.
    local band_pane = { [0] = 0 }
    local next_index = 1
    for r = 1, rows - 1 do
      steps[#steps + 1] = { direction = "bottom", percent = round_pct(rows - r + 1), target = 0 }
      band_pane[r] = next_index
      next_index = next_index + 1
    end
    -- Phase 2: within each band (in creation order), split into its columns via
    -- the horizontal recursion (--right, target = that band's pane). Last row may
    -- have fewer columns: cols for all rows except the last, where it is
    -- n - cols*(rows-1) (D-12: no placeholder panes).
    for r = 0, rows - 1 do
      local row_cols = cols
      if r == rows - 1 then
        row_cols = n - cols * (rows - 1)
      end
      for j = 1, row_cols - 1 do
        steps[#steps + 1] = {
          direction = "right",
          percent = round_pct(row_cols - j + 1),
          target = band_pane[r],
        }
      end
    end
    return steps
  end

  -- Unknown layout: validation (M.validate_layout) is the caller's gate; return
  -- an empty plan defensively so a bad layout never emits a malformed split.
  return steps
end

-- ---------------------------------------------------------------------------
-- M.parse_pane_spec(spec) -> {cmd, color, title, cwd, focus, size, shell} |
--   (nil, errmsg).
-- UI-SPEC Copywriting Contract --pane grammar (D-04/D-05/D-06/D-07):
--   "shell"            -> plain interactive shell (no command).
--   bare (no '=')      -> the whole value is the command.
--   key=value,...      -> cmd=/color=/title=/cwd=/focus=/size= (optional,
--                         order-independent).
-- The new fields (D-05/D-06/D-07):
--   * cwd   : carried RAW (a ~-prefix/$ENV/relative/absolute string). Resolution
--             needs the launch dir + env, which live in the IO-shell (Plan 04's
--             cli/commands/scene.lua) — this PURE module never resolves it.
--   * focus : boolean. `focus=true` -> true; absent -> nil (NOT false), so the
--             IO-shell can tell "no focus given" from "focus=false".
--   * size  : integer percent 1..100. Out-of-range / non-integer is a
--             validate-before-emit error (D-06).
-- Unknown key -> validate-before-emit error echoing the ORIGINAL spec + key.
-- ---------------------------------------------------------------------------
function M.parse_pane_spec(spec)
  spec = tostring(spec or "")

  -- D-04: the literal keyword `shell` means a plain shell, no command sent.
  if spec == "shell" then
    return { cmd = nil, color = nil, title = nil, shell = true }
  end

  -- Bare command form: no '=' anywhere -> the whole value is the command.
  if not spec:find("=", 1, true) then
    return { cmd = spec, color = nil, title = nil, shell = false }
  end

  local result = { cmd = nil, color = nil, title = nil, shell = false }
  for _, kv in ipairs(split_kv_segments(spec)) do
    local key, value = kv[1], kv[2]
    if key == "cmd" or key == "color" or key == "title" or key == "cwd"
      or key == "icon" then
      -- D-03: icon is carried RAW (a name like `node` or a literal glyph). The
      -- IO-shell resolves it to a glyph via titlelib.resolve_icon at emit time —
      -- this PURE parser keeps the original string, like cmd/color/title.
      result[key] = value
    elseif key == "focus" then
      -- D-05: boolean coercion. Only the literal `true` enables focus; any other
      -- value (including absent) leaves it nil so "no focus" is distinguishable.
      result.focus = (value == "true") or nil
    elseif key == "size" then
      -- D-06: integer percent in 1..100. Reject out-of-range / non-integer.
      local num = tonumber(value)
      if num == nil or num ~= math.floor(num) or num < 1 or num > 100 then
        return nil, string.format(
          "error: invalid --pane value '%s' — size must be an integer 1..100", spec)
      end
      result.size = math.floor(num)
    else
      return nil, string.format(
        "error: invalid --pane value '%s' — unknown key '%s' (expected cmd, color, title, cwd, focus, size, icon)",
        spec, key)
    end
  end
  -- D-04 parity for the key=value form: `cmd=shell` means a plain shell pane (no
  -- command sent), EXACTLY like the bare `shell` keyword — but here it may ALSO
  -- carry color/cwd/focus/size styling (D-13/D-14 want a teal-tinted working
  -- shell). Demote the command to a shell flag so the IO-shell sends no `shell`
  -- startup line while still applying the styling escapes (no nested `shell`
  -- command, no broken auto-title).
  if result.cmd == "shell" then
    result.cmd = nil
    result.shell = true
  end
  return result
end

-- ---------------------------------------------------------------------------
-- M.validate_focus(parsed_list) -> (true) | (false, errmsg).
-- D-05: at most ONE pane may carry focus=true. `parsed_list` is the array of
-- parse_pane_spec results. Validate-before-emit: more than one focused pane is a
-- hard error (the IO-shell bails with ZERO mux calls). Zero/one focus -> ok.
-- ---------------------------------------------------------------------------
function M.validate_focus(parsed_list)
  local count = 0
  for _, p in ipairs(parsed_list or {}) do
    if p and p.focus == true then
      count = count + 1
    end
  end
  if count > 1 then
    return false, "error: more than one pane marked focus=true"
  end
  return true
end

-- ---------------------------------------------------------------------------
-- M.size_percent(parsed, default_pct) -> int.
-- D-06: a pane with an explicit size= overrides the equal-share split percent
-- for ITS split step; a pane that omits size keeps the plan_splits default.
-- ---------------------------------------------------------------------------
function M.size_percent(parsed, default_pct)
  if parsed and parsed.size ~= nil then
    return parsed.size
  end
  return default_pct
end

-- ---------------------------------------------------------------------------
-- M.LAYOUTS — the 4 closed layout names in DISPLAY order (D-16 single source of
-- truth). Both M.validate_layout (below) and the `scene-layouts` completion
-- context (cli/commands/complete.lua) derive from this array, so "what validates"
-- and "what completes" can never drift. Order is intentional (tall first); do not
-- alphabetize.
-- ---------------------------------------------------------------------------
M.LAYOUTS = { "tall", "tall:mirrored", "grid", "horizontal" }

-- Membership set derived from M.LAYOUTS once at module load (no second literal
-- copy of the names — the array above is the only place they are written).
local LAYOUT_SET = {}
for _, name in ipairs(M.LAYOUTS) do LAYOUT_SET[name] = true end

-- ---------------------------------------------------------------------------
-- M.validate_layout(name) -> (true, nil) | (false, errmsg).
-- UI-SPEC: exact-match membership against M.LAYOUTS.
-- ---------------------------------------------------------------------------
function M.validate_layout(name)
  if LAYOUT_SET[name] then
    return true, nil
  end
  return false, string.format(
    "error: unknown layout '%s' — expected one of: %s",
    tostring(name), table.concat(M.LAYOUTS, ", "))
end

-- ---------------------------------------------------------------------------
-- M.validate_color(name) -> (true, nil) | (false, errmsg).
-- UI-SPEC Color Contract: 10-profile palette, case-insensitive. The error
-- message echoes the ORIGINAL case as given (not the lowercased lookup key).
-- ---------------------------------------------------------------------------
-- 10-profile palette in display order (D-16 single source). Both validate_color
-- and the `scene-colors` completion context derive from this ONE array, so the
-- completion can never advertise a color the validator rejects (mirrors the
-- M.LAYOUTS pattern above).
M.COLOR_NAMES = {
  "red", "orange", "yellow", "green", "teal",
  "cyan", "blue", "navy", "purple", "pink",
}
local COLOR_SET = {}
for _, name in ipairs(M.COLOR_NAMES) do COLOR_SET[name] = true end

-- Scene colors are NAMES-ONLY by design — a deliberate boundary, NOT a D-01 miss.
-- Standalone `wez pane/tab color` accept names + hex + #RRGGBBAA via the shared
-- cli.lib.color.validate_color, because they paint an accent/background directly.
-- A scene pane background, by contrast, is rendered from pane.lua's precomputed
-- MUTED_BG[name] table (the muted tint that keeps scene panes readable); that
-- muted variant exists ONLY for the 10 named palette colors, so arbitrary hex has
-- nothing to resolve to here. Keeping this validator names-only is what makes the
-- "names map to a muted background" contract truthful. Accepting hex in scenes is a
-- future capability (derive a muted variant from any hex), deferred — not in 6.1.
function M.validate_color(name)
  if COLOR_SET[tostring(name):lower()] then
    return true, nil
  end
  return false, string.format(
    "error: unknown color '%s' — expected one of: red, orange, yellow, green, teal, cyan, blue, navy, purple, pink",
    tostring(name))
end

-- ---------------------------------------------------------------------------
-- private: integer-coerce + range-check an id value.
-- Accepts numbers or numeric strings; rejects nil/empty/non-numeric/non-integer/negative.
-- ---------------------------------------------------------------------------
local function coerce_id(value)
  local num = tonumber(value)
  if num == nil then return false, nil end
  if num ~= math.floor(num) then return false, nil end -- reject 3.5 etc.
  if num < 0 then return false, nil end
  return true, math.floor(num)
end

-- ---------------------------------------------------------------------------
-- M.validate_pane_id(value) / M.validate_tab_id(value) -> (true, <int>) | (false, nil).
-- Pane and tab ids from the mux `list` output share one integer contract;
-- both names are exported so 04-02 reads as the call site intends.
-- ---------------------------------------------------------------------------
function M.validate_pane_id(value)
  return coerce_id(value)
end

M.validate_tab_id = M.validate_pane_id

-- ---------------------------------------------------------------------------
-- M.decide_materialization(panes, current_pane_id, n) -> plan table.
-- D-10/D-11 materialization decision, reimplemented purely. `panes` is an array
-- of { pane_id=<int>, tab_id=<int>, ... } (shape supplied by 04-02 from parsed
-- the mux `list --format json` output). The mode is driven SOLELY by whether the
-- CURRENT tab has exactly 1 pane (tab_pane_count == 1) -> reuse; else new-tab.
--
-- `n` is accepted for signature symmetry / future validation but does NOT drive
-- the mode decision here — the per-N split geometry is already encoded by
-- plan_splits(layout, n). Final pane count is enforced to be exactly N (D-12)
-- by the live wrapper applying plan_splits in the chosen target tab.
-- ---------------------------------------------------------------------------
function M.decide_materialization(panes, current_pane_id, n)
  panes = panes or {}
  local current_tab_id = nil
  for _, p in ipairs(panes) do
    if p.pane_id == current_pane_id then
      current_tab_id = p.tab_id
    end
  end
  local tab_pane_count = 0
  for _, p in ipairs(panes) do
    if p.tab_id == current_tab_id then
      tab_pane_count = tab_pane_count + 1
    end
  end
  if tab_pane_count == 1 then
    -- D-10: current tab has exactly 1 pane -> build in place, reuse as pane 1.
    return { mode = "reuse", target_tab_id = current_tab_id, first_pane_id = current_pane_id }
  end
  -- D-11: current tab has >=2 panes -> spawn a new tab in the same window; the
  -- live wrapper fills in target_tab_id/first_pane_id after spawning.
  return { mode = "new-tab", target_tab_id = nil, first_pane_id = nil }
end

return M
