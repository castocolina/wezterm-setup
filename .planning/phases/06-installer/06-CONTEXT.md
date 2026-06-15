# Phase 6: Ergonomic Installer - Context

**Gathered:** 2026-06-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 6 delivers the **ergonomic one-line remote installer** (INST-07) plus the
**cross-platform build-and-publish pipeline** that feeds it (INST-08).

A new user pastes a single `curl -fsSL <raw-url> | bash` (or `wget -qO- … | bash`)
command. That bootstrap downloads the repo to a temp path, installs/updates WezTerm
sudo-free (reusing INST-06), downloads the matching `wez` release binary for the
detected OS+arch, copies the managed assets via the existing `tools/setup.sh`, runs
`wez doctor` (clear pass/fail), and cleans up the temp checkout. README documents the
one-liner + post-install/config and the pipe-to-bash trust model.

The supply side (INST-08): a GitHub Actions matrix builds and publishes per-OS/arch
`wez` assets, and a maintainer can build/install/publish locally from Linux **or**
macOS.

**In scope:** the remote bootstrap entry script, wiring `tools/setup.sh` /
`tools/build.sh` (`WEZ_REMOTE_BOOTSTRAP=1`) to the real `castocolina` URLs, the GH
Actions release workflow, `make build` / `make publish` targets, the `wez update`
self-update subcommand (INST-09), README rewrite, the pipe-to-bash trust model.

**Out of scope (other phases):** re-implementing WezTerm emulator acquisition
mechanics (INST-06, Phase 1 / Phase 7); on-Mac *verification* of the macOS asset
(Phase 7); new CLI features.
</domain>

<decisions>
## Implementation Decisions

### Binary delivery & build/publish pipeline (INST-08)
- **P6-D01:** The `wez` binary is delivered as a **GitHub Actions release asset**. A CI
  **matrix** builds natively per target — `ubuntu-latest` → `linux-x86_64`, `macos-15-intel` →
  `darwin-x86_64` (Intel; GitHub removed `macos-13` on 2025-12-04 — corrected via 06-RESEARCH.md),
  `macos-14` → `darwin-aarch64` (Apple Silicon) — each via
  luastatic; the Silicon job ad-hoc-codesigns its asset. The remote installer downloads
  the asset, `chmod +x`, places it in `~/.local/bin` (already `setup.sh`'s `BIN_DIR`).
  **`.gz` compression is unnecessary** for such a small static binary → publish the raw
  binary asset (compression is the planner's call, low value). This activates the
  existing dormant `WEZ_REMOTE_BOOTSTRAP=1` path in `tools/build.sh`, now pointed at the
  real `github.com/castocolina/wezterm-setup` release URL.
- **P6-D08:** **Local build/install/publish is first-class, not an escape hatch.** New
  Makefile targets: `make build` (luastatic), `make install` (dogfood — bootstrap/reuse
  WezTerm + place the locally built `wez`), `make publish` (publish the asset for the
  current platform's OS+arch). It MUST work from **both Linux and macOS** so a maintainer
  on either OS can cut that platform's asset. Local and CI use the **same asset-naming
  contract** so either source produces interchangeable assets. (User's own flow: `make
  build` → `make install` uses the binary just built; `make publish` when releasing.)

### Remote install flow (INST-07)
- **P6-D02:** Flow: one-liner → fetch repo to a temp dir → run `tools/setup.sh` with
  `WEZ_REMOTE_BOOTSTRAP=1` → (a) bootstrap/reuse WezTerm (existing `.tar.xz` path), (b)
  download the `wez` release binary, (c) place managed config/scenes/completions → `wez
  doctor` pass/fail → remove the temp checkout. Ship both `curl` and `wget` variants.
- **P6-D07:** The launcher **detects OS + arch** by reusing `tools/lib/platform.sh`
  (`platform_os` → linux/macos, `platform_arch` → x86_64/aarch64), maps to the matching
  release-asset name, and downloads it. **If no asset exists for that OS/arch → fail with
  a clear, actionable error** — never a silent fallback to a wrong binary.

### WezTerm version policy & update-in-place (refines D-07 / D-08 for the installer)
- **P6-D09:** The installer **targets `nightly` by default** (not the pinned dated release),
  including the non-interactive pipe path — user preference; a pinned tag stays available for
  reproducibility when explicitly requested. **Update-in-place:** if a WezTerm is already
  present, compare its version datestamp against the latest available nightly; if the
  available one is **newer**, **update the binary** (fetch + swap). If already current (≥),
  reuse untouched (no-op). **HARD CONSTRAINT (extends D-07):** update-in-place applies ONLY
  to the **project-managed user-path install** (`~/.local/...`). A **system install is never
  modified** — verified real case: WezTerm here is the apt package `wezterm-nightly` in
  `/usr/bin` (root-owned, repo `apt.fury.io/wez`); the installer must never `sudo`/overwrite
  it. If only a system install exists and the user wants a newer nightly, the project places
  its **own** user-path copy that wins on `PATH`, leaving the system files intact.
- **P6-D10 (per-platform archive — unpack must be verified each OS):** WezTerm nightly ships
  **Linux = `.tar.xz`** (handled + verified in `bootstrap-wezterm.sh`) and **macOS = `.zip`**
  (contains `WezTerm.app` → `~/Applications`). `install_macos()` is currently a **STUB**;
  unpacking the macOS `.zip` and placing the `.app` is the Phase 7 gap and a mandatory
  unpack-verification step per platform.

### `wez update` self-update (INST-09)
- **P6-D11:** A **`wez update`** subcommand applies updates without retyping the remote URL.
  It invokes the **same GitHub launcher** the `curl|bash` one-liner uses — one entry point,
  one update flow (no divergent second path). It refreshes the `wez` binary, the managed
  config assets, and WezTerm when a newer `nightly` exists, all under P6-D09's rules
  (sudo-free, never touch a system install, update-in-place only for the user-path managed
  install) and P6-D05's trust model. Implementation notes for the planner:
  - **D-01 boundary:** `wez update` is a thin Lua command; the "is there an update?" version
    comparison may live in Lua, but the fetch/unpack/place is delegated to the shared
    bootstrap glue (the launcher), not re-implemented.
  - **Self-replacement gotcha:** a running binary replacing itself must download to a temp
    path and **atomically rename/swap** so the in-flight process doesn't corrupt itself.
  - **Completion (D-16):** add `update` to `cli/spec.lua` so `wez <Tab>` completes it with no
    script edit.
  - Clear **no-op message** when everything is already current.

### Packaging invariant
- **P6-D03 (INVARIANT):** **No AppImage, no Flatpak, nothing requiring sudo**, at any
  layer (WezTerm emulator *and* the `wez` binary). Linux = plain `.tar.xz`/raw binary to
  user-path. Extends the already-locked D-05 (AppImage banned over Pop!_OS/Ubuntu 24.04
  `libfuse2` removal) to also ban Flatpak and to cover the `wez` binary.

### Pipe-to-bash interactivity (INST-07 / INST-03 interaction)
- **P6-D04:** Under `curl … | bash` **stdin is consumed by the pipe** even when a terminal
  is attached. The remote bootstrap therefore reads interactive prompts from **`/dev/tty`**
  so the re-install decision (D-03 override/restore/skip) and the WezTerm version selector
  (D-08) stay interactive. README also shows the `bash <(curl …)` form. Only a genuinely
  headless run (no `/dev/tty`, e.g. CI) keeps D-03's non-zero abort; flags remain passable
  via `curl … | bash -s -- --force|--restore|--skip`.

### Trust model (INST-07, SC#5)
- **P6-D05:** Ship **inspect-before-run guidance + pin-to-tag/commit** in the README
  (`curl > file; read it; bash file`; pin a tag/commit instead of `main`); binary integrity
  via the inherited checksum verification at download. The **formal threat model is
  authored by the planner** at plan time.

### Documentation (INST-07, SC#4)
- **P6-D06:** The README install/config rewrite is **authored/reviewed with the
  `crafting-effective-readmes` skill**. Uses the real `castocolina` URLs; documents both
  `curl|bash` and `wget` variants plus post-install/config steps.

### Claude's Discretion
- Whether to fetch the temp repo via `git clone --depth 1` vs a tarball
  (`codeload.github.com/.../tar.gz`) — tarball avoids a `git` dependency; planner's call
  under P6-D02.
- Whether the `wez` release asset is raw vs `.gz` (P6-D01 leans raw — low value to compress
  a tiny static binary).
- Exact release-asset naming scheme and the GH Actions workflow file layout (under the
  same-contract rule of P6-D08).
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 6 requirements & roadmap
- `.planning/REQUIREMENTS.md` — INST-07 (one-line installer) + INST-08 (build/publish pipeline)
- `.planning/ROADMAP.md` §"Phase 6: Ergonomic Installer" — goal, 7 success criteria, invariant

### Existing install/build machinery (reuse — do not re-implement)
- `tools/setup.sh` — the installer glue (D-01); STEP sequence, `BIN_DIR=~/.local/bin`, markers
- `tools/bootstrap-wezterm.sh` — sudo-free WezTerm `.tar.xz` bootstrap (INST-06); `install_macos()` is a STUB
- `tools/build.sh` — build paths incl. the dormant `WEZ_REMOTE_BOOTSTRAP=1` release-download (lines ~23-34, `WEZ_RELEASE_TAG`/`WEZ_RELEASE_BASE` placeholders to repoint)
- `tools/lib/platform.sh` — `platform_os` / `platform_arch` / `platform_ubuntu_base` (P6-D07 OS+arch detection)
- `Makefile` — thin glue; gains `build` / `publish` targets (P6-D08)
- `README.md` — current install section has a NON-working `…/tools/setup.sh | sh` one-liner to replace

### Locked prior decisions (read first)
- `.planning/phases/01-foundation/01-CONTEXT.md` — D-01 (bash-only-glue boundary), D-02 (luastatic + release fallback), D-03 (no-TTY re-install abort), D-04..D-08 (WezTerm bootstrap + version selector), D-18 (Linux-first / macOS deferred)
- `.planning/MACOS-PARITY-AND-FOLLOWUPS.md` — macOS gaps incl. Apple Silicon ad-hoc codesign, `sha256sum`→`shasum`; Phase 7 driver
- `docs/macos-verification.md` + `tools/verify-macos.sh` — Phase 7 verification of the macOS asset built here

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `tools/build.sh` `WEZ_REMOTE_BOOTSTRAP=1` path: already designed to download a verified
  prebuilt `wez` release binary when luastatic is absent — repoint `WEZ_RELEASE_BASE` from
  the `github.com/you/...` placeholder to `castocolina` and it becomes the install path.
- `tools/lib/platform.sh`: OS+arch detection already exists and is sourceable — directly
  powers P6-D07 asset selection.
- `tools/setup.sh`: already sequences WezTerm bootstrap → build → asset placement →
  install-state; the remote bootstrap wraps it (fetch-to-temp + cleanup), not replaces it.

### Established Patterns
- **D-01 bash-glue boundary:** the remote entry script and Makefile targets are glue only;
  any decision logic stays in the Lua `wez` binary.
- **Idempotent marker-guarded registration** (OSC7 / completions markers in `setup.sh`) —
  the model for any rc/file edits the remote path makes.
- **Dogfood against a scratch HOME** (R4) — tests run setup against a copy; the remote
  bootstrap should be testable the same way (temp HOME + temp checkout).

### Integration Points
- New `tools/<remote-bootstrap>.sh` (name = planner) is the one-liner target; it fetches
  the repo then hands off to `tools/setup.sh`.
- New `.github/workflows/<release>.yml` matrix produces the assets the launcher consumes.
- `Makefile` `build`/`publish` targets share the asset contract with CI.

</code_context>

<specifics>
## Specific Ideas

- User strongly prefers a plain compressed/raw binary in `~/.local/bin` that is "discoverable
  from any terminal" (on PATH) and "no permission problems in any environment" (user-path,
  `chmod +x`, sudo-free).
- User questioned `.gz` value for a tiny binary → publish raw (P6-D01).
- User wants local build+publish to be a real, supported capability from Linux or macOS, not
  CI-only (P6-D08).
- User flagged that GH Actions macOS build support was uncertain → confirmed: `macos-13`
  (Intel) + `macos-14` (Apple Silicon) runners build both arches natively.

</specifics>

<deferred>
## Deferred Ideas

- **`brew` / `dmg` as a macOS WezTerm acquisition fallback** — sudo-free, fits **Phase 7**
  (macOS parity), not Phase 6.
- **`apt` / `dnf` / `pacman` fallback** — out of v1: they require sudo, violating the
  sudo-free invariant. Only reconsider if that constraint is ever relaxed.
- **On-Mac verification of the macOS `wez` asset** (Gatekeeper/quarantine/codesign runtime)
  — built here, verified in **Phase 7**.

</deferred>

---

*Phase: 6-installer*
*Context gathered: 2026-06-14*
