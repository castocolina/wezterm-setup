-- cli/commands/keys.lua
--
-- The `wez keys` subcommand (DIAG-02/03/04). The subcommand + `--json` flag are
-- ALREADY registered in cli/spec.lua by Plan 01 — this module ONLY implements the
-- behavior; it does NOT edit the spec.
--
-- What it does (D-13 / D-14):
--   1. Gather the live EFFECTIVE key table via `wezterm show-keys --lua`
--      (cli/lib/showkeys.lua), the NO-CONFIG BASELINE via `wezterm -n show-keys
--      --lua`, and OUR declared set from the installed keybindings.lua.
--   2. Classify every effective binding (3-way) and flag conflicts:
--        setup   = ours ∩ baseline ∩ effective
--        default = baseline ∩ effective, NOT ours
--        user    = effective, NOT baseline and NOT ours
--        conflict= any of OUR bindings ABSENT from effective (overridden), or a
--                  same key+mods mapping to a DIFFERENT action.
--   3. Group bindings by category (Tabs, Panes, Navigation, Font, Other).
--   4. Default output: a human-readable grouped table with a label + conflict
--      marker. `--json`: a jq-valid JSON document (vendored dkjson).
--
-- The classify()/build_json() helpers are PURE and fixture-testable with no live
-- WezTerm session (the autonomous gate). run() wires them to the real session.

local M = {}

-- Installed location of OUR keybindings source of truth (Plan 03). `wez` is a
-- luastatic bundle with no LUA_PATH, so this file is read from the installed
-- filesystem path, not from the bundle. $HOME is expanded at runtime.
local function keybindings_path()
  local home = os.getenv("HOME") or ""
  return home .. "/.config/wezterm/wezterm-setup/keybindings.lua"
end

-- Normalize a binding's key for cross-source matching. Our keybindings.lua uses
-- the `mapped:` prefix (D-09: fire on produced character); show-keys reports the
-- bare key. Strip a leading `mapped:` so the two compare on the same token.
local function norm_key(key)
  key = tostring(key or "")
  return (key:gsub("^mapped:", ""))
end

-- Canonicalize a mods string so 'CTRL|SHIFT' and 'SHIFT|CTRL' match. Split on
-- '|', drop NONE, sort, rejoin.
local function norm_mods(mods)
  mods = tostring(mods or "")
  local parts = {}
  for tok in mods:gmatch("[^|]+") do
    tok = tok:gsub("%s+", "")
    if tok ~= "" and tok ~= "NONE" then parts[#parts + 1] = tok end
  end
  table.sort(parts)
  return table.concat(parts, "|")
end

-- A stable identity key for (key, mods) matching across the three sources.
local function id_of(rec)
  return norm_key(rec.key) .. "\0" .. norm_mods(rec.mods)
end

-- Build a lookup set { id -> record } from a record list.
local function index_by_id(list)
  local idx = {}
  for _, r in ipairs(list or {}) do
    idx[id_of(r)] = r
  end
  return idx
end

-- Derive a display category for a binding. Prefer explicit metadata on our record
-- (a `category` field, if present); otherwise infer from the key/action text.
local function category_of(rec)
  if rec.category and rec.category ~= "" then return rec.category end
  local a = tostring(rec.action or "")
  local k = norm_key(rec.key)
  if a:find("Tab") then return "Tabs" end
  if a:find("Pane") or a:find("Split") or a:find("Zoom") then return "Panes" end
  if a:find("FontSize") then return "Font" end
  if a:find("ActivatePaneDirection") or a:find("SendString") or a:find("SendKey")
    or k:find("Arrow") then
    return "Navigation"
  end
  return "Other"
end

-- Our action records are DECLARATIVE tables ({type=...}); the effective table is
-- a verbatim `act....` STRING. A precise cross-form comparison is out of scope for
-- this plan (it would need an action renderer), so we only flag a same-key
-- divergence when both sides are comparable strings. When ours is a declarative
-- table we treat presence-in-effective as "ours wins" and rely on the
-- overridden-absence check for true conflicts.
local function actions_equivalent(ours_action, eff_action)
  if type(ours_action) == "table" then
    return true -- declarative form: not string-comparable here; absence check governs
  end
  return tostring(ours_action) == tostring(eff_action)
end

-- classify(effective, baseline, ours) -> (entries, conflicts)
--
-- Pure function (D-14). `effective`, `baseline`, `ours` are each a list of
-- { key, mods, action } records. Returns:
--   entries   : list of { key, mods, action, label, category } for every
--               effective binding, labeled setup/default/user.
--   conflicts : list of { key, mods, action, reason } for who-wins issues:
--               - an OUR binding absent from the effective table (overridden), or
--               - same key+mods where ours and effective map to DIFFERENT actions.
function M.classify(effective, baseline, ours)
  local base_idx = index_by_id(baseline)
  local ours_idx = index_by_id(ours)
  local eff_idx = index_by_id(effective)

  local entries = {}
  for _, e in ipairs(effective or {}) do
    local eid = id_of(e)
    local in_base = base_idx[eid] ~= nil
    local in_ours = ours_idx[eid] ~= nil

    local label
    if in_ours and in_base then
      label = "setup"
    elseif in_base then
      label = "default"
    else
      label = "user"
    end

    entries[#entries + 1] = {
      key = norm_key(e.key),
      mods = e.mods,
      action = e.action,
      label = label,
      category = category_of(e),
    }
  end

  local conflicts = {}
  for _, o in ipairs(ours or {}) do
    local oid = id_of(o)
    local eff = eff_idx[oid]
    if not eff then
      -- Our binding is absent from the effective table: it was overridden.
      conflicts[#conflicts + 1] = {
        key = norm_key(o.key),
        mods = o.mods,
        action = o.action,
        reason = "overridden",
      }
    elseif tostring(eff.action) ~= tostring(o.action)
      and not actions_equivalent(o.action, eff.action) then
      -- Same key+mods, different action: a who-wins divergence.
      conflicts[#conflicts + 1] = {
        key = norm_key(o.key),
        mods = o.mods,
        action = o.action,
        effective_action = eff.action,
        reason = "action-mismatch",
      }
    end
  end

  return entries, conflicts
end

-- Build the --json document: grouped + classified bindings plus the conflict list.
function M.build_json(entries, conflicts)
  -- Group entries by category for the document, preserving a stable category order.
  local order = { "Tabs", "Panes", "Navigation", "Font", "Other" }
  local seen = {}
  local groups = {}
  local function group_for(cat)
    if not seen[cat] then
      seen[cat] = { category = cat, bindings = {} }
      groups[#groups + 1] = seen[cat]
    end
    return seen[cat]
  end
  -- Seed known categories in order so output is deterministic.
  for _, c in ipairs(order) do group_for(c) end

  for _, e in ipairs(entries or {}) do
    local g = group_for(e.category or "Other")
    g.bindings[#g.bindings + 1] = {
      key = e.key, mods = e.mods, action = e.action, label = e.label,
    }
  end

  -- Drop empty seeded groups so the document only lists categories with bindings.
  local nonempty = {}
  for _, g in ipairs(groups) do
    if #g.bindings > 0 then nonempty[#nonempty + 1] = g end
  end

  return {
    bindings = nonempty,
    conflicts = conflicts or {},
  }
end

-- ---------------------------------------------------------------------------
-- Live wiring (run): gather the real tables, classify, render.
-- ---------------------------------------------------------------------------

-- Run a command and capture stdout. Returns the text, or nil + message on failure.
local function capture(cmd)
  local fh = io.popen(cmd .. " 2>/dev/null")
  if not fh then return nil, "could not spawn: " .. cmd end
  local out = fh:read("*a")
  local ok = fh:close()
  if not ok then return nil, "command failed: " .. cmd end
  return out
end

-- Load OUR declared bindings from the installed keybindings.lua. Returns a list of
-- normalized { key, mods, action, category } records. The action is kept as the
-- declarative table from that module; category is left nil (inferred at classify).
local function load_our_bindings()
  local path = keybindings_path()
  local chunk, err = loadfile(path)
  if not chunk then return nil, err end
  local ok, mod = pcall(chunk)
  if not ok or type(mod) ~= "table" or type(mod.keys) ~= "table" then
    return nil, "keybindings.lua did not return a key table"
  end
  local out = {}
  for _, k in ipairs(mod.keys) do
    out[#out + 1] = { key = k.key, mods = k.mods, action = k.action }
  end
  -- Disabled defaults are OUR declared intent too: a default we removed should not
  -- show as a live conflict, but it documents our set. We keep only mod.keys for
  -- classification; disabled_defaults inform conflict reasoning if needed later.
  return out
end

function M.run(args)
  args = args or {}
  local showkeys = require("cli.lib.showkeys")

  local eff_text, e1 = capture("wezterm show-keys --lua")
  if not eff_text then
    io.stderr:write("wez keys: cannot read live key table (" .. tostring(e1) .. ")\n")
    io.stderr:write("wez keys: a running WezTerm session is required.\n")
    return 1
  end
  local base_text = capture("wezterm -n show-keys --lua") or ""

  local effective = showkeys.parse(eff_text)
  local baseline = showkeys.parse_baseline(base_text)

  local ours, oerr = load_our_bindings()
  if not ours then
    -- Not installed: classify with an empty "ours" so we still list/label the
    -- effective table (every binding falls to default/user); note the gap.
    io.stderr:write("wez keys: keybindings.lua not found at "
      .. keybindings_path() .. " (" .. tostring(oerr) .. "); "
      .. "run the installer (install-state) first.\n")
    ours = {}
  end

  local entries, conflicts = M.classify(effective, baseline, ours)

  if args.json then
    local json = require("dkjson")
    io.write(json.encode(M.build_json(entries, conflicts), { indent = true }))
    io.write("\n")
    return 0
  end

  -- Human-readable grouped table.
  local doc = M.build_json(entries, conflicts)
  for _, g in ipairs(doc.bindings) do
    io.write(("\n== %s ==\n"):format(g.category))
    for _, b in ipairs(g.bindings) do
      local mods = (b.mods and b.mods ~= "" and b.mods ~= "NONE") and (b.mods .. "+") or ""
      io.write(("  %-18s %-9s %s\n"):format(mods .. tostring(b.key), "[" .. b.label .. "]", b.action))
    end
  end
  if #conflicts > 0 then
    io.write("\n== Conflicts (who-wins) ==\n")
    for _, c in ipairs(conflicts) do
      local mods = (c.mods and c.mods ~= "" and c.mods ~= "NONE") and (c.mods .. "+") or ""
      io.write(("  ! %-16s %s\n"):format(mods .. tostring(c.key), c.reason))
    end
  end
  io.write("\n")
  return 0
end

return M
