# wezterm-setup E2E Testing Battery — Product Requirements Document (PRD)

**Document Version:** 1.0
**Created:** 2026-06-24
**Clarification Rounds:** 2
**Quality Score:** 93/100

---

## Requirements Description

### Background

- **Business Problem:** Since Phase 7 (macOS ergonomics) began, the runtime surface
  changed by **~125 commits (45 touching `cli/`/`config/`/`tools/`, +4,674/−700 lines)**
  with verification done almost entirely at the unit/data layer and ad-hoc shell greps.
  The result: a series of user-facing regressions that all passed the existing tests —
  scene panes hanging, raw escape characters leaking into panes, the new-tab keybinding
  silently dead, `wez keys` broken, and a build that aborted `make install`. Each failure
  maps 1:1 to a test that does not exist. There is no repeatable, cross-platform end-to-end
  safety net, and the gap is specifically at the **running-application layer** (mux, GUI
  keybindings, rendered visuals) that unit tests cannot reach.
- **Target Users:** The solo maintainer, daily-driving WezTerm as a full multiplexer on
  **both Linux (Wayland + X11) and macOS**. The battery is a developer/maintainer tool,
  not an end-user feature.
- **Value Proposition:** A repeatable, **Linux-first**, cross-platform E2E battery covering
  ≥80% of real use cases so the next N runtime commits cannot silently regress behavior that
  has already been paid for — and so "verified" means *observed on a running system*, not
  *unit test green*.

### Feature Overview

- **Core Features:** A four-tier E2E battery:
  - **Tier 1 — Subcommands** (deterministic, headless): every `wez` subcommand + exit-code
    contract + emitted-bytes assertions. No mux, no GUI, no permissions.
  - **Tier 2 — Scenes** (live mux): each scene recipe × both launch modes, asserting pane
    count, cwd, user-vars, **no escape leak**, and a **responsiveness probe** (no hang).
  - **Tier 3 — Key combos:** *registration* (deterministic, via `wezterm show-keys`) **and**
    *firing* (OS input injection → assert mux effect).
  - **Tier 4 — Visuals:** hybrid **AI-vision (semantic rubric) + snapshot-diff (stable chrome)**
    on captured screenshots, per-platform committed baselines with manual approval.
- **Feature Boundaries:**
  - **In scope (v1):** all four tiers; Linux + macOS; local `make e2e` runner; a phased
    Linux CI gate for the deterministic tiers; a documented `make e2e-setup` for the
    permission/tool-dependent tiers; a platform-expectations module.
  - **Out of scope (v1):** macOS GUI tiers in headless CI (macOS GUI runs locally only);
    a hard machine-counted coverage % (coverage is directional/enumerated-as-built);
    testing WezTerm internals beyond this project's config/CLI surface.
- **User Scenarios:**
  1. `make e2e` locally on Mac or Linux before pushing → catches regressions pre-commit.
  2. Every PR/push → Linux CI runs the deterministic tiers (T1, T2, T3-registration) as a gate.
  3. After a config/keybinding change → T3 proves the chord still *registers and fires*.
  4. After a tab/scene visual change → T4 flags truncation/escape-leak/uneven tabs.

### Detailed Requirements

#### Tier 1 — Subcommands (deterministic, headless)
- **Input/Output:** invoke each `wez` subcommand; assert exit code, stdout/stderr shape, and
  emitted control bytes where applicable.
- Commands & assertions:
  - `wez version` → exit 0, prints a version string.
  - `wez doctor` → exit 0, gate lines present.
  - `wez keys` → exit 0, non-empty; `wez keys --json` → exit 0 + **valid parseable JSON**.
  - `wez completions bash|zsh` → exit 0, non-empty completion script.
  - `wez seed-scenes` (scratch `WEZTERM_SETUP_DIR`) → copies the 3 recipes (copy-if-absent).
  - `wez scene new …` → emits the expected recipe/spec text (no mux needed).
  - `wez pane color|title|icon` and `wez tab color|title|icon` (+ reset/clear) → exit 0 and
    **capture the emitted OSC bytes**, asserting they are well-formed (OSC-1337/OSC-11, correct
    terminators) — the same stdout mechanism the reuse-pane scene styling depends on.
  - `wez install-state` / `wez uninstall` → idempotency + non-interactive contracts
    (managed-block install/override, `--force`/`--skip`, exit codes; uninstall idempotent when
    the binary is absent; `dist/wez` fallback).
- **Edge cases:** unknown scene name → exit 1; empty recipes dir → exit 2; path-traversal → exit 1;
  non-interactive reinstall over an existing block → `--force` default, exit 0.

#### Tier 2 — Scenes (live mux)
- For **each recipe (ai, dev, docker) × each launch mode (reuse single-pane-tab AND new-tab)**:
  - Assert **pane count == recipe** (no extra/missing panes — explicit parity check, since "no
    additional panes beyond expected" is a hard requirement).
  - Assert each pane's **cwd == launch dir** (D-08) via `wezterm cli list`.
  - Assert **user-vars are set** (color/icon/title) on the styled panes.
  - Assert **no escape-char leak**: `wezterm cli get-text` contains no literal `printf '`,
    no raw octal `\nnn` run, no `quote>`.
  - Assert **responsiveness (no hang)**: send a unique marker via `send-text`, expect it echoed
    within a timeout; absence = hang = FAIL.
  - Always **clean up** spawned panes/tabs; never leave residue in the session.
- **Reuse mode is exercised explicitly** by first creating a single-pane tab and launching into
  it (the path that produced the reported hang); new-tab mode by launching from a ≥2-pane tab.

#### Tier 3 — Key combos
- **Registration (deterministic, CI-able):** parse `wezterm show-keys --lua`; for every curated
  action (SpawnTab, ClearScreenAndScrollback, Split H/V, ClosePane, ZoomToggle, RotatePanes ×2,
  ActivateTabRelative ×2, MoveTabRelative ×2, ActivatePaneDirection ×4, font ±/0, word-nav) assert
  **at least one Cmd-family AND one Ctrl-family chord resolves** to that action. (This is the check
  that would have caught the dead new-tab binding.)
- **Firing (local, OS injection):** inject the real chord at the OS layer and assert the **mux
  effect** (e.g. Cmd+T → tab count +1; Cmd+Shift+H → pane count +1):
  - macOS: `cliclick` / `osascript` System Events (needs Accessibility).
  - Linux X11: `xdotool`; Wayland: `ydotool`/`wtype`.
  - Self-skips cleanly when the tool/permission/mux is absent.

#### Tier 4 — Visuals (local, hybrid)
- Capture a screenshot of the WezTerm window (macOS `screencapture`; Linux `grim`/`scrot`/`import`).
- **AI-vision (semantic):** send the screenshot to a low-cost vision model with a committed,
  per-check **rubric** ("are all tab titles fully legible and even-width? any escape characters
  visible? is the focused pane clean?"). Robust to font/DPI noise; answers "looks right," not
  "pixels changed."
- **Snapshot-diff (chrome):** exact pixel diff with tolerance for stable, deterministic regions only.
- **Baselines:** committed under `tests/e2e/visual/{linux,macos}/` (rubrics, and any golden PNGs);
  first run generates candidates, the maintainer eyeballs and **manually approves** to baseline.

### Data Requirements
- **Platform-expectations module** (single source of truth) encoding legitimate Mac↔Linux deltas:
  keg Lua path vs system lua, `SUPER`=Cmd vs Win, bundle sibling symlinks (mac), bash 3.2 (mac)
  vs 5 (linux), Cmd-interception cases, X11 vs Wayland input tools. Tiers assert against this table
  so parity is explicit, not assumed.
- **Recipe inventory** (ai/dev/docker) and a curated **keybinding-action list** drive T2/T3 enumeration.

---

## Design Decisions

### Technical Approach
- **Architecture:** Assertion logic in **Lua** (identical across platforms, zero runtime deps,
  consistent with the existing `tests/` + `tools/run-tests.sh` harness and the `WEZTERM_INTEGRATION`
  self-skip gate). Orchestration that must shell out (mux driving, OS injection, screenshots) is
  **bash-3.2-safe** — chosen specifically because macOS ships bash 3.2 and Linux ships bash 5, a
  known portability footgun this project already guards against.
- **Key Components:**
  - `tests/e2e/` Lua tiers + a `tools/run-e2e.sh` (bash-3.2-safe) orchestrator.
  - `make e2e` (run battery), `make e2e-setup` (install input/screenshot tools + print the macOS
    permission steps), reusing the existing `make`/`run-tests.sh` plumbing.
  - A **platform-expectations** Lua module and a **self-skip gate** for every tier whose
    dependency (mux, input tool, permission) is unavailable — so CI and headless boxes never flake.
- **Gating model:** `make e2e` runs everything available locally; `WEZ_E2E_INPUT=1` /
  `WEZ_E2E_VISUAL=1` opt the permission-bound tiers in (else they self-skip). CI runs only the
  deterministic subset on Linux.
- **Interface Design:** Each tier emits TAP-ish `ok/FAIL` lines (matching the current harness) so
  results aggregate through `run-tests.sh`/CI uniformly.

### Migration & Reset Strategy (backup branch, main reset, reuse)

This PRD assumes a clean restart of the macOS work. Three explicit steps:

1. **Backup the delta (nothing is lost).** Archive the current `gsd/phase-07.1-macos-post-v1-follow-ups`
   HEAD (71 commits ahead of `main`) as a durable branch, e.g. `archive/phase-7-macos` (also push it).
   Every change — including the buggy ones — stays fully recoverable and cherry-pickable.

2. **Reset `main` — DECIDED: Option A.** Reset to **`v1.0.0` (`77d18cf`)**, the last *shipped*
   release. Keeps the working macOS **build/CI/bootstrap scaffolding** that produced the release,
   drops only the unverified post-v1 behavioral churn; rebuild scene/keys/tab behavior test-first
   on top. (Rejected alternative — Option B: reset to pre-Phase-7 `c066c92`, pure Linux, rebuild the
   entire macOS layer from scratch — more rework for a marginally cleaner slate.)

3. **What to reuse (cherry-pick forward, all independently verified this session):**
   - `39aa3b6` (+`59f803e` test) — dev-launcher Lua 5.4 resolution (made `make install` work; user-confirmed).
   - `7e72bf5` (+`dec5d59` test) — install-cycle: non-interactive reinstall + `dist/wez` uninstall fallback (Error 3 fixed).
   - `9d117cd` (+`2798d6f` test) — `make uninstall` idempotent when binary absent.
   - `4c765e1` (+`959dac0` test) — symlink all WezTerm bundle siblings on macOS (`wez keys` works; user-confirmed live).
   - **Reuse-with-suspicion / redo test-first (do NOT cherry-pick blind):** scene styling
     (leak/chunk/prelude/reuse-stdout), keybindings hybrid (broke new-tab), tab-title truncation —
     these become the first behaviors *rebuilt under the E2E battery*, not reapplied.

### Constraints
- **Performance:** the deterministic tiers must run fast enough to gate CI (target: full T1 < ~60s);
  mux/visual tiers may be slower and are local.
- **Compatibility:** Linux (Wayland + X11) + macOS; bash-3.2-safe orchestration; zero *runtime*
  dependencies (test-only tools installed via `make e2e-setup`, never required by `wez` itself).
- **Security:** sudo-free; no permission is required for the deterministic tiers; the permission-bound
  tiers (Accessibility for firing, Screen Recording for visuals) are opt-in and documented.
- **Scalability:** new subcommands/scenes/keybindings extend the inventory; tiers iterate over it.

### Risk Assessment
- **Flakiness (timing/races):** mitigate with explicit readiness/responsiveness probes, bounded
  retries, and deterministic cleanup; never a bare sleep as the contract.
- **AI-vision non-determinism / cost:** constrain with tight committed rubrics, the **cheapest
  vision-capable model (Haiku-class)**, and using AI-vision for *semantic* verdicts only
  (snapshot-diff for the deterministic chrome).
- **Baseline brittleness:** per-platform baselines + tolerance; AI-vision as the primary visual judge
  so golden-image churn is minimized.
- **macOS GUI in CI:** acknowledged gap — macOS GUI tiers run locally; only deterministic tiers gate CI.
- **Mux/tool/permission absent:** every dependent tier self-skips loudly (never a silent pass).
- **Reset risk:** the archive branch + tags make the reset fully reversible; the reuse list is
  limited to independently-verified commits.

---

## Acceptance Criteria

**v1 done-bar (DECIDED):** the **deterministic tiers (T1 + T2 + T3-registration) are MUST-PASS at
100%** and gate CI; **T3-firing and T4-visuals are local best-effort** (run + reported, non-blocking).
Coverage of the enumerated inventory (Appendix A) is directional ≥80%, with the deterministic tiers
at 100%.

### Functional Acceptance
- [ ] **Tier 1:** every `wez` subcommand has a smoke + contract test (exit code, output shape,
      emitted-byte well-formedness); all pass on Linux and macOS.
- [ ] **Tier 2:** all 3 recipes × both launch modes pass pane-count, cwd, user-var, no-leak, and
      responsiveness checks; spawned panes are always cleaned up.
- [ ] **Tier 3 (registration):** every curated action resolves with both a Cmd-family and a
      Ctrl-family chord in `show-keys`.
- [ ] **Tier 3 (firing):** injected chords produce the expected mux effect on each platform (local).
- [ ] **Tier 4:** AI-vision + snapshot checks run against committed per-platform baselines; the
      tab-title and clean-pane checks are present.
- [ ] **Platform parity:** the expectations module is the single source of Mac↔Linux deltas; tiers
      assert against it.

### Quality Standards
- [ ] Lua tiers pass `tools/run-tests.sh`; bash orchestration passes `bash -n` + `shellcheck` and is bash-3.2-safe.
- [ ] Self-skip is clean and logged for every dependency-absent tier (no silent passes, no hangs).
- [ ] No flakiness across **5 consecutive local runs** (N=5) for the mux tiers.
- [ ] Each tier emits aggregatable `ok/FAIL` output.

### User Acceptance
- [ ] `make e2e` runs end-to-end on both a Mac and a Linux box.
- [ ] `make e2e-setup` installs the input/screenshot tools and prints the macOS permission steps.
- [ ] Linux CI gate runs the deterministic tiers on every PR/push (phase 3).
- [ ] Docs: a `tests/e2e/README` with the tier matrix, the per-platform tool/permission table, and
      the manual visual-baseline approval flow; the Migration & Reset Strategy executed and recorded.

---

## Execution Phases

### Phase 1: Scaffolding + Tier 1 (Linux-first, deterministic)
**Goal:** A runnable local battery with the full deterministic subcommand layer and the platform module.
- [ ] Execute the Migration & Reset Strategy (archive branch, reset `main` per maintainer's option, cherry-pick the 4 verified fixes).
- [ ] `tests/e2e/` scaffold + `tools/run-e2e.sh` (bash-3.2-safe) + `make e2e` / `make e2e-setup` targets.
- [ ] Platform-expectations module + self-skip gate.
- [ ] Tier 1: all subcommands + exit-code/edge-case + emitted-byte assertions; green on Linux, then macOS.
- **Deliverables:** `make e2e` runs T1 on both platforms; README skeleton.
- **Time:** ~1–2 days.

### Phase 2: Tier 2 (scenes) + Tier 3 (registration)
**Goal:** Cover the layer that produced the worst regressions.
- [ ] Tier 2: recipes × modes, with pane-count/cwd/user-var/no-leak/responsiveness + cleanup.
- [ ] Tier 3 registration: `show-keys` Cmd+Ctrl coverage assertions for every action.
- [ ] Demonstrate the battery catching a deliberately reintroduced regression (scene leak + dead new-tab).
- **Deliverables:** mux-gated T2 + deterministic T3-registration; a recorded "caught a regression" run.
- **Time:** ~2–3 days.

### Phase 3: Linux CI gate (phased CI)
**Goal:** Make the deterministic tiers gate every change.
- [ ] Wire T1 + T2 + T3-registration into GitHub Actions on Linux (headless `wezterm-mux-server`).
- [ ] Self-skip verified in CI; gate blocks on real failures only.
- **Deliverables:** green CI gate on PRs/pushes.
- **Time:** ~1 day.

### Phase 4: Tier 3 (firing) + Tier 4 (visuals) — local, permission-bound
**Goal:** Close the GUI/visual gap locally.
- [ ] `make e2e-setup` installs input tools (cliclick / xdotool / ydotool) + screenshot tools; documents macOS Accessibility + Screen Recording.
- [ ] Tier 3 firing: inject chords → assert mux effects, per platform; opt-in + self-skip.
- [ ] Tier 4: hybrid AI-vision + snapshot, committed per-platform baselines, manual-approve flow.
- **Deliverables:** full local `make e2e` covering all four tiers; visual baselines committed.
- **Time:** ~2–3 days.

---

## Appendix A — Enumerated Use-Case Inventory

Coverage = items checked / total. **M** = must-pass (deterministic, gates CI). **B** = best-effort
(local, permission-bound, non-blocking). v1 target: **100% of M**, ≥80% overall.

### A.1 Tier 1 — Subcommands (all **M**, headless)
- [ ] `wez version` → exit 0, version string
- [ ] `wez doctor` → exit 0, gate lines present
- [ ] `wez keys` → exit 0, non-empty
- [ ] `wez keys --json` → exit 0, valid parseable JSON
- [ ] `wez completions bash` → exit 0, non-empty
- [ ] `wez completions zsh` → exit 0, non-empty
- [ ] `wez seed-scenes` (scratch dir) → 3 recipes copied (copy-if-absent; re-run keeps existing)
- [ ] `wez scene new …` → emits expected recipe/spec text
- [ ] `wez scene launch <unknown>` (recipes present) → exit 1
- [ ] `wez scene launch` (empty recipes dir) → exit 2
- [ ] `wez scene launch ../../etc/passwd` → exit 1 (traversal blocked)
- [ ] `wez pane color <name>` / `reset` → exit 0 + well-formed OSC bytes
- [ ] `wez pane title <text>` / clear → exit 0 + well-formed OSC bytes
- [ ] `wez pane icon <name>` → exit 0 + well-formed OSC bytes
- [ ] `wez tab color <name>` / `reset` → exit 0 + well-formed OSC bytes
- [ ] `wez tab title <text>` / clear → exit 0 + well-formed OSC bytes
- [ ] `wez tab icon <name>` → exit 0 + well-formed OSC bytes
- [ ] `wez install-state` fresh → managed block installed; re-run non-interactive → `--force` override, exit 0
- [ ] `wez uninstall` (binary present) → removes block/config/binary, exit 0
- [ ] `wez uninstall` (binary absent, no `dist/wez`) → idempotent warn, exit 0
- [ ] `wez uninstall` (binary absent, `dist/wez` present) → cleans via dev build, exit 0
- [ ] `wez update` → exit 0 / clean no-op when already latest (smoke)

### A.2 Tier 2 — Scenes (all **M**, live mux; self-skip if no mux)
For each of **ai / dev / docker** × **{reuse single-pane-tab, new-tab}** (6 cases), assert:
- [ ] pane count == recipe (no extra/missing panes)
- [ ] each pane cwd == launch dir (D-08)
- [ ] user-vars set (color/icon/title)
- [ ] no escape-char leak in `get-text` (no `printf '`, no `\nnn` run, no `quote>`)
- [ ] responsiveness probe passes (no hang)
- [ ] spawned panes cleaned up

### A.3 Tier 3 — Keybinding actions
Registration (**M**, `show-keys`): each action has ≥1 Cmd-family AND ≥1 Ctrl-family chord.
Firing (**B**, OS injection → mux effect): assert the effect for the chord-producing actions.
- [ ] ClearScreenAndScrollback — reg(M) / fire(B)
- [ ] SpawnTab (new tab) — reg(M) / fire(B: tab count +1)
- [ ] CloseCurrentTab — reg(M) / fire(B)
- [ ] ActivateTabRelative +1 / −1 — reg(M) / fire(B)
- [ ] MoveTabRelative left / right — reg(M) / fire(B)
- [ ] SplitHorizontal — reg(M) / fire(B: pane count +1)
- [ ] SplitVertical — reg(M) / fire(B: pane count +1)
- [ ] CloseCurrentPane — reg(M) / fire(B)
- [ ] TogglePaneZoomState — reg(M) / fire(B)
- [ ] RotatePanes Clockwise / CounterClockwise — reg(M) / fire(B)
- [ ] ActivatePaneDirection Left/Right/Up/Down — reg(M) / fire(B)
- [ ] IncreaseFontSize / DecreaseFontSize / ResetFontSize — reg(M) / fire(B)
- [ ] WordNav left / right (SendString ESC b / ESC f) — reg(M)

### A.4 Tier 4 — Visual checks (all **B**, hybrid AI-vision + snapshot; per-platform baselines)
- [ ] Tab titles fully legible and even-width across same-title tabs (AI-vision)
- [ ] No raw escape characters visible in any pane after a scene launch (AI-vision)
- [ ] Focused/first pane is clean after `wez scene launch` (AI-vision)
- [ ] Distinct per-pane background tints render (AI-vision / snapshot)
- [ ] Emoji icons occupy two cells and align (AI-vision)
- [ ] Fancy tab active vs inactive visual distinction (snapshot)

### A.5 Platform parity matrix (asserted via the expectations module)
- [ ] Lua 5.4 resolution (keg path on mac vs system on linux)
- [ ] `SUPER` = Cmd (mac) vs Win/Super (linux)
- [ ] Bundle sibling symlinks present (mac: wezterm-gui, mux-server, strip-ansi-escapes)
- [ ] bash-3.2-safe orchestration (mac bash 3.2 vs linux bash 5)
- [ ] Input-tool selection (mac cliclick / linux X11 xdotool / Wayland ydotool)

---

**Document Version:** 1.0
**Created:** 2026-06-24
**Clarification Rounds:** 3
**Quality Score:** 100/100
