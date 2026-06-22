# macOS Parity & Cross-Phase Follow-ups

> **Single source of truth** for everything pending after Phase 5. Phases 1–4 are
> CLOSED + verified and Phase 5 is feature-complete on Linux — so these items do NOT
> live inside individual phase dirs. macOS parity is the **batched cross-phase pass
> (decision D-18)**: one pass over all shipped features, driven on a real Mac by
> `docs/macos-verification.md` (step-by-step, agent-drivable) + `tools/verify-macos.sh`
> (auto-runs the non-interactive checks).
>
> Captured 2026-06-14. Sections are grouped by the capability/phase that ships the
> behavior, but the work itself is scheduled as the **upcoming macOS pass** (then
> `/gsd-complete-milestone`), not as reopened phases.

---

## A. Functional follow-ups (NOT macOS-specific — apply on every platform)

### A-1 ✅ RESOLVED 2026-06-14 — `scene new --layout`/`--color` value completion
- **Was:** the `scene)`→`new)` arm only completed flag *names*, so `wez scene new --layout <Tab>`
  fell back to filenames despite the `scene-layouts` context existing.
- **Fix shipped:**
  - `cli/lib/scene.lua` exposes `M.COLOR_NAMES` (ordered palette) and derives the validator from
    it (single source, mirrors `M.LAYOUTS`).
  - `cli/commands/complete.lua` adds a `scene-colors` context (palette, NO `reset`).
  - `cli/commands/completions.lua` `gen_zsh`+`gen_bash` `new)` arm branches on the previous word:
    `--layout) → scene-layouts`, `--color) → scene-colors`, else the flag names (zsh via
    `${words[CURRENT-1]}`, bash via `$prev`).
  - Regression tests: `completions_test.lua` (routing, both shells) + `complete_test.lua`
    (`scene-colors == scene.COLOR_NAMES`, no `reset`).
- **Verified:** full suite 31/31; `verify-macos.sh` PASS=26 FAIL=0; **bash runtime proven**
  (`--layout`→layouts, `--color`→10 colors, prefix `gr`→`grid`). zsh runtime: `zsh -n`-clean +
  text-correct.
- **zsh runtime CONFIRMED on macOS (07-05 §4/§6, 2026-06-22):** driven live in a real interactive
  zsh via `zsh/zpty` completion capture under `compinit -u` (no insecure-dir warning) — the
  `${words[CURRENT-1]}` arm fires: `wez scene new --layout <Tab>` → `tall tall:mirrored grid
  horizontal`; `wez scene new --color <Tab>` → the 10-color palette (no `reset`). A-1 fully closed.
- **Still open (minor, low priority):** `--pane` / `--title` values don't complete (no obvious
  closed candidate set for a `--pane` spec).

### A-3 `wez update` post-install launcher resolution (Phase 6 code-review, deferred)
- [ ] **Wire the installed binary to its companion shell scripts.** `cli/commands/update.lua`
      resolves `tools/install.sh` (launcher) + `tools/bootstrap-wezterm.sh` (the
      `wezterm_install_is_user_path` predicate + `resolve_want_datestamp`) via `repo_root()`,
      which inside the shipped luastatic bundle depends on `WEZ_REPO_DIR`. `tools/setup.sh`
      does **not** export `WEZ_REPO_DIR` nor place those scripts in a stable managed location,
      so `wez update`'s live delegation only works from a checkout today. Fix alongside cutting
      the first `vN.N.N` release (Open Q3): have `setup.sh` place `install.sh` +
      `bootstrap-wezterm.sh` under `${SETUP_DIR}/` and export `WEZ_REPO_DIR`, **or** have
      `update.lua` fall back to the remote `curl …/install.sh | bash` one-liner. The pure
      comparators + system-install guard are unaffected and fully tested.
      *(Phase 6 review Important #2; pure-logic half verified, live delegation is the gap.)*

### A-2 UX backlog from the Phase 5 review (deferred, not blocking)
- [ ] `wez scene list` — a first-class, non-error "what can I launch?" browse surface
      (reuses the existing `list_recipe_names` provider; closes the discoverability gap).
- [ ] Did-you-mean on unknown recipe (`scene launch dcoker` → "did you mean 'docker'?").
- [ ] Unify error-prefix convention project-wide (`error:` vs `wez <cmd>:`).
- [ ] Delete or align the dead `scene` dispatcher branch (`scene.lua` — unreachable since
      argparse intercepts bare `wez scene`).
- [ ] README: document the recipe `command` edge cases (comma-in-command + `=`-in-bare-command
      mis-split) so hand-editors know the safe shapes.

---

## B. Clarifications (NOT bugs — new requirements if wanted)

- **`bg` = `wez pane color`.** Setting a pane background IS `wez pane color <name|hex>`;
  there is no separate `bg` subcommand. A literal `bg` alias would be a new requirement.
- **`opacity` does not exist.** No pane/tab opacity control ships in v1. New requirement (v2)
  if desired.
- Shipped identity surface is exactly: `pane color`, `pane title`, `tab color`,
  `tab color --title`, `tab title` (titles accept an icon-name + text).

---

## C. macOS batched pass (D-18) — by capability

> Full step-by-step lives in `docs/macos-verification.md`. This is the checklist index;
> tick here as the runbook sections pass. Auto-checkable items are also covered by
> `tools/verify-macos.sh`.

### C-1 Toolchain & Gatekeeper (blocks everything — do first)
- [x] Xcode CLT / `clang` present; `luastatic` links a runnable **Mach-O** binary. *(07-05: CLT
      present, `setup-dev.sh` provisioned lua@5.4 + luastatic, `build.sh` built the static binary,
      `verify-macos.sh` §1 PASS.)*
- [x] **Gatekeeper / quarantine:** CLEARED (07-04 Task 2, D-07) — the curl-download install set NO
      `com.apple.quarantine` on `wez` or `WezTerm.app`; Gatekeeper did not block first launch.
      Manual `xattr -d` / right-click-open note retained as a browser-download fallback.
- [x] **Apple Silicon codesign:** verified at BUILD time (07-04 §A, macos-14 leg):
      `codesign --verify dist/wez` → valid + DesignatedRequirement satisfied; `./dist/wez version`
      ran on the arm64 runner. Real-Silicon first-launch is the non-gating Phase 7.1 check (D-01/D-06).
- [x] `tools/build.sh` remote path uses `shasum -a 256` (the D-08 portable branch); E2E checksum
      gate verified before chmod (07-04 §B). `sha256sum` absence noted, not fatal.
- [x] `tools/run-tests.sh` runs under this Mac's bash with the D-08 fix — unit suite green
      (`all 31 file(s) passed`, 07-05 auto gate §1).

### C-2 Install / uninstall (Phase 1 — INST-01..06)
- [x] All INST checks pass on macOS — INST-01 single managed block, INST-02 backup
      (fresh-install exception), INST-06 `.app` placement: 07-04 Task 2 live E2E (runbook §B).
- [x] **INST-06 real gap CLOSED:** `install_macos()` (implemented 07-02) downloads the official
      nightly `.zip` and places `~/Applications/WezTerm.app` sudo-free — confirmed live (07-04 §B,
      `wezterm 20260622-120102-6ff54928`).
- [x] `cp -R config/wezterm-setup/. dst/` trailing-dot semantics on BSD `cp` — no stray `.` entry;
      the config tree (`init.lua keybindings.lua cwd.lua … scenes/`) placed correctly (07-04/07-05).

### C-3 Foundation + doctor (Phase 1 — FOUND-01..05, DIAG-01)
- [x] CWD inheritance (OSC 7) fires on macOS shells after rc registration (FOUND-01, headline item)
      — 07-05 §3: `__wezterm_osc7` precmd active in zsh; `cli split-pane` child inherited the
      parent's `cd`-ed cwd (not `$HOME`), recorded via `wezterm cli list --format json`.
- [ ] `Cmd+K` clears screen+scrollback (maps to Command, not Control) (FOUND-02). *(07-05:
      modifier mapping CONFIRMED in the `wez keys` table — curated bindings ride `SUPER+…` = Command
      on macOS; the live keystroke repro is PENDING — screen locked during the harness drive.)*
- [x] `wez doctor` green / fails loudly on macOS (DIAG-01) — `doctor_exit=0`, all 5 core gates PASS
      (07-04 §B + 07-05 §3).

### C-4 Diagnostics + completion (Phase 1 — DIAG-02..05)
- [~] `wez keys` / `--json` / grouping / source classification on macOS. *(07-05 §4: grouping +
      `[setup]`/`[default]` source classification + Conflicts section all PASS;
      **`--json` FAILS** — cross-platform `dkjson` require-path bug, NOT a macOS divergence,
      deferred to a bugfix — see `deferred-items.md` 07-05 + runbook deviation #5.)*
- [x] Completions install on macOS: `compinit` loaded `_wez` with NO insecure-dir warning
      (`compinit -u`, user-owned site-functions); zsh `wez <Tab>` fires live. *(bash-completion@2
      runtime not exercised; generated bash script passes `bash -n`.)*
- [x] **Completion value coverage** — all 7 `__complete` contexts non-empty + driven live in zsh:
      `wez pane color <Tab>` (palette+reset), `wez tab color <Tab>`, `wez scene launch <Tab>`
      (`ai dev docker`), and A-1 `wez scene new --layout/--color <Tab>` (CONFIRMED — A-1 no longer
      the known-broken one; see A-1 above).

### C-5 Pane identity (Phase 2 — PANE-01..04)
- [ ] `wez pane color` (incl. `bg` == this) / `reset` / `title` / persistence on macOS.
- [ ] OSC 1337 `SetUserVar` → background mapping honored identically by macOS WezTerm.
- [ ] Emoji/icon glyph in pane title renders (cell-width differs on macOS).

### C-6 Tab identity (Phase 3 — TAB-01..05)
- [ ] Tab color / combined / priority / active-distinct on macOS.
- [ ] Tab-bar accent + active indicator + emoji glyph rendering parity (`format-tab-title.lua`).

### C-7 Ad-hoc scenes (Phase 4 — SCEN-01..02)
- [ ] All 4 layouts + per-pane commands + validate-before-emit on macOS.
- [ ] **Windowing:** reuse 1-pane tab / new tab in same window — never a per-scene Aqua window.

### C-8 Named scenes (Phase 5 — SCEN-03..06)
- [~] `scene launch` happy path (live mux) + all error/exit-code paths on macOS. *(07-05 §7c: ALL
      error/exit-code paths PASS against the installed scenes dir — no-name→2, unknown→1, traversal→1,
      malformed→1 no-traceback, no-recipes→2, copy matches UI-SPEC. The live happy-path VISUAL
      materialization is PENDING ui-ux — screen locked.)*
- [x] Seeding copy-if-absent (D-06 no-clobber) on macOS; `ls -1` / path resolver on APFS — 07-05
      §7a + auto gate §5: fresh seed → 3 `seeded`, reseed → `kept existing` byte-identical, installed
      `ai/dev/docker.toml` present.
- [x] `scene launch <Tab>` dynamic completion on macOS shells — 07-05 §7d: live zsh TAB →
      `ai dev docker`; dynamic add/remove `zzz` with no regeneration; `zsh -n`/`bash -n` clean.

---

## How to run the macOS pass (the future workflow this enables)

1. On the Mac: clone, then `bash tools/verify-macos.sh` for the auto-checkable gate.
2. Drive `docs/macos-verification.md` top-to-bottom (agent-drivable; pair with
   `agent-ui-ux-designer` for the visual/UX dimensions — tab-bar glyphs, pane bg, copy).
3. Log every divergence in the runbook's **macOS deviations** table.
4. Fold confirmed gaps back here; fix; then `/gsd-complete-milestone`.
