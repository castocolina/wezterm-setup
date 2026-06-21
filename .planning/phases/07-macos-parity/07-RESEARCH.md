# Phase 7: macOS Parity Pass (D-18) - Research

**Researched:** 2026-06-20
**Domain:** macOS toolchain/Gatekeeper, GitHub Actions macOS CI matrix, sudo-free `.app`/binary install, unattended end-to-end agent verification, cross-platform shell-harness portability (bash 3.2 / BSD userland)
**Confidence:** HIGH (most claims verified on THIS Intel Mac and against the repo's own scripts; a few CI runtime behaviors are MEDIUM — not exercisable without pushing a tag)

## Summary

Phase 7 is the v1 close gate. It has two correlated bodies of work — (1) **gap closure**: implement the deferred platform fixes (`install_macos` real `.app` placement, build-time ad-hoc codesign, `sha256sum`→`shasum`, `mapfile`→bash-3.2 loop, the macOS CI legs), and (2) **verification**: drive `tools/verify-macos.sh` + `docs/macos-verification.md` top-to-bottom on the available **Intel (x86_64)** Mac, flipping every "macOS deferred D-18" status to Done with recorded evidence.

The research goal was to make every step of that spine **unattended and self-verifying** so a single agent session on this Intel Mac can take it from "scripts written" to "v1 declared done" without a human in the loop. The good news: the repo is already 80% there. `tools/build.sh` and `tools/publish.sh` already contain portable `shasum` branches and an arm64 ad-hoc codesign step; `verify-macos.sh` already runs the non-interactive gate; `install.sh` already revives `/dev/tty` and degrades cleanly headless; `gh` 2.93 is installed with `gh run watch --exit-status` (the non-interactive CI wait primitive). The actual work is: close five concrete code gaps, fix one **latent CI bug** (`ci-setup-toolchain.sh` installs Homebrew `lua` which is now **5.5**, not the `lua5.4` `build.sh` requires), re-introduce the macOS legs into `release.yml`, and then run the verification loop and capture evidence.

This machine is the verification target: confirmed **Darwin x86_64, macOS 14.7.1**, with `clang` 16, `shasum`, `gh` 2.93, Homebrew 6.0.0, and **stock bash 3.2.57** present — but `lua5.4`, `luastatic`, `luarocks`, and `wezterm` are NOT yet installed, which is exactly why a sudo-free `make setup` / setup target (autonomy item #1) is needed.

**Primary recommendation:** Sequence the phase as gap-closure-first (per CONTEXT D-09 / §C-1 "blocks everything"): (1) add a sudo-free local toolchain setup target, (2) fix `ci-setup-toolchain.sh` lua@5.4 + keg-only path and re-introduce the macOS matrix legs in `release.yml`, (3) implement `install_macos()` + the harness portability fixes, (4) push a tag and `gh run watch --exit-status` the build to green, (5) drive the unattended E2E install + `verify-macos.sh` + runbook loop on this Intel Mac, capturing evidence into the runbook tables, then flip the REQUIREMENTS/coverage statuses. The arm64 asset flips on the shared-build + codesign + Intel-proven parity contract (D-01) — no Apple Silicon hardware run is in scope.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Mac access & verification model**
- **D-01 (REVISED 2026-06-20 — Phase 7/7.1 split):** Only an **Intel (x86_64)** Mac is available, but Phase 7 still delivers the **entire macOS build — including the arm64 (`darwin-aarch64`) asset built and ad-hoc-codesigned via CI/CD** — plus the **full agent-driven ecosystem verification** run on the Intel Mac. **Phase 7 is the v1 gate: completing it declares v1 done.** arm64 parity is expected from the shared build contract; **no Apple Silicon hardware run is required for the v1 close** — arm64 status flips on the shared CI/CD build + ad-hoc codesign + Intel-proven ecosystem parity.
- **D-01b (Phase 7.1 — post-v1 end-user distribution check, NON-gating):** A separate Phase 7.1 is carved out strictly for end-user distribution validation on real Apple Silicon — NOT agent engineering, NOT runbook re-execution. **Phase 7.1 does NOT gate v1.** Action: add a `Phase 7.1` entry to `ROADMAP.md`. **OUT OF SCOPE for Phase 7 — do NOT plan it.**
- **D-02:** The pass is **agent-driven on the Mac** — run Claude Code on the Mac to drive `verify-macos.sh` + the full runbook, including `agent-ui-ux-designer` for the UX/glyph sections.
- **D-03 (evidence bar — SC#4):** A "macOS deferred → Done" flip requires: `verify-macos.sh` PASS for auto-checkable items **+** the runbook's **macOS deviations table** filled in **+** `agent-ui-ux-designer` notes for visual sections. Each status flip cites the specific runbook section that proved it. **All of this evidence is Intel-runnable** — the bar is met this phase on the Intel Mac. arm64-specific concerns (codesign first-launch on Silicon) are NOT part of the v1 flip bar; Phase 7.1 confirms them post-v1.

**INST-06 — install_macos**
- **D-04:** Implement **real, sudo-free `.app` placement** (close the design-only stub). `install_macos()` must actually place `WezTerm.app` when absent — true parity with the Linux installer.
- **D-05:** Source = official WezTerm **nightly macOS `.zip`** → unzip `WezTerm.app` into **`~/Applications`** (user-path, no sudo, no DMG mount). Reuse the existing **nightly-default + `resolve_want_datestamp`** logic from Phase 6 (06-06). No `hdiutil`/DMG path.

**Codesign & Gatekeeper**
- **D-06:** **Auto ad-hoc codesign at build time** — `tools/build.sh` / CI runs `codesign -s - dist/wez` on the `darwin-aarch64` (and `darwin-x86_64`) asset before publishing. **Verified at build time this phase** (codesign produces a valid signature on the CI artifact; `codesign --verify` / `spctl` checks where runnable); real Apple Silicon **first-launch** confirmation is the Phase 7.1 end-user check.
- **D-07 (quarantine — verify-then-decide):** Do **not** preemptively strip `com.apple.quarantine`. First confirm on real hardware whether curl-downloaded `wez` and the unzipped `WezTerm.app` actually carry quarantine and trigger Gatekeeper (curl downloads frequently do **not** set it). **Only** add an `xattr -dr com.apple.quarantine` step to `install.sh` if the on-Mac pass shows Gatekeeper blocking. If added, document why; otherwise the runbook keeps the manual `xattr -d` / right-click-open fallback.

**Harness portability**
- **D-08:** The harness must **run on stock macOS** (bash 3.2 + BSD userland, zero extra installs).
  - Replace `mapfile` in `tools/run-tests.sh` with a bash-3.2-safe `while read` loop.
  - Replace `sha256sum` in `tools/build.sh`'s remote path with detected `shasum -a 256` (fall back / branch by availability).
  - Watch BSD `cp -R config/wezterm-setup/. dst/` trailing-dot semantics (no stray `.` entry) — verify on hardware (C-2).

### Claude's Discretion
- Exact ordering of the runbook drive vs. gap-closure within the phase (planner decides; gaps that block verification — toolchain, codesign, harness — come first per C-1 "blocks everything").
- Detection mechanism for `shasum` vs `sha256sum` (command -v branch vs OS switch).
- Whether the bash-3.2 read-loop is factored into a shared helper or inlined.

### Deferred Ideas (OUT OF SCOPE)
- **A-2 UX backlog (Phase 5 review)** — `wez scene list` browse surface, did-you-mean on unknown recipe, unified error-prefix convention, dead `scene` dispatcher branch cleanup, README recipe-command edge-case docs. v2.
- **A-3 `wez update` post-install launcher resolution** — `WEZ_REPO_DIR` export / managed-script placement. Touch only if the macOS pass surfaces it; otherwise its own follow-up.
- **A-1 `--pane` / `--title` value completion** — minor, low priority. (The `--layout`/`--color` half is resolved and only needs zsh-runtime confirmation on the runbook §6.)
- **`bg` alias / `opacity` control** — NOT bugs; would be new requirements (v2).
- **Phase 7.1 — Apple Silicon end-user distribution validation** (D-01b): post-v1, non-gating. Needs a `Phase 7.1` ROADMAP entry via `/gsd-phase`. Not blocking the v1 close.
</user_constraints>

<phase_requirements>
## Phase Requirements

> No new requirement IDs. Phase 7 flips the **macOS status** of existing IDs from "Done (Linux; macOS deferred D-18)" → "Done" with recorded evidence. Each flip cites a runbook section (D-03 bar).

| ID | Description | Research Support (how Phase 7 closes it on the Intel Mac) |
|----|-------------|----------------------------------------------------------|
| INST-01 | Single managed-block injection | Runbook §2 — `make install` then grep sentinel pair; auto-skipped by verify-macos.sh (mutates `~/.config/wezterm`), driven manually. |
| INST-06 | sudo-free WezTerm bootstrap (`.app`→`~/Applications`) | **GAP G3** — implement `install_macos()` real placement (D-04/D-05). Runbook §2 + prereq. |
| INST-07 | Ergonomic one-line remote installer | E2E loop §autonomy-3: trigger `tools/install.sh` after the build publishes; non-TTY handling already in `install.sh`. |
| FOUND-01 | CWD inheritance (OSC 7) on macOS | Runbook §3 (headline item) — live WezTerm session, per-shell. Not auto-checkable; `agent-ui-ux-designer` + live repro. |
| DIAG-05 | shell completions zsh+bash on macOS | verify-macos.sh §2/§3 auto-checks `__complete` contexts + `zsh -n`/`bash -n`; runbook §4 confirms zsh runtime (A-1 `--layout` arm). |
| PANE-01..04 | pane color/title/persistence | Runbook §5 — live session; OSC 1337 SetUserVar mapping; `agent-ui-ux-designer` for glyph/cell-width. |
| SCEN-03..06 | named scenes launch/seed/completion | verify-macos.sh §4 (exit-code contract) + §5 (copy-if-absent) auto; runbook §7 for live mux + zsh completion. |

> Note INST-08 (CI matrix) is the supply-side enabler the autonomy items #1/#2 build on; its on-Mac verify is the practical content of this phase even though it is not in the listed ID set.
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Local toolchain provisioning (lua5.4/luastatic) | Dev tooling (`tools/*.sh`, `make`) | — | sudo-free build deps; mirrors `ci-setup-toolchain.sh` but for an end-dev's own Mac (autonomy #1). |
| Cross-platform asset build + codesign + publish | CI/CD (`.github/workflows/release.yml`) | Maintainer (`make publish`) | Same-contract rule (P6-D08): CI and `make publish` must produce byte-identical assets. arm64 only buildable on a macOS arm64 runner (`macos-14`). |
| WezTerm emulator placement (`.app`) | Bootstrap glue (`bootstrap-wezterm.sh`) | — | sudo-free user-path `.app`→`~/Applications`; OS-switched body, same entry as Linux. |
| `wez` binary fetch + Gatekeeper clearance | Installer glue (`install.sh`/`setup.sh`/`build.sh` download path) | OS (Gatekeeper) | curl download (no quarantine) + ad-hoc codesign at build time clears arm64 SIGKILL. |
| Auto-checkable parity gate | Verifier (`verify-macos.sh`) | — | Non-interactive, non-destructive; exit non-zero on any hard fail. |
| Live/visual parity (glyphs, colors, cwd, windowing) | Runbook (`docs/macos-verification.md`) + `agent-ui-ux-designer` | Human/agent on live WezTerm | OSC/mux/render behavior is only observable in a live session. |
| Evidence capture + status flips | Planning artifacts (REQUIREMENTS.md / coverage / runbook tables) | — | D-03 bar: PASS output + deviations table + ui-ux notes, each flip cites a section. |

## Standard Stack

> Phase 7 installs **no new application dependencies** — it is a parity/verification phase over the existing Lua-config + bash-glue + Lua-5.4-CLI stack. The "stack" here is the **build/verification toolchain on macOS** and the **GitHub Actions macOS runner images**. All version-sensitive items verified below.

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Apple `clang` (Xcode CLT) | 16.0.0 (verified on this Mac) `[VERIFIED: local]` | C compiler for the luastatic link step → Mach-O `wez` | Ships with Xcode Command Line Tools; `xcode-select --install`. Already present here (`/Library/Developer/CommandLineTools`). |
| Homebrew `lua@5.4` | 5.4.8 (bottled, **keg-only**) `[VERIFIED: brew info]` | Lua 5.4 interpreter + `liblua5.4.a` for luastatic + test harness | `brew install lua` now installs **Lua 5.5** — WRONG for this project. MUST pin `lua@5.4`. Keg-only ⇒ not on PATH; resolve via `brew --prefix lua@5.4`. |
| `luastatic` (LuaRocks) | latest (no stable `--version`; capture via `luarocks show`) `[ASSUMED]` | Bundle Lua sources + interpreter into the single shipping `wez` Mach-O | Project's locked build tool (D-02). `luarocks install luastatic`. |
| `gh` (GitHub CLI) | 2.93.0 (verified on this Mac) `[VERIFIED: local]` | Non-interactive CI trigger + **wait** (`gh run watch --exit-status`) + release download/inspect | Already installed + authed pattern used throughout `release.yml`/`publish.sh`. The unattended-CI primitive. |
| `shasum -a 256` | BSD/Perl, present on this Mac `[VERIFIED: local]` | SHA-256 over assets (macOS has **no `sha256sum`**) | Portable digest; `build.sh`/`publish.sh`/`release.yml` already branch on it. |
| `codesign -s -` (ad-hoc) | system (Xcode CLT) `[CITED: developer.apple.com]` | Ad-hoc sign the built `wez` Mach-O so arm64 doesn't SIGKILL on first run | Sufficient to clear "killed: 9" on self-built arm64; no Apple Developer cert/notarization needed. `publish.sh` already does this for arm64. |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `xattr` | system | Inspect/strip `com.apple.quarantine` (D-07 verify-then-decide) | Only on the on-Mac pass; only strip if Gatekeeper actually blocks. |
| `spctl --assess` / `codesign --verify` | system | Verify signature/Gatekeeper assessment at build time (D-06 evidence) | After codesign, to record a valid-signature evidence line. |
| `unzip` / `ditto` | system | Unzip the WezTerm macOS `.zip` → `WezTerm.app` (D-05) | `install_macos()` placement. `ditto -x -k` is the macOS-native zip extractor that preserves resource forks/codesign; prefer over `unzip` for `.app`. |
| `bash-completion@2` (Homebrew) | brew | bash `wez <Tab>` runtime on macOS (stock bash is 3.2) | Runbook §4 only — the completion *scripts* are generated by `wez`; this is the loader. Record if needed. |
| `sw_vers` / `uname -m` | system | Record macOS version + arch for evidence | Runbook prereqs. This Mac: `14.7.1`, `x86_64`. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| WezTerm nightly `.zip` → `~/Applications` (D-05 locked) | `brew install --cask wezterm` / `.dmg` + `hdiutil` | DMG needs mount/eject; cask is a system-ish path. **Locked out by D-05** — `.zip`→`~/Applications` keeps Linux parity (no mount) and sudo-free. |
| `unzip` for `.app` | `ditto -x -k <zip> <dest>` | `ditto` is the Apple-blessed archive tool; preserves extended attrs / symlinks inside the `.app` bundle. Recommend `ditto`; fall back to `unzip` if absent (it isn't, both ship). |
| `gh run watch` polling | `gh run list --json status,conclusion --jq` loop | `gh run watch --exit-status` is purpose-built and non-interactive; the list-poll is the fallback when you need to find the run-id first. Use both: list to resolve id, watch to block. |

**Installation (local sudo-free toolchain — autonomy item #1, the new `make setup` / setup target):**
```bash
# Xcode CLT (one-time; interactive GUI prompt if missing — detect, instruct, do not auto-sudo)
xcode-select -p >/dev/null 2>&1 || xcode-select --install   # detect-then-instruct

# Lua 5.4 (keg-only) + luarocks + luastatic — Homebrew is user-owned, no sudo
brew list lua@5.4 >/dev/null 2>&1 || brew install lua@5.4
brew list luarocks >/dev/null 2>&1 || brew install luarocks
command -v luastatic >/dev/null 2>&1 || luarocks install luastatic

# keg-only lua@5.4 is NOT on PATH — expose it for build.sh have_luastatic() (needs `lua5.4`)
LUA54_PREFIX="$(brew --prefix lua@5.4)"
export PATH="${LUA54_PREFIX}/bin:${PATH}"        # provides lua5.4
# liblua5.4.a + headers for the luastatic link step live under:
#   ${LUA54_PREFIX}/lib/liblua5.4.a   ${LUA54_PREFIX}/include/lua5.4
```

**Version verification (run on the target Mac before building):**
```bash
brew --prefix lua@5.4 && ls "$(brew --prefix lua@5.4)/lib"/liblua*.a   # confirm static lib name
"$(brew --prefix lua@5.4)/bin/lua5.4" -v                               # confirm 5.4.x
luarocks show luastatic 2>&1 | head -1                                 # capture luastatic version
gh --version | head -1                                                 # confirm gh present + authed (gh auth status)
```

## Package Legitimacy Audit

> Phase 7 installs **no application packages** (npm/PyPI/crates). The only externally-fetched
> software is Homebrew formulae (`lua@5.4`, `luarocks`) and the LuaRocks `luastatic` rock —
> all already used by the verified `ci-setup-toolchain.sh` Linux path, plus the official
> WezTerm release `.zip` from `wez/wezterm` (same source as the verified Linux `.tar.xz` path).
> slopcheck does not cover Homebrew or LuaRocks ecosystems, so these are tagged per their
> provenance (official formula index / project-locked build tool).

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `lua@5.4` | Homebrew core | mature (5.4.8) | core formula | lua.org / github.com/lua/lua | n/a (not covered) | Approved `[VERIFIED: formulae.brew.sh]` |
| `luarocks` | Homebrew core | mature | core formula | github.com/luarocks/luarocks | n/a | Approved `[VERIFIED: formulae.brew.sh]` |
| `luastatic` | LuaRocks | mature | LuaRocks | github.com/ers35/luastatic | n/a | Approved (project-locked D-02; same rock CI installs) `[ASSUMED]` |
| WezTerm macOS `.zip` | github.com/wez/wezterm releases | official | official | github.com/wez/wezterm | n/a | Approved (same upstream as Linux asset) `[VERIFIED: existing bootstrap path]` |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
AUTONOMY SPINE (one unattended agent session on the Intel Mac)

  [1] LOCAL TOOLCHAIN SETUP                 [2] CI/CD BUILD + PUBLISH
  ┌─────────────────────────┐               ┌──────────────────────────────────────┐
  │ make setup / setup.sh   │               │ git tag vX.Y.Z && git push --tags     │
  │  detect xcode-select     │               │            │                          │
  │  brew lua@5.4 luarocks   │               │            ▼                          │
  │  luarocks luastatic      │               │ .github/workflows/release.yml         │
  │  export keg PATH         │               │  strategy.matrix:                     │
  └───────────┬─────────────┘               │   - ubuntu-latest    (linux-x86_64)   │
              │ local build OK                │   - macos-15-intel   (darwin-x86_64)  │
              ▼                               │   - macos-14         (darwin-aarch64) │
  ┌─────────────────────────┐               │  per leg: ci-setup-toolchain → build  │
  │ tools/build.sh           │               │   → codesign -s - (macOS)  → checksum  │
  │  luastatic → dist/wez    │               │   → gh release upload (--clobber)      │
  │  codesign -s - (macOS)   │               └──────────────────┬───────────────────┘
  │  smoke: wez version      │                                  │ assets + .sha256 published
  └─────────────────────────┘                                  ▼
              │                                ┌──────────────────────────────────────┐
              │  agent WAITS non-interactively │ gh run watch <id> --exit-status        │
              └──────────────────────────────▶│  (resolve id via gh run list --json)   │
                                               └──────────────────┬───────────────────┘
                                                                  │ green
                                                                  ▼
  [3] E2E INSTALL LOOP                        [4]/[5] VERIFY + EVIDENCE
  ┌──────────────────────────────────┐       ┌──────────────────────────────────────┐
  │ curl …/install.sh | bash          │       │ bash tools/verify-macos.sh  (AUTO gate)│
  │  (or tools/install.sh)            │       │   PASS/FAIL/SKIP → exit 0 required      │
  │  setup.sh: bootstrap WezTerm.app  │──────▶│ drive docs/macos-verification.md       │
  │   (install_macos → ~/Applications)│       │   §1-7 + agent-ui-ux-designer visual    │
  │  build.sh download wez-macos-x86  │       │ fill: results table + deviations table  │
  │  verify quarantine (D-07)         │       │ → flip REQUIREMENTS/coverage statuses   │
  │  wez doctor exit 0; version match │       │   (each flip cites a runbook section)   │
  └──────────────────────────────────┘       └──────────────────────────────────────┘
```

### Recommended Project Structure
```
tools/
├── setup.sh                 # EXISTING installer; add a sudo-free dev-toolchain setup target (or new make target)
├── ci-setup-toolchain.sh    # FIX install_macos(): lua@5.4 not lua; expose keg PATH (autonomy #2)
├── bootstrap-wezterm.sh     # IMPLEMENT install_macos() real .app placement (D-04/D-05)
├── build.sh                 # ALREADY portable (shasum branch); add macOS codesign-at-build for both arches (D-06)
├── publish.sh               # ALREADY codesigns arm64; widen to darwin-x86_64 per D-06 if desired
├── install.sh               # ALREADY /dev/tty-aware; conditional xattr-strip site (D-07, only if blocked)
├── run-tests.sh             # REPLACE mapfile → bash-3.2 while-read loop (D-08)
└── verify-macos.sh          # AUTO gate; extend to assert codesign/quarantine evidence where runnable
.github/workflows/
└── release.yml              # RE-INTRODUCE strategy.matrix over ubuntu + macos-15-intel + macos-14
docs/
└── macos-verification.md    # DRIVE top-to-bottom; fill results + deviations tables (evidence, autonomy #5)
```

### Pattern 1: Non-interactive CI wait (autonomy item #2 — the unattended push-then-wait)
**What:** After pushing a tag, block the agent on the build outcome without a TTY or human refresh.
**When to use:** Every CI-triggering step in the unattended loop.
**Example:**
```bash
# Source: gh 2.93 `gh run watch --help` [VERIFIED: local]
git tag v1.0.0 && git push origin v1.0.0
# Resolve the run id deterministically (newest run for this workflow on this ref):
run_id="$(gh run list --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
# Block until done; non-zero exit if the run failed — propagates to the agent's control flow:
gh run watch "$run_id" --exit-status --interval 10
# Post-mortem on failure (also non-interactive):
gh run view "$run_id" --log-failed
```

### Pattern 2: keg-only lua@5.4 path resolution for luastatic (autonomy item #1)
**What:** `brew install lua` ships 5.5; the project needs 5.4. `lua@5.4` is keg-only (not symlinked into PATH).
**When to use:** Both the local `make setup` target AND the CI macOS leg.
**Example:**
```bash
# Source: brew info lua / lua@5.4 [VERIFIED: local]
brew install lua@5.4 luarocks
luarocks install luastatic
PREFIX="$(brew --prefix lua@5.4)"
export PATH="${PREFIX}/bin:${PATH}"          # build.sh have_luastatic() checks `command -v lua5.4`
# luastatic link flags (keg-only lib + headers):
#   ${PREFIX}/lib/liblua5.4.a   -I${PREFIX}/include/lua5.4
# In Actions, persist onto the job PATH:
echo "${PREFIX}/bin" >> "$GITHUB_PATH"
```

### Pattern 3: Build-time ad-hoc codesign (D-06)
**What:** Sign the built `wez` Mach-O ad-hoc so a self-built arm64 binary is not SIGKILLed.
**When to use:** macOS legs of CI + `make publish`; both arches per D-06 (arm64 is the one that SIGKILLs unsigned; signing x86_64 too is harmless and uniform).
**Example:**
```bash
# Source: tools/publish.sh:54-59 (existing) + developer.apple.com Gatekeeper docs [CITED]
if [ "$(uname -s)" = "Darwin" ]; then
  codesign --force --sign - dist/wez            # ad-hoc; no cert
  codesign --verify --verbose dist/wez          # evidence: valid on-disk signature
  spctl --assess --type execute --verbose dist/wez 2>&1 || true  # ad-hoc won't "accept" — record, don't gate
fi
```
> NOTE: `spctl --assess` will REJECT an ad-hoc-signed binary ("rejected, no usable signature") — that is EXPECTED. Ad-hoc signing fixes the *kill-on-launch* of a self-built Mach-O; it does not make Gatekeeper *trust* it as a notarized app. The evidence to record is `codesign --verify` success, not `spctl` acceptance (D-06: "codesign produces a valid signature").

### Pattern 4: sudo-free `.app` placement via .zip → ~/Applications (D-04/D-05)
**What:** Implement the design-only `install_macos()` to actually fetch + place WezTerm.app.
**When to use:** `bootstrap-wezterm.sh install_macos()`.
**Example:**
```bash
# Source: mirrors install_linux() structure; D-05 reuses resolve_want_datestamp [pattern from repo]
install_macos() {
  local tag="$1" app_dir="${HOME}/Applications"
  # asset_name pattern already present in latest_nightly_datestamp(): WezTerm-macos-<tag>.zip
  local url; url="$(wezterm_macos_asset_url "${tag}")"     # NEW thin helper (mirror wezterm_release_asset_url)
  local tmp; tmp="$(mktemp -d)"; trap "rm -rf '${tmp}'" RETURN
  fetch_to "${url}" "${tmp}/WezTerm.zip" || return 1
  # integrity gate before extract (mirror verify_tarxz spirit; .zip magic = PK\x03\x04)
  ditto -x -k "${tmp}/WezTerm.zip" "${tmp}/unzipped"       # Apple-native; preserves bundle attrs
  mkdir -p "${app_dir}"
  rm -rf "${app_dir}/WezTerm.app"
  cp -R "${tmp}/unzipped/WezTerm.app" "${app_dir}/WezTerm.app"
  # D-07: do NOT pre-strip quarantine. curl-downloaded zips usually carry none.
  # Verify the binary inside runs (R2-style evidence, mirrors install_linux):
  "${app_dir}/WezTerm.app/Contents/MacOS/wezterm" --version >/dev/null 2>&1 \
    || { log "note: WezTerm.app placed but did not launch — check Gatekeeper/quarantine (D-07)"; }
}
```

### Pattern 5: bash-3.2-safe array fill (replace mapfile, D-08)
**What:** `mapfile -t ARR < <(cmd)` is bash 4+; stock macOS bash is 3.2.
**When to use:** `run-tests.sh:50` (and note `release.yml:210` also uses `mapfile`, but that runs on the Linux leg only — harmless, but consider for uniformity).
**Example:**
```bash
# Source: verify-macos.sh:108 / install.sh already use this idiom [VERIFIED: repo]
ALL_TESTS=()
while IFS= read -r f; do ALL_TESTS+=("$f"); done \
  < <(find "${TEST_ROOTS[@]}" -type f -name '*_test.lua' | sort)
```

### Anti-Patterns to Avoid
- **`brew install lua` for this project** — installs Lua 5.5; `build.sh have_luastatic()` needs `lua5.4`. ALWAYS `lua@5.4`. This is the latent CI bug.
- **Pre-stripping `com.apple.quarantine` unconditionally** — violates D-07; curl/wget downloads usually carry no quarantine. Verify first, strip only if Gatekeeper actually blocks.
- **Gating the build on `spctl --assess` of an ad-hoc binary** — it will always reject. Use `codesign --verify` for the D-06 evidence.
- **Using `/Applications` (system path)** — requires sudo, violates the project invariant. Always `~/Applications`.
- **DMG/`hdiutil` mount path** — locked out by D-05; use the `.zip`.
- **Treating arm64 first-launch as a Phase 7 blocker** — D-01: arm64 flips on the shared build + codesign + Intel parity; Apple-Silicon first-launch is the non-gating Phase 7.1 check.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Wait for a CI build to finish | A custom poll loop parsing `gh run list` text | `gh run watch <id> --exit-status` | Purpose-built, non-interactive, propagates pass/fail as exit code. |
| SHA-256 on macOS | A detection wrapper around md5/openssl | `shasum -a 256` (branch on `command -v sha256sum`) | Already the repo idiom; macOS has no `sha256sum`. |
| Unzip a `.app` bundle | Manual `unzip` + xattr fixup | `ditto -x -k` | Apple-native; preserves bundle metadata/codesign/symlinks. |
| Clear arm64 "killed: 9" | Disabling SIP / Gatekeeper, custom entitlements | `codesign --force --sign -` (ad-hoc) | Minimal, no cert, exactly clears self-built-Mach-O kill. |
| Platform/arch detection | New `uname` parsing | `tools/lib/platform.sh` `platform_os`/`platform_arch` | Single source; already drives asset names byte-identically across build/publish/CI. |
| WezTerm version selection on macOS | A macOS-specific version picker | Reuse `resolve_want_datestamp` + `select_release` (06-06) | D-05 requires both OSes track the same nightly contract. |
| Interactive prompts under `curl\|bash` | A new TTY shim | `install.sh`'s existing `{ : < /dev/tty; }` open-probe + `/dev/tty` redirect | Already solved in Phase 6; handles non-TTY degrade. |

**Key insight:** Phase 7 is overwhelmingly **wiring existing, verified primitives into a macOS branch + a CI matrix**, not inventing mechanisms. The repo already contains the portable digest branch, the arm64 codesign step, the TTY-revival install flow, and the asset-naming contract. The risk is in the *gaps* (design-only `install_macos`, the `lua` vs `lua@5.4` CI bug, the `mapfile`/bash-3.2 break) and in *unattended verification plumbing* (gh wait + evidence capture), not in net-new architecture.

## Runtime State Inventory

> Phase 7 is gap-closure + verification, not a rename/migration. There is no stored data, live-service config, or OS-registered state being renamed. The closest analogs are **what state the unattended verification mutates** and **what must already exist on the Mac** — captured below for the planner.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — verify-macos.sh is non-destructive (scratch `$TMPDIR` dirs only). The runbook §2 mutates `~/.config/wezterm/wezterm.lua` (install/uninstall) — back up first (`cp … /tmp/wezterm.lua.pre`), as the runbook already instructs. | Runbook §2 pre-state capture step (already documented). |
| Live service config | GitHub Releases — the unattended build publishes/clobbers `wez-macos-x86_64`, `wez-macos-aarch64` (+ `.sha256`) assets to a `v*` tag release. Pushing the first `v*` tag is a real, irreversible-ish action (Open Q below). | Plan a `checkpoint:human-verify` before the first `git push --tags` if desired; the nightly channel already auto-publishes. |
| OS-registered state | macOS: `~/Applications/WezTerm.app` placement (new, via `install_macos`); `~/.local/bin/wez`; rc-file source lines (`# wezterm-setup:osc7`, `# wezterm-setup:completions`) in `~/.zshrc`/`~/.bashrc`. All sudo-free, user-path, reversible via `make uninstall`. | None beyond existing uninstall coverage. |
| Secrets/env vars | CI uses `github.token` (`GH_TOKEN: ${{ github.token }}`) — already wired in `release.yml`; `permissions: contents: write`. No new secrets. Local `gh auth status` must be authed for the unattended trigger/wait. | Confirm `gh auth status` on the Mac before the loop. |
| Build artifacts | `dist/wez` (rebuilt), `wez-<os>-<arch>` + `.sha256` (CI temp), `wez.luastatic.c` (cleaned by build.sh). On macOS, `luastatic` may emit the `.c` in REPO_ROOT — build.sh already `rm -f`s it. | None — build.sh handles cleanup. |

**Nothing found requiring data migration** — verified by reading verify-macos.sh (scratch-only) and the runbook (explicit pre-state backup).

## Common Pitfalls

### Pitfall 1: `brew install lua` installs Lua 5.5, not 5.4 (the latent CI bug)
**What goes wrong:** `ci-setup-toolchain.sh install_macos()` runs `brew install lua luarocks`. Homebrew `lua` is now **5.5.0**. `build.sh have_luastatic()` requires `command -v lua5.4`; with only `lua` (5.5) present, the build silently degrades to the dev source-launcher (non-shippable) OR `luastatic` links against the wrong interpreter.
**Why it happens:** Homebrew moved the unversioned `lua` formula to 5.5; the script predates that and was never run on a Mac (release.yml comment: "Homebrew's `lua` is now 5.5 not 5.4").
**How to avoid:** `brew install lua@5.4` (keg-only) + export `$(brew --prefix lua@5.4)/bin` onto PATH. Capture `lua5.4 -v` to prove 5.4.x. The existing `assert_and_capture()` already fails loud if `lua5.4` is absent — keep that gate.
**Warning signs:** `build.sh` logs "dev source-launcher (NOT a release artifact)" on a macOS CI leg; `lua5.4: command not found`.

### Pitfall 2: keg-only lua@5.4 not on PATH
**What goes wrong:** Even after `brew install lua@5.4`, `lua5.4` and `liblua5.4.a` are NOT on the default PATH/linker path (keg-only). luastatic can't find the interpreter or static lib.
**Why it happens:** Homebrew marks versioned formulae keg-only to avoid clobbering the default.
**How to avoid:** `export PATH="$(brew --prefix lua@5.4)/bin:$PATH"` locally and `echo … >> "$GITHUB_PATH"` in CI; pass `$(brew --prefix lua@5.4)/lib/liblua5.4.a -I$(brew --prefix lua@5.4)/include/lua5.4` to the link step.
**Warning signs:** `lua5.4: command not found` after a successful `brew install`; luastatic link error "library not found for -llua".

### Pitfall 3: `mapfile` breaks the test harness on stock bash 3.2 (D-08)
**What goes wrong:** `run-tests.sh:50` `mapfile -t ALL_TESTS` — `mapfile` is bash 4+. Stock macOS `/bin/bash` is **3.2.57** (verified on this Mac). `run-tests.sh` shebang is `/usr/bin/env bash`; if that resolves to system bash, discovery fails with "mapfile: command not found".
**Why it happens:** macOS froze bash at 3.2 (GPLv3 avoidance).
**How to avoid:** Replace with the `while IFS= read -r … < <(…)` loop the rest of the repo already uses (verify-macos.sh:108, install.sh).
**Warning signs:** `run-tests: ` produces no test files / `mapfile: command not found` on macOS.

### Pitfall 4: Ad-hoc codesign does NOT pass `spctl` / Gatekeeper acceptance
**What goes wrong:** A plan that asserts `spctl --assess` accepts the ad-hoc-signed `wez` will fail — `spctl` rejects ad-hoc signatures by design.
**Why it happens:** Ad-hoc signing (`-s -`) only fixes the kernel SIGKILL of an unsigned self-built Mach-O; it does not produce a Developer-ID/notarized signature Gatekeeper trusts.
**How to avoid:** D-06 evidence = `codesign --verify` success (valid on-disk signature) + the binary running. `spctl` rejection is expected and recorded as such, not treated as a failure.
**Warning signs:** Confusing "rejected: no usable signature" (spctl, expected for ad-hoc) with an actual signing failure.

### Pitfall 5: Assuming curl-downloaded `wez`/`.zip` carry quarantine (D-07)
**What goes wrong:** Adding an unconditional `xattr -dr com.apple.quarantine` that mutates files unnecessarily.
**Why it happens:** Conflating browser downloads (which DO get quarantine) with curl/wget (which do NOT — verified by Apple-security sources). The E2E loop uses curl.
**How to avoid:** D-07 verify-then-decide. On the Mac, `xattr -p com.apple.quarantine <file>` after the curl install; only if present AND Gatekeeper blocks, add the strip to `install.sh` and document why. Otherwise keep the manual fallback note.
**Warning signs:** None at install time — the trap is over-engineering a strip that isn't needed.

### Pitfall 6: BSD `cp -R src/. dst/` trailing-dot semantics (C-2)
**What goes wrong:** `setup.sh:94` `cp -R "${REPO_ROOT}/config/wezterm-setup/." "${SETUP_DIR}/"` — GNU `cp` copies contents; some BSD `cp` behaviors create a literal `.` entry or copy differently.
**Why it happens:** BSD vs GNU `cp` differ on `src/.` trailing-dot interpretation.
**How to avoid:** Verify on this Mac (`ls -la "${SETUP_DIR}"` after install — no stray `.` dir). If it misbehaves, switch to `cp -R "${REPO_ROOT}/config/wezterm-setup/" "${SETUP_DIR}"` (copy the dir) or a `find … | cpio`/`ditto` form.
**Warning signs:** A `.` subdirectory inside `~/.config/wezterm/wezterm-setup/`, or missing files.

### Pitfall 7: `macos-13` / older Intel runner labels are removed
**What goes wrong:** Re-introducing a macOS matrix that names a removed runner image fails the workflow.
**Why it happens:** GitHub removed `macos-13` (Dec 4 2025) and the older Intel image P6-D01 originally named (release.yml comment already records this).
**How to avoid:** Intel x86_64 leg = `macos-15-intel` (the LAST x86_64 image, available until Aug 2027); arm64 leg = `macos-14` (Apple Silicon). `ubuntu-latest` for Linux.
**Warning signs:** "The runner image 'macos-13' is deprecated/unavailable" in the Actions log.

### Pitfall 8: zsh `compinit` insecure-directory warnings under Homebrew fpath
**What goes wrong:** On macOS, `compinit` may refuse to load completions, warning about insecure (group-writable) Homebrew-owned `fpath` dirs.
**Why it happens:** Homebrew dirs can be group-writable; zsh's security check flags them.
**How to avoid:** Runbook §4 records whether `compinit -u` (skip the security check) is needed; the installer writes `_wez` to a user-owned `~/.local/share/zsh/site-functions` which should be safe. Document, don't necessarily fix.
**Warning signs:** "zsh compinit: insecure directories" on a new shell; `wez <Tab>` doesn't complete.

## Code Examples

### Resolve run-id and block on CI outcome (unattended)
```bash
# Source: gh 2.93 run watch/list --help [VERIFIED: local]
gh auth status >/dev/null || { echo "gh not authed"; exit 1; }
run_id="$(gh run list --workflow release.yml --branch "$(git rev-parse --abbrev-ref HEAD)" \
            --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$run_id" --exit-status --interval 10 || { gh run view "$run_id" --log-failed; exit 1; }
```

### Verify a published asset downloads + checksum-matches (E2E fetch evidence)
```bash
# Source: build.sh download_release() contract [VERIFIED: repo]
tag="$(gh release list --limit 1 --json tagName --jq '.[0].tagName')"
gh release download "$tag" -p 'wez-macos-x86_64' -p 'wez-macos-x86_64.sha256' -D /tmp/e2e
( cd /tmp/e2e && shasum -a 256 -c wez-macos-x86_64.sha256 )   # exit 0 = match
chmod +x /tmp/e2e/wez-macos-x86_64
/tmp/e2e/wez-macos-x86_64 version                              # runs (no codesign needed for x86_64)
```

### Quarantine probe (D-07 verify-then-decide)
```bash
# Source: Apple security docs [CITED: hacktricks/Apple] + xattr(1)
curl -fsSL …/install.sh | bash          # the real E2E one-liner
xattr -p com.apple.quarantine ~/.local/bin/wez 2>/dev/null \
  && echo "QUARANTINED — consider install.sh strip (D-07)" \
  || echo "no quarantine on curl download (expected) — no strip needed"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `macos-13` / unlabeled Intel runner | `macos-15-intel` (Intel) + `macos-14` (arm64); `macos-26`/`macos-26-intel` now GA | macos-13 removed 2025-12-04; macos-15-intel added; macos-26 GA 2026-02-26 | Use `macos-15-intel` (last x86_64, until Aug 2027) + `macos-14` for arm64. `[VERIFIED: github.blog changelog]` |
| Homebrew `lua` = 5.4 | Homebrew `lua` = **5.5.0**; `lua@5.4` = 5.4.8 (keg-only) | (formula bump) | MUST pin `lua@5.4`; the unversioned `lua` now breaks the build. `[VERIFIED: brew info]` |
| release.yml 3-leg matrix (P6 design) | release.yml **collapsed to Linux-only** (macOS legs deferred to Phase 7) | Phase 6 (deferred) | Phase 7 RE-INTRODUCES `strategy.matrix` over the 3 runners. `[VERIFIED: release.yml:45-53]` |

**Deprecated/outdated:**
- `macos-13` and the originally-planned older Intel image: removed by GitHub — never name them.
- `brew install lua` as a 5.4 source: now 5.5; superseded by `lua@5.4`.
- x86_64 macOS runners overall: sunset **August 2027** (`macos-15-intel` is the last). Out of v1 scope but relevant to long-term CI.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `luastatic` (LuaRocks) version/availability tagged `[ASSUMED]` — no stable `--version`, slopcheck doesn't cover LuaRocks | Standard Stack | Low — it's the project-locked build tool already used on the Linux CI leg; `assert_and_capture` fails loud if absent. |
| A2 | `release.yml` macOS matrix legs will build cleanly once `lua@5.4`+keg-PATH fixes land | Architecture / Pitfall 1 | MEDIUM — not exercisable without pushing a tag; the lua@5.4 fix is the known blocker but a Mac runner may surface further issues (e.g. luastatic link flags). Mitigate: `workflow_dispatch` dry-run before the real `v*` tag. |
| A3 | WezTerm macOS nightly asset name follows `WezTerm-macos-<tag>.zip` (used in `latest_nightly_datestamp` already) | Pattern 4 (install_macos) | MEDIUM — confirm the exact current asset name on the wez/wezterm nightly release before wiring `wezterm_macos_asset_url`. The Linux side resolves a real asset; macOS side has only the design-only string today. |
| A4 | curl/wget downloads carry no `com.apple.quarantine` on this machine's macOS 14.7.1 | Pitfall 5 / D-07 | Low — D-07 is explicitly verify-then-decide; the probe in the runbook confirms it empirically, so a wrong assumption is caught, not shipped. |
| A5 | Ad-hoc-signed x86_64 `wez` runs without codesign on Intel (only arm64 SIGKILLs unsigned) | Pattern 3 | Low — verify-macos.sh already runs `dist/wez version` on this Intel Mac as the proof; arm64 SIGKILL is the documented case. |

## Open Questions (RESOLVED)

> All three resolved during planning (2026-06-20) — each disposition is baked into a plan task.

1. **First `v*` tag is a maintainer action (Open Q3 carried from Phase 6).** — **RESOLVED → Plan 07-04 Task 3.**
   - What we know: `release.yml` `v*` path is correctness-verified (actionlint/greps) but never run live; the nightly channel auto-publishes. `publish.sh` defaults `WEZ_RELEASE_TAG=v0.1.0`.
   - What's unclear: whether the agent should cut the first `v1.0.0` tag autonomously, or behind a human checkpoint. Tag pushes trigger real public releases.
   - **Resolution:** the first `git push --tags` is gated behind a `blocking-human` checkpoint task (07-04 Task 3, `autonomous: false`); the `workflow_dispatch` nightly path is the unattended dry-run that proves the macOS legs build + codesign + upload before the real tag.

2. **Exact current WezTerm macOS nightly asset filename (A3).** — **RESOLVED → Plan 07-02 Task 1 (execution-time API confirm).**
   - What we know: code references `WezTerm-macos-nightly.zip` in `latest_nightly_datestamp`.
   - What's unclear: whether per-dated-release assets use `WezTerm-macos-<datestamp>.zip` or a different scheme.
   - **Resolution:** 07-02 Task 1's first action queries the wez/wezterm releases API for the nightly + a dated tag's assets[] before finalizing `wezterm_macos_asset_url` (mirroring the Linux `wezterm_release_asset_url` shape), recording the API-confirmed filename + date in a code comment as an acceptance gate. The RED test asserts host + `.zip` suffix only, so the exact name is bounded to execution time.

3. **Should the agent VERIFY (not just build) arm64 in this phase?** — **RESOLVED → Plan 07-03 Task 2 (macos-14 in-build smoke).**
   - What we know: D-01 says arm64 flips on shared-build + codesign + Intel parity; no Apple-Silicon hardware run. D-06 says arm64 first-launch is the Phase 7.1 check.
   - **Resolution:** on the `macos-14` (arm64) CI leg, run `codesign --verify dist/wez` and (since the runner IS arm64) `./dist/wez version` as a free in-build smoke — strengthening arm64 evidence WITHOUT local Silicon hardware, fully Intel-session-driven via `gh run watch`. That log line is captured as arm64 evidence. Real arm64 first-launch remains the out-of-scope, non-gating Phase 7.1 check.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Apple clang / Xcode CLT | luastatic link → Mach-O | ✓ | 16.0.0 | — (autonomy #1 detects + instructs `xcode-select --install`) |
| `lua5.4` | build + test harness | ✗ (not installed) | — | `brew install lua@5.4` + keg PATH (autonomy #1) |
| `luastatic` | shipping binary build | ✗ | — | `luarocks install luastatic`; else dev launcher (non-shippable) |
| `luarocks` | install luastatic | ✗ | — | `brew install luarocks` |
| `wezterm` | live runbook §3-7 | ✗ | — | `install_macos()` places `WezTerm.app` (D-04) OR `brew install --cask wezterm` for the runbook (record as gap) |
| `gh` (authed) | CI trigger + wait + release download | ✓ | 2.93.0 | `gh auth login` if not authed |
| `shasum` | checksum | ✓ | system | — |
| `codesign` | ad-hoc sign | ✓ | system (CLT) | — |
| `brew` | toolchain provisioning | ✓ | 6.0.0 | — |
| stock `bash` | harness shebang | ✓ (3.2.57) | 3.2 | the D-08 mapfile fix makes 3.2 sufficient |

**Missing dependencies with no fallback:** none — every missing item is installable sudo-free via the autonomy #1 setup target on this Mac.
**Missing dependencies with fallback:** `lua5.4`/`luastatic`/`luarocks`/`wezterm` — all installed by the new setup target or `brew`; until then `build.sh` degrades to the dev launcher (fine for `wez` behavior checks, not for the shipping artifact).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Plain Lua 5.4 `*_test.lua` files run under `lua5.4`, orchestrated by `tools/run-tests.sh` (bash harness) |
| Config file | none — discovery is `find tests cli config -name '*_test.lua'` |
| Quick run command | `LUA_BIN=lua5.4 ./tools/run-tests.sh` (or `LUA_BIN="$(brew --prefix lua@5.4)/bin/lua5.4" …`) |
| Full suite command | `make test` (≡ `./tools/run-tests.sh`; `WEZTERM_INTEGRATION=1` adds live tests) |
| Auto gate | `bash tools/verify-macos.sh` — non-interactive, non-destructive macOS parity gate (must exit 0) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| (harness) | bash-3.2 discovery works | smoke | `/bin/bash tools/run-tests.sh` (stock 3.2) | ✅ after D-08 fix |
| DIAG-05 | `__complete` contexts non-empty | unit/smoke | `bash tools/verify-macos.sh` §2 | ✅ verify-macos.sh |
| DIAG-05 | generated completions pass `zsh -n`/`bash -n` | smoke | `bash tools/verify-macos.sh` §3 | ✅ verify-macos.sh |
| SCEN-03/04 | scene-launch exit-code contract | unit | `bash tools/verify-macos.sh` §4 | ✅ verify-macos.sh |
| SCEN-06 | copy-if-absent seeding | unit | `bash tools/verify-macos.sh` §5 | ✅ verify-macos.sh |
| INST-06 | `install_macos()` places WezTerm.app | integration | new test + runbook §2/prereq (live) | ❌ Wave 0 — add `bootstrap_macos_test.lua` (pure path/url logic) |
| D-06 | codesign produces valid signature | smoke | `codesign --verify dist/wez` in build/CI | ❌ Wave 0 — add to build.sh macOS branch + capture in CI log |
| INST-01..06, FOUND-01, PANE-*, TAB-*, SCEN live | full parity | manual (live WezTerm) | `docs/macos-verification.md` §2-7 + `agent-ui-ux-designer` | ✅ runbook (manual by design) |

### Sampling Rate
- **Per task commit:** `LUA_BIN=… ./tools/run-tests.sh` (unit suite + `bash -n` gate over tools/*.sh).
- **Per wave merge:** `bash tools/verify-macos.sh` (full auto gate, exit 0).
- **Phase gate:** verify-macos.sh PASS + full runbook driven + deviations table filled + every macOS status flipped (D-03), full suite green before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `tools/run-tests.sh` mapfile→while-read fix (D-08) — so the harness runs under stock bash 3.2 (the very thing being verified).
- [ ] `cli/lib/` or `tests/` unit test for the new `install_macos()` url/path logic (pure, headless — mirror the Linux `install_linux` sourced-function tests).
- [ ] `codesign --verify` assertion added to build.sh macOS branch (and surfaced in the CI macOS-leg log as arm64/x86_64 evidence).
- [ ] Toolchain install: the autonomy #1 setup target (`make setup` or `tools/setup-dev.sh`) — installs lua@5.4/luarocks/luastatic sudo-free, exposes keg PATH.

*(Existing test infrastructure — 30 `*_test.lua` files + verify-macos.sh — covers the bulk; the gaps above are the macOS-specific additions.)*

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1`, `security_block_on: high`. Phase 7 ships
> no network service and no auth surface; the relevant security domain is **supply-chain integrity
> of the downloaded/published binary** and **the curl|bash trust model** (already established Phase 6).

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No user auth surface. CI uses scoped `github.token` (`permissions: contents: write`). |
| V3 Session Management | no | — |
| V4 Access Control | yes (CI) | Least-privilege workflow token (`contents: write` only) — already in `release.yml`. No manual channel input to spoof (github.ref is the only signal). |
| V5 Input Validation | yes | Asset/tag names derived from `platform.sh` (not user input); `assert_safe_members`/`verify_tarxz` gate Linux extraction — add an analogous `.zip` integrity check in `install_macos` before extract. |
| V6 Cryptography | yes | Per-asset `.sha256` verified BEFORE chmod +x (`build.sh download_release`) — portable via `shasum -a 256`. Ad-hoc codesign is integrity-of-self, not trust. |

### Known Threat Patterns for {macOS install + GitHub-published binary}
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Tampered/MITM'd `wez` download | Tampering | Per-asset SHA-256 verified before exec (existing); abort on mismatch. |
| Unsigned arm64 Mach-O killed / users disable Gatekeeper | Tampering / DoS | Ad-hoc codesign at build (D-06) so users never need to weaken Gatekeeper. |
| `.zip` path-traversal on extract | Tampering | `ditto`/`unzip` into a temp dir + reject `..`/absolute members before copying `WezTerm.app` (mirror `assert_safe_members`). |
| Malicious nightly tag / spoofed channel | Spoofing | `github.ref`-only channel resolution (no dispatch input); stable = latest-release API (prereleases excluded). |
| `curl\|bash` partial-stream execution | Tampering | `main()` invoked on the literal last line (existing install.sh); truncation can't run a half-command. |

## Sources

### Primary (HIGH confidence)
- This Intel Mac (local probes): `uname`, `sw_vers` (14.7.1, x86_64), `clang` 16.0.0, `shasum`, `gh` 2.93.0, `brew` 6.0.0, stock bash 3.2.57, `brew info lua`/`lua@5.4` (5.5.0 / 5.4.8 keg-only), `gh run watch --help`. `[VERIFIED: local]`
- Repo scripts (read in full): `tools/build.sh`, `tools/publish.sh`, `tools/bootstrap-wezterm.sh`, `tools/install.sh`, `tools/setup.sh`, `tools/run-tests.sh`, `tools/ci-setup-toolchain.sh`, `tools/lib/platform.sh`, `tools/verify-macos.sh`, `.github/workflows/release.yml`, `docs/macos-verification.md`, `.planning/MACOS-PARITY-AND-FOLLOWUPS.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, CONTEXT.md. `[VERIFIED: repo]`
- GitHub Changelog — macos-26 GA / macos-15-intel availability + macos-13 removal. `[CITED: github.blog/changelog]`

### Secondary (MEDIUM confidence)
- Apple Gatekeeper / quarantine / codesign behavior (curl downloads carry no quarantine; ad-hoc signing is local-only; `spctl`/`codesign`/`xattr` CLI). `[CITED: hacktricks.wiki, developer.apple.com forums, gregoryszorc apple-codesign docs]`
- luastatic + Homebrew keg-only `lua@5.4` link pattern (`$(brew --prefix lua@5.4)/lib/liblua5.4.a`). `[CITED: github.com/ers35/luastatic, formulae.brew.sh]`

### Tertiary (LOW confidence)
- Exact current WezTerm macOS nightly/dated asset filename — to confirm against wez/wezterm releases API at plan/implement time (Open Q2 / A3).

## Metadata

**Confidence breakdown:**
- Standard stack / toolchain: HIGH — versions verified on the actual target Mac; the `lua@5.4` vs `lua` issue confirmed via `brew info`.
- Architecture (CI matrix, autonomy spine): HIGH for the design; MEDIUM for live CI behavior (macOS legs not exercisable without a tag — mitigated by `workflow_dispatch` dry-run).
- `install_macos` implementation: MEDIUM — pattern is sound and mirrors `install_linux`, but the exact WezTerm macOS asset URL needs API confirmation (A3).
- Pitfalls: HIGH — each is grounded in a specific repo line + a verified platform fact.
- Gatekeeper/codesign: HIGH for the mechanism (multiple authoritative sources agree curl≠quarantine, ad-hoc≠spctl-trust); arm64 first-launch deliberately out of scope per D-01.

**Research date:** 2026-06-20
**Valid until:** 2026-07-20 (stable; but GitHub runner labels and Homebrew lua formula version are fast-moving — re-confirm `macos-15-intel` availability and `brew info lua@5.4` if planning slips past ~30 days).
