---
quick_id: 260618-dpp
type: execute
description: Install WezTerm .desktop launcher + icon into user-space XDG dirs (install_linux)
files_modified:
  - tools/bootstrap-wezterm.sh
  - tests/cli/bootstrap_update_test.lua
autonomous: true
must_haves:
  truths:
    - "install_linux places the shipped .desktop into $XDG/applications and the icon(s) into $XDG/icons so WezTerm appears in the desktop launcher and can be pinned"
    - "The step is sudo-free, idempotent, Linux-only, decision-free glue (D-01), and never fails the install if the files or the cache tools are absent"
    - "The current already-installed WezTerm gets the launcher entry immediately (no reinstall needed)"
  artifacts:
    - "tools/bootstrap-wezterm.sh: a new install_desktop_entry() (or inline step) invoked after the wezterm symlink in install_linux"
  key_links:
    - "tools/bootstrap-wezterm.sh (install_linux symlink step)"
    - "tests/cli/bootstrap_update_test.lua (TEXT + sourced-no-run harness)"
    - "~/.local/share/applications/org.wezfurlong.wezterm.desktop (live target)"
---

# Quick Task 260618-dpp: WezTerm desktop launcher integration

<objective>
Make the WezTerm app visible/pinnable in the desktop bar. The tarball already ships
`org.wezfurlong.wezterm.desktop` + a hicolor icon; `install_linux` only symlinks the binary
and never places them in XDG dirs, so the launcher is invisible. Add the desktop-integration
step to `install_linux`, and apply it to the current install so the icon appears now.
</objective>

<context>
- `install_linux()` in `tools/bootstrap-wezterm.sh` extracts the tarball to
  `${release_dir}=${PREFIX}/${tag}` and symlinks `${release_dir}/wezterm/usr/bin/wezterm`
  → `${BIN_DIR}/wezterm` (~/.local/bin). Shipped desktop assets live at
  `${release_dir}/wezterm/usr/share/applications/org.wezfurlong.wezterm.desktop` and
  `${release_dir}/wezterm/usr/share/icons/hicolor/<size>/apps/org.wezfurlong.wezterm.png`.
- The `.desktop` has `Exec=wezterm start --cwd .` (PATH-resolved via ~/.local/bin) and
  `Icon=org.wezfurlong.wezterm` (resolves from the hicolor theme once the png is placed) —
  leave both AS-IS.
- SCOPE: install side only. `wez uninstall` is wezterm-setup-only and does NOT remove the
  WezTerm app, and there is no app-uninstall path — so there is no orphan to pair-remove here.
  macOS (.app bundle) is OUT OF SCOPE (Phase 7). Guard the step to the Linux path.
- D-01: pure bash glue, no install/version decisions. Sudo-free. Idempotent (cp -f).
- Test harness `tests/cli/bootstrap_update_test.lua` asserts on script TEXT + sourced-no-run
  behavior (BASH_SOURCE/$0 guard means sourcing does not run main).
- Tooling present in this env: shellcheck, desktop-file-validate, update-desktop-database,
  gtk-update-icon-cache (all best-effort at runtime — must NOT be required).
- Current install tag dir: ~/.local/opt/wezterm/nightly/wezterm (resolve the real tag).
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add desktop-integration step to install_linux + regression test</name>
  <files>tools/bootstrap-wezterm.sh, tests/cli/bootstrap_update_test.lua</files>
  <read_first>
    - tools/bootstrap-wezterm.sh (install_linux() — the `ln -sfn ... ${BIN_DIR}/wezterm` line is the insertion point; the log()/err() helpers; the platform/Linux branch in main)
    - tests/cli/bootstrap_update_test.lua (TEXT-assertion + sourced-no-run harness shape to mirror)
  </read_first>
  <action>
    In tools/bootstrap-wezterm.sh add a focused helper (e.g. `install_desktop_entry()`) taking the
    release dir, and CALL it from install_linux immediately AFTER the `ln -sfn ... ${BIN_DIR}/wezterm`
    symlink. The helper must:
      - resolve `xdg="${XDG_DATA_HOME:-$HOME/.local/share}"`;
      - locate the shipped desktop file at `<release_dir>/wezterm/usr/share/applications/org.wezfurlong.wezterm.desktop`;
        if absent, `log` and return 0 (non-fatal skip);
      - `mkdir -p "$xdg/applications"` and `cp -f` the .desktop there;
      - mirror ALL shipped icons: `find "<release_dir>/wezterm/usr/share/icons" -type f` and copy each
        into the matching `$xdg/icons/<relative-path>` (preserve the hicolor/<size>/apps structure;
        mkdir -p the target dir per file) — not just the 128x128 png;
      - best-effort, non-fatal cache refresh: `update-desktop-database "$xdg/applications" 2>/dev/null || true`
        and `gtk-update-icon-cache -f -t "$xdg/icons/hicolor" 2>/dev/null || true` (both may be absent);
      - log what it placed. Leave the .desktop Exec/Icon untouched.
    Guard so it runs only on the Linux install path (it's called from install_linux, which is already
    Linux-only — keep it that way; do NOT wire it into any macOS path).
    Then add a regression assertion to tests/cli/bootstrap_update_test.lua mirroring the existing
    TEXT-assertion style: assert the script contains the new helper name and the key markers
    (`XDG_DATA_HOME`, `applications`, `org.wezfurlong.wezterm.desktop`, `update-desktop-database` or
    `gtk-update-icon-cache`), and that install_linux invokes the helper after the symlink.
  </action>
  <verify>
    <automated>bash -n tools/bootstrap-wezterm.sh && shellcheck -x tools/bootstrap-wezterm.sh && lua5.4 tests/cli/bootstrap_update_test.lua</automated>
  </verify>
  <acceptance_criteria>
    - `bash -n tools/bootstrap-wezterm.sh` exits 0; `shellcheck -x tools/bootstrap-wezterm.sh` clean (no new warnings).
    - The helper is defined and called after the `${BIN_DIR}/wezterm` symlink: `grep -n 'install_desktop_entry' tools/bootstrap-wezterm.sh` shows a definition AND a call site inside install_linux.
    - The helper references `XDG_DATA_HOME`/`.local/share`, `applications`, and is non-fatal when files/tools are absent (uses `|| true` on the cache commands and a guarded skip when the .desktop is missing).
    - `lua5.4 tests/cli/bootstrap_update_test.lua` passes with the new assertion(s).
    - `./tools/run-tests.sh` introduces no NEW failures vs the known baseline (cli/lib/recipe_test.lua "2.9d ai.toml", commit 723af62, out of scope).
  </acceptance_criteria>
  <done>install_linux installs the .desktop + icons into XDG dirs (sudo-free, idempotent, non-fatal, Linux-only); bootstrap test covers it; static checks clean.</done>
</task>

<task type="auto">
  <name>Task 2: Apply to the current install so the launcher appears now + verify live</name>
  <files>(no repo files — operates on ~/.local/opt/wezterm + ~/.local/share)</files>
  <read_first>
    - tools/bootstrap-wezterm.sh (the new install_desktop_entry helper — source it to invoke against the live install)
  </read_first>
  <action>
    Resolve the actual installed tag dir under ~/.local/opt/wezterm (e.g. nightly) and run the new
    desktop-integration logic against it so org.wezfurlong.wezterm.desktop + the icon(s) land under
    ~/.local/share now. Prefer SOURCING the script and calling the helper (the BASH_SOURCE/$0 guard
    means sourcing does not run main) with the resolved release dir; otherwise replicate the helper's
    cp/mkdir steps directly. Do NOT trigger a WezTerm re-download. Do NOT touch
    ~/.config/wezterm/wezterm.lua or scenes/.
  </action>
  <verify>
    <automated>test -f ~/.local/share/applications/org.wezfurlong.wezterm.desktop && ls ~/.local/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png && desktop-file-validate ~/.local/share/applications/org.wezfurlong.wezterm.desktop && echo "launcher OK"</automated>
  </verify>
  <acceptance_criteria>
    - `~/.local/share/applications/org.wezfurlong.wezterm.desktop` exists.
    - `~/.local/share/icons/hicolor/128x128/apps/org.wezfurlong.wezterm.png` exists.
    - `desktop-file-validate ~/.local/share/applications/org.wezfurlong.wezterm.desktop` exits 0 (best-effort — record output if it warns).
  </acceptance_criteria>
  <done>The current WezTerm install now has a user-space launcher entry + icon; it should appear in the app menu / be pinnable (user may need to log out/in or restart the shell/panel for some DEs).</done>
</task>

</tasks>

<verification>
- bash -n + shellcheck -x on tools/bootstrap-wezterm.sh clean.
- lua5.4 tests/cli/bootstrap_update_test.lua passes (new regression assertion green).
- ./tools/run-tests.sh: no new failures vs the recipe_test baseline.
- ~/.local/share/applications/org.wezfurlong.wezterm.desktop present + desktop-file-validate clean; icon present.
</verification>

<success_criteria>
- install_linux durably installs the launcher + icons (sudo-free, idempotent, Linux-only, non-fatal).
- Current install has the launcher now.
- Regression test added; static checks clean; no new suite failures.
</success_criteria>

<artifacts_this_phase_produces>
- `tools/bootstrap-wezterm.sh`: new `install_desktop_entry()` helper + its call site in `install_linux` after the wezterm symlink.
- `tests/cli/bootstrap_update_test.lua`: new regression assertion(s) for the desktop-integration step.
- Live: `~/.local/share/applications/org.wezfurlong.wezterm.desktop` + `~/.local/share/icons/hicolor/.../org.wezfurlong.wezterm.png`.
</artifacts_this_phase_produces>

<output>
Create `.planning/quick/260618-dpp-install-wezterm-desktop-launcher-icon-in/260618-dpp-SUMMARY.md` when done.
</output>
