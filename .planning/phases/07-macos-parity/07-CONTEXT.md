# Phase 7: macOS Parity Pass - Context

**Gathered:** 2026-06-15
**Revised:** 2026-06-20 — Phase 7 / 7.1 split locked (v1 done at end of Phase 7; arm64 end-user check carved to non-gating Phase 7.1)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 7 is the **macOS parity gate (D-18)** — the final gate before v1 is declared done. It delivers two correlated bodies of work:

1. **Verification** — drive `tools/verify-macos.sh` (auto gate) and `docs/macos-verification.md` (full runbook) top-to-bottom on real Mac hardware, flipping every "macOS deferred D-18" status in REQUIREMENTS.md / coverage to **Done** with recorded evidence.
2. **Gap closure** — implement the deferred platform fixes that the verification depends on: toolchain/Gatekeeper, INST-06 real `.app` placement, build-time codesign, and harness portability to stock macOS.

**No new requirement IDs.** This phase flips the macOS status of existing IDs (INST-01/06/07, FOUND-01, DIAG-05, PANE-01..04, SCEN-03..06) and closes the C-1..C-8 gaps in `.planning/MACOS-PARITY-AND-FOLLOWUPS.md`.

**Scope anchor:** clarify HOW to verify/close on macOS — never add new capabilities. Behavior parity is the target, not new features.

</domain>

<decisions>
## Implementation Decisions

### Mac access & verification model
- **D-01 (REVISED 2026-06-20 — Phase 7/7.1 split):** Only an **Intel (x86_64)** Mac is available this session, but Phase 7 still delivers the **entire macOS build — including the arm64 (`darwin-aarch64`) asset built and ad-hoc-codesigned via CI/CD** — plus the **full agent-driven ecosystem verification** (install_macos `.app` placement, harness portability, the complete runbook, OSC/CWD/pane/tab/scene parity, visual/UX review) run on the Intel Mac. **Phase 7 is the v1 gate: completing it declares v1 done** (see D-01b). arm64 parity is treated as expected from the shared build contract; **no Apple Silicon hardware run is required for the v1 close** — arm64 status flips on the strength of the shared CI/CD build + ad-hoc codesign + Intel-proven ecosystem parity.
  - *(Original D-01: assumed both Apple Silicon and Intel available this phase — superseded. An intermediate revision deferred the whole arm64 path to a later session and blocked arm64 flips on that evidence — also superseded by the 7/7.1 split below.)*
- **D-01b (Phase 7.1 — post-v1 end-user distribution check, NON-gating):** A separate **Phase 7.1** is carved out strictly for **end-user distribution validation on real Apple Silicon** — NOT agent engineering, NOT runbook re-execution. Its sole job: confirm the shipped artifact downloads / installs / launches on an arm Mac and **report any execution problems**, with the expectation of an experience identical to Intel. **Phase 7.1 does NOT gate v1** — it runs after v1 is declared done; any surprises feed a follow-up fix rather than reopening the milestone. **Action:** add a `Phase 7.1` entry to `ROADMAP.md` (via `/gsd-phase`) capturing this end-user-only, non-gating scope.
- **D-02:** The pass is **agent-driven on the Mac** — run Claude Code on the Mac to drive `verify-macos.sh` + the full runbook, including the `agent-ui-ux-designer` visual review for the UX/glyph sections (tab-bar accents, pane bg, emoji cell-width, copy).
- **D-03 (evidence bar — SC#4):** A "macOS deferred → Done" flip requires: `verify-macos.sh` PASS for auto-checkable items **+** the runbook's **macOS deviations table** filled in **+** `agent-ui-ux-designer` notes for visual sections. Each status flip cites the specific runbook section that proved it. **All of this evidence is Intel-runnable** — the bar is met this phase on the Intel Mac. arm64-specific concerns (codesign first-launch on Silicon) are not part of the v1 flip bar per D-01; Phase 7.1 confirms them post-v1.

### INST-06 — install_macos
- **D-04:** Implement **real, sudo-free `.app` placement** (close the design-only stub). `install_macos()` in `tools/bootstrap-wezterm.sh` must actually place `WezTerm.app` when absent — true parity with the Linux installer, matching ROADMAP SC#3.
- **D-05:** Source = official WezTerm **nightly macOS `.zip`** → unzip `WezTerm.app` into **`~/Applications`** (user-path, no sudo, no DMG mount). Reuse the existing **nightly-default + `resolve_want_datestamp`** logic from Phase 6 (06-06) for version selection so macOS and Linux track the same nightly contract. No `hdiutil`/DMG path.

### Codesign & Gatekeeper
- **D-06:** **Auto ad-hoc codesign at build time** — `tools/build.sh` / CI runs `codesign -s - dist/wez` on the `darwin-aarch64` (and `darwin-x86_64`) asset before publishing, so the shipped `wez` binary runs on first launch without user intervention. **Verified at build time this phase** (codesign produces a valid signature on the CI artifact; `codesign --verify` / `spctl` checks where runnable); real Apple Silicon **first-launch** confirmation is the Phase 7.1 end-user check (a self-built arm64 Mach-O is otherwise SIGKILL'd unsigned).
- **D-07 (quarantine — verify-then-decide):** Do **not** preemptively strip `com.apple.quarantine`. First confirm on real hardware whether curl-downloaded `wez` and the unzipped `WezTerm.app` actually carry quarantine and trigger Gatekeeper (curl downloads frequently do **not** set it). **Only** add an `xattr -dr com.apple.quarantine` step to `install.sh` if the on-Mac pass shows Gatekeeper blocking. If added, document why; otherwise the runbook keeps the manual `xattr -d` / right-click-open fallback as a note.

### Harness portability
- **D-08:** The harness must **run on stock macOS** (bash 3.2 + BSD userland, zero extra installs) — preserves the sudo-free / zero-dependency philosophy.
  - Replace `mapfile` in `tools/run-tests.sh` with a bash-3.2-safe `while read` loop.
  - Replace `sha256sum` in `tools/build.sh`'s remote path with detected `shasum -a 256` (fall back / branch by availability).
  - Watch BSD `cp -R config/wezterm-setup/. dst/` trailing-dot semantics (no stray `.` entry) — verify on hardware (C-2).

### Full unattended autonomy (REVISED 2026-06-21)
- **D-09 (all waves autonomous — supersedes the human-checkpoint gates):** the entire phase runs UNATTENDED end-to-end. No `autonomous: false` task remains. The agent drives gh/CI, push, `gh run watch`, log-driven fix + re-push, the curl/install E2E, and the on-Mac parity verification with no human nod.
- **D-10 (auto-push the stable `v*` tag, green-gated — supersedes RESEARCH Open Q1 / the prior blocking-human checkpoint):** the agent cuts + pushes the first stable `v*` tag AUTOMATICALLY, gated only on BOTH the `workflow_dispatch` dry-run AND the real E2E install being green. The green-gate is the sole safety rail (a stable tag is an irreversible public release; the user accepted this trade for full autonomy). When no tag context exists, the unattended path operates on **nightly** builds.
- **D-11 (branch-aware E2E — living branch):** the dispatch targets the current branch explicitly (`gh workflow run release.yml --ref "$(git branch --show-current)"`), and the build version string carries a **`+<branchname>`** suffix when the branch is not `main` (e.g. `nightly-YYYYMMDD+gsd-phase-07-macos-parity`) so the E2E loop installs and verifies *this branch's* artifact. This is the MINIMAL branch-awareness needed for the autonomous loop — the full bootstrapper version-listing UX is deferred (see Deferred Ideas).
- **D-12 (parity verification is agent-driven via a real harness — reinforces D-02):** 07-05 drives WezTerm with `tmux` + `wezterm cli` for keystroke/feature flows, captures visuals with `screencapture`, feeds them to the `agent-ui-ux-designer` subagent for the visual/glyph judgment, and flips the D-18 statuses on the green evidence — no manual visual sign-off.

### Claude's Discretion
- Exact ordering of the runbook drive vs. gap-closure within the phase (planner decides; gaps that block verification — toolchain, codesign, harness — come first per C-1 "blocks everything").
- Detection mechanism for `shasum` vs `sha256sum` (command -v branch vs OS switch).
- Whether the bash-3.2 read-loop is factored into a shared helper or inlined.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase drivers (the source of truth for this phase)
- `.planning/MACOS-PARITY-AND-FOLLOWUPS.md` — the single checklist index (sections A/B/C); C-1..C-8 enumerate every gap by capability, A-1 (resolved) and A-2/A-3 (deferred UX/launcher backlog).
- `docs/macos-verification.md` — the full step-by-step on-Mac runbook (508 lines); drive top-to-bottom, fill the macOS deviations table.
- `tools/verify-macos.sh` — the non-interactive auto gate (182 lines); must PASS on real Mac.

### Files that close the gaps
- `tools/bootstrap-wezterm.sh` — `install_macos()` stub to implement (D-04/D-05); also holds `wezterm_install_is_user_path` + `resolve_want_datestamp` (nightly/datestamp logic to reuse).
- `tools/build.sh` — add build-time ad-hoc codesign (D-06); replace `sha256sum`→`shasum` on remote path (D-08).
- `tools/install.sh` — launcher; potential quarantine-strip site (D-07, conditional).
- `tools/run-tests.sh` — replace `mapfile` with bash-3.2-safe loop (D-08).
- `tools/setup.sh` — relevant to A-3 (deferred) WEZ_REPO_DIR / managed-script placement.

### Requirements & roadmap
- `.planning/ROADMAP.md` §"Phase 7: macOS Parity Pass (D-18)" — goal + 4 success criteria.
- `.planning/REQUIREMENTS.md` — IDs whose "macOS deferred D-18" status flips here (INST-01/06/07, FOUND-01, DIAG-05, PANE-01..04, SCEN-03..06).
- `.planning/PROJECT.md` — platform constraint ("Linux + macOS parity for every shipped feature", sudo-free both platforms, zero external deps for config layer).

### Prior decisions referenced
- `.planning/PROJECT.md` decisions table — CLI language Lua 5.4 (macOS build deferred D-05), OSC 7 CWD (macOS verify deferred D-05), full `wezterm cli` surface (macOS column pending).
- `.planning/phases/06-installer/06-CONTEXT.md` — Phase 6 nightly-default + update-in-place + asset/sha256 contract that the macOS asset build rides on.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`resolve_want_datestamp` + nightly-default logic** (`tools/bootstrap-wezterm.sh`, from 06-06): reuse verbatim for the macOS `.zip` version selection so both OSes track the same nightly.
- **`wezterm_install_is_user_path` predicate**: the user-path / system-install guard already exists; `install_macos` placement to `~/Applications` is a user-path install by construction.
- **Per-asset `.sha256` contract + `download_release()`** (Phase 6): the macOS asset already flows through CI; this phase verifies it on hardware and adds codesign.

### Established Patterns
- **Sudo-free, user-path-only install** (project invariant — no AppImage/Flatpak analog; no system mutation). `.app` placement MUST honor this → `~/Applications`, never `/Applications` with sudo.
- **Verify-before-declaring-done** (CLAUDE.md critical rule): every flip needs recorded `wez doctor` / runbook evidence, no "should work on macOS".
- **Zero external dependencies** for the config/runtime layer; harness portability (D-08) extends that ethos to dev tooling on stock macOS.

### Integration Points
- `install_macos()` connects the existing Linux install flow's structure to a macOS branch — same entry, OS-switched body.
- Codesign hooks into the existing `tools/build.sh` / CI release matrix (06-03) right before publish.
- The runbook + `verify-macos.sh` already enumerate every capability's macOS check; planning maps gaps → fixes → runbook sections.

</code_context>

<specifics>
## Specific Ideas

- The macOS WezTerm artifact is specifically the **nightly `.zip`** (not `.dmg`) — chosen for simplicity and Linux consistency (no mount/eject).
- Codesign is specifically **ad-hoc** (`codesign -s -`, no Developer ID / notarization) — sufficient to clear the SIGKILL-on-unsigned-arm64 issue without an Apple paid cert.
- Quarantine handling is explicitly **conditional on observed behavior** — the user does not want an unnecessary `xattr` mutation baked in if curl downloads don't actually get quarantined.

</specifics>

<deferred>
## Deferred Ideas

- **A-2 UX backlog (Phase 5 review)** — `wez scene list` browse surface, did-you-mean on unknown recipe, unified error-prefix convention, dead `scene` dispatcher branch cleanup, README recipe-command edge-case docs. Not blocking; future phase / v2.
- **A-3 `wez update` post-install launcher resolution** — wiring the installed binary to its companion shell scripts (`WEZ_REPO_DIR` export / managed-script placement, or remote one-liner fallback). Tied to cutting the first `vN.N.N` release (Open Q3); pure comparators already verified. Touch only if the macOS pass surfaces it; otherwise its own follow-up.
- **A-1 `--pane` / `--title` value completion** — minor, low priority; no obvious closed candidate set. (The `--layout`/`--color` half is resolved and only needs zsh-runtime confirmation on the runbook §6.)
- **`bg` alias / `opacity` control** — clarified as NOT bugs; would be new requirements (v2), out of scope.
- **Phase 7.1 — Apple Silicon end-user distribution validation** (per D-01b): post-v1, non-gating, end-user-driven (no agent engineering). Confirms the shipped artifact installs/launches on real arm hardware and reports execution problems; expects Intel parity. Needs a `Phase 7.1` ROADMAP entry via `/gsd-phase`. Not blocking the v1 close.
- **Branch-aware bootstrapper — full UX (deferred follow-up, decided 2026-06-21):** cross-platform installer capability, NOT macOS-specific, so out of the Phase 7 macOS gate. Scope: the bootstrapper lists available **nightly AND release** versions, defaults to the **latest from its originating branch**, **shows releases from that branch**, and accepts a **`--branch <name>`** flag to target a different branch. Phase 7 ships only the MINIMAL slice needed for the autonomous E2E loop (D-11: `--ref` dispatch + `+branchname` version). The listing UI + `--branch` flag + branch-default install UX are their own installer follow-up phase (cross-platform; plan after Phase 7 closes via `/gsd-phase`).

</deferred>

---

*Phase: 7-macos-parity*
*Context gathered: 2026-06-15*
