-- Fixture tests for cli/lib/scene.lua (pure scene-building helpers).
-- Run from the repo root: `lua5.4 cli/lib/scene_test.lua`
-- Pure: no wezterm / no I/O. Mirrors cli/lib/title_test.lua's check/eq harness.

local M = require("cli.lib.scene")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else
    fail = fail + 1
    io.stderr:write("FAIL: " .. name .. "\n")
  end
end
local function eq(name, got, want)
  check(name .. " (got " .. tostring(got) .. ")", got == want)
end

-- Recursive table comparison (==/eq only compares scalars / table identity).
-- Mirrors eq's structure but recurses into nested tables/arrays.
local function deep_eq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deep_eq(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end
-- Serialize a table for failure messages (1-level deep is enough for steps).
local function dump(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for k, val in pairs(v) do
    parts[#parts + 1] = tostring(k) .. "=" .. (type(val) == "table" and dump(val) or tostring(val))
  end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end
local function teq(name, got, want)
  check(name .. " (got " .. dump(got) .. ")", deep_eq(got, want))
end

-- ============================================================================
-- 1* plan_splits(layout, n) -> ordered array of split-step tables
-- ============================================================================

-- 1a N=1 special case (all 4 layouts) -> empty table {}
teq("1a plan_splits tall N=1", M.plan_splits("tall", 1), {})
teq("1b plan_splits tall:mirrored N=1", M.plan_splits("tall:mirrored", 1), {})
teq("1c plan_splits horizontal N=1", M.plan_splits("horizontal", 1), {})
teq("1d plan_splits grid N=1", M.plan_splits("grid", 1), {})

-- 1e tall N=3: main pane stays LEFT, so the first stack pane is sent RIGHT@50 of
-- pane 0 (wezterm --right -> new pane right, main stays left); then bottom@50 of pane 1.
-- (the right-side pane created by step 1; 100/(remaining=2)).
teq("1e plan_splits tall N=3", M.plan_splits("tall", 3), {
  { direction = "right", percent = 50, target = 0 },
  { direction = "bottom", percent = 50, target = 1 },
})

-- 1f tall:mirrored N=3: mirror of tall -> main pane on the RIGHT, so the first
-- stack pane is sent LEFT@50; stacking identical.
teq("1f plan_splits tall:mirrored N=3", M.plan_splits("tall:mirrored", 3), {
  { direction = "left", percent = 50, target = 0 },
  { direction = "bottom", percent = 50, target = 1 },
})

-- 1g horizontal N=4: exactly 3 steps, percents [25,33,50] (100/4,100/3,100/2),
-- each direction=right, each targeting the original un-split remainder (pane 0).
teq("1g plan_splits horizontal N=4", M.plan_splits("horizontal", 4), {
  { direction = "right", percent = 25, target = 0 },
  { direction = "right", percent = 33, target = 0 },
  { direction = "right", percent = 50, target = 0 },
})

-- 1h grid N=5: cols=3 rows=2. 1 row-band split (bottom@50) + col splits
-- (row1: 3 cols -> 2 splits [33,50]; row2: 5-3*1=2 cols -> 1 split [50]).
-- Total step count = 1 + 2 + 1 = 4. First step is the row-band split.
local g5 = M.plan_splits("grid", 5)
eq("1h grid N=5 step count == 4", #g5, 4)
teq("1i grid N=5 first step is row-band split", g5[1],
  { direction = "bottom", percent = 50, target = 0 })

-- 1j tall N=2: single split (no stacking; r=1 after step 1 means no further split).
-- main pane stays LEFT, so the one stack pane goes RIGHT@50.
teq("1j plan_splits tall N=2", M.plan_splits("tall", 2), {
  { direction = "right", percent = 50, target = 0 },
})

-- 1k horizontal N=2: single split right@50 of the original remainder (pane 0).
teq("1k plan_splits horizontal N=2", M.plan_splits("horizontal", 2), {
  { direction = "right", percent = 50, target = 0 },
})

-- 1l grid N=4 (perfect square): cols=2 rows=2. 1 row-band split + 1 col split
-- per row = 3 steps total. First step is the row-band split (bottom@50, pane 0).
local g4 = M.plan_splits("grid", 4)
eq("1l grid N=4 step count == 3", #g4, 3)
teq("1l2 grid N=4 first step is row-band split", g4[1],
  { direction = "bottom", percent = 50, target = 0 })

-- ============================================================================
-- 2* parse_pane_spec(spec) -> {cmd, color, title, shell}
-- ============================================================================

-- 2a bare command form (no '=')
teq("2a parse bare htop", M.parse_pane_spec("htop"),
  { cmd = "htop", color = nil, title = nil, shell = false })
-- 2b literal keyword 'shell' (D-04)
teq("2b parse shell keyword", M.parse_pane_spec("shell"),
  { cmd = nil, color = nil, title = nil, shell = true })
-- 2c full key=value form
teq("2c parse cmd+color+title", M.parse_pane_spec("cmd=htop,color=red,title=Monitor"),
  { cmd = "htop", color = "red", title = "Monitor", shell = false })
-- 2d order-independent key=value
teq("2d parse order-independent", M.parse_pane_spec("color=blue,cmd=htop"),
  { cmd = "htop", color = "blue", title = nil, shell = false })
-- 2e value containing spaces; only the FIRST '=' splits key from value
teq("2e parse value with spaces", M.parse_pane_spec("title=Logs,cmd=tail -f app.log"),
  { cmd = "tail -f app.log", color = nil, title = "Logs", shell = false })
-- 2f empty string -> bare command form with cmd="" (the zero-`--pane`-flags
-- empty-state error is a 04-02/04-03 concern, NOT a single empty spec here).
teq("2f parse empty spec -> bare cmd=''", M.parse_pane_spec(""),
  { cmd = "", color = nil, title = nil, shell = false })
-- 2g whitespace after commas is trimmed (the readable D-06 form must parse):
-- 'cmd=docker stats, color=teal, title=stats' — spaces around keys/values ignored.
teq("2g parse spaced D-06 form", M.parse_pane_spec("cmd=docker stats, color=teal, title=stats"),
  { cmd = "docker stats", color = "teal", title = "stats", shell = false })

-- ============================================================================
-- 2.5* parse_pane_spec gains cwd / focus / size (D-05/D-06/D-07)
-- ============================================================================

-- 2h cwd/focus/size carried alongside cmd/color (raw cwd kept; resolution is the
-- IO-shell's job). focus coerces "true"->true, size coerces "30"->30 (integer).
teq("2h parse cwd+focus+size",
  M.parse_pane_spec("cmd=top, color=teal, cwd=~/x, focus=true, size=30"),
  { cmd = "top", color = "teal", title = nil, cwd = "~/x", focus = true, size = 30, shell = false })

-- 2i a plain shell pane still parses unchanged (cwd/focus/size absent -> nil).
teq("2i parse shell still unchanged", M.parse_pane_spec("shell"),
  { cmd = nil, color = nil, title = nil, shell = true })

-- 2i2 STYLED shell pane (06.1-07): `cmd=shell, color=...` means a plain shell
-- pane (no command sent) that ALSO carries styling — D-13/D-14's teal working
-- shell. The cmd=shell is demoted to shell=true so no nested `shell` startup
-- line runs, while color survives so the OSC-11 tint applies. WITHOUT this the
-- seed loader would silently drop the teal on every shell pane.
teq("2i2 parse cmd=shell, color=teal -> styled shell",
  M.parse_pane_spec("cmd=shell, color=teal"),
  { cmd = nil, color = "teal", title = nil, shell = true })

-- 2j cwd alone (literal absolute) is carried raw.
teq("2j parse cwd alone", M.parse_pane_spec("cmd=vim, cwd=/srv/app"),
  { cmd = "vim", color = nil, title = nil, cwd = "/srv/app", focus = nil, size = nil, shell = false })

-- 2k focus absent -> nil (NOT false); only an explicit focus=true sets it true.
do
  local p = M.parse_pane_spec("cmd=htop")
  check("2k focus absent is nil", p ~= nil and p.focus == nil)
end

-- 2l size lower bound: size=1 accepted (integer 1).
teq("2l parse size=1 ok", M.parse_pane_spec("cmd=x, size=1"),
  { cmd = "x", color = nil, title = nil, cwd = nil, focus = nil, size = 1, shell = false })
-- 2m size upper bound: size=100 accepted.
teq("2m parse size=100 ok", M.parse_pane_spec("cmd=x, size=100"),
  { cmd = "x", color = nil, title = nil, cwd = nil, focus = nil, size = 100, shell = false })

-- 2n size out of range / non-integer -> validate-before-emit error.
do
  local res, err = M.parse_pane_spec("cmd=x, size=0")
  check("2n size=0 rejected (nil result)", res == nil)
  eq("2n2 size=0 message", err,
    "error: invalid --pane value 'cmd=x, size=0' — size must be an integer 1..100")
  res, err = M.parse_pane_spec("cmd=x, size=101")
  check("2o size=101 rejected", res == nil and err ~= nil)
  res, err = M.parse_pane_spec("cmd=x, size=abc")
  check("2p size=abc rejected", res == nil and err ~= nil)
end

-- 2q unknown key error now lists the EXTENDED allowed set (cmd/color/title/cwd/focus/size).
do
  local res, err = M.parse_pane_spec("cmd=htop, bogus=1")
  check("2q unknown key returns nil", res == nil)
  eq("2q2 unknown key message lists extended set", err,
    "error: invalid --pane value 'cmd=htop, bogus=1' — unknown key 'bogus' (expected cmd, color, title, cwd, focus, size)")
end

-- ============================================================================
-- 2.6* validate_focus(parsed_list) — at most ONE focus=true pane (D-05)
-- ============================================================================
do
  -- zero focus panes -> ok
  local ok = M.validate_focus({ { focus = nil }, { focus = nil } })
  check("2r validate_focus zero focus ok", ok == true)
  -- exactly one focus pane -> ok
  ok = M.validate_focus({ { focus = true }, { focus = nil } })
  check("2s validate_focus one focus ok", ok == true)
  -- two focus panes -> error (validate-before-emit)
  local ok2, err = M.validate_focus({ { focus = true }, { focus = true } })
  check("2t validate_focus two focus rejected", ok2 == false)
  eq("2t2 validate_focus message", err,
    "error: more than one pane marked focus=true")
end

-- ============================================================================
-- 2.7* size_percent(parsed, default_pct) — size overrides the equal-share step
-- ============================================================================
do
  eq("2u size_percent uses parsed.size when set",
    M.size_percent({ size = 30 }, 50), 30)
  eq("2v size_percent falls back to default when size nil",
    M.size_percent({ size = nil }, 50), 50)
  eq("2w size_percent default when parsed nil",
    M.size_percent(nil, 33), 33)
end

-- ============================================================================
-- 3* validate_layout(name)
-- ============================================================================
do
  local ok, err = M.validate_layout("tall")
  check("3a validate_layout tall ok", ok == true and err == nil)
  ok, err = M.validate_layout("tall:mirrored")
  check("3b validate_layout tall:mirrored ok", ok == true and err == nil)
  ok, err = M.validate_layout("grid")
  check("3c validate_layout grid ok", ok == true and err == nil)
  ok, err = M.validate_layout("horizontal")
  check("3d validate_layout horizontal ok", ok == true and err == nil)
  ok, err = M.validate_layout("bogus")
  check("3e validate_layout bogus rejected", ok == false)
  eq("3e2 validate_layout bogus message", err,
    "error: unknown layout 'bogus' — expected one of: tall, tall:mirrored, grid, horizontal")
end

-- ============================================================================
-- 4* validate_color(name)  (case-insensitive; echoes original case in error)
-- ============================================================================
do
  local ok, err = M.validate_color("RED")
  check("4a validate_color RED (case-insensitive) ok", ok == true and err == nil)
  for _, c in ipairs({ "red", "orange", "yellow", "green", "teal", "cyan", "blue", "navy", "purple", "pink" }) do
    local cok, cerr = M.validate_color(c)
    check("4b validate_color " .. c .. " ok", cok == true and cerr == nil)
  end
  ok, err = M.validate_color("mauve")
  check("4c validate_color mauve rejected", ok == false)
  eq("4c2 validate_color mauve message", err,
    "error: unknown color 'mauve' — expected one of: red, orange, yellow, green, teal, cyan, blue, navy, purple, pink")
end

-- ============================================================================
-- 5* parse_pane_spec unknown-key error (echoes ORIGINAL full spec + offending key)
-- ============================================================================
do
  local res, err = M.parse_pane_spec("cmd=htop,foo=bar")
  check("5a unknown key returns nil result", res == nil)
  eq("5b unknown key message", err,
    "error: invalid --pane value 'cmd=htop,foo=bar' — unknown key 'foo' (expected cmd, color, title, cwd, focus, size)")
end

-- ============================================================================
-- 6* validate_pane_id / validate_tab_id (integer coercion + range)
-- ============================================================================
do
  local ok, v = M.validate_pane_id(42)
  check("6a validate_pane_id 42 (number) -> true,42", ok == true and v == 42)
  ok, v = M.validate_pane_id("42")
  check("6b validate_pane_id '42' (string) -> true,42", ok == true and v == 42)
  ok, v = M.validate_pane_id("abc")
  check("6c validate_pane_id 'abc' -> false,nil", ok == false and v == nil)
  ok, v = M.validate_pane_id(3.5)
  check("6d validate_pane_id 3.5 -> false,nil", ok == false and v == nil)
  ok, v = M.validate_pane_id(nil)
  check("6e validate_pane_id nil -> false,nil", ok == false and v == nil)
  ok, v = M.validate_pane_id("")
  check("6f validate_pane_id '' -> false,nil", ok == false and v == nil)
  -- validate_tab_id shares the same contract.
  ok, v = M.validate_tab_id("10")
  check("6g validate_tab_id '10' -> true,10", ok == true and v == 10)
end

-- ============================================================================
-- 7* decide_materialization(panes, current_pane_id, n) (D-10/D-11)
-- ============================================================================
do
  -- current tab has exactly 1 pane -> reuse (D-10)
  teq("7a decide reuse (1-pane tab)",
    M.decide_materialization({ { pane_id = 1, tab_id = 10 } }, 1, 1),
    { mode = "reuse", target_tab_id = 10, first_pane_id = 1 })
  -- current tab has >=2 panes -> new-tab (D-11)
  teq("7b decide new-tab (2-pane tab)",
    M.decide_materialization({ { pane_id = 1, tab_id = 10 }, { pane_id = 2, tab_id = 10 } }, 1, 3),
    { mode = "new-tab", target_tab_id = nil, first_pane_id = nil })
end

-- ============================================================================
-- 8* M.LAYOUTS single source of truth (04-03): the 4 closed layout names, in
-- display order, consumed by BOTH validate_layout and the scene-layouts
-- completion context (cli/commands/complete.lua). No second literal copy.
-- ============================================================================
teq("8a M.LAYOUTS exact contents/order", M.LAYOUTS,
  { "tall", "tall:mirrored", "grid", "horizontal" })
do
  -- validate_layout must accept EVERY name in M.LAYOUTS (proves it derives from
  -- the same set, not an independent copy that could drift).
  local all_ok = true
  for _, name in ipairs(M.LAYOUTS) do
    local ok = M.validate_layout(name)
    if ok ~= true then all_ok = false end
  end
  check("8b validate_layout accepts every M.LAYOUTS name", all_ok)
  -- A name NOT in M.LAYOUTS is rejected.
  local ok = M.validate_layout("diagonal")
  check("8c validate_layout rejects a name not in M.LAYOUTS", ok == false)
end

io.write(string.format("\nscene_test: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
