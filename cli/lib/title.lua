-- cli/lib/title.lua
--
-- Shared icon-name title resolver (D-03). The icon map + resolve_title were
-- LIFTED verbatim out of cli/commands/pane.lua so both `wez pane title` and
-- `wez tab title` consume ONE copy. Pure: no `wezterm`, no I/O.
--
-- Phase 6.2 (D-05): the legacy first-word glyph swap is REMOVED from steady
-- state — title text is now fully literal. Icons come ONLY from the new `icon`
-- attribute resolved via M.resolve_icon (D-02). The ICONS map stays as the
-- documented shortcut for icon NAMES, no longer consulted by resolve_title.

local M = {}

-- The shared color module owns build_osc1337 (the base64 OSC 1337 SetUserVar
-- builder). emit_icon (IN-01) reuses it so the icon-emit orchestration lives ONCE
-- here. color.lua has no requires, so this introduces no circular dependency.
local color = require("cli.lib.color")

-- Icon-name shortcut map (D-02): the documented names that resolve_icon maps to
-- a glyph. Any other input passes through verbatim (literal emoji/glyph/text).
M.ICONS = {
  node = "💚", python = "🐍", rust = "🦀", go = "🐹",
  docker = "🐳", k8s = "☸️", server = "🖥️", db = "🗄️", ssh = "🔐", deploy = "🚀",
  git = "🔀", build = "🔨", test = "🧪", debug = "🐛", edit = "✏️", log = "📋",
  shell = "🐚", config = "⚙️", search = "🔍", ai = "🧠", fire = "🔥", alert = "⚠️",
}

--- Resolve an icon input into a glyph (D-02). A known ICONS name (case-insensitive)
-- maps to its glyph; ANY other input (literal emoji/glyph/text) is returned
-- verbatim — no reject. nil/empty -> "". Pure.
function M.resolve_icon(input)
  if input == nil then
    return ""
  end
  local s = tostring(input)
  if s == "" then
    return ""
  end
  return M.ICONS[s:lower()] or s
end

--- Shared icon-emit orchestration (IN-01 / D-01): the ONE implementation of the
-- `wez tab icon` / `wez pane icon` (and `--icon`) emit body, previously copy-pasted
-- byte-for-byte across tab.lua and pane.lua. Normalizes the reset/empty cases
-- (nil / "reset" / "" -> "" payload, which clears WEZTERM_TAB_ICON), resolves the
-- name->glyph via M.resolve_icon, and writes the OSC 1337 SetUserVar through the
-- caller-supplied `emit_fn` (the I/O sink stays in the command module, keeping this
-- helper free of a hard io dependency). icon shares ONE carrier across tab + pane.
function M.emit_icon(emit_fn, raw)
  if raw == nil or tostring(raw):lower() == "reset" then
    raw = ""
  end
  emit_fn(color.build_osc1337("WEZTERM_TAB_ICON", M.resolve_icon(raw)))
end

--- Resolve the positional words after `title` into the final title string (D-05).
-- Title text is fully literal — the first word is NEVER swapped for a glyph.
-- "reset"/empty -> ""; otherwise the words join verbatim (original case preserved).
function M.resolve_title(words)
  words = words or {}
  if #words == 0 then
    return ""
  end
  if tostring(words[1]):lower() == "reset" then
    return ""
  end
  return table.concat(words, " ")
end

--- Single-string variant for the `--title "<text>"` flag (combined form). Title
-- text is fully literal (D-05 — no first-word glyph swap). "reset"/empty -> "";
-- otherwise the input trimmed (original case + internal spacing preserved).
function M.resolve_title_str(s)
  s = tostring(s or "")
  local first = s:match("^%s*(%S+)")
  if not first then
    return ""
  end
  if first:lower() == "reset" then
    return ""
  end
  return s:match("^%s*(.-)%s*$")
end

--- Basename of a path string (last non-empty segment). Pure; trailing slashes
-- ignored. "/" -> "/", "" -> "/". Used by expand_cwd; exposed for testing.
function M.basename(path)
  local stripped = tostring(path or ""):gsub("/+$", "")
  local base = stripped:match("[^/]+$") or stripped
  if base == "" then base = "/" end
  return base
end

--- Replace the literal `{cwd}` token in a title with the basename of launch_dir.
-- This is the SANCTIONED, shell-free way to put the launch directory name in a
-- title (recipes + `--pane title=` + `--title`): a recipe/title MUST NOT run
-- `$(...)` (D-08 security forbids shell eval), so `{cwd}` is the safe equivalent
-- of `$(basename "$PWD")`. Pure: no `wezterm`, no I/O — the caller supplies the
-- launch dir. All occurrences are replaced; non-token text is untouched.
function M.expand_cwd(s, launch_dir)
  if s == nil then
    return s
  end
  s = tostring(s)
  if not s:find("{cwd}", 1, true) then
    return s
  end
  local base = M.basename(launch_dir)
  return (s:gsub("{cwd}", function() return base end))
end

--- Compose the displayed title when a resolved title may be empty (D-11/D-12/D-13).
-- This is the SINGLE shared helper applied by BOTH the tab-side render (Plan 03)
-- and the pane-side scene loop (Plan 04), so the empty-title cwd fallback is one
-- rule, not two divergent copies.
--   * A non-empty `title` always wins, returned as-is (D-11 — explicit wins).
--   * Otherwise fall back to basename(launch_dir) (D-11/D-12 — cwd self-label).
--   * With a non-empty `icon` present, prepend `icon + " "` (D-13 — icon + base).
-- Pure: reuses M.basename; no `wezterm`, no I/O.
function M.fallback_title(title, icon, launch_dir)
  if type(title) == "string" and title ~= "" then
    return title
  end
  local base = M.basename(launch_dir)
  if type(icon) == "string" and icon ~= "" then
    return icon .. " " .. base
  end
  return base
end

-- ---------------------------------------------------------------------------
-- Legacy icon-in-title parse-and-warn (D-06). The ONLY migration surface Phase
-- 6.2 ships: when a known ICONS-map name is typed as the LEADING word of a literal
-- title (the old icon-in-title shortcut, removed in D-05), warn ONCE per process
-- that the icon now lives in its own attribute. This NEVER swaps the word, alters
-- the title text, or changes exit status — the title stays fully literal (D-05).
-- There is deliberately NO `wez doctor` gate, advisory probe, auto-fix, or
-- persistent migration tracking (D-06, overrides ROADMAP G-2b). This is shared so
-- BOTH `wez tab title` and `wez pane title` reuse ONE implementation (D-01).
-- ---------------------------------------------------------------------------

-- Module-level one-time guard: the warn fires at most once per process invocation.
local legacy_icon_warned = false

--- Reset the one-time guard. Test-only seam so each test case can observe the warn.
function M.reset_legacy_icon_warn()
  legacy_icon_warned = false
end

--- If the FIRST whitespace-delimited word of `title_text` (lower-cased) is a known
-- ICONS-map name, write ONE warning line to stderr suggesting `<suggest>` (e.g.
-- "wez tab icon"). `cmd_prefix` is the user-facing command label (e.g.
-- "wez tab title"). The warn is bounded to one line per process by the guard above.
-- Returns true if it warned (this call), false otherwise. It NEVER modifies the
-- title or returns a different title.
function M.warn_legacy_icon_title(title_text, cmd_prefix, suggest)
  if legacy_icon_warned then
    return false
  end
  local s = tostring(title_text or "")
  local first = s:match("^%s*(%S+)")
  if not first then
    return false
  end
  if M.ICONS[first:lower()] == nil then
    return false
  end
  legacy_icon_warned = true
  io.stderr:write(
    cmd_prefix .. ': "' .. first .. '" looks like a legacy icon-name title — '
    .. "use `" .. suggest .. " " .. first .. "` instead\n")
  return true
end

return M
