-- tests/e2e/platform.lua
--
-- Platform-expectations table: the SINGLE source of truth for legitimate
-- Mac<->Linux deltas (PRD Appendix A.5). Later tiers assert parity AGAINST this
-- table so a per-OS difference is an explicitly-named expectation, never an
-- accidental assumption.
--
-- PURITY (mirrors cli/lib/color.lua 13-14): no wezterm dependency. The module
-- loads under plain lua5.4 so its data + the three detection helpers are
-- unit-testable in isolation. Detection that genuinely needs `uname` or a
-- compositor probe shells out via io.popen (mirroring tools/lib/platform.sh
-- platform_os/platform_arch). There is no wezterm dependency.
--
-- Detection helpers (they shell out and branch — not a passive lookup):
--   platform_os()   -> "linux" | "macos" | "<lowercased uname>" (passthrough),
--                      lowercased via Lua string.lower (NOT ${var^^}).
--   platform_arch() -> "x86_64" | "aarch64" (arm64->aarch64, amd64->x86_64).
--   detect_screenshot_tool() -> "spectacle" | "grim" | "gnome-screenshot" | nil
-- The "data table" description applies to M.expectations specifically, not to
-- every export of this module.

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

local function pgrep_x(name)
  local p = io.popen("pgrep -x " .. name .. " 2>/dev/null", "r")
  if not p then return false end
  local out = p:read("*l") or ""
  p:close()
  return out:match("%S") ~= nil
end

-- M.detect_screenshot_tool() -> "spectacle" | "grim" | "gnome-screenshot" | nil
--
-- Mirrored from tools/e2e-setup.sh install_screenshot_tool (D-08). The two
-- languages cannot share a source file, so this ~10-line compositor detection
-- is duplicated across the bash/Lua boundary — grep for
-- `install_screenshot_tool` / `detect_screenshot_tool` together when changing
-- either copy. Check order matches the setup script: $XDG_CURRENT_DESKTOP /
-- $XDG_SESSION_TYPE (session type is recorded there, not branched on) / a
-- pgrep probe for kwin_wayland, sway, gnome-shell. Unrecognized -> nil
-- (the setup script falls back to grim; this helper does not install).
function M.detect_screenshot_tool()
  local desktop = os.getenv("XDG_CURRENT_DESKTOP") or ""
  if pgrep_x("kwin_wayland") or desktop == "KDE" then
    return "spectacle"
  end
  if pgrep_x("sway") then
    return "grim"
  end
  if pgrep_x("gnome-shell") then
    return "gnome-screenshot"
  end
  return nil
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

  -- Input tools (Tier 3 firing, 06.9): macOS uses cliclick. Linux Wayland FIRING
  -- in this phase uses xdotool against a forced-XWayland window — never ydotool.
  -- ydotool is still provisioned by `make e2e-setup` (Plan 02) for completeness /
  -- future-compositor coverage, but it is NOT the mechanism Tier 3 Firing fires
  -- through today.
  input_tools = {
    mac = { "cliclick" },
    linux = {
      "xdotool (X11)",
      "ydotool (Wayland, provisioned only — Tier 3 fires via xdotool+forced-XWayland, see note)",
    },
    note = "OS input injection (06.9): macOS uses cliclick. Linux Wayland FIRING "
      .. "uses xdotool against a forced-XWayland WezTerm window (enable_wayland = "
      .. "false), never ydotool. ydotool is provisioned only for completeness / "
      .. "future-compositor coverage. Tier 3 firing self-skips when xdotool cannot "
      .. "resolve that forced-XWayland test window, or when a canary keystroke "
      .. "does not mutate pane text on this compositor.",
  },

  -- ---------------------------------------------------------------------------
  -- Chord-family registration expectations (Tier 3 registration, Plan 03 / D-06).
  -- For each curated action (PRD Appendix A.3, keyed by its WezTerm action TYPE
  -- name) this maps the chord FAMILIES that MUST be present in the live registered
  -- key map (`wezterm show-keys --lua`) on each OS. Family vocabulary:
  --   "SUPER" (Cmd-family), "CTRL" (Ctrl-family), "ALT" (Alt-family).
  -- A record's `mods` string belongs to a family when it CONTAINS that token, so
  -- `SHIFT|SUPER` is Cmd-family and `ALT|CTRL` is BOTH Ctrl- and Alt-family.
  --
  -- These sets are the families that LEGITIMATELY register on each OS — derived by
  -- cross-checking config/wezterm-setup/keybindings.lua against the live effective
  -- table (defaults folded with our managed bindings), NOT the PRD's blanket
  -- "Cmd AND Ctrl per action" intent. A divergence from that blanket intent is a
  -- DOCUMENTED finding (D-06/D-07), not a forced false-fail: the Tier 3 test
  -- asserts `chord_families[os]` so a legitimate Mac<->Linux delta never spuriously
  -- fails while a SILENTLY-DROPPED binding still does.
  chord_families = {
    -- macOS: SUPER = Cmd, and the managed SUPER chords (clear / new-tab / close-tab
    -- / font zoom) DO reach WezTerm, so the Cmd-family registers for them in
    -- addition to the WezTerm defaults.
    mac = {
      ClearScreenAndScrollback = { "SUPER", "CTRL" },
      SpawnTab                 = { "SUPER", "CTRL" },
      CloseCurrentTab          = { "SUPER", "CTRL" },
      ActivateTabRelative      = { "SUPER", "CTRL" },
      MoveTabRelative          = { "CTRL" },
      SplitHorizontal          = { "ALT", "CTRL" },
      SplitVertical            = { "ALT", "CTRL" },
      CloseCurrentPane         = { "ALT" },
      TogglePaneZoomState      = { "ALT", "CTRL" },
      RotatePanes              = { "ALT" },
      ActivatePaneDirection    = { "ALT", "CTRL" },
      IncreaseFontSize         = { "SUPER", "CTRL" },
      DecreaseFontSize         = { "SUPER", "CTRL" },
      ResetFontSize            = { "SUPER", "CTRL" },
      SendString               = { "CTRL" },
    },
    -- Linux: SUPER = the Win/Super key, which the desktop/WM frequently GRABS
    -- (Pop!_OS/GNOME), so several managed SUPER chords never reach WezTerm and do
    -- NOT appear in the effective table. The families below are exactly what the
    -- live `wezterm show-keys --lua` registers on this platform (verified against
    -- keybindings.lua + the WezTerm defaults).
    linux = {
      ClearScreenAndScrollback = { "CTRL" }, -- Ctrl+Shift+K (the SUPER+K is WM-shadowed)
      SpawnTab                 = { "CTRL" }, -- Ctrl+Shift+T default fold; the managed SUPER+T does NOT register on Linux
      CloseCurrentTab          = { "CTRL" }, -- Ctrl+Shift+W fallback
      ActivateTabRelative      = { "SUPER", "CTRL" }, -- SUPER {/} default + CTRL PageUp/PageDown
      MoveTabRelative          = { "CTRL" }, -- Ctrl+Shift+PageUp/PageDown
      SplitHorizontal          = { "ALT", "CTRL" }, -- ours: Alt+Shift+H; default: Ctrl+Alt families
      SplitVertical            = { "ALT", "CTRL" },
      CloseCurrentPane         = { "ALT" }, -- ours: Alt+Shift+X (no masking default)
      TogglePaneZoomState      = { "ALT", "CTRL" },
      RotatePanes              = { "ALT" }, -- config-only family; WezTerm ships no RotatePanes default
      ActivatePaneDirection    = { "ALT", "CTRL" },
      IncreaseFontSize         = { "CTRL" },
      DecreaseFontSize         = { "CTRL" },
      ResetFontSize            = { "CTRL" },
      SendString               = { "CTRL" }, -- word-nav: config-only Ctrl+Arrow (no Cmd/Ctrl masking default)
    },
    note = "SUPER is Cmd on macOS and the Super/Win key on Linux (WM-grabbed on "
      .. "Pop!_OS/GNOME). The Tier 3 registration test asserts chord_families[os] "
      .. "(NOT a blanket cross-platform set) so a legitimate Mac<->Linux delta — "
      .. "e.g. the managed SUPER+T new-tab not reaching WezTerm on Linux — never "
      .. "spuriously fails, while a dropped binding still does. LINUX CATCH-SCOPE: "
      .. "Tier 3 can only catch a dead binding in a family that registers on Linux, "
      .. "so the SpawnTab catch is on its CTRL-family chord (the Ctrl+Shift+T "
      .. "default fold), NOT the absent SUPER one — this is exactly the registration "
      .. "the Plan 04 break harness drops to prove the dead-new-tab catch.",
  },

  fire_chords = {
    linux = {
      ClearScreenAndScrollback = "ctrl+shift+k",
      SpawnTab = "ctrl+shift+t",
      CloseCurrentTab = "ctrl+shift+w",
      -- R6 probe 02: xdotool keysym for Tab is `Tab` (not ASCII). PageUp/PageDown
      -- are NOT valid xdotool names (`No such key name`); use Prior/Next.
      ActivateTabRelative = { next = "ctrl+Tab", prev = "ctrl+shift+Tab" },
      MoveTabRelative = { left = "ctrl+shift+Prior", right = "ctrl+shift+Next" },
      SplitHorizontal = "alt+shift+h",
      SplitVertical = "alt+shift+v",
      CloseCurrentPane = "alt+shift+x",
      TogglePaneZoomState = "alt+shift+z",
      RotatePanes = { clockwise = "alt+shift+r", counterclockwise = "alt+shift+e" },
      ActivatePaneDirection = {
        left = "alt+Left",
        right = "alt+Right",
        up = "alt+Up",
        down = "alt+Down",
      },
      -- WezTerm DEFAULT Ctrl+=/-/0 (managed SUPER+/-/0 is WM-shadowed on Linux).
      -- R6 probe 02: xdotool keysyms are `equal`/`minus`/`0`, not ASCII `+`/`-`.
      IncreaseFontSize = "ctrl+equal",
      DecreaseFontSize = "ctrl+minus",
      ResetFontSize = "ctrl+0",
    },
    -- Phase-7 macOS-parity follow-on; documented, not built or verified here.
    mac = {
      ClearScreenAndScrollback = "cmd+k",
      SpawnTab = "cmd+t",
      CloseCurrentTab = "cmd+w",
      ActivateTabRelative = { next = "ctrl+Tab", prev = "ctrl+shift+Tab" },
      MoveTabRelative = { left = "ctrl+shift+Prior", right = "ctrl+shift+Next" },
      SplitHorizontal = "alt+shift+h",
      SplitVertical = "alt+shift+v",
      CloseCurrentPane = "alt+shift+x",
      TogglePaneZoomState = "alt+shift+z",
      RotatePanes = { clockwise = "alt+shift+r", counterclockwise = "alt+shift+e" },
      ActivatePaneDirection = {
        left = "alt+Left",
        right = "alt+Right",
        up = "alt+Up",
        down = "alt+Down",
      },
      IncreaseFontSize = "cmd+equal",
      DecreaseFontSize = "cmd+minus",
      ResetFontSize = "cmd+0",
    },
    note = "Linux values are xdotool `key` chord strings, derived from keybindings.lua's live-"
      .. "registering CTRL/ALT-family chords (matching chord_families.linux). Complete for "
      .. "all 12 PRD Appendix A.3 fire(B)-eligible actions (ClearScreenAndScrollback, SpawnTab, "
      .. "CloseCurrentTab, ActivateTabRelative, MoveTabRelative, SplitHorizontal, SplitVertical, "
      .. "CloseCurrentPane, TogglePaneZoomState, RotatePanes, ActivatePaneDirection, and the "
      .. "Increase/Decrease/ResetFontSize family). WordNav/SendString is reg(M)-only and has no "
      .. "fire_chords entry. Font-size fires WezTerm's DEFAULT Ctrl+=/-/0 (xdotool equal/minus/0) "
      .. "because the managed SUPER rows are WM-shadowed on Linux. macOS firing is a documented "
      .. "Phase 7 macOS-parity follow-on per this project's established Linux-first/macOS-deferred "
      .. "pattern — structurally mirrored here, not built or verified here.",
  },
}

return M
