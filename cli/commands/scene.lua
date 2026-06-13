-- cli/commands/scene.lua
--
-- The `wez scene new` LIVE ORCHESTRATION layer (Phase 4: Ad-hoc Scenes, SCEN-01).
--
-- This is the I/O / trust-boundary half of `wez scene new`. The PURE algorithmic
-- core lives in cli/lib/scene.lua (04-01): split sequencing, --pane spec parsing,
-- layout/color validation, materialization decision, pane/tab-id integer coercion.
-- This module consumes those helpers and drives the multiplexer CLI to actually
-- build the tab. It is the ONLY scene module that shells out.
--
-- Pipeline (strict ordering — validate-before-emit, two-phase build):
--   0. Validate-before-emit  : parse + validate EVERY --layout/--pane/--color
--                              value. Any failure prints the exact UI-SPEC error
--                              to stderr and returns non-zero WITH ZERO mux calls
--                              (no half-built tab — T-04-03).
--   1. Topology read         : `... cli list --format json` -> the full panes
--                              array {pane_id, tab_id}; current pane from the
--                              WEZTERM_PANE env var. Feeds decide_materialization.
--   2. Phase A (spawn/split) : reuse pane 1 (mode=reuse) or spawn a new tab
--                              (mode=new-tab), then run plan_splits steps. Every
--                              pane id read back from mux output is int-validated
--                              via scenelib.validate_pane_id BEFORE it is ever
--                              interpolated into a later command line (T-04-01).
--   3. Phase B (styling/cmd) : per-pane OSC-11 background + OSC-1337 title (reusing
--                              pane.lua's builders + MUTED_BG, never re-derived),
--                              a `clear` for the D-09 clean-pane bar, then the
--                              startup command as a DISTINCT trailing line (never
--                              concatenated into an escape sequence — T-04-02).
--                              Tab-level color/title via set-tab-title --tab-id
--                              reuses tab.lua's parse_stored/merge_title encoding.
--   4. Focus                 : activate-pane on the layout's main pane (pane 1).
--
-- Reuse discipline (no re-derived palettes / encodings):
--   * per-pane background hex   -> panelib.MUTED_BG  (same table as `wez pane color`)
--   * OSC builders              -> panelib.build_osc11 / build_osc1337
--   * title resolution          -> titlelib.resolve_title_str (shared D-03 resolver)
--   * tab color:title encoding  -> tablib.parse_stored / merge_title / write_tab_title

local M = {}

local scenelib = require("cli.lib.scene")
local panelib = require("cli.commands.pane")
local tablib = require("cli.commands.tab")
local titlelib = require("cli.lib.title")

-- ---------------------------------------------------------------------------
-- Single-quote shell escaper (same proven helper as tab.lua's shquote / CR-02):
-- a single quote is rewritten as '\'' so a value containing a quote or any shell
-- metacharacter cannot break out of the quoting and inject a command. EVERY
-- user-derived string (pane payloads, etc.) passed to os.execute/io.popen goes
-- through this.
-- ---------------------------------------------------------------------------
local function shquote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Decode JSON with the vendored dkjson, resolving both from source (CWD on
-- package.path) and inside the luastatic bundle (module baked as cli.vendor.dkjson).
-- Mirrors tab.lua's decode_json.
local function decode_json(text)
  local ok, dkjson = pcall(require, "cli.vendor.dkjson")
  if not ok then ok, dkjson = pcall(require, "dkjson") end
  if not ok or type(dkjson) ~= "table" then return nil end
  return dkjson.decode(text)
end

-- ---------------------------------------------------------------------------
-- Topology read: parse `... cli list --format json` into the FULL panes array
-- decide_materialization expects -- {pane_id=<int>, tab_id=<int>} for EVERY entry
-- (this is the difference from tab.lua's read_current_tab, which keeps only the
-- active tab). Degrades to {} on no-session / decode failure so the caller can
-- still decide (an empty topology means current_pane_id is unknown -> new-tab).
-- ---------------------------------------------------------------------------
function M.read_topology()
  local fh = io.popen("wezterm cli list --format json 2>/dev/null")
  if not fh then return {} end
  local out = fh:read("*a")
  fh:close()
  if not out or out == "" then return {} end
  local data = decode_json(out)
  if type(data) ~= "table" then return {} end
  local panes = {}
  for _, entry in ipairs(data) do
    if type(entry) == "table" then
      local ok_p, pid = scenelib.validate_pane_id(entry.pane_id)
      local ok_t, tid = scenelib.validate_tab_id(entry.tab_id)
      if ok_p and ok_t then
        panes[#panes + 1] = { pane_id = pid, tab_id = tid }
      end
    end
  end
  return panes
end

-- Run a mux command that prints a new pane id on stdout (spawn / split-pane),
-- read the first token, and validate it as an int BEFORE returning it for reuse
-- downstream (T-04-01). Returns (pane_id|nil, errmsg).
local function run_capture_pane_id(cmd)
  local fh = io.popen(cmd .. " 2>/dev/null")
  if not fh then return nil, "error: could not run mux command" end
  local out = fh:read("*a") or ""
  fh:close()
  local token = out:match("%S+")
  local ok, pid = scenelib.validate_pane_id(token)
  if not ok then
    return nil, "error: mux returned a non-numeric pane id"
  end
  return pid
end

-- Map a plan_splits direction to the split-pane CLI flag.
local DIR_FLAG = {
  left = "--left", right = "--right", top = "--top", bottom = "--bottom",
}

-- ---------------------------------------------------------------------------
-- M.run_new(args) -> exit code.
-- args.layout   : string (the --layout value)
-- args.pane     : array of raw --pane spec strings (argparse repeatable option);
--                 args.panes accepted as an alias for direct/test invocation.
-- args.color    : optional tab-level color name
-- args.title    : optional tab-level title text
-- ---------------------------------------------------------------------------
function M.run_new(args)
  args = args or {}
  local raw_panes = args.pane or args.panes or {}

  -- =========================================================================
  -- Step 0: VALIDATE-BEFORE-EMIT. No `wezterm cli spawn`/`split-pane` may run
  -- before this block returns successfully. (Verified by the line-ordering grep:
  -- the spawn/split-pane calls appear textually AFTER this block, in Phase A.)
  -- =========================================================================

  -- Zero --pane is a usage error (exact UI-SPEC copy).
  if #raw_panes == 0 then
    io.stderr:write("error: wez scene new requires at least one --pane (got 0)\n")
    return 2
  end

  -- Unknown --layout (exact UI-SPEC copy via scenelib).
  local ok_layout, layout_err = scenelib.validate_layout(args.layout)
  if not ok_layout then
    io.stderr:write(layout_err .. "\n")
    return 2
  end

  -- Parse + validate EVERY --pane spec; collect parsed specs before any mux call.
  local parsed = {}
  for i = 1, #raw_panes do
    local spec_parsed, parse_err = scenelib.parse_pane_spec(raw_panes[i])
    if not spec_parsed then
      io.stderr:write(parse_err .. "\n")
      return 2
    end
    if spec_parsed.color ~= nil then
      local ok_color, color_err = scenelib.validate_color(spec_parsed.color)
      if not ok_color then
        io.stderr:write(color_err .. "\n")
        return 2
      end
    end
    parsed[i] = spec_parsed
  end

  -- Tab-level --color (if given) validated the same way.
  if args.color ~= nil then
    local ok_tab_color, tab_color_err = scenelib.validate_color(args.color)
    if not ok_tab_color then
      io.stderr:write(tab_color_err .. "\n")
      return 2
    end
  end

  local n = #parsed

  -- =========================================================================
  -- Step 1: TOPOLOGY READ + materialization decision.
  -- =========================================================================
  local panes = M.read_topology()
  local current_pane_id = tonumber(os.getenv("WEZTERM_PANE"))
  local plan = scenelib.decide_materialization(panes, current_pane_id, n)

  -- =========================================================================
  -- Step 2: PHASE A -- spawn/split only. Build the pane_ids array (creation
  -- order, 1-based: pane_ids[1] = original/main pane, pane_ids[k+1] = pane
  -- created by the k-th split). EVERY id is an int already validated by either
  -- decide_materialization (first_pane_id) or run_capture_pane_id (T-04-01).
  -- =========================================================================
  local pane_ids = {}

  if plan.mode == "reuse" then
    pane_ids[1] = plan.first_pane_id
  else
    -- new-tab: a flagless spawn makes a new tab in the SAME window (D-11/D-12)
    -- and prints the new pane id.
    local pid, spawn_err = run_capture_pane_id("wezterm cli spawn")
    if not pid then
      io.stderr:write((spawn_err or "error: spawn failed") .. "\n")
      return 1
    end
    pane_ids[1] = pid
  end

  -- Apply the layout's split plan. plan_splits targets are creation-order indices
  -- (original pane = 0), so target t maps to pane_ids[t + 1].
  for _, step in ipairs(scenelib.plan_splits(args.layout, n)) do
    local target_pid = pane_ids[(step.target or 0) + 1]
    local flag = DIR_FLAG[step.direction]
    if not flag or not target_pid then
      io.stderr:write("error: internal split plan produced an invalid step\n")
      return 1
    end
    local cmd = string.format(
      "wezterm cli split-pane --pane-id %d %s --percent %d",
      target_pid, flag, tonumber(step.percent) or 50)
    local new_pid, split_err = run_capture_pane_id(cmd)
    if not new_pid then
      io.stderr:write((split_err or "error: split-pane failed") .. "\n")
      return 1
    end
    pane_ids[#pane_ids + 1] = new_pid
  end

  -- Defensive: after Phase A we expect exactly n panes. Log but continue so a
  -- mux quirk does not silently swallow the discrepancy.
  if #pane_ids ~= n then
    io.stderr:write(string.format(
      "warning: built %d panes but expected %d (split plan / mux mismatch)\n",
      #pane_ids, n))
  end

  -- =========================================================================
  -- Step 3: PHASE B -- per-pane styling + startup command (strict two-phase:
  -- runs only AFTER all of Phase A completed, never interleaved, per Pitfall 2).
  -- =========================================================================
  for i = 1, #pane_ids do
    local pid = pane_ids[i]
    local spec_parsed = parsed[i]
    if spec_parsed then
      local payload = {}
      local escapes = {}

      -- Per-pane OSC-11 muted background (reuse pane.lua's MUTED_BG + build_osc11;
      -- never a re-derived hex). color was already validated above.
      if spec_parsed.color ~= nil then
        local hex = panelib.MUTED_BG[tostring(spec_parsed.color):lower()]
        if hex then
          escapes[#escapes + 1] = panelib.build_osc11(hex)
        end
      end

      -- Title: explicit title= wins (D-07); else derive an auto-title from the
      -- startup command's first word. Both go through the shared resolver so
      -- icon-name shortcuts behave exactly like `wez pane title`.
      local title_str = nil
      if spec_parsed.title ~= nil then
        title_str = titlelib.resolve_title_str(spec_parsed.title)
      elseif spec_parsed.cmd ~= nil and not spec_parsed.shell then
        -- D-07 auto-title: cli/lib/title.lua has no command->title heuristic, so
        -- the auto-title is the command's first word (resolved through the same
        -- icon map for parity with explicit titles).
        local first_word = tostring(spec_parsed.cmd):match("%S+")
        if first_word then
          title_str = titlelib.resolve_title_str(first_word)
        end
      end
      if title_str ~= nil and title_str ~= "" then
        escapes[#escapes + 1] = panelib.build_osc1337("WEZTERM_TAB_TITLE", title_str)
      end

      local has_styling = #escapes > 0
      local has_cmd = spec_parsed.cmd ~= nil and not spec_parsed.shell

      if has_styling or has_cmd then
        -- D-09: the OSC escapes must reach the TERMINAL's output parser, not the
        -- shell's line editor. send-text writes to the pane PTY (= shell stdin),
        -- so raw control bytes are consumed by the line editor (zsh's zle silently
        -- swallows them — so the color never even applies — while bash's readline
        -- echoes the printable tail as `11;#...1337;...` garbage). Emit them via
        -- `printf` instead: the shell EXECUTES printf and its OUTPUT carries the
        -- bytes to the terminal, which interprets the OSC. Octal-escape every byte
        -- so the typed line is pure printable ASCII (no raw ESC for readline to
        -- mangle) needing no shell quoting; printf '\nnn' octal works in bash & zsh.
        if has_styling then
          local octal = table.concat(escapes):gsub(".", function(c)
            return string.format("\\%03o", string.byte(c))
          end)
          payload[#payload + 1] = "printf '" .. octal .. "'\n"
        end
        -- D-09 clean-pane bar: a `clear` AFTER the escape injection but BEFORE the
        -- startup command runs, so no residue / stray blank lines remain and the
        -- command's own output is the first visible thing.
        payload[#payload + 1] = "clear\n"
        -- Startup command as a DISTINCT trailing line (NOT concatenated into an
        -- escape sequence — prevents OSC injection/breakout, T-04-02). A `shell`
        -- pane (D-04) gets no command appended.
        if has_cmd then
          payload[#payload + 1] = tostring(spec_parsed.cmd) .. "\n"
        end
        local text = table.concat(payload)
        os.execute(string.format(
          "wezterm cli send-text --pane-id %d --no-paste %s",
          pid, shquote(text)))
      end
      -- A `shell` pane with no color/title sends NOTHING (truly untouched, D-09).
    end
  end

  -- =========================================================================
  -- Tab-level styling (D-05): set-tab-title --tab-id on the scene's tab, reusing
  -- tab.lua's color:title encoding (parse_stored + merge_title). Only when a
  -- tab-level --color or --title was given.
  -- =========================================================================
  if args.color ~= nil or args.title ~= nil then
    local target_tab_id = plan.target_tab_id
    if target_tab_id == nil then
      -- new-tab path: re-read topology to find the tab that now owns pane 1.
      for _, p in ipairs(M.read_topology()) do
        if p.pane_id == pane_ids[1] then
          target_tab_id = p.tab_id
        end
      end
    end
    if target_tab_id ~= nil then
      -- Read-modify-write: preserve whichever half (color/title) was not given.
      local cur = M.read_current_tab_title(target_tab_id)
      local cur_color, cur_title = tablib.parse_stored(cur)
      local opts = { cur_color = cur_color, cur_title = cur_title }
      if args.color ~= nil then
        local _, normalized = scenelib.validate_color(args.color)
        opts.set_color = tostring(args.color):lower()
        -- normalized is the lowercased name; keep it as the stored color half.
        opts.set_color = normalized or opts.set_color
      end
      if args.title ~= nil then
        opts.set_title = titlelib.resolve_title_str(args.title)
      end
      local merged = tablib.merge_title(opts)
      tablib.write_tab_title(merged, target_tab_id)
    end
  end

  -- =========================================================================
  -- Step 4: FOCUS the layout's main pane (pane 1 in all 4 layouts).
  -- =========================================================================
  if pane_ids[1] ~= nil then
    os.execute("wezterm cli activate-pane --pane-id " .. tostring(pane_ids[1]))
  end

  -- D-09 / UI-SPEC: success is silent on stdout.
  return 0
end

-- ---------------------------------------------------------------------------
-- Read a specific tab's stored title from the mux list (for the tab-level
-- read-modify-write). Returns the stored "<color>:<title>" string, or "" if the
-- tab is not found / no session.
-- ---------------------------------------------------------------------------
function M.read_current_tab_title(tab_id)
  local fh = io.popen("wezterm cli list --format json 2>/dev/null")
  if not fh then return "" end
  local out = fh:read("*a")
  fh:close()
  if not out or out == "" then return "" end
  local data = decode_json(out)
  if type(data) ~= "table" then return "" end
  for _, entry in ipairs(data) do
    if type(entry) == "table" then
      local _, tid = scenelib.validate_tab_id(entry.tab_id)
      if tid == tab_id and entry.tab_title then
        return entry.tab_title
      end
    end
  end
  return ""
end

-- ---------------------------------------------------------------------------
-- M.run(args): command entry. Branches on the selected `scene` subcommand
-- (args.scene_cmd), mirroring pane.lua / tab.lua's dispatcher shape.
-- ---------------------------------------------------------------------------
function M.run(args)
  local sub = args and args.scene_cmd
  if sub == "new" then
    return M.run_new(args)
  end
  io.stderr:write("wez scene: expected a subcommand (new)\n")
  return 2
end

return M
