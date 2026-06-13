---
slug: install-config-e2e
status: resolved
trigger: "Two foundational install/config bugs found during a Phase 4 e2e attempt: (1) local `make install` tries a remote release-download; (2) installed WezTerm config errors on load and opens two windows. Both root causes already proven; add a real e2e smoke test to close the unit-test blind spot."
created: 2026-06-13
updated: 2026-06-13
resolved: 2026-06-13
resolution: |
  BUG 1 (remote download on local install) fixed in tools/build.sh — local source build path is
  luastatic -> dev-launcher; release-download gated behind WEZ_REMOTE_BOOTSTRAP=1 (f07b30b).
  BUG 2 (config apply() throws -> two windows) fixed in config/wezterm-setup/init.lua — dotted
  requires (require("wezterm-setup.keybindings") etc.) resolve via WezTerm's <config-dir>/?.lua
  template, replacing the debug.getinfo self-bootstrap that CRASHED live (WezTerm's Lua sandbox has
  no `debug` library) (eab1726). The first fix attempt (dbdc7cc, debug.getinfo) regressed live and
  was superseded.
  Regression guard: tests/integration/install_config_load_integration_test.lua emulates WezTerm's
  package.path AND nils out `debug`, closing the blind spot where unit tests passed under lua5.4
  (which HAS debug) (a857857, hardened).
  Verified: config loads cleanly in a real wezterm-mux-server process (single window); user
  confirmed the visual + single-window launch. Both bugs closed.
---

# Debug Session: install-config-e2e

> Two distinct but co-located bugs in the Phase-1 install/config layer, plus a missing e2e regression guard. Both root causes are ALREADY PROVEN (see Evidence) — this session is fix + verify + regression-test, not open-ended investigation.

## Symptoms

- **Expected:** `make install` on the local source tree builds/uses `wez` with zero network access; the injected WezTerm managed block loads cleanly and opens exactly one window.
- **Actual:** (1) local `make install` attempts `curl https://github.com/you/wezterm-setup/releases/download/v0.1.0/wez-linux-x86_64` → HTTP 404, then falls back to dev-launcher. (2) Launching WezTerm after install opens TWO windows (config-error window + main) because the managed block's `apply()` throws.
- **Errors:**
  - `[build] ERROR: failed to download https://github.com/you/wezterm-setup/releases/download/v0.1.0/wez-linux-x86_64` (`curl: (22) ... 404`)
  - `init.lua:27: module 'keybindings' not found` (reproduced under WezTerm's package.path)
- **Timeline:** Surfaced 2026-06-12 during the first real end-to-end install attempt (to run Phase 4 `wez scene new` repros). Never validated live before — only unit tests ran.
- **Reproduction:** `make uninstall install` on a box with `lua5.4` but no `luastatic`; then launch WezTerm.

## Current Focus

hypothesis: |
  BUG 1 (build.sh path order): `tools/build.sh main()` falls back to `download_release` whenever `have_luastatic()` is false, BEFORE the dev source-launcher. A local source install must never download. Fix: for a local build, go luastatic → dev-launcher directly; gate `download_release` behind an explicit remote-bootstrap opt-in (env flag / separate entry), since the pinned+checksummed release-download belongs only to the future `curl|bash` remote installer (placeholder base `github.com/you/...` is also unset).
  BUG 2 (config nested-require resolution): the managed block injected by `cli/commands/install_state.lua` is just `require('wezterm-setup').apply(config)` with no `package.path` setup. `config/wezterm-setup/init.lua` does flat `require("keybindings"/"cwd"/"format-tab-title")`, which fail under WezTerm's real package.path (only `~/.config/wezterm/` is on it, not the `wezterm-setup/` subdir) → `apply()` throws → WezTerm shows a config-error window alongside the main window. Fix options: (a) init.lua bootstraps package.path from its own location via `debug.getinfo`/`...`; (b) switch nested requires to dotted module names `require("wezterm-setup.keybindings")`; (c) installer emits a package.path line into the managed block. Prefer the fix that keeps the module self-contained AND import-safe under plain lua5.4 unit tests.
test: "Reproduced BUG 2 directly: lua5.4 with package.path set to the config dir only → init.lua:27 module 'keybindings' not found."
expecting: both fixes applied; `make install` runs offline; a real WezTerm config-load smoke test passes; existing 154 unit tests stay green.
next_action: "CYCLE 2: BUG2's first fix (debug.getinfo) crashed live (WezTerm has no debug lib); replaced with dotted requires + hardened the e2e guard to emulate the sandbox (debug=nil). Commit eab1726. Headless proofs: hardened guard CATCHES the debug approach; dotted fix loads cleanly under debug=nil + config-dir-only path; unit 8/8 + integration 9/9 green. Awaiting human verification: re-run `make install` (copies the fixed init.lua) then launch real WezTerm and confirm exactly ONE window."
reasoning_checkpoint:
  hypothesis: |
    BUG1: build.sh main() calls download_release() before build_dev_launcher() when have_luastatic() is false, hitting the placeholder remote base on a local source install.
    BUG2: config/wezterm-setup/init.lua does flat require("keybindings"/"cwd"/"format-tab-title") with no package.path bootstrap; under WezTerm's resolution (config dir only) the require('wezterm-setup') entry loads init.lua via the ?/init.lua form, but the sibling requires then look in the config ROOT, not the wezterm-setup/ subdir -> module not found -> apply() throws -> config-error window.
  confirming_evidence:
    - "build.sh:169-180 main(): have_luastatic false -> download_release first; WEZ_RELEASE_BASE line 44 defaults to placeholder github.com/you/..."
    - "luastatic absent on this box (command -v luastatic empty) confirms the BUG1 trigger condition."
    - "Re-reproduced BUG2: lua5.4 with package.path = scratch-config-dir only -> require('wezterm-setup') -> init.lua:27: module 'keybindings' not found (no file <cfgdir>/keybindings.lua)."
    - "Unit tests require('init') with package.path = config dir, NOT require('wezterm-setup') -> a dotted-require fix would break the unit harness; self-bootstrap is the compatible fix."
  falsification_test: "After fix: same package.path=config-dir-only repro requiring 'wezterm-setup' and calling apply({}) returns NO error; and build.sh on a no-luastatic box makes ZERO network calls and emits the dev launcher."
  fix_rationale: |
    BUG2 self-bootstrap (debug.getinfo(1,'S').source -> own dir -> prepend <dir>/?.lua to package.path BEFORE the sibling requires) makes init.lua resolve its siblings regardless of how it was required. Addresses the root cause (sibling resolution), not the symptom (the error window). Keeps apply_test.lua green because prepending a path is additive and the test's own path entry still resolves 'init'. luastatic only bundles cli/, not config/, so the config-layer change does not affect the single-binary bundle.
    BUG1 reorder: local build path becomes luastatic -> dev-launcher; download_release is retained but gated behind explicit WEZ_REMOTE_BOOTSTRAP=1 opt-in for the future remote installer. A local source install never touches the network.
  blind_spots: "Real WezTerm prepends additional package.path entries; the repro uses the documented config-dir-only subset. debug.getinfo source string format under WezTerm's Lua should match standard (leading '@'); handled by stripping a leading '@'."
tdd_checkpoint: ""

## Evidence

- timestamp: 2026-06-13 — `tools/build.sh` lines 168-180 `main()`: `if have_luastatic() ... else if download_release() ... else build_dev_launcher()`. `have_luastatic()` (lines 51-55) requires luastatic AND lua5.4 AND cc/gcc; absent luastatic → `download_release` runs first. `WEZ_RELEASE_BASE` defaults to `https://github.com/you/wezterm-setup/releases/download` (line 44, placeholder org `you`).
- timestamp: 2026-06-13 — Live install log confirms the order: `[build] Lua toolchain absent -> release-download fallback` → `curl: (22) ... 404` → `[build] no luastatic and no fetchable release -> dev source-launcher`.
- timestamp: 2026-06-13 — Managed block in `~/.config/wezterm/wezterm.lua` is exactly `require('wezterm-setup').apply(config)` (no package.path). Builder: `cli/commands/install_state.lua:172` (and :290) emit only that line.
- timestamp: 2026-06-13 — `config/wezterm-setup/init.lua:27-29` does flat `require("keybindings")`, `require("cwd")`, `require("format-tab-title")`. No package.path bootstrap anywhere in the config tree.
- timestamp: 2026-06-13 — Proof of BUG 2: `lua5.4 -e 'package.path="~/.config/wezterm/?.lua;~/.config/wezterm/?/init.lua;"..package.path; require("wezterm-setup")'` → `false`, error `init.lua:27: module 'keybindings' not found`. WezTerm's default package.path includes only the config dir, not the `wezterm-setup/` subdir.
- timestamp: 2026-06-13 — Blind spot confirmed: `tests/config/apply_test.lua` passes only because the unit harness puts the subdir on package.path; it never exercises WezTerm's real resolution. No integration/e2e test covers install→config-load.

## Eliminated

- hypothesis: "Two windows caused by duplicate format-tab-title handlers (user's inline one + managed apply)" — eliminated: duplicate `wezterm.on` handlers do not spawn windows; and `apply()` throws before its handler registers. The window-error is the config error, not handler duplication. (The stale inline copy in the user's wezterm.lua is a separate cleanliness issue, not the cause.)

## Resolution

root_cause: |
  BUG1 (build.sh path order): tools/build.sh main() called download_release()
  whenever have_luastatic() was false, BEFORE the dev source-launcher. On a box
  with lua5.4 but no luastatic, a LOCAL `make install` therefore attempted a
  network fetch against the placeholder WEZ_RELEASE_BASE (github.com/you/...),
  404'd, then fell back to the dev launcher. Root cause: the remote release-
  download (a future remote-installer-only artifact) was wired into the DEFAULT
  local build path.
  BUG2 (config nested-require resolution): config/wezterm-setup/init.lua did flat
  `require("keybindings"/"cwd"/"format-tab-title")` with NO package.path bootstrap.
  Under WezTerm's real resolution (only the config dir ~/.config/wezterm/ is on
  package.path), the managed-block `require('wezterm-setup')` loads init.lua via
  the `?/init.lua` form, but the bare sibling requires then resolve against the
  config ROOT — not the wezterm-setup/ subdir — so `module 'keybindings' not
  found` -> apply() throws -> WezTerm opens a config-error window beside the main
  one. The unit tests masked this because they `require("init")` with the subdir
  explicitly on package.path; none exercised WezTerm's config-dir-only resolution.
fix: |
  BUG1: tools/build.sh main() reordered so the LOCAL path is luastatic ->
  dev-launcher directly (never the network). download_release() is retained but
  gated behind an explicit `WEZ_REMOTE_BOOTSTRAP=1` opt-in (the future curl|bash
  remote installer's entry); header comment + dev-launcher log message updated to
  match. Placeholder WEZ_RELEASE_BASE left as-is until real releases exist.
  BUG2 (CYCLE 1 — REVERTED): init.lua self-bootstrapped package.path via
  debug.getinfo(1,"S").source. This crashed LIVE in WezTerm: its embedded Lua
  sandbox does NOT expose the `debug` library, so `debug.getinfo` errored with
  `attempt to index a nil value (global 'debug')` at init.lua:42 — config still
  failed to load, two windows persisted. The e2e guard MISSED it because it ran
  the driver under full lua5.4 (which HAS debug). Root lesson: lua5.4 != WezTerm's
  Lua env; the guard must emulate the sandbox.
  BUG2 (CYCLE 2 — SHIPPED, commit eab1726): init.lua uses DOTTED module requires
  instead — require("wezterm-setup.keybindings"/".cwd"/".format-tab-title"). These
  resolve to <config-dir>/wezterm-setup/<sibling>.lua via WezTerm's existing
  <config-dir>/?.lua template, needing NO debug, NO wezterm global, and NO
  package.path mutation. The unit harness (tests/config/apply_test.lua) adds the
  config ROOT (config/?.lua) to package.path so the same dotted names resolve under
  plain lua5.4 too (require("init") still resolves via the subdir entry). The e2e
  guard's BUG2 driver now sets `debug = nil` to emulate the WezTerm sandbox —
  proven to FAIL on the cycle-1 debug.getinfo approach and PASS on the dotted fix.
  luastatic bundles only cli/, not config/, so this layer is unaffected.
  REGRESSION GUARD: tests/integration/install_config_load_integration_test.lua —
  (a) stages the config tree as setup.sh does, builds the REAL managed block via
  install_state.managed_block, and in a FRESH lua5.4 child with package.path =
  config-dir-only runs the block + apply() on a stub config, asserting NO error
  (this FAILS with `init.lua:27: module 'keybindings' not found` when BUG2 is
  reintroduced — verified by splicing out the fix); (b) runs tools/build.sh with
  luastatic forced absent + WEZ_REMOTE_BOOTSTRAP unset + WEZ_RELEASE_BASE pointed
  at an unreachable host, asserting the release-download path is NEVER taken and a
  runnable dev launcher is produced. Wired to run under `WEZTERM_INTEGRATION=1`
  via tools/run-tests.sh (tests/integration/*).
  SECONDARY (D-07, confirm-only): already honored, no change. bootstrap-wezterm.sh
  detect_and_reuse() reuses any adequate preexisting WezTerm untouched and only
  ever symlinks a fetched install into ~/.local/bin; uninstall_state.lua manages
  only {block, wezterm-setup/ config subtree, wez CLI, backups} and NEVER touches
  the `wezterm` binary at all — so a preexisting system WezTerm always stays intact.
verification: |
  - BUG2 falsification (config-dir-only repro): lua5.4 with package.path = scratch
    config dir only -> require('wezterm-setup').apply({}) succeeds with NO error
    (was: init.lua:27 module 'keybindings' not found). apply_test.lua stays green.
  - BUG1 offline build: `WEZ_RELEASE_BASE=<unreachable> ./tools/build.sh` on this
    no-luastatic box -> NO release-download path, emits the dev launcher, and
    `dist/wez version` -> "wez 0.1.0". Zero network calls.
  - Clean install cycle (scratch HOME dogfood): offline build -> place config ->
    `wez install-state` injects the managed block -> headless WezTerm-style dofile
    of the injected wezterm.lua loads cleanly with 28 keys populated (apply ran, no
    error window).
  - Live `wez doctor` on this box (after refreshing the installed config tree with
    the fixed source): ALL core integrity gates PASS, including "config dofiles
    cleanly" (was FAIL with the BUG2 error). Only the advisory "live WezTerm
    session reachable" FAILs (expected headless; never affects exit code).
  - Regression guard proven effective: with BUG2 reintroduced the integration test
    FAILS on the exact module-not-found error; with the fix it passes (13/13).
  - Full suite green: unit `make test` 219 assertions / 0 failed across 8 files;
    integration `WEZTERM_INTEGRATION=1 make test` 232 assertions / 0 failed across
    9 files (adds the new integration test). spec_test.lua's stale
    "main{'doctor'} exits non-zero" assertion — which only passed because the live
    install was BROKEN — was corrected to assert dispatch + numeric exit code
    without coupling to live install health (the blind spot the integration test
    now covers).
files_changed:
  - config/wezterm-setup/init.lua  # BUG2: self-bootstrap package.path from own dir before sibling requires
  - tools/build.sh                 # BUG1: local build never downloads; release-download gated behind WEZ_REMOTE_BOOTSTRAP=1
  - tests/integration/install_config_load_integration_test.lua  # regression guard for BUG1 + BUG2 (WEZTERM_INTEGRATION=1)
  - tests/cli/spec_test.lua        # fix stale doctor assertion coupled to live (broken) install state

## Constraints / Locked decisions

- Pure Lua 5.4, relative requires only (luastatic-compatible), zero external deps. The BUG 2 fix MUST keep init.lua import-safe under plain lua5.4 unit tests (apply_test.lua) AND working under real WezTerm.
- Release-download is a FUTURE end-of-project artifact for the remote `curl|bash` installer; do NOT wire it into local install. Placeholder `github.com/you/...` stays until real releases exist.
- Uninstall must remove WezTerm ONLY if our bootstrap installed it (e.g. into ~/.local/bin); a preexisting system WezTerm stays intact (D-07). If the current uninstall already honors this, just confirm; otherwise align it. (Secondary to the two bugs above.)
- Phase 4 is paused at the 04-02 human-verify checkpoint and resumes after this session lands a working config.
