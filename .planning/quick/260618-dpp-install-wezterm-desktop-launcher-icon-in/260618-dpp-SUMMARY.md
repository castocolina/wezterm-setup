---
quick_id: 260618-dpp
type: execute
subsystem: installer / bootstrap
description: Install WezTerm .desktop launcher + icon into user-space XDG dirs (install_linux)
tags: [installer, bootstrap, xdg, desktop-entry, linux]
key-files:
  modified:
    - tools/bootstrap-wezterm.sh
    - tests/cli/bootstrap_update_test.lua
  live-placed:
    - ~/.local/share/applications/org.wezfurlong.wezterm.desktop
    - ~/.local/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png
decisions:
  - D-01 glue only — no install/version decisions in the new step
  - Mirror ALL shipped icons via find (future-proof), not just 128x128
  - Non-fatal everywhere — guarded skip when .desktop absent; cache tools `|| true`
metrics:
  tasks: 2
  files_changed: 2
  completed: 2026-06-18
---

# Quick Task 260618-dpp: WezTerm desktop launcher integration Summary

WezTerm now self-registers in the Linux desktop launcher: `install_linux` places the
shipped `org.wezfurlong.wezterm.desktop` into `${XDG_DATA_HOME}/applications` and mirrors
every shipped hicolor icon into `${XDG_DATA_HOME}/icons` (sudo-free, idempotent, non-fatal),
and the current install was patched live so the entry appears now without a reinstall.

## What was done

### Task 1 — desktop-integration step + regression test
- Added `install_desktop_entry(release_dir)` to `tools/bootstrap-wezterm.sh`:
  - Resolves `xdg="${XDG_DATA_HOME:-$HOME/.local/share}"`.
  - Locates `<release_dir>/wezterm/usr/share/applications/org.wezfurlong.wezterm.desktop`;
    if absent, logs and `return 0` (non-fatal skip).
  - `mkdir -p "$xdg/applications"` and `cp -f` the `.desktop` (idempotent overwrite).
  - Mirrors **all** shipped icons: `find <release_dir>/wezterm/usr/share/icons -type f`,
    preserving the `hicolor/<size>/apps` structure (per-file `mkdir -p` of the target dir).
  - Best-effort, non-fatal cache refresh: `update-desktop-database ... 2>/dev/null || true`
    and `gtk-update-icon-cache -f -t "$xdg/icons/hicolor" 2>/dev/null || true`.
  - Leaves the `.desktop` `Exec=`/`Icon=` untouched (PATH/theme-resolved).
- Wired the call into `install_linux` immediately **after** the
  `ln -sfn "${target}" "${BIN_DIR}/wezterm"` symlink (Linux-only path; not wired to macOS).
- Added 11 regression assertions to `tests/cli/bootstrap_update_test.lua` mirroring the
  existing TEXT + body-scoped harness: helper defined, XDG/applications markers, desktop
  filename, `find`-based icon mirror, non-fatal cache tools, guarded skip, `cp -f`,
  `|| true`, helper invoked, and the **call-after-symlink ordering** check.

### Task 2 — apply to the current install + live verify
- Resolved the real tag dir `~/.local/opt/wezterm/nightly`.
- Sourced the script under `bash` (the `BASH_SOURCE/$0` guard prevents `main()` running)
  and called `install_desktop_entry "$TAG_DIR"`. Output:
  `placed .../applications/org.wezfurlong.wezterm.desktop` and `placed 1 icon file(s)`.
- No WezTerm re-download; `~/.config/wezterm/wezterm.lua` and `scenes/` untouched.

## Verification (real output, not "should work")

Task 1:
- `bash -n tools/bootstrap-wezterm.sh` → exit 0.
- `shellcheck -x tools/bootstrap-wezterm.sh` → clean (no new warnings).
- `lua5.4 tests/cli/bootstrap_update_test.lua` → **39 passed, 0 failed**.
- `./tools/run-tests.sh` → only the known out-of-scope baseline fails
  (`cli/lib/recipe_test.lua "2.9d ai.toml"`, commit 723af62). **No NEW failures.**

Task 2:
- `test -f ~/.local/share/applications/org.wezfurlong.wezterm.desktop` → present.
- `~/.local/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png` → present (9259 bytes).
- `desktop-file-validate <.desktop>` → exit 0. One non-fatal `hint:` about multiple main
  Categories (`System;TerminalEmulator;Utility;`) — this is shipped upstream content left
  AS-IS per scope; not an error.

## Deviations from Plan

None — plan executed exactly as written. (The `bash`-wrapper around the source step in
Task 2 was an environment detail: the shell harness runs zsh, so sourcing the bash script
required an explicit `bash -c`. No logic change.)

## Known Stubs

None.

## Notes / follow-ups (out of scope)

- macOS `.app` launcher integration remains deferred (Phase 7 / D-18) — the new helper is
  Linux-only by design, gated through `install_linux`.
- Some DEs/panels may need a shell/panel restart or re-login before the entry surfaces.

## Self-Check: PASSED
- FOUND: tools/bootstrap-wezterm.sh (install_desktop_entry defined + called after symlink)
- FOUND: tests/cli/bootstrap_update_test.lua (regression assertions, 39 passed)
- FOUND: ~/.local/share/applications/org.wezfurlong.wezterm.desktop
- FOUND: ~/.local/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png
