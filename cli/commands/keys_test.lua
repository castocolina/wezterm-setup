-- Fixture tests for cli/commands/keys.lua — the curated-first `wez keys` renderer
-- (Phase 06.5 Plan 02: D-01 canonicalize / D-02 fixed mod order / D-05 curated-first
-- sectioning / D-06 ANSI-red conflicts / D-07 action grouping / D-08 case collapse +
-- the platform label). These are PURE fixture tests — they drive the NEW exports and
-- the run() renderer through committed show-keys samples with NO live WezTerm session.
-- Run from the repo root: `lua5.4 cli/commands/keys_test.lua`

-- Make `cli/...` + vendored deps (dkjson, used by the --json path) requireable
-- regardless of invocation CWD (matches cli/commands/scene_test.lua's bootstrap).
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/../.." -- cli/commands -> repo root
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  package.path,
}, ";")

local M = require("cli.commands.keys")
local showkeys = require("cli.lib.showkeys")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else
    fail = fail + 1
    io.stderr:write("FAIL: " .. name .. "\n")
  end
end
local function eq(name, got, want)
  check(name .. " (got " .. tostring(got) .. " | want " .. tostring(want) .. ")", got == want)
end

-- capture(fn) — stub io.write + io.stderr so run()-level output is testable headlessly
-- (copied verbatim from cli/commands/pane_test.lua).
local function capture(fn)
  local out, err = {}, {}
  local real_write, real_stderr = io.write, io.stderr
  io.write = function(...) for _, v in ipairs({ ... }) do out[#out + 1] = tostring(v) end end
  io.stderr = { write = function(_self, ...) for _, v in ipairs({ ... }) do err[#err + 1] = tostring(v) end end }
  local code = fn()
  io.write, io.stderr = real_write, real_stderr
  return code, table.concat(out), table.concat(err)
end

-- ── D-01 canonicalize_key (letter-only fold; digits/named keys pass through) ──
do
  local k, m = M.canonicalize_key("X", "ALT")
  eq("c1 canonicalize letter X/ALT -> x", k, "x")
  eq("c1 canonicalize letter X/ALT -> mods +SHIFT", m, "ALT|SHIFT")

  local k2, m2 = M.canonicalize_key("1", "ALT|SHIFT")
  eq("c2 digit 1 key unchanged", k2, "1")
  eq("c2 digit 1 mods unchanged", m2, "ALT|SHIFT")

  local k3, m3 = M.canonicalize_key("PageUp", "CTRL|SHIFT")
  eq("c3 named key PageUp unchanged", k3, "PageUp")
  eq("c3 named key PageUp mods unchanged", m3, "CTRL|SHIFT")

  local k4, m4 = M.canonicalize_key("z", "CTRL|SHIFT")
  eq("c4 already-lowercase+SHIFT z unchanged", k4, "z")
  eq("c4 already-lowercase+SHIFT z mods unchanged", m4, "CTRL|SHIFT")

  -- ^%a$ guard: a symbol does NOT fold (not a letter)
  local k5, m5 = M.canonicalize_key("=", "SUPER")
  eq("c5 symbol = unchanged (^%a$ guard)", k5, "=")
  eq("c5 symbol = mods unchanged", m5, "SUPER")

  -- Uppercase letter that ALREADY carries SHIFT: lowercase, mods unchanged (SHIFT kept)
  local k6, m6 = M.canonicalize_key("Z", "CTRL|SHIFT")
  eq("c6 uppercase Z with SHIFT -> z", k6, "z")
  eq("c6 uppercase Z with SHIFT mods unchanged", m6, "CTRL|SHIFT")
end

-- ── D-02 render_mods (fixed order SUPER>CTRL>ALT>SHIFT, '+' join) ─────────────
eq("m1 render_mods reorders to CTRL+SHIFT", M.render_mods("SHIFT|CTRL"), "CTRL+SHIFT")
eq("m2 render_mods ALT+SHIFT", M.render_mods("ALT|SHIFT"), "ALT+SHIFT")
eq("m3 render_mods full fixed order", M.render_mods("SHIFT|CTRL|SUPER"), "SUPER+CTRL+SHIFT")
eq("m4 render_mods NONE -> empty (no leading +)", M.render_mods("NONE"), "")
eq("m5 render_mods empty -> empty", M.render_mods(""), "")
eq("m6 render_mods single SUPER", M.render_mods("SUPER"), "SUPER")
eq("m7 render_mods all four", M.render_mods("SHIFT|ALT|CTRL|SUPER"), "SUPER+CTRL+ALT+SHIFT")

-- ── Regression: norm_mods / id_of keep the PIPE form (classify matching intact) ──
eq("r1 norm_mods keeps pipe form (classify identity)", M.norm_mods("SHIFT|CTRL"), "CTRL|SHIFT")
check("r2 id_of stays pipe-joined (no '+')",
  (function()
    local id = M.id_of({ key = "w", mods = "SHIFT|CTRL" })
    return id:find("|", 1, true) ~= nil and id:find("+", 1, true) == nil
  end)())

-- ── D-07 group_by_action (one row per action, reliable-chord-first) ──────────
-- An action reachable by [SUPER+w (arrives first), CTRL+SHIFT+w (arrives second)]
-- renders ONE row, CTRL+SHIFT+w FIRST (reliability rank wins over insertion order).
do
  local entries = {
    { key = "w", mods = "SUPER", action = "act.CloseCurrentTab", label = "setup", category = "Tabs" },
    { key = "w", mods = "CTRL|SHIFT", action = "act.CloseCurrentTab", label = "setup", category = "Tabs" },
  }
  local rows = M.group_by_action(entries)
  eq("g1 group collapses to ONE row", #rows, 1)
  eq("g1 group action preserved", rows[1].action, "act.CloseCurrentTab")
  eq("g1 group chord-list reliable-first (CTRL+SHIFT before SUPER)",
    rows[1].chords, "CTRL+SHIFT+w, SUPER+w")

  -- D-08 case-variant collapse: two records that canonicalize to the same (key,mods)
  -- → ONE rendered row (CTRL+SHIFT+z and CTRL+SHIFT+Z fold to one).
  local twins = {
    { key = "z", mods = "CTRL|SHIFT", action = "act.Foo", label = "setup", category = "Other" },
    { key = "Z", mods = "CTRL|SHIFT", action = "act.Foo", label = "setup", category = "Other" },
  }
  local trows = M.group_by_action(twins)
  eq("g2 D-08 case twins collapse to one row", #trows, 1)
  eq("g2 D-08 single chord (no duplicate)", trows[1].chords, "CTRL+SHIFT+z")

  -- Intra-class tie broken by ORIGINAL insertion order (two SUPER chords, never alpha).
  local ties = {
    { key = "b", mods = "SUPER", action = "act.Bar", label = "setup", category = "Other" },
    { key = "a", mods = "SUPER", action = "act.Bar", label = "setup", category = "Other" },
  }
  local tierows = M.group_by_action(ties)
  eq("g3 intra-class tie keeps insertion order (b before a)",
    tierows[1].chords, "SUPER+b, SUPER+a")
end

-- ── D-03/D-04 platform_label (SUPER -> Super/Cmd; all -> inline annotation) ──
eq("p1 platform_label SUPER linux -> Super+w", M.platform_label("w", "SUPER", "linux"), "Super+w")
eq("p2 platform_label SUPER macos -> Cmd+w", M.platform_label("w", "SUPER", "macos"), "Cmd+w")
eq("p3 platform_label SUPER all -> inline annotation",
  M.platform_label("w", "SUPER", "all"), "Cmd+w (macOS) / Super+w (Linux)")
eq("p4 platform_label non-Super chord is platform-invariant (linux)",
  M.platform_label("x", "ALT|SHIFT", "linux"), "ALT+SHIFT+x")
eq("p5 platform_label non-Super chord under all has NO annotation",
  M.platform_label("x", "ALT|SHIFT", "all"), "ALT+SHIFT+x")

-- ── D-06 color gate (PURE decision: --json / NO_COLOR / non-TTY -> false) ────
eq("cg1 --json -> no color", M.color_enabled({ json = true }, false, true), false)
eq("cg2 NO_COLOR set -> no color", M.color_enabled({}, true, true), false)
eq("cg3 non-TTY -> no color", M.color_enabled({}, false, false), false)
eq("cg4 plain TTY + no NO_COLOR + not json -> color", M.color_enabled({}, false, true), true)

-- ── D-06 conflict-row format (PINNED literal, all three args bound) ──────────
-- `("  ! %-16s %-30s %s\n"):format(chord, reason, "[CONFLICT]")`
-- chord "CTRL+SHIFT+w" (12) padded to 16 = 4 trailing spaces; reason "overridden"
-- (10) padded to 30 = 20 trailing spaces; then the literal "[CONFLICT]".
eq("cr1 conflict row pinned literal byte-exact",
  M.conflict_row("CTRL+SHIFT+w", "overridden"),
  "  ! CTRL+SHIFT+w     overridden                     [CONFLICT]\n")
-- cr2 asserts M.conflict_row as a GENERIC formatter only — `action-mismatch` is NOT a
-- live-reachable reason after 06.5-05 dropped that classify branch (the renderer now
-- emits only `overridden`). This pins the format string, not a reachable code path.
eq("cr2 conflict row action-mismatch reason",
  M.conflict_row("SUPER+k", "action-mismatch"),
  "  ! SUPER+k          action-mismatch                [CONFLICT]\n")

-- ── run()-level: section ordering, color/json gating, footnote (via fixtures) ──
-- Load the committed show-keys samples and drive run() with an injected color gate
-- so the test is deterministic regardless of the test host's TTY/env.
local function read_fixture(path)
  local fh = assert(io.open(path, "r"))
  local txt = fh:read("*a"); fh:close()
  return txt
end
local eff_text = read_fixture(repo_root .. "/tests/fixtures/showkeys_effective.lua")
local base_text = read_fixture(repo_root .. "/tests/fixtures/showkeys_baseline.lua")
local effective = showkeys.parse(eff_text)
local baseline = showkeys.parse_baseline(base_text)
check("f0 fixtures parse into non-empty record lists",
  #effective > 0 and #baseline > 0)

-- Synthetic "ours":
--  * `Enter`/`ALT` is present in BOTH the effective AND baseline fixtures, so it
--    classifies as `setup` (ours ∩ baseline ∩ effective) -> guarantees a non-empty
--    managed section + the Linux Super footnote.
--  * `zzz_absent`/`CTRL|SHIFT` is absent from the effective table -> a guaranteed
--    `overridden` conflict so the conflict section (and its red SGR) is exercised.
local ours_with_conflict = {
  { key = "Enter", mods = "ALT", action = { type = "ToggleFullScreen" } },
  { key = "zzz_absent", mods = "CTRL|SHIFT", action = { type = "Phantom" } },
}

-- D-05 ordering + footnote + color present on a TTY (color_force=true).
local _, out_tty = capture(function()
  return M.run({ platform = "linux", _ours = ours_with_conflict, _color_force = true,
    _effective_text = eff_text, _baseline_text = base_text })
end)
local mi = out_tty:find("== Managed %(overrides%) ==")
local di = out_tty:find("== WezTerm defaults ==")
check("f1 managed header appears", mi ~= nil)
check("f2 defaults header appears", di ~= nil)
check("f3 D-12 managed header BEFORE defaults header", mi and di and mi < di)
check("f4 Linux Super footnote present on linux",
  out_tty:find("Note: On Linux the Super key", 1, true) ~= nil)
check("f5 conflict row has red SGR \\27[31m on a TTY", out_tty:find("\27[31m", 1, true) ~= nil)
check("f6 conflict summary header bold-red \\27[1;31m on a TTY",
  out_tty:find("\27[1;31m", 1, true) ~= nil)
check("f7 conflict row has the ! prefix + [CONFLICT] token",
  out_tty:find("! ", 1, true) ~= nil and out_tty:find("[CONFLICT]", 1, true) ~= nil)

-- --json: NO SGR byte anywhere.
local _, out_json = capture(function()
  return M.run({ json = true, _ours = ours_with_conflict, _color_force = true,
    _effective_text = eff_text, _baseline_text = base_text })
end)
check("f8 --json output contains NO \\27[ byte", out_json:find("\27[", 1, true) == nil)

-- Color gate OFF (no TTY): plain text, no SGR even with conflicts present.
local _, out_plain = capture(function()
  return M.run({ platform = "linux", _ours = ours_with_conflict, _color_force = false,
    _effective_text = eff_text, _baseline_text = base_text })
end)
check("f9 no-TTY: conflicts present but NO \\27[ byte",
  out_plain:find("\27[", 1, true) == nil and out_plain:find("[CONFLICT]", 1, true) ~= nil)

-- macos platform: footnote OMITTED.
local _, out_mac = capture(function()
  return M.run({ platform = "macos", _ours = ours_with_conflict, _color_force = false,
    _effective_text = eff_text, _baseline_text = base_text })
end)
check("f10 macos platform OMITS the Linux Super footnote",
  out_mac:find("Note: On Linux the Super key", 1, true) == nil)

-- ═════════════════════════════════════════════════════════════════════════════
-- Plan 06.5-05 — canonical cross-source matching + three-group classify + true-
-- conflict-only filter (D-12 / D-13 / D-14-fix). These assertions pin the root-
-- cause id_of canonicalization and the renderer's three-section grouping.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── D-14-fix: id_of canonicalizes (case-fold letter base + implicit→explicit
-- SHIFT + mod normalization) so a letter chord we own matches the effective form ──
-- Our `mapped:x` + `ALT|SHIFT` MUST share an identity with the live `X` + `ALT`.
eq("id1 id_of canonical-folds: mapped:x/ALT|SHIFT == X/ALT",
  M.id_of({ key = "mapped:x", mods = "ALT|SHIFT" }),
  M.id_of({ key = "X", mods = "ALT" }))
-- And bare lowercase `x` + `ALT|SHIFT` (no mapped: prefix) folds to the same token.
eq("id2 id_of canonical-folds: x/ALT|SHIFT == X/ALT",
  M.id_of({ key = "x", mods = "ALT|SHIFT" }),
  M.id_of({ key = "X", mods = "ALT" }))
-- Digits/symbols/named keys still pass through unchanged (no spurious folding).
eq("id3 id_of digit 1/SUPER unchanged shape",
  M.id_of({ key = "1", mods = "SUPER" }), "1\0SUPER")
eq("id4 id_of named PageUp/CTRL|SHIFT unchanged shape",
  M.id_of({ key = "PageUp", mods = "CTRL|SHIFT" }), "PageUp\0CTRL|SHIFT")
-- A DIFFERENT letter must NOT collide.
check("id5 id_of does NOT over-fold: y/ALT|SHIFT != X/ALT",
  M.id_of({ key = "y", mods = "ALT|SHIFT" }) ~= M.id_of({ key = "X", mods = "ALT" }))
-- id_of still keeps the pipe form (no '+'), preserving the classify identity (r2 regression).
check("id6 id_of stays pipe-joined after fold (no '+')",
  (function()
    local id = M.id_of({ key = "X", mods = "ALT" })
    return id:find("|", 1, true) ~= nil and id:find("+", 1, true) == nil
  end)())

-- ── D-12 three-group classify keyed on (in_ours, in_base) ────────────────────
do
  -- effective: an ALT+SHIFT letter we own (folds from X/ALT) that is NOT a baseline
  -- default → must classify in_ours, label `added` (Our additions). A pure default
  -- (in_base, not ours) → label `default`. A foreign binding (neither) → `user`.
  local effective = {
    { key = "X", mods = "ALT", action = "act.CloseCurrentPane" },        -- ours ∖ base
    { key = "w", mods = "CTRL|SHIFT", action = "act.CloseCurrentTab" },  -- ours ∩ base
    { key = "F11", mods = "", action = "act.ToggleFullScreen" },         -- base, not ours
    { key = "q", mods = "CTRL", action = "act.QuitApplication" },        -- neither
  }
  local baseline = {
    { key = "w", mods = "CTRL|SHIFT", action = "act.CloseCurrentTab" },
    { key = "F11", mods = "", action = "act.ToggleFullScreen" },
  }
  local ours = {
    { key = "mapped:x", mods = "ALT|SHIFT", action = { type = "CloseCurrentPane" } },
    { key = "mapped:w", mods = "CTRL|SHIFT", action = { type = "CloseCurrentTab" } },
  }
  local entries = M.classify(effective, baseline, ours)
  local by_id = {}
  for _, e in ipairs(entries) do by_id[M.id_of(e)] = e end

  local x_entry = by_id[M.id_of({ key = "X", mods = "ALT" })]
  check("cl1 our ALT+SHIFT letter is recognized as ours (not [user])",
    x_entry ~= nil and x_entry.label ~= "user")
  eq("cl2 our addition (ours ∖ base) → group additions / label added",
    x_entry and x_entry.group, "additions")
  eq("cl3 our addition label is 'added'", x_entry and x_entry.label, "added")

  local w_entry = by_id[M.id_of({ key = "w", mods = "CTRL|SHIFT" })]
  eq("cl4 managed override (ours ∩ base) → group managed", w_entry and w_entry.group, "managed")
  eq("cl5 managed override label is 'setup'", w_entry and w_entry.label, "setup")

  local f_entry = by_id[M.id_of({ key = "F11", mods = "" })]
  eq("cl6 pure default (base ∖ ours) → group defaults", f_entry and f_entry.group, "defaults")
  eq("cl7 pure default label is 'default'", f_entry and f_entry.label, "default")

  local q_entry = by_id[M.id_of({ key = "q", mods = "CTRL" })]
  eq("cl8 foreign (neither) → group defaults", q_entry and q_entry.group, "defaults")
  eq("cl9 foreign label is 'user'", q_entry and q_entry.label, "user")
end

-- ── D-13 conflicts = true conflicts only ────────────────────────────────────
do
  local effective = {
    -- present (ours wins): a non-Super override we declare IS in effective.
    { key = "w", mods = "CTRL|SHIFT", action = "act.CloseCurrentTab" },
    -- present via canonical fold: our ALT+SHIFT letter shows as X/ALT live.
    { key = "X", mods = "ALT", action = "act.CloseCurrentPane" },
  }
  local baseline = {}
  local ours = {
    -- present → NOT a conflict (ours wins).
    { key = "mapped:w", mods = "CTRL|SHIFT", action = { type = "CloseCurrentTab" } },
    -- present after canonical fold → NOT a conflict.
    { key = "mapped:x", mods = "ALT|SHIFT", action = { type = "CloseCurrentPane" } },
    -- ABSENT + non-Super → TRUE conflict.
    { key = "mapped:Tab", mods = "CTRL", action = { type = "ActivateTabRelative" } },
    -- ABSENT but SUPER-bearing → SUPPRESSED (WM-grabbed; not a real conflict).
    { key = "mapped:t", mods = "SUPER", action = { type = "SpawnTab" } },
  }
  local _, conflicts = M.classify(effective, baseline, ours)
  local cset = {}
  for _, c in ipairs(conflicts) do cset[M.id_of(c)] = c end

  eq("cf1 exactly ONE true conflict", #conflicts, 1)
  check("cf2 the lone conflict is the absent NON-Super Tab/CTRL",
    cset[M.id_of({ key = "Tab", mods = "CTRL" })] ~= nil)
  check("cf3 present override (w) is NOT a conflict (ours wins)",
    cset[M.id_of({ key = "w", mods = "CTRL|SHIFT" })] == nil)
  check("cf4 present-after-fold (x) is NOT a false 'overridden' conflict",
    cset[M.id_of({ key = "X", mods = "ALT" })] == nil)
  check("cf5 absent SUPER chord is SUPPRESSED from conflicts",
    cset[M.id_of({ key = "t", mods = "SUPER" })] == nil)
  for _, c in ipairs(conflicts) do
    check("cf6 no conflict row carries SUPER",
      tostring(c.mods):find("SUPER", 1, true) == nil)
  end
end

-- ── D-12 run() renders THREE sections in order, against the live fixtures ─────
-- Drive run() with our REAL installed-shape bindings so the ALT+SHIFT letters land
-- under "Our additions", the CTRL+SHIFT overrides under "Managed (overrides)", and
-- everything else under "WezTerm defaults".
do
  local ours_real = {
    { key = "mapped:w", mods = "CTRL|SHIFT", action = { type = "CloseCurrentTab" } },   -- managed (ours ∩ base)
    { key = "mapped:x", mods = "ALT|SHIFT", action = { type = "CloseCurrentPane" } },   -- addition (X/ALT in eff)
    { key = "mapped:h", mods = "ALT|SHIFT", action = { type = "SplitHorizontal" } },    -- addition (H/ALT in eff)
    { key = "mapped:Tab", mods = "CTRL", action = { type = "ActivateTabRelative" } },   -- absent non-Super → conflict
    { key = "mapped:t", mods = "SUPER", action = { type = "SpawnTab" } },               -- absent SUPER → suppressed
  }
  local _, out = capture(function()
    return M.run({ platform = "linux", _ours = ours_real, _color_force = false,
      _effective_text = eff_text, _baseline_text = base_text })
  end)
  local mi = out:find("== Managed %(overrides%) ==")
  local ai = out:find("== Our additions ==")
  local di = out:find("== WezTerm defaults ==")
  check("s1 Managed (overrides) header present", mi ~= nil)
  check("s2 Our additions header present", ai ~= nil)
  check("s3 WezTerm defaults header present", di ~= nil)
  check("s4 section order Managed < Additions < Defaults",
    mi and ai and di and mi < ai and ai < di)
  check("s5 our ALT+SHIFT addition rendered under Our additions (ALT+SHIFT+x)",
    out:find("ALT+SHIFT+x", 1, true) ~= nil)
  -- conflicts: the absent non-Super Tab/CTRL is a true conflict; NO Super row.
  check("s6 a true non-Super conflict row is rendered",
    out:find("[CONFLICT]", 1, true) ~= nil)
  -- s7: scan every rendered line bearing [CONFLICT]; NONE may carry a Super chord.
  local super_conflict = false
  for line in out:gmatch("[^\n]+") do
    if line:find("[CONFLICT]", 1, true) and line:find("Super", 1, true) then
      super_conflict = true
    end
  end
  check("s7 NO conflict row carries Super (suppressed)", not super_conflict)
  -- the old single-section header MUST be gone (replaced by the three-group form).
  check("s8 old '== wezterm-setup (managed) ==' header removed",
    out:find("== wezterm%-setup %(managed%) ==") == nil)

  -- ── 06.5-05 refinement: chord-first dynamic-width row layout ───────────────
  -- Each rendered row is `  <chords>  [<tag>]  <action>` — chord BEFORE tag BEFORE
  -- action, two-space gutters, columns aligned PER SECTION. We assert (a) ordering
  -- on a single row, and (b) the action column starts at a consistent offset for two
  -- rows of differing chord-list length within the SAME section.

  -- (a) row ordering: chord precedes [tag] precedes action on a binding row.
  do
    local row_ok = false
    for line in out:gmatch("[^\n]+") do
      -- A binding row begins with two spaces + a chord (mods/key), carries a [tag]
      -- and an `act.`/action string; skip headers (`==`), conflicts (`!`), footnote.
      local ci, ti = line:find("%[%w+%]")  -- the bracketed tag, e.g. [setup]
      if ci and line:sub(1, 2) == "  " and not line:find("^  !") and line:find("==") == nil then
        local chord_start = line:find("%S")            -- first non-space (chord col)
        local action_start = line:find("act%.")        -- action col (declarative dump)
        if chord_start and action_start and chord_start < ci and (not action_start or action_start > (ti or 0)) then
          row_ok = true
        end
      end
    end
    check("s9 a binding row renders chord-first then [tag] then action", row_ok)
  end

  -- (b) column alignment within one section: collect the action-column offset of
  -- every binding row in the FIRST section (Managed) and assert they all match,
  -- regardless of differing chord-list widths.
  do
    -- Slice the Managed section: from its header to the next `==` header.
    local seg = out:sub(mi)
    local nxt = seg:find("\n== ", 5)
    if nxt then seg = seg:sub(1, nxt) end
    local offsets, lengths = {}, {}
    for line in seg:gmatch("[^\n]+") do
      if line:sub(1, 2) == "  " and not line:find("^  !") and line:find("==") == nil then
        local tag_start = line:find("%[%w+%]")
        local action_start = line:find("act%.")
        if tag_start and action_start then
          offsets[#offsets + 1] = action_start
          lengths[#lengths + 1] = line:find("%S") and (tag_start - line:find("%S")) or 0
        end
      end
    end
    local aligned = #offsets >= 1
    for i = 2, #offsets do
      if offsets[i] ~= offsets[1] then aligned = false end
    end
    check("s10 action column aligned across Managed rows (dynamic per-section width)",
      aligned and #offsets >= 1)
  end
end

io.write(string.format("\nkeys_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
