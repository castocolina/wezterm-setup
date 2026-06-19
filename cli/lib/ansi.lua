-- cli/lib/ansi.lua
--
-- Pure ANSI SGR text-color helper (D-06). Emits the EXACT red sequences the
-- conflict renderer (Plan 02) and the e2e lane (Plan 04) assert against:
--   conflict rows           -> red       `\27[31m`  … `\27[0m`  (SGR 31 / reset 0)
--   conflict summary header -> bold red  `\27[1;31m` … `\27[0m` (SGR 1;31 / reset 0)
--
-- This is a DISTINCT concern from cli/lib/color.lua, which emits OSC *background*
-- color (OSC 11 / OSC 1337). That module is intentionally NOT reused here:
-- overloading the background emitter for a text-SGR concern is a locked
-- anti-pattern (RESEARCH Anti-Patterns). Text color lives in its own pure module.
--
-- PURITY: no require("wezterm"), no io.*, no os.execute, no os.getenv. The
-- module loads under plain lua5.4 so its logic is unit-testable in isolation.
--
-- ANSI-injection safety: each helper wraps its argument VERBATIM — it never
-- inspects or escapes the string. Wrapping untrusted text is the CALLER's
-- decision; callers (Plan 02) MUST pass only our own fixed columns, never the
-- opaque untrusted `action` string (T-06.5-01).

local M = {}

--- Wrap s in SGR 31 (red foreground) + reset 0. Argument wrapped verbatim.
function M.red(s)
  return "\27[31m" .. tostring(s) .. "\27[0m"
end

--- Wrap s in SGR 1;31 (bold red) + reset 0. Argument wrapped verbatim.
function M.bold_red(s)
  return "\27[1;31m" .. tostring(s) .. "\27[0m"
end

return M
