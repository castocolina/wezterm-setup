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

-- Normalize a binding's key for cross-source matching. Our keybindings.lua uses
-- the `mapped:` prefix (D-09: fire on produced character); show-keys reports the
-- bare key. Strip a leading `mapped:` so the two compare on the same token.
local function norm_key(key)
  key = tostring(key or "")
  return (key:gsub("^mapped:", ""))
end

-- Canonicalize a mods string so 'CTRL|SHIFT' and 'SHIFT|CTRL' match. Split on
-- '|', drop NONE, sort, rejoin. PIPE FORM — this is the cross-source identity key
-- (D-02 caveat / RESEARCH Pattern 2): the HUMAN render uses render_mods() with the
-- fixed SUPER>CTRL>ALT>SHIFT order + '+' separator instead; norm_mods MUST stay
-- pipe-joined so classify() matching across the three sources is undisturbed.
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
M.norm_mods = norm_mods

-- A stable identity key for (key, mods) matching across the three sources.
--
-- D-14-fix (root cause): the three sources spell the SAME chord differently —
-- our keybindings.lua declares `mapped:x` + `ALT|SHIFT` while the live effective
-- table reports the WezTerm-folded `X` + `ALT`. The identity MUST therefore
-- canonicalize (strip `mapped:`, case-fold the letter base, make the implicit
-- SHIFT explicit) BEFORE normalizing the mods, so a binding we own is never
-- misclassified `[user]` nor falsely flagged `overridden`. canonicalize_key is
-- defined below (M.canonicalize_key); it is a forward reference resolved at call
-- time, so id_of always sees the same fold the render path uses.
local function id_of(rec)
  local key = norm_key(rec.key)
  local ck, cm = M.canonicalize_key(key, rec.mods)
  return ck .. "\0" .. norm_mods(cm)
end
M.id_of = id_of

-- ---------------------------------------------------------------------------
-- PURE display transforms (D-01/D-02/D-03/D-04/D-07/D-08). No io/os/wezterm —
-- fixture-testable headless (the autonomous gate). The host-OS default, the
-- TTY/NO_COLOR gate, and the actual io.write live in run() (the IO shell).
-- ---------------------------------------------------------------------------

--- D-01 letter-only canonicalize: an uppercase single ASCII letter with no SHIFT
--- folds to lowercase + explicit SHIFT (`ALT+X` -> `ALT+SHIFT+x`). Digits, symbols,
--- and named keys (`1`, `=`, `PageUp`) pass through UNCHANGED (RESEARCH Pitfall 2).
function M.canonicalize_key(key, mods)
  key = tostring(key or "")
  mods = tostring(mods or "")
  if key:match("^%a$") and key:upper() == key then
    -- Letter base: always lowercase. Add SHIFT only if absent (uppercase implies it).
    local has_shift = mods:find("SHIFT", 1, true) ~= nil
    local new_mods = mods
    if not has_shift then
      new_mods = (mods == "" or mods == "NONE") and "SHIFT" or (mods .. "|SHIFT")
    end
    return key:lower(), new_mods
  end
  return key, mods
end

-- Fixed render order rank for the HUMAN modifier form (D-02). Unknown -> 99.
local MOD_RANK = { SUPER = 1, CTRL = 2, ALT = 3, SHIFT = 4 }

--- D-02 human mod renderer: split on '|', drop NONE/empty, sort by the fixed
--- SUPER>CTRL>ALT>SHIFT rank, join with '+'. NONE/empty -> "" (no leading '+').
function M.render_mods(mods)
  mods = tostring(mods or "")
  local parts = {}
  for tok in mods:gmatch("[^|]+") do
    tok = tok:gsub("%s+", "")
    if tok ~= "" and tok ~= "NONE" then parts[#parts + 1] = tok end
  end
  table.sort(parts, function(a, b)
    return (MOD_RANK[a] or 99) < (MOD_RANK[b] or 99)
  end)
  return table.concat(parts, "+")
end

-- Render a full chord (mods + base key) in the human '+'-joined form.
local function render_chord(key, mods)
  local m = M.render_mods(mods)
  if m == "" then return tostring(key) end
  return m .. "+" .. tostring(key)
end

--- D-03/D-04 platform label: map the SUPER token to `Super` (linux) / `Cmd` (macos).
--- Under `all`, a Super-bearing chord renders the inline annotation
--- `"Cmd+w (macOS) / Super+w (Linux)"`; non-Super chords are platform-invariant.
function M.platform_label(key, mods, platform)
  key = tostring(key or "")
  mods = tostring(mods or "")
  local has_super = mods:find("SUPER", 1, true) ~= nil
  if not has_super then
    -- Platform-invariant: render once with no annotation.
    return render_chord(key, mods)
  end
  if platform == "all" then
    local mac = render_chord(key, mods):gsub("SUPER", "Cmd")
    local lin = render_chord(key, mods):gsub("SUPER", "Super")
    return mac .. " (macOS) / " .. lin .. " (Linux)"
  end
  local label = (platform == "macos") and "Cmd" or "Super"
  return (render_chord(key, mods):gsub("SUPER", label))
end

-- Reliability rank for D-07 multi-chord ordering: rank 1 = layout-stable terminal
-- chord (CTRL and SHIFT and NOT SUPER), rank 2 = WM-grab-prone SUPER chord, rank 3
-- = anything else. Lower renders first; equal rank -> original insertion index.
local function reliability_rank(mods)
  mods = tostring(mods or "")
  local has_ctrl = mods:find("CTRL", 1, true) ~= nil
  local has_shift = mods:find("SHIFT", 1, true) ~= nil
  local has_super = mods:find("SUPER", 1, true) ~= nil
  if has_ctrl and has_shift and not has_super then return 1 end
  if has_super then return 2 end
  return 3
end

--- D-07 action-centric grouping (+ D-08 case collapse): collapse `entries` to one
--- row per action, building the `, `-joined chord list ordered reliable-chord-first
--- (CTRL+SHIFT before SUPER); intra-class ties keep ORIGINAL insertion order. Each
--- record is canonicalized first, so case-variant twins fold to one chord. Returns
--- a list of { action, label, category, chords }.
function M.group_by_action(entries)
  local order = {}            -- action -> first-seen index (stable group order)
  local groups = {}           -- action -> { action, label, category, chords = {} }
  local seen_chord = {}       -- action -> { canon-chord -> true } (dedupe twins)

  for i, e in ipairs(entries or {}) do
    local key, mods = M.canonicalize_key(e.key, e.mods)
    local action = tostring(e.action)
    local chord = render_chord(key, mods)
    if not groups[action] then
      order[#order + 1] = action
      groups[action] = { action = action, label = e.label, category = e.category, chords = {} }
      seen_chord[action] = {}
    end
    if not seen_chord[action][chord] then
      seen_chord[action][chord] = true
      groups[action].chords[#groups[action].chords + 1] = {
        text = chord, rank = reliability_rank(mods), idx = i,
      }
    end
  end

  local rows = {}
  for _, action in ipairs(order) do
    local g = groups[action]
    table.sort(g.chords, function(a, b)
      if a.rank ~= b.rank then return a.rank < b.rank end
      return a.idx < b.idx
    end)
    local texts = {}
    for _, c in ipairs(g.chords) do texts[#texts + 1] = c.text end
    rows[#rows + 1] = {
      action = g.action, label = g.label, category = g.category,
      chords = table.concat(texts, ", "),
    }
  end
  return rows
end

--- D-06 color gate (PURE decision): emit SGR only when NOT --json AND NO_COLOR is
--- unset AND stdout is a TTY. The host gathers no_color/tty in the IO shell.
function M.color_enabled(args, no_color, is_tty)
  args = args or {}
  if args.json then return false end
  if no_color then return false end
  if not is_tty then return false end
  return true
end

--- D-06 conflict row (PINNED literal): `"  ! %-16s %-30s %s\n"` with arg1=chord,
--- arg2=reason (our own fixed token overridden/action-mismatch), arg3=the literal
--- token "[CONFLICT]". The renderer + test target this ONE format string.
function M.conflict_row(chord, reason)
  return ("  ! %-16s %-30s %s\n"):format(tostring(chord), tostring(reason), "[CONFLICT]")
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

-- D-13: who-wins is decided purely by presence in the effective table. Our action
-- records are DECLARATIVE tables ({type=...}); the effective table is a verbatim
-- `act....` STRING, so a string-level action comparison is not meaningful here.
-- Presence-in-effective = ours wins (no conflict); absence of a non-Super binding =
-- the one true conflict. No same-key action-mismatch branch (dropped in 06.5-05).

-- classify(effective, baseline, ours) -> (entries, conflicts)
--
-- Pure function (D-12 / D-13 / D-14-fix). `effective`, `baseline`, `ours` are each
-- a list of { key, mods, action } records, matched on the CANONICAL id_of identity
-- (case-folded letter base + explicit SHIFT + normalized mods), so our `mapped:x` +
-- `ALT|SHIFT` matches the live `X` + `ALT`. Returns:
--   entries   : list of { key, mods, action, label, category, group } for every
--               effective binding. The `group` keys the three-section render and is
--               derived purely from (in_ours, in_base):
--                 in_ours and in_base       -> group "managed",   label "setup"
--                 in_ours and not in_base    -> group "additions", label "added"
--                 not in_ours and in_base    -> group "defaults",  label "default"
--                 not in_ours and not in_base-> group "defaults",  label "user"
--   conflicts : TRUE conflicts only (D-13). A conflict is recorded ONLY when an OUR
--               binding is absent from the effective table AFTER canonical matching
--               AND its mods do NOT contain SUPER (Linux WM grabs Super chords by
--               design — the reliable Ctrl+Shift sibling is what matters; a grabbed
--               Super chord is never a real conflict). A binding PRESENT in effective
--               means ours wins — no conflict row (the old action-mismatch noise on a
--               present-but-declarative binding is dropped).
function M.classify(effective, baseline, ours)
  local base_idx = index_by_id(baseline)
  local ours_idx = index_by_id(ours)
  local eff_idx = index_by_id(effective)

  local entries = {}
  for _, e in ipairs(effective or {}) do
    local eid = id_of(e)
    local in_base = base_idx[eid] ~= nil
    local in_ours = ours_idx[eid] ~= nil

    local group, label
    if in_ours and in_base then
      group, label = "managed", "setup"
    elseif in_ours and not in_base then
      group, label = "additions", "added"
    elseif in_base then
      group, label = "defaults", "default"
    else
      group, label = "defaults", "user"
    end

    entries[#entries + 1] = {
      key = norm_key(e.key),
      mods = e.mods,
      action = e.action,
      label = label,
      group = group,
      category = category_of(e),
    }
  end

  local conflicts = {}
  for _, o in ipairs(ours or {}) do
    local oid = id_of(o)
    local eff = eff_idx[oid]
    local has_super = tostring(o.mods or ""):find("SUPER", 1, true) ~= nil
    if not eff and not has_super then
      -- TRUE conflict (D-13): a NON-Super binding we declare is genuinely absent
      -- from the effective table after canonical matching → it was overridden.
      -- Present bindings (ours wins) and Super-bearing chords (WM-grabbed) are
      -- intentionally NOT reported.
      conflicts[#conflicts + 1] = {
        key = norm_key(o.key),
        mods = o.mods,
        action = o.action,
        reason = "overridden",
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

-- Installed location of OUR keybindings source of truth (Plan 03). `wez` is a
-- luastatic bundle with no LUA_PATH, so this file is read from the installed
-- filesystem path, not from the bundle. $HOME is expanded at runtime. This is an
-- IO-shell helper (it reads os.getenv) — it lives below the PURE banner beside
-- capture()/load_our_bindings() so the purity boundary stays unambiguous (MINOR-3).
local function keybindings_path()
  local home = os.getenv("HOME") or ""
  return home .. "/.config/wezterm/wezterm-setup/keybindings.lua"
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
  -- INTENTIONAL SCOPE BOUNDARY (D-13): we load ONLY mod.keys, NOT mod.disabled_defaults.
  -- Under the D-13 conflict definition (conflict = an OUR binding ABSENT from the
  -- effective table) disabled_defaults are NOT conflict participants — they are
  -- defaults we REMOVE, not bindings we ADD, so they cannot be "overridden". This is
  -- a deliberate decision, not an oversight: the trade-off is that a removed default
  -- which silently fails to disable would NOT surface here. If that case ever needs
  -- surfacing it is a separate "expected-removed-but-still-present" check, distinct
  -- from the absent-ours conflict this classify reports.
  return out
end

-- Detect whether stdout (fd 1) is a TTY (IO shell — HIGH-4). NEW probe: color.lua
-- and ansi.lua are PURE and have no TTY detector, and no module anywhere provides
-- one, so this lives here in run()'s shell beside capture(). FAIL CLOSED: any
-- failure to spawn/read/close, or any output other than exactly "0\n", -> false
-- (a restricted host that cannot probe degrades to plain text, never stray SGR).
local function stdout_is_tty()
  local fh = io.popen("test -t 1; echo $?")
  if not fh then return false end
  local out = fh:read("*a")
  local ok = fh:close()
  if not ok then return false end
  return out == "0\n"
end

-- The locked 3-line Linux Super footnote (UI-SPEC §Platform Label, verbatim).
local LINUX_SUPER_FOOTNOTE =
  "  Note: On Linux the Super key is often claimed by your desktop\n" ..
  "  (e.g. Pop!_OS grabs Super+W / Super+K), so Super chords may not\n" ..
  "  reach WezTerm. The Ctrl+Shift chord listed first is the reliable one.\n"

-- Inner category order preserved as the grouping within each section (D-05 / RESEARCH Open Q2).
local CATEGORY_ORDER = { "Tabs", "Panes", "Navigation", "Font", "Other" }

-- Render the chord-list of one action row through the platform label so a Super
-- chord shows Super/Cmd (or the inline all-annotation). The reliable-first order
-- established by group_by_action is preserved.
local function platformize_chords(chords, platform)
  local out = {}
  for chord in (chords .. ", "):gmatch("(.-), ") do
    -- Re-split chord into mods + base key to feed platform_label. The base key is
    -- the final '+'-separated token; everything before is the mod string.
    local mods, key
    local plus = chord:match("^(.*)%+([^%+]+)$")
    if plus then
      mods = chord:match("^(.*)%+[^%+]+$"):gsub("%+", "|")
      key = chord:match("%+([^%+]+)$")
    else
      mods, key = "", chord
    end
    out[#out + 1] = M.platform_label(key, mods, platform)
  end
  return table.concat(out, ", ")
end

-- Render one section (managed or defaults) of action rows grouped by category.
-- Returns the text; emits nothing for an empty section (caller omits the header).
local function render_section(header, entries, platform)
  if #entries == 0 then return "" end
  local rows = M.group_by_action(entries)
  -- Bucket rows by category, preserving the fixed inner category order.
  local by_cat, order = {}, {}
  for _, r in ipairs(rows) do
    local cat = r.category or "Other"
    if not by_cat[cat] then by_cat[cat] = {}; order[#order + 1] = cat end
    by_cat[cat][#by_cat[cat] + 1] = r
  end
  local function cat_rank(c)
    for i, name in ipairs(CATEGORY_ORDER) do if name == c then return i end end
    return #CATEGORY_ORDER + 1
  end
  table.sort(order, function(a, b)
    local ra, rb = cat_rank(a), cat_rank(b)
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  -- Pre-render the per-row columns and compute dynamic widths PER SECTION so each
  -- section aligns independently (chord-first layout): chords | [tag] | action.
  -- The chord list is platformized first because that is the width that displays.
  local rendered = {}
  local cw, lw = 0, 0  -- widest chord-list, widest bracketed tag (>= len("[default]"))
  local MIN_LW = #"[default]"
  if lw < MIN_LW then lw = MIN_LW end
  for _, cat in ipairs(order) do
    for _, r in ipairs(by_cat[cat]) do
      local chords = platformize_chords(r.chords, platform)
      local tag = "[" .. r.label .. "]"
      if #chords > cw then cw = #chords end
      if #tag > lw then lw = #tag end
      rendered[#rendered + 1] = { chords = chords, tag = tag, action = r.action }
    end
  end
  -- Left-pad to a column width WITHOUT string.format's `%-<N>s` spec: Lua 5.4 caps a
  -- format field width at two digits, so a wide column (e.g. a `--platform all`
  -- inline-annotated chord list >= 100 bytes) would raise "invalid conversion
  -- specification: '%-136s'" and abort the render mid-section. Manual padding has no
  -- width ceiling. action trails free-width (no padding) so its length never shifts
  -- the other columns.
  local function pad(s, w)
    s = tostring(s)
    local n = w - #s
    return n > 0 and (s .. string.rep(" ", n)) or s
  end
  local buf = { ("\n== %s ==\n"):format(header) }
  for _, row in ipairs(rendered) do
    buf[#buf + 1] = "  " .. pad(row.chords, cw) .. "  " .. pad(row.tag, lw) .. "  " .. row.action .. "\n"
  end
  return table.concat(buf)
end

function M.run(args)
  args = args or {}
  local showkeys = require("cli.lib.showkeys")
  local ansi = require("cli.lib.ansi")

  -- Live capture (IO), with test-injection seams so the renderer is headless-testable.
  local eff_text = args._effective_text
  if not eff_text then
    local e1
    eff_text, e1 = capture("wezterm show-keys --lua")
    if not eff_text then
      io.stderr:write("wez keys: cannot read live key table (" .. tostring(e1) .. ")\n")
      io.stderr:write("wez keys: a running WezTerm session is required.\n")
      return 1
    end
  end
  local base_text = args._baseline_text or capture("wezterm -n show-keys --lua") or ""

  local effective = showkeys.parse(eff_text)
  local baseline = showkeys.parse_baseline(base_text)

  local ours = args._ours
  if not ours then
    local oerr
    ours, oerr = load_our_bindings()
    if not ours then
      io.stderr:write("wez keys: keybindings.lua not found at "
        .. keybindings_path() .. " (" .. tostring(oerr) .. "); "
        .. "run the installer (install-state) first.\n")
      ours = {}
    end
  end

  local entries, conflicts = M.classify(effective, baseline, ours)

  if args.json then
    -- D-06: the JSON document is NEVER colorized — no ansi.* call on this path.
    local json = require("dkjson")
    io.write(json.encode(M.build_json(entries, conflicts), { indent = true }))
    io.write("\n")
    return 0
  end

  -- Host-OS default for the platform label (IO shell); honor an explicit --platform.
  local platform = args.platform
  if platform ~= "linux" and platform ~= "macos" and platform ~= "all" then
    local uname = capture("uname -s") or ""
    platform = uname:match("Darwin") and "macos" or "linux"
  end

  -- D-06 color gate (IO shell decision feeding the pure M.color_enabled). The
  -- _color_force seam lets the headless suite assert both branches deterministically.
  local is_tty
  if args._color_force ~= nil then
    is_tty = args._color_force
  else
    is_tty = stdout_is_tty()
  end
  local color = M.color_enabled(args, os.getenv("NO_COLOR") ~= nil, is_tty)

  -- D-12 three-group sectioning, keyed on the classify `group` field:
  --   managed   = ours ∩ baseline   → "== Managed (overrides) =="
  --   additions = ours ∖ baseline   → "== Our additions =="
  --   defaults  = NOT ours          → "== WezTerm defaults =="
  -- Rendered in that fixed order; empty groups print no header (render_section).
  local managed, additions, defaults = {}, {}, {}
  for _, e in ipairs(entries) do
    if e.group == "managed" then
      managed[#managed + 1] = e
    elseif e.group == "additions" then
      additions[#additions + 1] = e
    else
      defaults[#defaults + 1] = e
    end
  end

  io.write(render_section("Managed (overrides)", managed, platform))
  io.write(render_section("Our additions", additions, platform))
  -- Linux Super footnote: once, after our managed/additions blocks, on linux/all
  -- only — and only when we actually showed something of ours worth footnoting.
  if (#managed > 0 or #additions > 0) and (platform == "linux" or platform == "all") then
    io.write("\n" .. LINUX_SUPER_FOOTNOTE)
  end
  io.write(render_section("WezTerm defaults", defaults, platform))

  -- D-06 conflicts: only when present; red on a TTY, the action string is NEVER
  -- SGR-wrapped (we colorize only our fixed conflict-row columns).
  if #conflicts > 0 then
    local hdr = "== Conflicts (who-wins) =="
    io.write("\n" .. (color and ansi.bold_red(hdr) or hdr) .. "\n")
    for _, c in ipairs(conflicts) do
      local key, mods = M.canonicalize_key(c.key, c.mods)
      local chord = M.platform_label(key, mods, platform)
      local row = M.conflict_row(chord, c.reason)
      io.write(color and ansi.red(row) or row)
    end
  end
  io.write("\n")
  return 0
end

return M
