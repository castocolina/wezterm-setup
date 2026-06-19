-- tests/docs_drift_test.lua
--
-- DURABLE documentation drift-check (Phase 06.4, D-08/D-09). This is the
-- verification backbone for the whole documentation phase: it enumerates the
-- project's REAL source surface (subcommands, flags, keybinding chords, scene
-- layouts/colors/fields) PROGRAMMATICALLY from the source-of-truth modules, then
-- scans the governed docs (README.md + every focused docs/*.md page that exists)
-- and asserts every DOCUMENTED token references something that EXISTS in source.
--
-- Direction is documented -> exists ONLY (D-09): a doc that names a nonexistent
-- command/flag/keybinding/scene-field FAILS the suite. It deliberately does NOT
-- assert the reverse (that every source surface must appear in the docs) — what
-- to document is an authoring choice, not a test concern.
--
-- Zero-config discovery (D-08): the file is named `*_test.lua` under `tests/`, so
-- `tools/run-tests.sh` finds it via `find ... -name '*_test.lua'` and `make test`
-- runs it. NO Makefile / runner edit is required.
--
-- Runnable directly: `lua5.4 tests/docs_drift_test.lua`.
--
-- The enumerators are DERIVED FROM SOURCE (never a hardcoded list), mirroring the
-- spec-driven discipline of tests/cli/completions_test.lua:61-65 — adding a
-- subcommand / layout / color / scene field automatically extends the check.

-- Make `cli/...`, the vendored deps, AND `keybindings` (which lives under
-- config/wezterm-setup/) requireable regardless of invocation CWD. This file is
-- directly under tests/, so repo_root is one level up (NOT two like tests/cli/).
local this_dir = (arg and arg[0] or ""):match("^(.*)/[^/]-$") or "."
local repo_root = this_dir .. "/.." -- tests/ -> repo root
package.path = table.concat({
  repo_root .. "/?.lua",
  repo_root .. "/cli/vendor/?.lua",
  repo_root .. "/config/wezterm-setup/?.lua", -- so require("keybindings") resolves
  package.path,
}, ";")

local passed, failed = 0, 0
local function check(label, ok, detail)
  if ok then
    passed = passed + 1
    print(string.format("  ok   - %s", label))
  else
    failed = failed + 1
    print(string.format("  FAIL - %s%s", label, detail and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

local spec = require("cli.spec")
local scene = require("cli.lib.scene")
local keys = require("cli.commands.keys")

-- ============================================================================
-- SOURCE-SURFACE ENUMERATORS (derived programmatically — never hardcoded lists)
-- ============================================================================

-- source_subcommands() -> set of the registered subcommand names from
-- spec.subcommand_names(), MINUS the hidden internal __complete (never a
-- user-documentable token). Derived from the REAL spec, so it grows with it.
local function source_subcommands()
  local hidden = { ["__complete"] = true }
  local set = {}
  for _, n in ipairs(spec.subcommand_names()) do
    if not hidden[n] then set[n] = true end
  end
  return set
end

-- flag_accepts(argv) -> true iff the documented invocation `argv` parses cleanly
-- against the REAL spec parser (spec.build_parser():pparse). A registered flag
-- (e.g. {"keys","--platform","linux"}) -> true; an unregistered one
-- (e.g. {"tab","color","blue","--bogus"}) -> false. Same acceptance/rejection
-- idiom cli/spec_test.lua uses, so the check follows the spec, not a literal list.
local function flag_accepts(argv)
  local parser = spec.build_parser()
  -- argparse's `--help` action calls os.exit(0) on the WHOLE process; a documented
  -- `wez <cmd> --help` example (e.g. docs/cli.md) would otherwise silently terminate
  -- this test mid-scan with exit 0 (a false PASS). Sandbox os.exit around the parse:
  -- a help/usage exit is caught and treated as ACCEPTED (--help is a universally valid
  -- flag), while genuine parse failures still come back false via pparse.
  local real_exit = os.exit
  local help_exited = false
  os.exit = function() help_exited = true; error("__drift_sandboxed_exit__", 0) end
  local pok, ok = pcall(function() return parser:pparse(argv) end)
  os.exit = real_exit
  if help_exited then return true end
  if not pok then return false end
  return ok == true
end

-- Normalize a DOCUMENTED chord (human "+"-joined form like "Ctrl+Shift+W",
-- "Super+K", "Alt+Shift+R") into the SAME canonical identity the keybindings
-- data uses. We REUSE the exported keys.id_of (which already chains
-- norm_key + canonicalize_key + norm_mods); we only translate the human mod
-- labels (Ctrl/Shift/Alt/Super/Cmd) to the WezTerm tokens and lowercase a
-- single-letter base key so the documented capital-letter label (e.g. "Super+K")
-- maps to the lowercase data entry without spuriously implying SHIFT.
local DOC_MOD_TOKEN = {
  Ctrl = "CTRL", Shift = "SHIFT", Alt = "ALT", Super = "SUPER", Cmd = "SUPER",
}
local function doc_chord_id(chord)
  local parts = {}
  for tok in chord:gmatch("[^+]+") do parts[#parts + 1] = tok end
  if #parts == 0 then return nil end
  local key = parts[#parts]
  parts[#parts] = nil
  -- A bare single ASCII letter label means "that letter key"; lowercase it so the
  -- uppercase doc convention ("Super+K") matches the lowercase data entry. An
  -- explicit Shift modifier still adds SHIFT through canonicalize via the mods.
  if key:match("^%a$") then key = key:lower() end
  local mods = {}
  for _, m in ipairs(parts) do
    mods[#mods + 1] = DOC_MOD_TOKEN[m] or m:upper()
  end
  return keys.id_of({ key = key, mods = table.concat(mods, "|") })
end

-- source_chords() -> set of canonical chord identities for every entry in
-- require("keybindings").keys, built via the EXPORTED keys.id_of (strips the
-- `mapped:` prefix, case-folds the letter base, normalizes mod order). So a
-- documented `Ctrl+Shift+W` matches the `mapped:w` + `CTRL|SHIFT` data entry
-- regardless of mod order or the prefix.
local function source_chords()
  local kb = require("keybindings") -- module table; `keys` is a TOP-LEVEL field
  local set = {}
  for _, e in ipairs(kb.keys) do
    set[keys.id_of(e)] = true
  end
  return set
end

-- source_layouts() / source_colors() -> the closed enumerations straight from
-- scene.lua's single-source arrays (D-16), so "what validates" == "what the doc
-- may name".
local function source_layouts()
  local set = {}
  for _, name in ipairs(scene.LAYOUTS) do set[name] = true end
  return set
end

local function source_colors()
  local set = {}
  for _, name in ipairs(scene.COLOR_NAMES) do set[name] = true end
  return set
end

-- source_scene_fields() -> the union of the per-pane field keys that
-- scene.parse_pane_spec actually parses (derived by probing the parser with a
-- spec exercising every field, NOT a frozen literal) plus the recipe-level
-- aliases and tab-level fields the recipe/spec layer accepts. `command` is the
-- TOML alias for `cmd` (recipe.lua), and `shell` is the synthetic post-parse
-- boolean the parser sets — both are legitimate documented field names.
local function source_scene_fields()
  local set = {}
  -- Probe parse_pane_spec with a spec naming every per-pane field so the field
  -- set is read back from the parser's own result keys, not hardcoded.
  local parsed = scene.parse_pane_spec(
    "cmd=top, color=teal, title=stats, cwd=~, icon=python, focus=true, size=40")
  assert(type(parsed) == "table", "parse_pane_spec probe must succeed")
  for k in pairs(parsed) do set[k] = true end
  -- `shell` is a synthetic flag the parser sets for shell panes; surface it by
  -- probing the `shell` keyword form so it is read from a real parse too.
  local sh = scene.parse_pane_spec("shell")
  assert(type(sh) == "table", "parse_pane_spec('shell') must succeed")
  for k in pairs(sh) do set[k] = true end
  -- Recipe/TOML aliases + tab-level fields (recipe.lua / spec tab namespace).
  -- `command` is the TOML alias for cmd; layout/follow_pane_color are tab-level.
  set["command"] = true
  set["layout"] = true
  set["follow_pane_color"] = true
  return set
end

-- Count members of a set (for non-empty self-tests).
local function set_count(s)
  local n = 0
  for _ in pairs(s) do n = n + 1 end
  return n
end

-- ============================================================================
-- TASK 1 SELF-TESTS: prove every enumerator is non-empty and derived from source
-- before the doc scanner (Task 2) is wired on top of them.
-- ============================================================================

local SUBCOMMANDS = source_subcommands()
local CHORDS = source_chords()
local LAYOUTS = source_layouts()
local COLORS = source_colors()
local SCENE_FIELDS = source_scene_fields()

check("source_subcommands() is non-empty", set_count(SUBCOMMANDS) > 0,
  "count=" .. set_count(SUBCOMMANDS))
check("source_subcommands() excludes hidden __complete", SUBCOMMANDS["__complete"] == nil)
check("source_subcommands() includes a known command (doctor)", SUBCOMMANDS["doctor"] == true)
check("source_subcommands() includes scene", SUBCOMMANDS["scene"] == true)

check("source_chords() is non-empty", set_count(CHORDS) > 0, "count=" .. set_count(CHORDS))
check("source_chords() contains Ctrl+Shift+W (close tab)",
  CHORDS[doc_chord_id("Ctrl+Shift+W")] == true)
check("source_chords() contains Super+K (clear)",
  CHORDS[doc_chord_id("Super+K")] == true)

check("source_layouts() is non-empty", set_count(LAYOUTS) > 0, "count=" .. set_count(LAYOUTS))
check("source_layouts() contains tall", LAYOUTS["tall"] == true)
check("source_colors() is non-empty", set_count(COLORS) > 0, "count=" .. set_count(COLORS))
check("source_colors() contains green", COLORS["green"] == true)

check("source_scene_fields() is non-empty", set_count(SCENE_FIELDS) > 0,
  "count=" .. set_count(SCENE_FIELDS))
check("source_scene_fields() contains cmd", SCENE_FIELDS["cmd"] == true)
check("source_scene_fields() contains size", SCENE_FIELDS["size"] == true)
check("source_scene_fields() contains icon", SCENE_FIELDS["icon"] == true)
check("source_scene_fields() contains command alias", SCENE_FIELDS["command"] == true)

-- flag_accepts: a registered flag parses; an unregistered one is rejected. This
-- proves the parse-driven predicate fires in both directions before Task 2 feeds
-- documented invocations through it.
check("flag_accepts true for registered {keys,--platform,linux}",
  flag_accepts({ "keys", "--platform", "linux" }) == true)
check("flag_accepts true for registered {tab,color,blue,--title,api}",
  flag_accepts({ "tab", "color", "blue", "--title", "api" }) == true)
check("flag_accepts false for unregistered {tab,color,blue,--bogus}",
  flag_accepts({ "tab", "color", "blue", "--bogus" }) == false)

-- ============================================================================
-- TASK 2: GOVERNED-DOC SCANNER + documented-to-exists assertions
-- ============================================================================

-- governed_docs() -> list of { path, text } for every doc file under audit that
-- EXISTS at run time: README.md (always) plus every focused docs/*.md page. In
-- Wave 1 the focused pages do not exist yet, so an absent optional page is simply
-- skipped (NOT a failure) — the check is valid on whatever governed docs DO exist.
local GOVERNED_DOC_PATHS = {
  "README.md",
  -- Focused pages Plan 03 writes; tolerated-if-absent in Wave 1.
  "docs/cli.md",
  "docs/scenes.md",
  "docs/keybindings.md",
  "docs/install.md",
  "docs/troubleshooting.md",
}
local function read_file(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local text = fh:read("*a")
  fh:close()
  return text
end
local function governed_docs()
  local docs = {}
  for _, rel in ipairs(GOVERNED_DOC_PATHS) do
    local text = read_file(repo_root .. "/" .. rel)
    if text then
      docs[#docs + 1] = { path = rel, text = text }
    end
  end
  return docs
end

-- A documented token is only a COMMAND CLAIM when it appears in a command context:
-- inside an inline `backtick span` or as a line in a fenced ``` code block. Prose
-- mentions (e.g. "the wez binary" in a comment) are NOT command invocations and
-- must not be validated as subcommands. We therefore collect command-context
-- spans first, and extract tokens only from those.
--
-- Returns a list of { text, doc, line } command-context fragments.
local function command_spans(doc)
  local spans = {}
  local lineno = 0
  local in_fence = false
  for line in (doc.text .. "\n"):gmatch("(.-)\n") do
    lineno = lineno + 1
    local fence = line:match("^%s*```")
    if fence then
      in_fence = not in_fence
    elseif in_fence then
      -- Whole line of a fenced block is a command context.
      spans[#spans + 1] = { text = line, doc = doc.path, line = lineno }
    else
      -- Outside a fence: only the contents of inline `backtick spans`.
      for span in line:gmatch("`([^`]+)`") do
        spans[#spans + 1] = { text = span, doc = doc.path, line = lineno }
      end
    end
  end
  return spans
end

-- Extract documented `wez <subcommand>` tokens from a command span. Only the FIRST
-- word after `wez` is the subcommand (pane/tab/scene nest further, but their first
-- token is the registered top-level subcommand the allow-list owns). Shell
-- comments inside a fence (a `#`-led line) are ignored.
local function extract_subcommands(span)
  local out = {}
  local text = span.text
  -- Drop a shell-comment tail so `# keep wez binary` is not read as a command.
  text = text:gsub("#.*$", "")
  for sub in text:gmatch("wez%s+([a-z][a-z-]*)") do
    out[#out + 1] = sub
  end
  return out
end

-- Reconstruct a `wez <cmd> ... --flag ...` argv from a fenced/inline command span
-- so flag_accepts can validate it against the real parser. We tokenize on
-- whitespace, drop the leading `wez`, and stop at a shell-comment `#`. Quoted
-- values are collapsed to a single placeholder token so the parser sees a value,
-- not split words. Returns nil when the span is not a `wez ...` invocation.
local function span_to_argv(span)
  local text = span.text:gsub("#.*$", "")
  if not text:match("wez%s") then return nil end
  -- Keep only from the first `wez` onward.
  text = text:gsub("^.-(wez%s)", "%1")
  local argv = {}
  -- Replace quoted strings with a single bareword placeholder VALUE.
  text = text:gsub('"[^"]*"', "VALUE"):gsub("'[^']*'", "VALUE")
  for tok in text:gmatch("%S+") do
    argv[#argv + 1] = tok
  end
  if argv[1] ~= "wez" then return nil end
  table.remove(argv, 1) -- drop the leading `wez`
  return argv
end

-- Extract documented keybinding chords from a doc's keybinding table rows. A chord
-- is a "+"-joined token of mod labels + a final key (e.g. `Ctrl+Shift+W`,
-- `Alt+Shift+R`, `Super+K`). We only consider chords whose pieces are ALL known
-- mod labels or a plain key, and whose base key is ASCII (arrow-glyph chords like
-- `Alt+←` map to named keys `LeftArrow`/`RightArrow` and are normalized/skipped
-- here — they're validated via the named-key data, not the glyph).
local KNOWN_MOD = { Ctrl = true, Shift = true, Alt = true, Super = true, Cmd = true }
local function looks_like_chord(token)
  if not token:find("+", 1, true) then return false end
  local parts = {}
  for p in token:gmatch("[^+]+") do parts[#parts + 1] = p end
  if #parts < 2 then return false end
  -- Every part except the last must be a known modifier label.
  for i = 1, #parts - 1 do
    if not KNOWN_MOD[parts[i]] then return false end
  end
  -- Base key must be a bare ASCII letter/word (skip glyphs like ← and punctuation
  -- we cannot normalize to a data key here).
  local key = parts[#parts]
  return key:match("^%a$") ~= nil or key:match("^%a%w*$") ~= nil
end
local function extract_chords(span)
  local out = {}
  for token in span.text:gmatch("[%w]+%+[%w%+]+") do
    if looks_like_chord(token) then out[#out + 1] = token end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Drive the documented tokens through the Task-1 enumerators (documented ->
-- exists). One check() per token, labelled with doc path + line so a failure
-- points at the exact offending reference.
-- ---------------------------------------------------------------------------
local docs = governed_docs()
check("governed_docs() finds at least README.md", #docs > 0, "#docs=" .. #docs)

for _, doc in ipairs(docs) do
  local spans = command_spans(doc)

  -- Subcommands: each documented `wez <cmd>` must be a registered subcommand.
  for _, span in ipairs(spans) do
    for _, sub in ipairs(extract_subcommands(span)) do
      check(
        string.format("%s:%d documents real subcommand `wez %s`", span.doc, span.line, sub),
        SUBCOMMANDS[sub] == true,
        "not a registered subcommand")
    end
  end

  -- Flags: each reconstructable `wez <cmd> ... --flag ...` invocation must parse.
  for _, span in ipairs(spans) do
    local argv = span_to_argv(span)
    if argv and #argv >= 1 and SUBCOMMANDS[argv[1]] then
      -- Only assert when the invocation names at least one flag (a flag claim).
      local has_flag = false
      for _, a in ipairs(argv) do
        if a:match("^%-%-") then has_flag = true break end
      end
      if has_flag then
        check(
          string.format("%s:%d documents an accepted invocation `wez %s`",
            span.doc, span.line, table.concat(argv, " ")),
          flag_accepts(argv) == true,
          "spec parser rejected this documented invocation")
      end
    end
  end

  -- Chords: each documented chord must exist in the keybinding data.
  for _, span in ipairs(spans) do
    for _, chord in ipairs(extract_chords(span)) do
      local id = doc_chord_id(chord)
      check(
        string.format("%s:%d documents real keybinding `%s`", span.doc, span.line, chord),
        id ~= nil and CHORDS[id] == true,
        "chord not present in keybindings.lua")
    end
  end
end

-- ---------------------------------------------------------------------------
-- Scene fenced-TOML scan: any `field =` key inside a ```toml block, and any
-- `--layout <name>` / `--color <name>` value in a documented scene command, must
-- be a real scene field / layout / color. The TOML field keys are validated
-- against source_scene_fields(); layout/color VALUES against the enums.
-- ---------------------------------------------------------------------------
local function toml_blocks(doc)
  local blocks = {}
  local in_toml = false
  local lineno = 0
  local cur
  for line in (doc.text .. "\n"):gmatch("(.-)\n") do
    lineno = lineno + 1
    local open = line:match("^%s*```%s*toml%s*$")
    local close = line:match("^%s*```%s*$")
    if open then
      in_toml = true
      cur = { start = lineno, lines = {} }
    elseif in_toml and close then
      in_toml = false
      blocks[#blocks + 1] = cur
      cur = nil
    elseif in_toml then
      cur.lines[#cur.lines + 1] = { text = line, line = lineno }
    end
  end
  return blocks
end

for _, doc in ipairs(docs) do
  for _, block in ipairs(toml_blocks(doc)) do
    for _, l in ipairs(block.lines) do
      -- A top-level `key = value` or `[[panes]]`/`[panes]` header.
      local key = l.text:match("^%s*([%w_]+)%s*=")
      if key then
        check(
          string.format("%s:%d documents real scene field `%s`", doc.path, l.line, key),
          SCENE_FIELDS[key] == true,
          "not a parsed scene field")
      end
    end
  end

  -- --layout / --color VALUES in documented scene commands.
  for _, span in ipairs(command_spans(doc)) do
    local lay = span.text:match("%-%-layout%s+([%w:]+)")
    if lay then
      check(
        string.format("%s:%d documents real layout `%s`", doc.path, span.line, lay),
        LAYOUTS[lay] == true, "not a real layout")
    end
    local col = span.text:match("%-%-color%s+([%w]+)")
    if col then
      check(
        string.format("%s:%d documents real color `%s`", doc.path, span.line, col),
        COLORS[col] == true, "not a real color")
    end
  end
end

-- ---------------------------------------------------------------------------
-- fires_on_bad_reference (D-09 FIRING PROOF): feed a fabricated bad subcommand,
-- a bad `--flag` argv, a bad chord, and a bad scene field through the SAME
-- predicates the real scan uses, and assert each is REJECTED. This is the durable
-- proof that the drift-check actually FAILS on a planted nonexistent reference —
-- not merely that the real docs happen to pass. Direction stays documented ->
-- exists ONLY: there is NO assertion that a source surface must appear in a doc.
do
  check("fires: bad subcommand `wez frobnicate` is rejected",
    SUBCOMMANDS["frobnicate"] ~= true)
  check("fires: bad invocation `wez tab color blue --bogusflag` is rejected",
    flag_accepts({ "tab", "color", "blue", "--bogusflag" }) == false)
  check("fires: bad chord `Ctrl+Alt+Q` is rejected",
    CHORDS[doc_chord_id("Ctrl+Alt+Q")] ~= true)
  check("fires: bad scene field `nonexistent_field` is rejected",
    SCENE_FIELDS["nonexistent_field"] ~= true)
  check("fires: bad layout `octopus` is rejected", LAYOUTS["octopus"] ~= true)
  check("fires: bad color `chartreuse` is rejected", COLORS["chartreuse"] ~= true)
end

-- ============================================================================
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
