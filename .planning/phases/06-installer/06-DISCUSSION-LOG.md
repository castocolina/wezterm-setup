# Phase 6: Ergonomic Installer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-14
**Phase:** 6-installer
**Areas discussed:** Binary acquisition, Repo publishing & releases, Pipe-to-bash trust model, Re-run / no-TTY behavior, Cross-platform build/publish

---

## Binary acquisition (`wez`)

| Option | Description | Selected |
|--------|-------------|----------|
| Cascade luastatic → release → source-launcher | Build local if toolchain; else verified release; else source-launcher (lua5.4 floor) | |
| Source-launcher as v1 path | Remote always runs Lua source via the dev launcher; no published releases needed | |
| Release-binary mandatory | One-liner only installs a checksum-verified release binary | |

**User's choice:** Free-text — wants a compressed/raw release binary (`.gz`?) placed in `~/.local/bin` (per-OS path), discoverable from any terminal (on PATH), no permission issues (user-path, sudo-free). Later: "we can compile and package a binary, but is `.gz` necessary for that tiny binary? We need a git workflow to make the binary available; the launcher downloads it + WezTerm, unpacks, makes them available."
**Notes:** Resolved to **release asset via GH Actions** (P6-D01); `.gz` deemed unnecessary for a small static binary → raw asset. Activates the dormant `WEZ_REMOTE_BOOTSTRAP=1` path in `build.sh`.

---

## Repo publishing & releases

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 6 cuts the first release | Publish repo + per-platform assets + checksums + CI now | ✓ |
| Source-launcher interim, release as destination | URL-parameterized; falls back to source-launcher until a release exists | |

**User's choice:** Configured the real remote (`git@github.com:castocolina/wezterm-setup.git`, default `main`) mid-discussion, then directed that the cross-platform CI build/publish be a real requirement.
**Notes:** Real URLs now pin the installer + release paths. Became INST-08.

---

## Cross-platform build/publish (GH Actions vs local)

| Option | Description | Selected |
|--------|-------------|----------|
| CI matrix only | GH Actions builds all three OS/arch targets | |
| CI matrix + first-class local `make build/publish` | CI is the convenience path; maintainer can also build+publish locally from Linux or macOS | ✓ |

**User's choice:** "I want anyone to be able to build locally and publish… I'd like to do build, install, download the WezTerm binary and use the binary I made available; but publishing from Linux or Mac should also work."
**Notes:** Confirmed GH Actions has macOS Intel (`macos-13`) + Apple Silicon (`macos-14`) runners → both arches buildable in CI. Local `make build/install/publish` made first-class (P6-D08). macOS asset *build* wired in Phase 6; on-Mac *verification* is Phase 7.

---

## Pipe-to-bash trust model

| Option | Description | Selected |
|--------|-------------|----------|
| Docs inspect-before-run + URL pinnable | README guidance + pin-to-tag/commit; inherited binary checksum | ✓ |
| Script signature/checksum verification | Bootstrap verifies its own script before executing | |

**User's choice:** Option 1, plus: "we need to review all the README with the `crafting-effective-readmes` skill."
**Notes:** Formal threat model deferred to the planner (SC#5). README authored/reviewed via the skill (P6-D06).

---

## Re-run / no-TTY behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Safe default + flags via `bash -s --` | No prior install → install; existing block + no TTY → D-03 abort; flags passable | ✓ |
| Idempotent update by default | Re-run updates + re-applies block without confirmation | |

**User's choice:** Challenged the premise — "why would I run without a TTY if this is meant for TTY use?"
**Notes:** Reframed the real issue: `curl | bash` consumes stdin even with a terminal attached. Resolution (P6-D04): read prompts from `/dev/tty` so re-install (D-03) + version selector (D-08) stay interactive; only genuinely headless runs keep the abort.

---

## Claude's Discretion

- Temp-repo fetch via `git clone --depth 1` vs tarball (`codeload`) — tarball avoids a `git` dep.
- Release asset raw vs `.gz` (leans raw).
- Release-asset naming scheme + GH Actions workflow file layout (shared CI/local contract).

## Deferred Ideas

- `brew` / `dmg` macOS WezTerm acquisition fallback → Phase 7 (sudo-free).
- `apt` / `dnf` / `pacman` fallback → out of v1 (requires sudo; violates sudo-free invariant).
- On-Mac verification of the macOS `wez` asset (Gatekeeper/quarantine/codesign) → Phase 7.
