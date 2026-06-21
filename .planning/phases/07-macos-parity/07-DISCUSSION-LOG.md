# Phase 7: macOS Parity Pass - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-15
**Phase:** 07-macos-parity
**Areas discussed:** Mac access & target arch, INST-06 install_macos, Codesign & Gatekeeper, Harness portability

---

## Mac access & target arch — hardware

| Option | Description | Selected |
|--------|-------------|----------|
| Apple Silicon only | arm64 verified; darwin-x86_64 CI-built-only | |
| Intel only | x86_64 verified; Silicon + ad-hoc codesign unverified | |
| Both Silicon + Intel | Verify both arches end-to-end; every darwin asset + codesign gets hardware evidence | ✓ |
| No Mac right now | Prep-only; flips wait for a future on-Mac session | |

**User's choice:** Both Silicon + Intel
**Notes:** Enables full SC#1/SC#2 closure this phase across both arches.

## Mac access & target arch — verification model / evidence (SC#4)

| Option | Description | Selected |
|--------|-------------|----------|
| Agent on the Mac + deviations table | Claude Code drives verify-macos.sh + runbook; PASS/FAIL + deviations table + agent-ui-ux-designer notes; flips cite runbook section | ✓ |
| Manual self-drive + screenshots | User drives runbook by hand; checked boxes + screenshots; UX agent pass skipped/manual | |
| Auto-gate only | verify-macos.sh PASS sufficient; interactive/visual sections deferred | |

**User's choice:** Agent on the Mac + deviations table
**Notes:** Sets the evidence bar (D-03) for flipping deferred→Done.

---

## INST-06 — install_macos behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Real .app placement (sudo-free) | Download macOS WezTerm, place WezTerm.app in ~/Applications; matches ROADMAP SC#3 | ✓ |
| Document pre-install as supported | Require user to install WezTerm.app themselves; just verify/detect | |
| Detect + guided fallback | Detect; if absent print exact brew/download steps and exit | |

**User's choice:** Real .app placement (sudo-free)

## INST-06 — artifact source / version target

| Option | Description | Selected |
|--------|-------------|----------|
| Nightly .zip → unzip to ~/Applications | Official nightly macOS .zip, unzip; reuse nightly-default + resolve_want_datestamp; no DMG | ✓ |
| Nightly .dmg → hdiutil mount + copy | More native, adds mount/eject complexity | |
| Let research decide format | Lock requirement, let researcher pick .zip vs .dmg | |

**User's choice:** Nightly .zip → unzip to ~/Applications
**Notes:** Consistency with Linux nightly contract (Phase 6, 06-06); avoids DMG mount edge cases.

---

## Codesign & Gatekeeper — signing

| Option | Description | Selected |
|--------|-------------|----------|
| Auto ad-hoc sign at build time | build.sh/CI runs codesign -s - on darwin assets before publish; verified on Silicon | ✓ |
| Sign on install, not build | Ship unsigned; install.sh signs locally after fetch | |
| Document manual signing only | Runbook documents codesign + xattr as user steps | |

**User's choice:** Auto ad-hoc sign at build time

## Codesign & Gatekeeper — quarantine

| Option | Description | Selected |
|--------|-------------|----------|
| Strip quarantine during install | install.sh runs xattr -dr com.apple.quarantine on wez + WezTerm.app | |
| Document manual removal only | Leave quarantine; runbook tells user to xattr -d / right-click-open | |
| Verify-then-decide | Confirm on hardware whether artifacts actually get quarantined; only strip if Gatekeeper blocks | ✓ |

**User's choice:** Verify-then-decide
**Notes:** curl downloads often don't set quarantine; avoid an unnecessary xattr mutation (D-07).

---

## Harness portability

| Option | Description | Selected |
|--------|-------------|----------|
| Run on stock macOS (bash 3.2 + BSD) | Replace mapfile with 3.2-safe read loop; sha256sum→shasum -a 256; zero extra installs | ✓ |
| Require bash 4+ / coreutils | Keep mapfile/sha256sum; document brew install as dev prereq | |
| Stock for runtime, brew for dev | Runtime stock; test harness may assume brew bash/coreutils | |

**User's choice:** Run on stock macOS (bash 3.2 + BSD)
**Notes:** Preserves the sudo-free / zero-dependency philosophy for dev tooling too.

---

## Refinement session — 2026-06-20 (Mac access model, re-discussed)

> Context: only an Intel Mac is available this session. The original "Both Silicon + Intel"
> choice (above) could not hold. Re-opened the Mac-access gray area to decide how Phase 7 closes.

### Reconciling "v1 done" with Intel-only availability

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 7 = Intel close, v1 ships | Drop arm64 hardware req from Phase 7 SC; arm64 codesign hardware flip = tracked follow-up | |
| Split: Phase 7 (full build incl. arm64 via CI/CD + ecosystem) + Phase 7.1 (arm64 end-user distribution check only) | Phase 7 does all engineering + agent-driven verification incl. arm64 CI/CD build & codesign; 7.1 is end-user-only distribution validation | ✓ |
| Keep Phase 7 open | Leave Phase 7 partial until a later arm64 session; v1 not declared done | |

**User's choice:** Split into Phase 7 + Phase 7.1.
**User's exact framing:** "Phase 7 is for entire macOS build including arm over CI/CD and full ecosystem checks; 7.1 can be split only for end-user validation, not for agent running things — only distribution checks and report any execution problems, but we expect same experience from Intel chips."

### Where "v1 done" lands

| Option | Description | Selected |
|--------|-------------|----------|
| v1 done at end of Phase 7 | Phase 7 (full build incl. arm64 CI/CD + codesign + Intel ecosystem verification) declares v1 done; 7.1 is post-v1, non-gating | ✓ |
| v1 done after Phase 7.1 | 7.1 Apple Silicon end-user report is the true final gate | |

**User's choice:** v1 done at end of Phase 7. Phase 7.1 is a post-v1, non-gating end-user distribution smoke check.
**Resulting CONTEXT changes:** D-01 rewritten + D-01b added (7/7.1 split); D-03 clarified (evidence bar is Intel-runnable); D-06 codesign "verified at build time, Silicon first-launch confirmed in 7.1"; Phase 7.1 added to Deferred Ideas with a `/gsd-phase` action to add the ROADMAP entry.

---

## Claude's Discretion

- Ordering of runbook drive vs. gap closure (gaps that block verification first, per C-1).
- `shasum` vs `sha256sum` detection mechanism.
- Whether the bash-3.2 read loop is a shared helper or inlined.

## Deferred Ideas

- A-2 UX backlog (scene list, did-you-mean, error-prefix unification, dead dispatcher branch, recipe-command docs) — future / v2.
- A-3 `wez update` post-install launcher resolution (WEZ_REPO_DIR / managed-script placement or remote fallback) — tied to first vN.N.N release.
- A-1 `--pane` / `--title` value completion — minor, low priority.
- `bg` alias / `opacity` control — clarified as new requirements (v2), not bugs.
