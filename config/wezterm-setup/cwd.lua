-- wezterm-setup :: cwd
--
-- CWD inheritance for new tabs and panes (FOUND-01).
--
-- Per decisions/cwd-mechanism.md: pane-split / new-tab cwd inheritance is
-- WezTerm DEFAULT behavior. WezTerm reads the source pane's cwd at spawn time
-- (OSC 7 `file://HOST/path` when the shell emits it -- which our shipped
-- shell-integration guarantees on zsh + bash -- with the OS-level read,
-- `/proc` on Linux / libproc on macOS, as the backstop).
--
-- Therefore this module needs NO custom split/spawn handler and NO event hooks.
-- Adding such logic would only risk overriding the correct default behavior.
-- The module exists to (a) make the "no custom logic needed" decision explicit
-- and auditable, and (b) provide a single seam where any future, intentional
-- cwd policy (e.g. a default domain) would live -- consumed by init.lua's
-- apply().
--
-- D-18: cross-platform. No `/proc` assumptions here; the OS-read backstop is
-- WezTerm's own concern. Verified on Linux; macOS re-verification deferred.

local M = {}

--- Apply cwd-related settings to the user's config.
-- Intentionally a no-op on the config table: cwd inheritance is WezTerm's
-- default and the shipped OSC 7 shell integration supplies the accurate cwd.
-- Returns the same config object it received (augment contract, D-17).
-- @param config table  the user's WezTerm config object
-- @return table        the same config object
function M.apply(config)
  -- No custom split/spawn logic (cwd-mechanism.md). Inheritance is the
  -- WezTerm default; the shell integration emits OSC 7 so the cwd is accurate.
  return config
end

return M
