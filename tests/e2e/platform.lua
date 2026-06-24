-- tests/e2e/platform.lua
--
-- Platform-expectations table: the SINGLE source of truth for legitimate
-- Mac<->Linux deltas (PRD Appendix A.5). Later tiers assert parity AGAINST this
-- table so a per-OS difference is an explicitly-named expectation, never an
-- accidental assumption.
--
-- PURITY (mirrors cli/lib/color.lua 13-14): no wezterm dependency. The module
-- loads under plain lua5.4 so its data + the two detection helpers are
-- unit-testable in isolation. Detection that genuinely needs `uname` shells out
-- via io.popen (mirroring tools/lib/platform.sh platform_os/platform_arch), but
-- there is no wezterm dependency and no decision logic — this is a data table.
--
-- Detection semantics MIRROR tools/lib/platform.sh 19-38 exactly:
--   platform_os()   -> "linux" | "macos" | "<lowercased uname>" (passthrough),
--                      lowercased via Lua string.lower (NOT ${var^^}).
--   platform_arch() -> "x86_64" | "aarch64" (arm64->aarch64, amd64->x86_64).

local M = {}

-- Read one line of command output, trimmed. Returns "" on failure.
local function uname(flag)
  local p = io.popen("uname " .. flag .. " 2>/dev/null", "r")
  if not p then return "" end
  local out = p:read("*l") or ""
  p:close()
  return out
end

-- platform_os -> "linux" | "macos" | "<lowercased uname -s>" (unknown passthrough).
-- Mirrors platform.sh 19-27: Linux->linux, Darwin->macos, else lowercased uname.
function M.platform_os()
  local s = uname("-s")
  if s == "Linux" then
    return "linux"
  elseif s == "Darwin" then
    return "macos"
  elseif s == "" then
    return "unknown"
  end
  return string.lower(s)
end

-- platform_arch -> "x86_64" | "aarch64" (normalized). Mirrors platform.sh 30-38:
-- x86_64/amd64 -> x86_64, aarch64/arm64 -> aarch64, else passthrough.
function M.platform_arch()
  local m = uname("-m")
  if m == "x86_64" or m == "amd64" then
    return "x86_64"
  elseif m == "aarch64" or m == "arm64" then
    return "aarch64"
  elseif m == "" then
    return "unknown"
  end
  return m
end

-- ---------------------------------------------------------------------------
-- PRD A.5 parity rows. Each entry is keyed by CONCERN and names the legitimate
-- per-OS expectation, so a later tier asserts `expected[os]` instead of
-- hardcoding one platform's value. `mac` / `linux` hold the legitimate value (or
-- a list of values) for that OS; `note` explains WHY the delta is legitimate.
-- ---------------------------------------------------------------------------
M.expectations = {
  -- Lua resolution: macOS resolves Lua from the Homebrew keg path; Linux uses the
  -- system lua5.4. The dev launcher must find SOME lua5.4 on both.
  lua_resolution = {
    mac = "keg path (Homebrew Cellar/opt lua@5.4)",
    linux = "system lua5.4 on PATH",
    note = "macOS Homebrew does not symlink keg-only lua@5.4 onto PATH; the "
      .. "launcher resolves the keg path. Linux ships lua5.4 on PATH directly.",
  },

  -- SUPER modifier: the platform-natural 'super' key differs. WezTerm bindings
  -- that use SUPER map to Cmd on macOS and the Win/Super key on Linux.
  super_key = {
    mac = "Cmd (Command)",
    linux = "Super (Win key)",
    note = "SUPER is Cmd on macOS and the Win/Super key on Linux; a keybinding "
      .. "annotated for both platforms shows (macOS) and (Linux) on the row.",
  },

  -- Bundle sibling symlinks: macOS needs the WezTerm.app bundle siblings symlinked
  -- next to `wezterm` so `wez keys` (which shells `wezterm show-keys`) resolves;
  -- on Linux these binaries are already on PATH.
  bundle_siblings = {
    mac = { "wezterm-gui", "wezterm-mux-server", "strip-ansi-escapes" },
    linux = {},
    note = "macOS-only: the WezTerm.app bundle keeps siblings inside the app, so "
      .. "install symlinks wezterm-gui / wezterm-mux-server / strip-ansi-escapes "
      .. "next to wezterm. On Linux they are packaged on PATH already.",
  },

  -- Bash version: orchestration must be bash-3.2-safe because macOS ships bash 3.2
  -- (no mapfile/readarray, no declare -A, no ${var^^}); Linux ships bash 5.
  bash_version = {
    mac = "3.2",
    linux = "5",
    note = "macOS ships the ancient bash 3.2 (GPLv2); Linux ships bash 5. All "
      .. "shipped orchestration avoids bash-4 constructs so it runs on both.",
  },

  -- Input tools (Tier 3 firing, 06.9): macOS uses cliclick; Linux uses xdotool on
  -- X11 and ydotool on Wayland. Named here so 06.9 asserts against this row.
  input_tools = {
    mac = { "cliclick" },
    linux = { "xdotool (X11)", "ydotool (Wayland)" },
    note = "OS input injection (06.9): macOS uses cliclick; Linux uses xdotool "
      .. "under X11 and ydotool under Wayland. Tier 3 firing self-skips when the "
      .. "platform-appropriate tool is absent.",
  },
}

return M
