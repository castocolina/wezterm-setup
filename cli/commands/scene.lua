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
--                              (mode=new-tab), then run plan_splits steps. Each
--                              spawn/split passes `--cwd <resolved>` so the pane
--                              opens DIRECTLY in its target dir with NO visible
--                              `cd` line (D-08 clean pane); a per-pane `size=`
--                              overrides the equal-share `--percent` (D-06). Every
--                              pane id read back from mux output is int-validated
--                              via scenelib.validate_pane_id BEFORE it is ever
--                              interpolated into a later command line (T-04-01).
--   2b. Phase A styling     : per-pane OSC-11 background + OSC-1337 title (reusing
--                              pane.lua's builders + MUTED_BG, never re-derived) +
--                              a ScrollbackAndViewport clear are delivered as the
--                              spawn PRELUDE — every pane is launched as
--                              `<shell> -c 'printf "<octal>"; exec "$SHELL" -l'` so
--                              the OSC bytes are emitted as PROGRAM OUTPUT (parsed
--                              by the terminal) BEFORE the interactive shell starts,
--                              then the pane becomes the user's login shell. This
--                              avoids the interactive shell's line editor that
--                              caused both the printf-leak and the blank-pane hang
--                              (07.1-scene-prelude). Tab-level WEZTERM_TAB_COLOR
--                              rides every pane's prelude (D-02/D-03/D-04).
--   3. Phase B (cmd)         : the startup command as a DISTINCT send-text line
--                              (never concatenated into an escape sequence —
--                              T-04-02); a reused pane (no spawn -> no prelude) also
--                              gets its styling here via per-escape self-erasing
--                              printf. The tab title is PURE text via set-tab-title
--                              — no `<color>:<title>` encoding.
--   4. Focus                 : activate-pane on the focus=true pane if any, else
--                              the layout's main pane (pane 1) — D-05.
--
-- Reuse discipline (no re-derived palettes / encodings / resolvers — D-01):
--   * per-pane background hex   -> panelib.MUTED_BG  (same table as `wez pane color`)
--   * OSC builders              -> panelib.build_osc11 / build_osc1337
--   * cwd grammar resolution     -> cwdlib.resolve / cwdlib.validate (ONE resolver)
--   * title resolution          -> titlelib.resolve_title_str (shared D-03 resolver)
--   * pure-text tab title sink   -> tablib.write_tab_title

local M = {}

local scenelib = require("cli.lib.scene")
local recipelib = require("cli.lib.recipe")
local panelib = require("cli.commands.pane")
local tablib = require("cli.commands.tab")
local titlelib = require("cli.lib.title")
local cwdlib = require("cli.lib.cwd")

-- IN-02: shquote + decode_json live ONCE in cli/lib/shell.lua now (the
-- security-sensitive escaper must be single-sourced, shared with tab.lua). Local
-- aliases keep the call sites below unchanged. EVERY user-derived string passed to
-- os.execute / io.popen flows through shquote.
local shelllib = require("cli.lib.shell")
local shquote = shelllib.shquote
local decode_json = shelllib.decode_json

-- ---------------------------------------------------------------------------
-- cwd IO-shell boundary (D-07/D-08): the PURE cli/lib/cwd resolver needs the
-- launch dir + an env snapshot, both of which are process state living ONLY here.
--   * launch_dir = the CLI process $PWD (RESEARCH Open Q1) — the directory the
--     user ran `wez scene new/launch` from. Each pane inherits it unless a cwd=
--     overrides (D-07).
--   * env snapshot = the variables the cwd grammar may reference ($NAME / ~).
--     We snapshot HOME + every $NAME the values actually reference lazily via
--     os.getenv at validate/resolve time (cwd.validate/resolve read env[NAME]).
-- A tiny metatable-backed table defers os.getenv so cwd.lua stays pure while the
-- IO-shell owns the single os.getenv trust boundary.
-- ---------------------------------------------------------------------------
local function launch_dir()
  return os.getenv("PWD") or "."
end

local function env_snapshot()
  return setmetatable({}, { __index = function(_, k) return os.getenv(k) end })
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

-- The throwaway interpreter for the spawn prelude (`<shell> -c '...'`). This only
-- runs the one-shot `printf <octal>; exec "$SHELL" -l` body — the LASTING pane
-- shell is the user's interactive login shell exec'd by the body's `exec
-- "$SHELL"`. We resolve $SHELL here so the prelude interpreter matches the user's
-- shell where possible, falling back to /bin/sh (always present; POSIX printf +
-- exec). os.getenv is the IO trust boundary, so this lives in the IO-shell.
local function prelude_shell()
  local sh = os.getenv("SHELL")
  if sh and sh ~= "" then return sh end
  return "/bin/sh"
end

-- Render the spawn-prelude PROG argv (from M.build_pane_spawn_command) into a
-- shquoted ` -- <shell> <-c> <body>` suffix appended to a `wezterm cli
-- spawn`/`split-pane` command line. Every argv element is shquote'd individually
-- (T-04-02 / T-04-01): the body carries octal-only printf bytes + a fixed exec,
-- and nothing user-derived is concatenated raw into it.
local function prelude_suffix(escapes)
  local argv = M.build_pane_spawn_command(escapes, prelude_shell())
  local parts = { "--" }
  for _, a in ipairs(argv) do
    parts[#parts + 1] = shquote(a)
  end
  return " " .. table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------
-- M.build_pane_escapes(spec_parsed, opts) -> array of escape strings.
--
-- PURE (no io/os/mux) per-pane escape builder, extracted from the Phase B loop so
-- the split carriers (D-03/D-07/D-09) and the per-pane cwd-basename title fallback
-- (D-12/D-13) are unit-testable WITHOUT a live session. Every value still flows
-- through panelib.build_osc1337 (base64) so a malicious recipe value cannot break
-- out of the escape (T-06.2-08), and NO new emitter / resolver / basename is
-- defined — it reuses titlelib.resolve_icon + titlelib.fallback_title + the OSC
-- builders. The caller octal-renders this array into the SAME self-erasing printf.
--
-- opts fields (the tab-level carriers ride EVERY pane so the tab identity is
-- stable regardless of which pane is focused — format-tab-title reads the ACTIVE
-- pane's user_vars):
--   tab_color_value  : tab's own color name (lowercased) or nil (-> WEZTERM_TAB_COLOR).
--   tab_icon_value   : tab's resolved icon GLYPH or nil; a pane with no own icon
--                      falls back to it (-> WEZTERM_TAB_ICON) so a glyph always renders.
--   follow_pane_color: truthy -> emit WEZTERM_TAB_FOLLOW_PANE="1" (D-09).
--   ldir             : launch dir for the {cwd} expand + the empty-title basename.
-- ---------------------------------------------------------------------------
function M.build_pane_escapes(spec_parsed, opts)
  opts = opts or {}
  local ldir = opts.ldir
  local escapes = {}

  -- Per-pane OSC-11 muted background (reuse pane.lua's MUTED_BG + build_osc11;
  -- never a re-derived hex). color was already validated upstream.
  local resolved_color = nil
  if spec_parsed.color ~= nil then
    resolved_color = tostring(spec_parsed.color):lower()
    local hex = panelib.MUTED_BG[resolved_color]
    if hex then
      escapes[#escapes + 1] = panelib.build_osc11(hex)
    end
  end

  -- D-03: resolve the per-pane icon ONCE (name -> glyph, or literal pass-through)
  -- via the shared resolver. Used by BOTH the icon emit and the icon-aware
  -- empty-title fallback (D-13) so a pane shows `<glyph> <basename>` consistently.
  local resolved_icon = nil
  if spec_parsed.icon ~= nil and tostring(spec_parsed.icon) ~= "" then
    resolved_icon = titlelib.resolve_icon(spec_parsed.icon)
  elseif opts.tab_icon_value ~= nil and opts.tab_icon_value ~= "" then
    -- Tab-icon fallback (D-03): a pane with no own icon inherits the tab-level
    -- icon (already resolved to a glyph by the caller). format-tab-title reads
    -- the ACTIVE pane's WEZTERM_TAB_ICON, so without this the tab's identity
    -- glyph would vanish whenever a pane that set no icon is focused — the tab
    -- icon must ride every pane to render consistently.
    resolved_icon = opts.tab_icon_value
  end

  -- Title: explicit title= wins (D-11); else derive an auto-title from the startup
  -- command's first word. Both go through the shared resolver so icon-name
  -- shortcuts behave exactly like `wez pane title`.
  local title_str = nil
  if spec_parsed.title ~= nil then
    title_str = titlelib.resolve_title_str(spec_parsed.title)
  elseif spec_parsed.cmd ~= nil and not spec_parsed.shell then
    local first_word = tostring(spec_parsed.cmd):match("%S+")
    if first_word then
      title_str = titlelib.resolve_title_str(first_word)
    end
  end
  -- {cwd} token (shell-free): expand to the launch dir basename (D-08).
  if title_str ~= nil then
    title_str = titlelib.expand_cwd(title_str, ldir)
  end
  -- D-12/D-13: a pane whose resolved title is empty self-labels by its launch-dir
  -- basename via the SHARED fallback_title (icon-aware: `<glyph> <basename>` when
  -- the pane carries an icon). An explicit non-empty title is returned unchanged.
  -- Reuse the SAME ldir as the rest of the pane setup — no re-derived basename.
  local emit_title = titlelib.fallback_title(title_str or "", resolved_icon, ldir)
  if emit_title ~= nil and emit_title ~= "" then
    escapes[#escapes + 1] = panelib.build_osc1337("WEZTERM_TAB_TITLE", emit_title)
  end

  -- D-03: per-pane icon carrier. Folded into the same self-erasing printf line so
  -- it leaves no standalone scrollback line. base64'd (T-06.2-08).
  if resolved_icon ~= nil and resolved_icon ~= "" then
    escapes[#escapes + 1] = panelib.build_osc1337("WEZTERM_TAB_ICON", resolved_icon)
  end

  -- D-07: a per-pane color accent writes WEZTERM_PANE_COLOR (split from the tab's
  -- own WEZTERM_TAB_COLOR). format-tab-title reads it for the active-pane accent.
  if resolved_color ~= nil then
    escapes[#escapes + 1] = panelib.build_osc1337("WEZTERM_PANE_COLOR", resolved_color)
  end

  -- Tab-level accent (D-07: WEZTERM_TAB_COLOR) + the follow opt-in carrier (D-09)
  -- ride EVERY pane, not just pane 1. WezTerm's format-tab-title reads the ACTIVE
  -- pane's user_vars, so a tab color / follow carrier emitted on pane 1 alone
  -- disappears the instant another pane is focused, flipping the tab to neutral
  -- (the "tab color permutes with the panes" defect). Emitting the tab's own
  -- identity on every pane keeps it stable across focus changes; the per-pane
  -- WEZTERM_PANE_COLOR above is still distinct (used only when following).
  if opts.tab_color_value ~= nil then
    escapes[#escapes + 1] = panelib.build_osc1337("WEZTERM_TAB_COLOR", opts.tab_color_value)
  end
  -- D-09: follow_pane_color emits the LOCKED carrier WEZTERM_TAB_FOLLOW_PANE="1"
  -- (W3). Default OFF -> nothing emitted when unset.
  if opts.follow_pane_color then
    escapes[#escapes + 1] = panelib.build_osc1337("WEZTERM_TAB_FOLLOW_PANE", "1")
  end

  return escapes
end

-- ---------------------------------------------------------------------------
-- M.build_pane_spawn_command(escapes, shell_path) -> PROG argv {shell, "-c", body}.
--
-- PURE (no io/os/mux) builder for the styling-delivery SPAWN PRELUDE. Returns the
-- PROG argv that EVERY pane (the initial spawn AND each split) is launched with:
-- a NON-interactive `<shell> -c '<body>'` whose body
--   1. emits the pane's styling OSC bytes via ONE octal `printf '<octal>'` — run
--      as the spawned PROGRAM, so the bytes go to the program's STDOUT and are
--      parsed by the TERMINAL's output parser; then
--   2. `exec "$SHELL" -l` — replaces the prelude process with the user's
--      interactive LOGIN shell, so the pane ends up a normal working shell.
--
-- WHY a spawn prelude and NOT `send-text` into the interactive shell
-- (07.1-scene-prelude): the prior delivery typed `printf '<octal>'` into the
-- pane's freshly-spawned INTERACTIVE shell. That runs the bytes through the
-- shell's LINE EDITOR (zsh's zle / bash's readline), which is racy on a
-- not-yet-ready shell — and BOTH prior attempts failed live there:
--   * one giant ~1.1KB printf  -> the closing `'`+newline was lost, zsh stranded
--     at `quote>`, and the literal `printf '...'` leaked into the pane.
--   * one printf PER escape (53a49cf, SUPERSEDED) -> broke the single
--     self-erasing printf's clean-pane property; the pane showed a BLANK/FROZEN
--     screen (a hang).
-- Emitting the OSC as the SPAWNED PROGRAM'S OUTPUT bypasses the line editor
-- entirely: no typing, no race, no `quote>`, no hang, no leak. Proven in a plain
-- shell: `sh -c 'printf "<octal>"; exec "$SHELL" -l'` emits the OSC then gives a
-- clean working login shell.
--
-- The octal idiom is UNCHANGED (\%03o per byte -> pure printable ASCII, no raw
-- ESC, no shell quoting; printf '\nnn' octal works in bash & zsh). The
-- self-erasing clean-pane behavior is preserved: the caller appends
-- CLEAR_SCROLLBACK_AND_VIEWPORT as the LAST escape, so the printf's own (here
-- nonexistent, since it's program output not a typed line) echo plus any banner
-- is wiped (viewport + scrollback + cursor home) and the pane starts clean.
--
-- `exec "$SHELL"` (the spawned shell's OWN $SHELL env var), not the build-time
-- shell_path: shell_path only chooses the throwaway prelude interpreter; the
-- pane's lasting shell must be the user's configured login shell. shell_path nil
-- -> /bin/sh (always present, POSIX printf + exec).
-- ---------------------------------------------------------------------------
function M.build_pane_spawn_command(escapes, shell_path)
  local shell = (shell_path ~= nil and shell_path ~= "") and shell_path or "/bin/sh"
  local body
  if escapes and #escapes > 0 then
    local octal = (table.concat(escapes):gsub(".", function(c)
      return string.format("\\%03o", string.byte(c))
    end))
    -- printf (program output -> terminal parser) THEN hand the pane to the user's
    -- interactive login shell. The `;` sequences them in one POSIX -c body.
    body = "printf '" .. octal .. "'; exec \"$SHELL\" -l"
  else
    -- No styling for this pane: still exec the interactive login shell so the
    -- pane is a normal working shell (the prelude is total).
    body = "exec \"$SHELL\" -l"
  end
  return { shell, "-c", body }
end

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

  -- Validate every cwd value (per-pane + tab-level) BEFORE any mux call (D-08
  -- clean-pane needs the resolved cwd at spawn, so a bad cwd must bail here with
  -- ZERO panes built — T-06.1-08). cwdlib.validate rejects $(...)/backticks and
  -- unset $ENV references; the env snapshot is the process env.
  local env = env_snapshot()
  for i = 1, #parsed do
    if parsed[i].cwd ~= nil then
      local ok_cwd, cwd_err = cwdlib.validate(parsed[i].cwd, env)
      if not ok_cwd then
        io.stderr:write(cwd_err .. "\n")
        return 2
      end
    end
  end
  if args.cwd ~= nil then
    local ok_tab_cwd, tab_cwd_err = cwdlib.validate(args.cwd, env)
    if not ok_tab_cwd then
      io.stderr:write(tab_cwd_err .. "\n")
      return 2
    end
  end

  -- D-05: at most ONE pane may carry focus=true (validate-before-emit). >1 bails
  -- with ZERO mux calls.
  local ok_focus, focus_err = scenelib.validate_focus(parsed)
  if not ok_focus then
    io.stderr:write(focus_err .. "\n")
    return 2
  end

  local n = #parsed

  -- =========================================================================
  -- Step 1: TOPOLOGY READ + materialization decision.
  -- =========================================================================
  local panes = M.read_topology()
  -- WR-05: distinguish a legitimate "not in a pane" (WEZTERM_PANE unset -> a fresh
  -- new-tab build is the right default) from "in a pane but WEZTERM_PANE is garbage"
  -- (a non-numeric value silently degrades to new-tab, masking a real environment
  -- problem when the user expected an in-place reuse build). Only the latter gets a
  -- one-line note so the soft-degrade is auditable (the project's verify-don't-assume
  -- posture); an unset var stays silent.
  local raw_pane = os.getenv("WEZTERM_PANE")
  local current_pane_id = tonumber(raw_pane)
  if raw_pane ~= nil and raw_pane ~= "" and current_pane_id == nil then
    io.stderr:write(string.format(
      "warning: WEZTERM_PANE is set but not a valid pane id (%q); "
      .. "building a new tab instead of reusing the current pane\n", raw_pane))
  end
  local plan = scenelib.decide_materialization(panes, current_pane_id, n)

  -- =========================================================================
  -- Step 2: PHASE A -- spawn/split only. Build the pane_ids array (creation
  -- order, 1-based: pane_ids[1] = original/main pane, pane_ids[k+1] = pane
  -- created by the k-th split). EVERY id is an int already validated by either
  -- decide_materialization (first_pane_id) or run_capture_pane_id (T-04-01).
  -- =========================================================================
  local pane_ids = {}

  -- D-07/D-08: resolve each pane's cwd to an ABSOLUTE path here (the only place
  -- with the launch dir + env). A pane that omits cwd inherits the tab-level cwd
  -- (args.cwd) and ultimately the launch dir. The resolved path is passed to the
  -- spawn/split `--cwd` so the pane opens DIRECTLY in it (no visible `cd` line).
  local ldir = launch_dir()
  local tab_cwd_value = args.cwd -- tab-level default (may be nil -> launch dir)
  local function resolved_cwd_for(idx)
    local raw = parsed[idx] and parsed[idx].cwd or tab_cwd_value
    return cwdlib.resolve(raw, ldir, env)
  end

  -- ---------------------------------------------------------------------------
  -- Pre-compute each pane's styling escapes BEFORE Phase A (07.1-scene-prelude):
  -- the styling OSC bytes are now delivered as the spawn PRELUDE (program output),
  -- so they must be known at spawn time, not in a later send-text. This is PURE
  -- (build_pane_escapes) and depends only on already-validated values.
  -- ---------------------------------------------------------------------------
  -- Tab accent (D-02/D-03): WEZTERM_TAB_COLOR rides every pane's prelude (folded
  -- into the escapes below). Resolved once; scene colors are names-only + already
  -- validated.
  local tab_color_value = nil
  if args.color ~= nil then
    tab_color_value = tostring(args.color):lower()
  end
  -- D-03: resolve the tab-level icon ONCE to a glyph. Panes that set no icon of
  -- their own inherit it (build_pane_escapes), so the tab's identity glyph rides
  -- every pane and renders no matter which pane is focused.
  local tab_icon_value = nil
  if args.icon ~= nil and tostring(args.icon) ~= "" then
    tab_icon_value = titlelib.resolve_icon(args.icon)
  end

  -- The same ScrollbackAndViewport wipe the Ctrl+Shift+K binding performs: ED
  -- viewport (\27[2J) + ED scrollback (\27[3J) + cursor home (\27[H). Appended
  -- LAST to every pane's escapes so the prelude self-erases any banner/echo and
  -- the pane starts clean (D-09 clean-pane).
  local CLEAR_SCROLLBACK_AND_VIEWPORT = "\27[2J\27[3J\27[H"

  -- escapes_by_idx[i] = the styling escapes for parsed pane i, with the CLEAR
  -- appended last. Always non-empty (the CLEAR is always present), so every pane
  -- gets a styling prelude.
  local escapes_by_idx = {}
  for i = 1, n do
    local spec_parsed = parsed[i]
    local escapes = M.build_pane_escapes(spec_parsed, {
      tab_color_value = tab_color_value,
      tab_icon_value = tab_icon_value,
      follow_pane_color = args.follow_pane_color,
      ldir = ldir,
    })
    escapes[#escapes + 1] = CLEAR_SCROLLBACK_AND_VIEWPORT
    escapes_by_idx[i] = escapes
  end

  if plan.mode == "reuse" then
    -- Pane 1 already exists (the current pane), opened in the launch dir. D-07's
    -- default IS the launch dir, so a reused pane with no explicit cwd is already
    -- correct; no spawn happens, so no `--cwd` can be applied to it. The reused
    -- pane already runs an interactive shell, so its styling cannot ride a spawn
    -- prelude — it is delivered via the per-escape send-text fallback in Phase B
    -- (a reused pane is the user's CURRENT shell, already past the line-editor
    -- race that broke fresh spawns; one printf per escape is safe here).
    pane_ids[1] = plan.first_pane_id
  else
    -- new-tab: a spawn makes a new tab in the SAME window (D-11/D-12), opened
    -- DIRECTLY in pane 1's resolved cwd (D-08 clean pane), and prints the new id.
    -- The spawn PRELUDE (D-09): the pane is launched as `<shell> -c 'printf
    -- "<octal>"; exec "$SHELL" -l'` so the OSC bytes are emitted as program output
    -- (never typed into a line editor) and the pane then becomes the user's
    -- interactive login shell. --cwd still applies so the pane opens in its dir.
    local pid, spawn_err = run_capture_pane_id(
      "wezterm cli spawn --cwd " .. shquote(resolved_cwd_for(1))
      .. prelude_suffix(escapes_by_idx[1]))
    if not pid then
      io.stderr:write((spawn_err or "error: spawn failed") .. "\n")
      return 1
    end
    pane_ids[1] = pid
  end

  -- Apply the layout's split plan. plan_splits targets are creation-order indices
  -- (original pane = 0), so target t maps to pane_ids[t + 1]. The k-th split step
  -- creates the pane whose parsed index is (#pane_ids + 1) at that moment, so its
  -- cwd (D-07) and size override (D-06) come from that parsed entry.
  for _, step in ipairs(scenelib.plan_splits(args.layout, n)) do
    local target_pid = pane_ids[(step.target or 0) + 1]
    local flag = DIR_FLAG[step.direction]
    if not flag or not target_pid then
      io.stderr:write("error: internal split plan produced an invalid step\n")
      return 1
    end
    local new_idx = #pane_ids + 1
    -- D-06: an explicit size= on the new pane overrides the equal-share percent.
    local pct = scenelib.size_percent(parsed[new_idx], tonumber(step.percent) or 50)
    -- D-08: the split pane opens DIRECTLY in its resolved cwd (clean pane).
    -- D-09 (07.1-scene-prelude): the split carries the SAME spawn prelude as the
    -- initial spawn — `-- <shell> -c 'printf "<octal>"; exec "$SHELL" -l'` — so its
    -- styling OSC is emitted as program output (no line-editor race) and the pane
    -- becomes the user's interactive login shell.
    local cmd = string.format(
      "wezterm cli split-pane --pane-id %d %s --percent %d --cwd %s",
      target_pid, flag, pct, shquote(resolved_cwd_for(new_idx)))
      .. prelude_suffix(escapes_by_idx[new_idx])
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
  -- Step 3: PHASE B -- per-pane STARTUP COMMAND (+ the reuse pane's styling).
  -- Strict two-phase: runs only AFTER all of Phase A completed (Pitfall 2).
  --
  -- 07.1-scene-prelude: the styling OSC for every SPAWNED pane was already
  -- emitted by the spawn PRELUDE (program output, before the interactive shell)
  -- in Phase A — it is NO LONGER typed into the interactive shell here. Phase B's
  -- remaining job is:
  --   1. (reuse pane only) deliver the reused pane's styling. A reused pane is the
  --      user's CURRENT, already-ready interactive shell — it was not spawned, so
  --      it has no prelude — but it is also past the line-editor race that broke
  --      fresh spawns. Its styling is delivered as one short self-erasing `printf
  --      '<octal>'` PER escape (each well under 1KB; the CLEAR appended last wipes
  --      the echoes). This is the ONLY send-text styling path left.
  --   2. (every pane) the STARTUP COMMAND, as a DISTINCT short send-text line
  --      `<cmd>\n` — small and safe (NOT the giant OSC payload), delivered the
  --      same way as before. NEVER concatenated into an escape/OSC string
  --      (prevents OSC injection/breakout — T-04-02). A `shell` pane gets none.
  -- =========================================================================
  local reuse_pane1 = (plan.mode == "reuse")

  for i = 1, #pane_ids do
    local pid = pane_ids[i]
    local spec_parsed = parsed[i]
    if spec_parsed then
      -- 1. Reused pane 1's styling via per-escape self-erasing printf (the only
      --    pane without a spawn prelude). escapes_by_idx already has the CLEAR
      --    appended last. Octal-encode each escape into its own short printf so no
      --    single typed line overflows the interactive shell's line editor.
      if reuse_pane1 and i == 1 then
        local pane1_escapes = escapes_by_idx[1] or {}
        for _, esc in ipairs(pane1_escapes) do
          local octal = (esc:gsub(".", function(c)
            return string.format("\\%03o", string.byte(c))
          end))
          os.execute(string.format(
            "wezterm cli send-text --pane-id %d --no-paste %s",
            pid, shquote("printf '" .. octal .. "'\n")))
        end
      end

      -- 2. Startup command (D-04): a DISTINCT short line, NEVER folded into an
      --    escape sequence (T-04-02). A `shell` pane sends nothing.
      local has_cmd = spec_parsed.cmd ~= nil and not spec_parsed.shell
      if has_cmd then
        os.execute(string.format(
          "wezterm cli send-text --pane-id %d --no-paste %s",
          pid, shquote(tostring(spec_parsed.cmd) .. "\n")))
      end
    end
  end

  -- =========================================================================
  -- Tab-level styling (D-02/D-03/D-04): the scene tab accent rides
  -- WEZTERM_TAB_COLOR via OSC (NO `<color>:<title>` prefix encoding) and the tab
  -- title is written as PURE text via set-tab-title. scene.lua NO LONGER depends
  -- on the legacy color:title encoding (the dead tablib.merge_title builder was
  -- removed in IN-03). Only runs when a tab-level --color or --title was given.
  -- =========================================================================
  if args.color ~= nil or args.title ~= nil then
    -- COLOR (D-02/D-03): the WEZTERM_TAB_COLOR accent rides EVERY pane's spawn
    -- prelude (folded into escapes_by_idx above via tab_color_value), emitted as
    -- program output — NOT a separate post-spawn send-text, which would leave a
    -- `printf '...'` line in a pane's scrollback. format-tab-title reads the
    -- active pane's WEZTERM_TAB_COLOR.

    -- TITLE: pure resolved text via set-tab-title --tab-id (no color prefix, no
    -- read-modify-write). Reuses tab.lua's write_tab_title sink + the shared
    -- title resolver. Resolve the target tab id from the built pane 1.
    if args.title ~= nil then
      local target_tab_id = plan.target_tab_id
      if target_tab_id == nil then
        -- The new-tab path leaves plan.target_tab_id nil because the tab did not
        -- exist at decide_materialization time. pane_ids[1] here is the NEWLY
        -- spawned pane (absent from the pre-spawn topology), so resolving its tab
        -- genuinely requires a POST-spawn read — the cached pre-spawn `panes`
        -- cannot contain it (WR-04: the reuse path already has target_tab_id, so
        -- this is the ONE remaining read, not a redundant duplicate of line ~334).
        for _, p in ipairs(M.read_topology()) do
          if p.pane_id == pane_ids[1] then
            target_tab_id = p.tab_id
          end
        end
      end
      if target_tab_id ~= nil then
        -- {cwd} token expands to the launch dir basename (shell-free, D-08).
        local tab_title = titlelib.expand_cwd(
          titlelib.resolve_title_str(args.title), ldir)
        tablib.write_tab_title(tab_title, target_tab_id)
      else
        -- WR-04: make the silent drop observable. When neither the plan nor the
        -- post-spawn topology yields the new tab's id (race / mux quirk), the
        -- requested --title cannot be applied; surface a one-line note instead of
        -- building the scene mute so the dropped title is auditable.
        io.stderr:write(
          "warning: could not resolve the new tab id; --title was not applied\n")
      end
    end
  end

  -- =========================================================================
  -- Step 4: FOCUS (D-05). Activate the pane explicitly marked focus=true if one
  -- exists (validate_focus already guaranteed at most one); otherwise default to
  -- the layout's main pane (pane 1 in all 4 layouts).
  -- =========================================================================
  local focus_pid = pane_ids[1]
  for i = 1, #pane_ids do
    if parsed[i] and parsed[i].focus == true then
      focus_pid = pane_ids[i]
      break
    end
  end
  if focus_pid ~= nil then
    os.execute("wezterm cli activate-pane --pane-id " .. tostring(focus_pid))
  end

  -- D-09 / UI-SPEC: success is silent on stdout.
  return 0
end

-- ---------------------------------------------------------------------------
-- M.scenes_dir() -> the user's co-located scenes dir (D-04). The ONE resolver
-- shared by `scene launch` (this file), completion (05-04), and the seeder
-- (05-02) — Pitfall 6: a second resolver would let completion advertise a
-- recipe launch resolves to a different dir. Ports uninstall_state's
-- default_setup_dir env precedence, appending /scenes:
--   WEZTERM_SETUP_DIR (dogfood/test override) -> /scenes
--   WEZTERM_CONFIG_DIR                         -> /wezterm-setup/scenes
--   XDG_CONFIG_HOME/wezterm                    -> /wezterm-setup/scenes
--   ~/.config/wezterm                          -> /wezterm-setup/scenes
-- ---------------------------------------------------------------------------
function M.scenes_dir()
  local setup = os.getenv("WEZTERM_SETUP_DIR")
  if setup and setup ~= "" then return setup .. "/scenes" end
  local cfg = os.getenv("WEZTERM_CONFIG_DIR")
  if cfg and cfg ~= "" then return cfg .. "/wezterm-setup/scenes" end
  local xdg = os.getenv("XDG_CONFIG_HOME")
  if xdg and xdg ~= "" then return xdg .. "/wezterm/wezterm-setup/scenes" end
  local home = os.getenv("HOME") or ""
  return home .. "/.config/wezterm/wezterm-setup/scenes"
end

-- ---------------------------------------------------------------------------
-- M.list_recipe_names(dir) -> { <basename-without-ext>, ... } (sorted).
-- The SINGLE provider feeding BOTH shell completion (05-04) and the launch
-- error-hint block below (single source of truth). Globs the dir via the
-- shipped `newest_backup` io.popen("ls -1") idiom (the path is shquote'd so a
-- metacharacter cannot break out), keeps only `*.toml`, strips the extension,
-- and sorts. A missing or empty dir returns {} (no error — the Tab-time and
-- empty-state contracts depend on this).
-- ---------------------------------------------------------------------------
function M.list_recipe_names(dir)
  local names = {}
  if not dir or dir == "" then return names end
  local fh = io.popen("ls -1 -- " .. shquote(dir) .. " 2>/dev/null")
  if not fh then return names end
  for entry in fh:lines() do
    local base = entry:match("^(.+)%.toml$")
    if base then names[#names + 1] = base end
  end
  fh:close()
  table.sort(names)
  return names
end

-- ---------------------------------------------------------------------------
-- Emit the available-recipes hint block (UI-SPEC row 122) to stderr: the
-- `available recipes:` header, one `  - <name>` line per recipe (sorted, from
-- the SAME single-provider M.list_recipe_names), and a `try:` suggestion using
-- the first name. Caller guarantees #names > 0.
-- ---------------------------------------------------------------------------
local function emit_recipe_hint(names)
  io.stderr:write("available recipes:\n")
  for _, n in ipairs(names) do
    io.stderr:write("  - " .. n .. "\n")
  end
  io.stderr:write("try: wez scene launch " .. names[1] .. "\n")
end

-- The user-facing display path for the scenes dir in error copy (UI-SPEC).
local DISPLAY_SCENES_DIR = "~/.config/wezterm/wezterm-setup/scenes/"

-- The actionable recovery line shared by every no-recipes state (UI-SPEC rows
-- 119/120): points at the REAL reseed command (`wez seed-scenes`, the
-- copy-if-absent path) rather than a vague "reinstall". Indented guidance, never
-- carries its own `error:` prefix — so a caller that already emitted an `error:`
-- line stays at ONE `error:` token per invocation.
local function emit_seed_hint()
  io.stderr:write("  run: wez seed-scenes to restore the seeded examples (ai, docker, dev)\n")
end

-- The no-recipes ERROR (UI-SPEC row 120): emitted when a NAME was given but the
-- scenes dir is missing or holds no `.toml`. Here the missing recipes ARE the
-- primary failure, so it leads with `error:`; the no-name path instead leads
-- with its own usage error and appends only emit_seed_hint() (one `error:`).
local function emit_no_recipes()
  io.stderr:write("error: no scene recipes found in " .. DISPLAY_SCENES_DIR .. "\n")
  emit_seed_hint()
end

-- ---------------------------------------------------------------------------
-- M.run_launch(args) -> exit code. The SCEN-04 structural-equivalence seam:
-- a thin IO-shell that resolves the scenes dir, guards the name, reads
-- <name>.toml, hands the RAW STRING to the PURE cli/lib/recipe.lua (parse +
-- validate + map), then delegates to the SAME M.run_new the `scene new` path
-- uses (D-03: build NOTHING new — no argv, no subprocess, no re-implemented
-- geometry/palette/OSC). Validate-before-emit: every error path exits BEFORE
-- any mux call, so a bad launch builds ZERO panes.
--   args.name : the recipe basename (without .toml).
-- ---------------------------------------------------------------------------
function M.run_launch(args)
  args = args or {}
  local name = args.name
  local dir = M.scenes_dir()
  local names = M.list_recipe_names(dir)

  -- 1. No name given -> usage error (exit 2). When recipes exist, append the
  --    available-recipes hint; otherwise the no-recipes guidance.
  if not name or name == "" then
    -- The usage error is the SINGLE `error:` line for this invocation. When no
    -- recipes exist we append only the seed-hint guidance line (I-1) — NOT a
    -- second `error: no scene recipes found` line, which would double the
    -- `error:` token for one failure.
    io.stderr:write("error: wez scene launch requires a recipe name (got none)\n")
    if #names > 0 then
      emit_recipe_hint(names)
    else
      emit_seed_hint()
    end
    return 2
  end

  -- 2. Guard the name BEFORE any io.open (T-05-08 path-traversal block, T-05-01
  --    from 05-01): rejects empty/`/`/`..` so a name with a separator never
  --    reaches the filesystem. The resolved path is always <scenes_dir>/<name>.toml.
  local guard_ok, guard_err = recipelib.guard_name(name)
  if not guard_ok then
    io.stderr:write("error: " .. guard_err .. "\n")
    return 1
  end

  -- 3. No recipes present at all -> no-recipes guidance (exit 2).
  if #names == 0 then
    emit_no_recipes()
    return 2
  end

  -- 4. Open <name>.toml. Absent -> not-found error + available-recipes hint
  --    (exit 1). (guard_name already ensured name has no separator/`..`.)
  local path = dir .. "/" .. name .. ".toml"
  local fh = io.open(path, "rb")
  if not fh then
    io.stderr:write("error: no scene recipe named '" .. name
      .. "' in " .. DISPLAY_SCENES_DIR .. "\n")
    emit_recipe_hint(names)
    return 1
  end

  -- 5. Read the bytes and hand the RAW STRING to the pure loader/mapper. On a
  --    parse/validate failure -> recipe-is-invalid (exit 1), building ZERO panes
  --    (T-05-09). recipe.lua's reason is the no-name form `error: scene recipe
  --    is invalid: <reason>`; re-frame it with this file's `'<name>'`.
  local raw = fh:read("*a") or ""
  fh:close()
  local mapped, map_err = recipelib.load_and_map(raw)
  if not mapped then
    -- Strip BOTH the load_and_map framing AND any leading `error: ` that the
    -- reused validate_layout/validate_color strings already carry, so the line
    -- reads `error: scene recipe '<name>' is invalid: <reason>` with a SINGLE
    -- `error:` token (no `error: ... invalid: error: ...` double-prefix).
    local reason = tostring(map_err)
      :gsub("^error: scene recipe is invalid: ", "")
      :gsub("^error: ", "")
    io.stderr:write("error: scene recipe '" .. name .. "' is invalid: " .. reason .. "\n")
    return 1
  end

  -- 6. Success -> the SINGLE materialization path (SCEN-04). Silent on stdout
  --    (inherits Phase 4 D-09).
  return M.run_new(mapped)
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
  if sub == "launch" then
    return M.run_launch(args)
  end
  io.stderr:write("wez scene: expected a subcommand (new, launch)\n")
  return 2
end

return M
