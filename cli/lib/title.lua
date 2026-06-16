-- cli/lib/title.lua
--
-- Shared icon-name title resolver (D-03). The icon map + resolve_title were
-- LIFTED verbatim out of cli/commands/pane.lua so both `wez pane title` and
-- `wez tab title` consume ONE copy. Pure: no `wezterm`, no I/O.

local M = {}

-- Icon-name shortcut map (D-04): a leading token matching one of these names is
-- replaced by its glyph; the rest of the input is the title text.
M.ICONS = {
  node = "💚", python = "🐍", rust = "🦀", go = "🐹",
  docker = "🐳", k8s = "☸️", server = "🖥️", db = "🗄️", ssh = "🔐", deploy = "🚀",
  git = "🔀", build = "🔨", test = "🧪", debug = "🐛", edit = "✏️", log = "📋",
  shell = "🐚", config = "⚙️", search = "🔍", ai = "🧠", fire = "🔥", alert = "⚠️",
}

--- Resolve the positional words after `title` into the final title string.
-- First token is an icon name -> glyph + (optional) rest; "reset"/empty -> "".
-- Otherwise the words join verbatim (original case preserved).
function M.resolve_title(words)
  words = words or {}
  if #words == 0 then
    return ""
  end
  if tostring(words[1]):lower() == "reset" then
    return ""
  end
  local glyph = M.ICONS[tostring(words[1]):lower()]
  if glyph then
    if #words == 1 then
      return glyph
    end
    local rest = {}
    for i = 2, #words do rest[#rest + 1] = words[i] end
    return glyph .. " " .. table.concat(rest, " ")
  end
  return table.concat(words, " ")
end

--- Single-string variant for the `--title "<text>"` flag (combined form). Split
-- on the first whitespace run into (first, rest), then behave like resolve_title:
-- icon-name first token -> glyph + optional rest; "reset"/empty -> ""; otherwise
-- the input trimmed (original case + internal spacing preserved).
function M.resolve_title_str(s)
  s = tostring(s or "")
  local first, rest = s:match("^%s*(%S+)%s*(.-)%s*$")
  if not first then
    return ""
  end
  if first:lower() == "reset" then
    return ""
  end
  local glyph = M.ICONS[first:lower()]
  if glyph then
    return rest ~= "" and (glyph .. " " .. rest) or glyph
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

return M
