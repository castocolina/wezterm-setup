---
phase: 07
reviewers: [opencode]
reviewed_at: 2026-09-09T23:56:00Z
plans_reviewed: [07-01-PLAN.md, 07-02-PLAN.md, 07-03-PLAN.md, 07-04-PLAN.md, 07-05-PLAN.md, 07-06-PLAN.md, 07-07-PLAN.md]
models:
  opencode: "xai/grok-4.6"
model_sources:
  opencode: "config"
---

# Cross-AI Plan Review — Phase 07

## Consensus Summary

Single-reviewer cycle (opencode/grok-4.6, source-grounded with full repo access). Overall risk rated HIGH until 07-01/07-02 are tightened; 07-03-07-07 are otherwise executable. Three HIGH-severity structural findings block Wave 1 from doing what it claims:

1. **07-02 never actually produces a Mach-O binary on macOS.** `tools/build.sh`'s `lua_cflags` assignment always succeeds (falls through to a hardcoded default), so the plan's "when lua_cflags is still empty AND brew succeeds" insertion point is dead code — it never runs. `have_luastatic()` also requires `lua5.4` literally on PATH, which a keg-only Homebrew `lua@5.4` never satisfies. Net effect: the dev-launcher fallback silently continues, exactly the bug this plan exists to fix.
2. **07-01 does not close its own auto-gate.** `tools/verify-macos.sh:49-50` still does `export LUA_BIN="${LUA_BIN:-lua}"` when `lua5.4` is absent — Task 2's new resolver only runs when the caller did NOT already export LUA_BIN, so the auto-gate keeps forcing Lua 5.5, the exact bug Task 1 fixes in source. Task 2 never edits this line.
3. **07-05's real install checkpoint can silently install the wrong code.** `curl .../main/tools/install.sh | bash` (and `bash tools/install.sh` with its `WEZ_REF=main` default) fetches published `main`, whose `install_macos()` is still the stub — 07-03's real implementation lives only on this working branch until merged. The plan never pins `WEZ_REF=<this-branch>`, so the checkpoint could pass while testing nothing from 07-03.

### Agreed Strengths
(single-reviewer cycle — no cross-reviewer agreement to synthesize; see per-plan Strengths above)
- The wave ordering itself is correct: fix the suite -> produce a real Mach-O -> implement install -> codesign/CI -> mutate the real machine -> live WezTerm -> flip statuses.
- 07-03's TDD port from `archive/phase-7-macos` (real `install_macos`, PK-magic, `ditto`, four-sibling `ln -sfn` loop) is verified against the actual archived branch content and is sound.
- 07-06/07-07's human-checkpoint framing (live WezTerm session, evidence-gated status flips) matches the project's own established pattern and correctly refuses to rubber-stamp Apple Silicon codesign as Done without arm64 evidence.

### Agreed Concerns
(single-reviewer cycle; see the three HIGH items above and the Cross-plan table in the full review)
- 07-04 tags `requirements: [INST-07]` when the actual work (CI matrix + codesigned darwin assets) is INST-08.
- 07-03 Task 2 does a real live network fetch (nightly .zip) inside an `autonomous: true` task — should be isolated as a checkpoint or network-optional.
- 07-07's blanket "flip all 13 requirement IDs to Done" risks a false v1 close for Apple Silicon (INST-08 aarch64) unless 07-04's macos-14 CI leg is confirmed to have run and passed.

### Divergent Views
Not applicable — single-reviewer cycle.

---

## OpenCode Review

I'll verify each plan against the actual source rather than reviewing in isolation. Loading the referenced files and the phase context first.
The Lua const-reassignment bug and the auto-gate’s NOTE-only probes check out. Next I’ll verify the build, install, and CI claims against the live files.
# Phase 7 Plan Review (verified against source)

Phase 7’s seven plans match the real gaps: `split_kv_segments` really does reassign its `for` control variable (`cli/lib/scene.lua:39-42`), `install_macos()` is still a log-and-return stub (`tools/bootstrap-wezterm.sh:489-494`), `have_luastatic`/`build_with_luastatic` cannot resolve a keg-only Homebrew `lua@5.4`, and `release.yml` is still a single `ubuntu-latest` job (`:51-53`). Wave order is right: fix the suite, produce a Mach-O, implement install, then codesign/CI, then mutate the real machine, then live WezTerm, then flip statuses.

Two structural problems will make Wave 1 lie. Plan 07-02’s keg probe as written never fires because `lua_cflags` is never empty (`tools/build.sh:110-113`), and `have_luastatic()` still requires `lua5.4` on PATH (`:92-94`), so the shipping path stays the dev launcher. Plan 07-01’s auto-gate still exports `LUA_BIN=lua` (`tools/verify-macos.sh:49-50`), which disables the new resolver and re-runs the suite under Homebrew Lua 5.5.

Overall risk: **HIGH** until 07-01/07-02 are tightened; 07-03–07-07 are otherwise executable.

---

## 07-01 — Lua 5.4+ const bug + harness gates

**Summary.** The compile bug is real and the proposed rename is the right fix. Portability probes as PASS/FAIL are the right shape. The plan does not close the auto-gate’s own `LUA_BIN=lua` trap, and it treats `mapfile`/`sha256sum` as still-open code gaps when both are already fixed in the scripts.

**Strengths**
- `segment = trim(segment)` at `cli/lib/scene.lua:42` is a genuine Lua 5.4+ const-loop-var compile error. Existing `parse_pane_spec` cases in `cli/lib/scene_test.lua:115-129` (comma/space trimming) are a real regression guard.
- `tools/verify-macos.sh:57-59` only `note()`s `sha256sum`; there is no `mapfile` assertion. Promoting those to `pass`/`fail` with comment-line filtering matches the grep-gate hygiene already used in `tests/cli/bootstrap_macos_test.lua` on the archive branch.
- `tools/run-tests.sh:28-32` really does hard-exit 127 if the literal `lua5.4` is missing. Mirroring `resolve_dev_lua()` (`tools/build.sh:428-452`) is the correct idiom.

**Concerns**
- **HIGH** — `tools/verify-macos.sh:49-50` still does `export LUA_BIN="${LUA_BIN:-lua}"` when `lua5.4` is absent. Task 2’s resolver only runs when the caller did **not** export `LUA_BIN`. The auto-gate therefore forces Lua 5.5, which is the bug Task 1 just fixed. Task 2 never edits this block.
- **HIGH** — Task 2’s `<automated>` verify is a broken `A && B && echo STALE || run verify-macos.sh` chain: a remaining `mapfile` still runs the auto-gate; a stale `LUA_BIN=lua` line prints `STALE_DOC_STILL_PRESENT` and skips the live run.
- **MEDIUM** — `mapfile` in `tools/run-tests.sh` is already gone (`:56-64`, while-read). `sha256sum` already has a `shasum -a 256` fallback (`tools/build.sh:392-396`). Task 2 correctly gates these, but `docs/macos-verification.md:111-114` and `:463` still claim the harness uses `mapfile`. Task 2 only rewrites the `LUA_BIN=lua` sentence (`:109-110`), so the runbook stays wrong.
- **LOW** — Task 1’s verify itself falls back to `LUA_BIN=lua ./tools/run-tests.sh`.

**Suggestions**
- In Task 2, change `verify-macos.sh:49-50` to the same 3-step resolver (PATH `lua5.4` → keg → `lua -v` matches `Lua 5.4`). Never export `LUA_BIN=lua` on faith.
- Split the verify command: fail closed on mapfile count, fail closed on stale `LUA_BIN=lua`, then run the auto-gate.
- While editing Section 1, delete the stale mapfile warning (`docs/macos-verification.md:111-114`, `:463`, appendix `:481`).

**Risk:** **HIGH** — without the `verify-macos.sh` LUA_BIN fix, Success Criterion 1’s auto-gate still compiles the suite under 5.5.

---

## 07-02 — luastatic Mach-O build

**Summary.** Header/lib resolution really is Linux-shaped and will miss a Homebrew keg. The plan’s insertion point is wrong: `lua_cflags` is never empty, and `have_luastatic()` never looks at the keg, so Task 2 can install `luastatic` and still get the dev launcher.

**Strengths**
- `build_with_luastatic()` (`tools/build.sh:109-128`) tries `pkg-config lua5.4` / `lua-5.4` / `lua`, then `-I/usr/include/lua5.4`, and walks only Linux `liblua5.4.a` paths. No `brew --prefix lua@5.4` exists here. `resolve_dev_lua()` (`:428-452`) already has the keg idiom to copy.
- Live facts in the plan (keg-only, `include/lua/` not `include/lua5.4/`, `lua.pc` not `lua5.4.pc`) match how Homebrew ships `lua@5.4`.
- Task 2’s `file dist/wez` + `./dist/wez version` bar is the right C-1 close-out. `main()` already smoke-tests non-empty `version` output (`:517-523`).

**Concerns**
- **HIGH** — cflags assignment always succeeds:

```110:113:tools/build.sh
  lua_cflags="$(pkg-config --cflags lua5.4 2>/dev/null \
    || pkg-config --cflags lua-5.4 2>/dev/null \
    || pkg-config --cflags lua 2>/dev/null \
    || echo '-I/usr/include/lua5.4')"
```

  Task 1 says “when `lua_cflags` is still empty AND brew succeeds.” That condition is dead. A mechanical edit after this assignment never takes the keg path; luastatic then compiles against missing `/usr/include/lua5.4`.
- **HIGH** — `have_luastatic()` (`:92-94`) requires `command -v lua5.4`. Homebrew `lua@5.4` is keg-only, so it is not on PATH. Task 1 forbids touching `resolve_dev_lua` and never mentions `have_luastatic`. Task 2 only puts `~/.luarocks/bin` on PATH. Result: `main()` (`:482-510`) still takes `build_dev_launcher`. The verify `grep -q "built static binary"` then fails — or worse, a previous `dist/wez` is mistaken for a new Mach-O.
- **MEDIUM** — `resolve_dev_lua`’s comment (`:437`) claims the keg idiom already lives in `build_with_luastatic` at lines 202-209. Those lines are `resolve_stable_latest()`, not keg detection. Stale comment, not a code bug.
- **MEDIUM** — if a CI Mac has `pkg-config` and the generic `lua` 5.5 formula, the third probe (`pkg-config --cflags lua`) wins with 5.5 headers and the keg probe never runs.

**Suggestions**
- Split the `|| echo` off. Order: pkg-config lua5.4 → lua-5.4 → (optional: skip bare `lua` on Darwin) → keg `-I${keg}/include/lua` → then `-I/usr/include/lua5.4`.
- Give `have_luastatic()` the same keg PATH check as `resolve_dev_lua`, or prepend `"$(brew --prefix lua@5.4)/bin"` before the build in Task 2.
- Verify with `file dist/wez` **and** a log line that is unique to this run, not a leftover `dist/wez`.

**Risk:** **HIGH** — as written, this plan does not produce a shipping Mach-O on a stock Homebrew Mac.

---

## 07-03 — real `install_macos` + siblings TDD

**Summary.** Archive port is the right move: `archive/phase-7-macos` has the test file, `wezterm_macos_asset_url()`, and a full `install_macos` with PK-magic, member-safety, `ditto`, and the four-sibling `ln -sfn` loop. `WEZTERM_APP_DIR` is a necessary scratch-dir seam. One verify step is network-heavy for an `autonomous: true` plan.

**Strengths**
- Stub is exactly as described (`tools/bootstrap-wezterm.sh:489-494`). `wezterm_macos_asset_url` is absent from `tools/lib/wezterm-release.sh`. `fetch_to` already exists (`:339`). `PREFIX`/`BIN_DIR` already override (`:63-64`).
- Archived tests are text + sourced-helper only (no live download) — safe RED/GREEN.
- `tests/e2e/tier1/keys_siblings_e2e_test.lua:94-117` really does gate on `OS == "macos"` then `command -v` each sibling. Prepending a scratch `WEZTERM_BIN_DIR` is the correct non-destructive fire.
- Archived sibling loop already includes `strip-ansi-escapes`. Threat T-07-06/07/08 match the archived body’s ordering (magic before `ditto`, named siblings only, no `sudo`/`hdiutil`/`xattr`).
- `${WEZTERM_APP_DIR:-${HOME}/Applications}` still contains `${HOME}/Applications`, so the verbatim archive assertions (`boot_has("${HOME}/Applications")`) stay green.

**Concerns**
- **MEDIUM** — Task 2 is `autonomous: true` yet does a real nightly `.zip` fetch. Rate-limit or layout drift fails the whole plan. The unit suite does not need that fetch; isolate the live proof as a separate checkpoint (or a skip-if-no-network).
- **MEDIUM** — `files_modified` omits `docs/macos-verification.md` / `tools/verify-macos.sh:175`, which still say `install_macos()` is design-only. After this plan those lines are false; 07-05/07-07 are supposed to fill the runbook, but the auto-gate skip text will mislead until then.
- **LOW** — archived `bootstrap_macos_test.lua` never greps `strip-ansi-escapes` (only `wezterm-gui` / `wezterm-mux-server`). E2E covers the fourth binary; the unit file does not. Porting verbatim keeps that hole.
- **LOW** — `keys_siblings_e2e_test.lua` does not use `WEZ_BIN`. The verify’s `WEZ_BIN=./dist/wez` is unused. Harmless, but it falsely implies a 07-02 dependency.

**Suggestions**
- Keep TDD autonomous; make the scratch `install_macos nightly` + quarantine `xattr` recording a `checkpoint:human-verify` (or `network:required` with a pinned dated tag, not floating `nightly`).
- After GREEN, update `verify-macos.sh:175` so the auto-gate no longer tells operators to pre-install WezTerm.
- Add one unit assertion for `strip-ansi-escapes` rather than relying only on e2e.

**Risk:** **MEDIUM** — implementation is sound; the live-fetch-in-autonomous-task is the main failure mode.

---

## 07-04 — codesign + CI matrix

**Summary.** Restoring a 3-leg matrix and signing at build time is the right INST-08/D-06 close. Codesign-as-warning fights the smoke test and the “don’t publish a dead arm64 asset” threat. Frontmatter tags INST-07; the work is INST-08. Task 3 as a blocking human checkpoint is correct.

**Strengths**
- Header at `.github/workflows/release.yml:44-50` explicitly defers macOS legs and names `macos-15-intel` / `macos-14`. Build job is a single `runs-on: ubuntu-latest` (`:51-53`). Codesign comment at `:122-123` is stale once Task 1 lands.
- `tools/ci-setup-toolchain.sh:61-65` really does `brew install lua luarocks` (generic 5.5). `assert_and_capture` then requires `lua5.4` on PATH (`:89-91`) — the same keg-only bug 07-01/07-02 hit. Exporting `${keg}/bin` onto `PATH`/`GITHUB_PATH` is required, not optional.
- Prune step uses `mapfile` (`:210`). Scoping it to the ubuntu leg is the right D-08 fix; rewriting `mapfile` is unnecessary.
- `workflow_dispatch` already exists (`:32`). Task 3 can fire without a tag.
- `main()` smoke-tests `"${OUT}" version` (`tools/build.sh:517-523`). On arm64, an unsigned binary dies here, so CI will not upload a SIGKILL’d asset even if codesign is non-fatal.

**Concerns**
- **HIGH** — Task 1 makes codesign failure a warning so “a local dev build is not bricked.” On Apple Silicon that unsigned binary is inert; on CI the smoke test then fails the job anyway. Pick one: **fatal on Darwin** (matches T-07-11 and INST-08’s “Silicon asset ad-hoc-codesigned”), warning only if `codesign` is absent.
- **MEDIUM** — `requirements: [INST-07]` is the wrong ID. This plan is INST-08 (matrix + codesigned darwin assets) plus D-06. INST-07 is the curl|bash one-liner (07-05).
- **MEDIUM** — `install_macos()` in `ci-setup-toolchain.sh` still does `luarocks install luastatic` **without** `--local` and without adding `~/.luarocks/bin` (Linux does both, `:48-57`). Task 2 only switches the formula. macos-14 may still fail `command -v luastatic`.
- **MEDIUM** — CONTEXT D-01 promised Intel **and** Silicon hardware this phase. Task 1 records x86_64-only local verification. The macos-14 CI leg **is** arm64 runtime evidence if smoke-test runs after codesign — 07-07 should cite that instead of a blanket “unverified.”
- **LOW** — `grep -c "brew --prefix lua@5.4"` in 07-02’s verify can pass from `resolve_dev_lua` alone if Task 1’s keg probe is folded into one occurrence. 07-04 should not rely on that count.

**Suggestions**
- Make `codesign_macos_binary` fatal when `platform_os` is macos and `codesign` exists; skip (don’t warn-and-continue) only when `codesign` is missing.
- Mirror Linux: `luarocks install --local luastatic` + persist `~/.luarocks/bin` and the lua@5.4 keg on `GITHUB_PATH`.
- Retag requirements `[INST-08]` (and D-06). In Task 3, record macos-14 `./dist/wez version` as the arm64 SIGKILL-avoidance evidence D-01 asked for.

**Risk:** **MEDIUM** — YAML restore is straightforward; codesign-non-fatal + luarocks PATH are the legs most likely to go red on first run.

---

## 07-05 — real install / doctor / uninstall cycle

**Summary.** Right checkpoint: first plan that mutates `~/.config/wezterm` and `~/Applications`. Backup-first and “log divergences, don’t paper over” match D-03. The one-liner-vs-branch seam is under-specified and can install **main’s stub** `install_macos` instead of this branch’s real one.

**Strengths**
- Section 2 of `docs/macos-verification.md:122-139` really lists the stdout lines, sentinel pair, and `.bak.*` backup the checkpoint compares against.
- `tools/install.sh:113` already has `WEZ_BOOTSTRAP_CMD`; `:128-133` really revive `/dev/tty`. Precondition on 07-02/07-03 is correct.
- T-07-13 backup-before-mutate is the right control for a real-dotfile edit.

**Concerns**
- **HIGH** — `curl …/main/tools/install.sh | bash` fetches **published `main`**, whose `install_macos` is still the stub. Even `bash tools/install.sh` defaults `WEZ_REF=main` (`tools/install.sh:76`) and unpacks that tarball. `WEZ_BOOTSTRAP_CMD=./tools/setup.sh` runs local setup **after** still downloading main. The plan never says `WEZ_REF=<this-branch>`. Human review can catch it; an executor following the curl one-liner will not exercise 07-03 at all.
- **MEDIUM** — Task 2 drives `make uninstall` against the real machine, then reinstalls. If uninstall excision regresses on BSD, the Task 1 backup is the only rollback. Spell the restore command (`cp /tmp/wezterm.lua.pre ~/.config/wezterm/wezterm.lua`) in the checkpoint.
- **LOW** — BSD `cp -R` trailing-dot is listed in the runbook (`:38`, `:465`) and CONTEXT D-08. Easy to skip in the report; call it out as a required observation.

**Suggestions**
- Default the checkpoint to `WEZ_REF=<current-branch> bash tools/install.sh` (or `./tools/setup.sh --force` from the checkout). Use the `main` one-liner only after merge.
- Record Gatekeeper against **real** `~/Applications/WezTerm.app`, distinct from 07-03’s scratch `xattr` (the plan already says this; keep it as a hard report line).

**Risk:** **MEDIUM** — process is right; wrong-ref install is the silent miss.

---

## 07-06 — live WezTerm + visual review

**Summary.** This is the only honest place for FOUND-01, DIAG-05, PANE-*, SCEN-*. Routing GUI work through `checkpoint:human-verify` matches project convention. A-1 zsh confirmation is a real leftover (`MACOS-PARITY-AND-FOLLOWUPS.md` A-1 still says confirm on runbook §6). Naming `e2e-visual-review` instead of a vague “looks fine” is the right D-02 mechanism.

**Strengths**
- `tools/verify-macos.sh:90-105` checks `__complete` contexts including `scene-layouts` but **not** `scene-colors`, and the zsh Tab path cannot be auto-gated. Putting A-1 in Task 1 is correct.
- Windowing invariant is named in the runbook (`docs/macos-verification.md:43`) and C-7. Checking no per-scene Aqua window is the actual SCEN macOS risk.
- Skill `.claude/skills/e2e-visual-review/SKILL.md` exists in this repo.

**Concerns**
- **MEDIUM** — Task 2 covers TAB-01..05 in the Results table, but those IDs are already Complete in REQUIREMENTS.md with no macOS-deferred note. Fine to verify; 07-07 must not treat a TAB flip as closing a D-18 deferral that isn’t there.
- **MEDIUM** — `verify-macos.sh:121-126` still talks about “KNOWN-BUG A-1” as possibly unwired. After 07-06 closes A-1, that block should become a real pass/fail or 07-07 will leave a contradictory NOTE in the auto-gate.
- **LOW** — OSC 7 “needs a NEW shell” is easy to skip; the runbook already flags it. Keep it as a blocking observation, not a “we ran `wez doctor` in the old shell.”

**Suggestions**
- Task 1: also `wez __complete scene-colors` (auto-gate gap) plus the zsh Tab check.
- Require the visual-review skill’s per-item checklist in the SUMMARY (tab accent, emoji cell-width, active vs inactive, no Aqua window) — T-07-15 already says this; make it an acceptance line, not a hope.

**Risk:** **LOW** — scope is verification, not new code. Residual risk is rubber-stamping visuals.

---

## 07-07 — D-07 decision + status flips

**Summary.** Closing from cited SUMMARYs, and refusing to mark Apple Silicon Done without evidence, is the right gate. Two honesty traps: flipping all 13 IDs including ones this hardware/CI did not prove, and treating 07-04’s x86_64-only note as if macos-14 never ran.

**Strengths**
- D-07 “verify-then-decide” matches CONTEXT and `tools/install.sh` having no `xattr` today (confirmed: no `com.apple.quarantine` in `install.sh`). Adding a Darwin-gated strip only if 07-03/07-05 measured a block is correct.
- REQUIREMENTS.md traceability really is inconsistent: INST-01/06 still say “macOS deferred D-18” (`:85`, `:90`); PANE-01..04 and SCEN-03/04/06 are bare `Pending` (`:104-116`); ROADMAP coverage is more detailed. Reconciling both docs is necessary.
- T-07-17 (no citation, no flip) is the right control against a fake v1 close.

**Concerns**
- **HIGH** — acceptance says every one of the 13 IDs gets `Done (Phase 7, macOS: …)`. CONTEXT D-01 required Silicon evidence. If 07-04 Task 3’s macos-14 leg failed or was skipped, INST-08’s darwin-aarch64 asset is **not** Done. The plan allows a blanket flip plus a footnote. That footnote must block INST-08/SC#3, not sit under them as Done-with-asterisk.
- **MEDIUM** — INST-07/08/09 are `Pending` in REQUIREMENTS.md even on Linux. Flipping them to “Done (Phase 7, macOS: …)” without also recording that Phase 6 already shipped the Linux half will make traceability look like Phase 7 implemented the one-liner.
- **MEDIUM** — `autonomous: true` on a plan whose Task 1 **must** read 07-03/07-05 SUMMARYs. If those SUMMARYs omit the literal `xattr` output, Task 1 cannot decide. Make “quarantine evidence present in SUMMARYs” a precondition, not an in-task hope.
- **LOW** — placeholder deviations table (`docs/macos-verification.md:444-447`) is three empty rows. Removing unused placeholders is specified; also tick or strike the “Candidate deviations” checklist (`:449-471`), several of which 07-01/07-02 already disproved (`mapfile`, `sha256sum`).

**Suggestions**
- Per ID: `Done` only with `plan-id` + runbook section; otherwise `Open: <reason>`. Do not use `Done` for the arm64 SIGKILL case unless 07-04’s macos-14 smoke test is on record.
- Precondition Task 1 on 07-03 SUMMARY containing the scratch `xattr -p` line and 07-05 SUMMARY containing the real-`~/Applications` Gatekeeper observation.
- Tick MACOS-PARITY C-1 `sha256sum`/`mapfile` from **07-01’s gate** (code already landed earlier), not as if 07-07 fixed them.

**Risk:** **MEDIUM** — bookkeeping plan; the damage mode is a false v1 close, which T-07-17 only catches if citations stay mandatory.

---

## Cross-plan / phase-level

| Issue | Severity | Where |
|---|---|---|
| `have_luastatic` + never-empty `lua_cflags` → Wave 1 never produces a Mach-O | HIGH | 07-02; blocks 07-04/07-05 |
| `verify-macos.sh` exports `LUA_BIN=lua` → suite runs under 5.5 | HIGH | 07-01; poisons SC#1 |
| Wrong git ref on the real one-liner → stub `install_macos` | HIGH | 07-05 |
| D-08 `mapfile`/`sha256sum` already fixed in code; docs/C-1 still open | MEDIUM | 07-01, 07-07 |
| CONTEXT D-01 (both arches) vs 07-04/07-07 (x86_64 + optional CI) | MEDIUM | 07-04 Task 3 is the close if macos-14 smoke-tests |
| 07-04 tagged INST-07 instead of INST-08 | MEDIUM | frontmatter |
| 07-03 live nightly fetch inside `autonomous: true` | MEDIUM | 07-03 Task 2 |
| Wave file-disjoint claim holds (07-01/02/03 touch distinct files) | — | OK, but 07-02 must actually build or 07-03’s `dist/wez` is irrelevant |

**Does this phase achieve the ROADMAP goal?** After the HIGH fixes: yes for Intel macOS parity of INST/FOUND/DIAG/PANE/SCEN, with D-07 decided from evidence. Not yet as written: 07-02 will not produce the shipping artifact, 07-01’s auto-gate can still run the wrong Lua, and 07-07 can stamp Done on an arm64 asset that never ran.

**Recommended before execute:** patch 07-01 Task 2 (`verify-macos.sh` resolver + verify command) and 07-02 Task 1–2 (`lua_cflags` restructure + `have_luastatic` keg PATH). Do not start Wave 2 until `file dist/wez` reports Mach-O and `codesign` is in the same build step.
