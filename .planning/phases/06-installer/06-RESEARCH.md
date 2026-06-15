# Phase 6: Ergonomic Installer - Research

**Researched:** 2026-06-14
**Domain:** Remote `curl|bash` bootstrap installers, GitHub Actions release matrices (luastatic single binary), POSIX self-replacing-binary update, WezTerm nightly asset acquisition, pipe-to-bash interactivity via `/dev/tty`
**Confidence:** HIGH (most claims verified against current sources or the live repo; ONE locked CONTEXT decision is now stale — see the flagged P6-D01 runner correction)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

> These are LOCKED. Research answers *how* to satisfy them, never *whether*. One locked
> decision (P6-D01's `macos-13` Intel runner) has been overtaken by an upstream GitHub change
> since discuss-phase — flagged below as a **required correction**, not a relitigation.

### Locked Decisions

- **P6-D01:** `wez` binary delivered as a **GitHub Actions release asset**. CI **matrix** builds
  natively per target — `ubuntu-latest` → `linux-x86_64`, `macos-13` → `darwin-x86_64` (Intel),
  `macos-14` → `darwin-aarch64` (Apple Silicon) — each via luastatic; the Silicon job
  ad-hoc-codesigns its asset. Installer downloads the asset, `chmod +x`, places in `~/.local/bin`.
  **Raw binary** (no `.gz` — compression is the planner's call, low value). Activates the dormant
  `WEZ_REMOTE_BOOTSTRAP=1` path in `tools/build.sh`, repointed to the real
  `github.com/castocolina/wezterm-setup` release URL.
  > ⚠️ **REQUIRED CORRECTION (see Architecture Patterns + State of the Art):** the `macos-13`
  > runner image was **fully removed by GitHub on 2025-12-04** `[VERIFIED: github.com/actions/runner-images#13046]`.
  > It does not exist in June 2026. The Intel x86_64 job MUST use **`macos-15-intel`** (the
  > supported Intel label through Aug 2027) or `macos-13-large`/`macos-14-large`. This does not
  > change the *intent* of P6-D01 (build Intel natively, ad-hoc-codesign Silicon) — only the
  > runner label. Confirm with the user at plan time; it is a label swap, nothing more.
- **P6-D02:** Flow: one-liner → fetch repo to temp dir → run `tools/setup.sh` with
  `WEZ_REMOTE_BOOTSTRAP=1` → bootstrap/reuse WezTerm → download `wez` release binary → place
  managed assets → `wez doctor` pass/fail → remove temp checkout. Ship `curl` AND `wget` variants.
- **P6-D03 (INVARIANT):** **No AppImage, no Flatpak, nothing requiring sudo**, at any layer.
  Linux = plain `.tar.xz`/raw binary to user-path.
- **P6-D04:** Read interactive prompts from **`/dev/tty`** under the pipe (stdin is consumed).
  README also shows `bash <(curl …)`. Genuinely headless (no `/dev/tty`, CI) keeps D-03's
  non-zero abort; flags passable via `curl … | bash -s -- --force|--restore|--skip`.
- **P6-D05:** Trust model = **inspect-before-run guidance + pin-to-tag/commit** in README +
  inherited checksum verification at download. Formal threat model authored by the planner.
- **P6-D06:** README install/config rewrite authored/reviewed with the `crafting-effective-readmes`
  skill. Real `castocolina` URLs; both `curl|bash` and `wget` variants + post-install steps.
- **P6-D07:** Launcher detects OS+arch via `tools/lib/platform.sh`, maps to the matching
  release-asset name, downloads it. **No asset for OS/arch → fail with a clear, actionable
  error.** Never a silent fallback to a wrong binary.
- **P6-D08:** **Local build/install/publish is first-class.** New Makefile targets `make build`
  (luastatic), `make install` (dogfood), `make publish` (publish current-platform asset). MUST
  work from **both Linux and macOS**. Local + CI share the **same asset-naming contract**.
- **P6-D09:** Installer **targets `nightly` by default** (incl. non-interactive). Update-in-place:
  if WezTerm present, compare its datestamp vs latest nightly; if available is **newer**, update
  the binary (fetch+swap); if `≥`, reuse untouched (no-op). **HARD CONSTRAINT:** update-in-place
  applies ONLY to the **project-managed user-path install** (`~/.local/...`). A **system install
  is never modified** — verified real case: WezTerm here is the apt package `wezterm-nightly` in
  `/usr/bin` (root-owned). If only a system install exists, place the project's own user-path copy
  that wins on `PATH`, leaving system files intact.
- **P6-D10:** Per-platform archive — Linux `.tar.xz` (handled) vs macOS `.zip` (contains
  `WezTerm.app` → `~/Applications`). `install_macos()` is a STUB; macOS unpack is the Phase 7 gap.
- **P6-D11:** `wez update` subcommand invokes the **same GitHub launcher** the one-liner uses
  (single entry point). Refreshes `wez` binary + managed assets + WezTerm-if-newer-nightly under
  P6-D09 rules + P6-D05 trust model. D-01 boundary: thin Lua command; version comparison MAY live
  in Lua, fetch/unpack/place delegated to the shared bootstrap glue. Self-replacement gotcha:
  download to temp, atomically rename/swap. Completion via `cli/spec.lua` (D-16). Clear no-op when
  current.

### Claude's Discretion

- **git clone --depth 1 vs tarball** (`codeload.github.com/.../tar.gz`) — tarball avoids a `git`
  dependency; planner's call under P6-D02. → **Recommendation: tarball (see Don't Hand-Roll + Pattern 5).**
- **`wez` release asset raw vs `.gz`** — P6-D01 leans raw. → **Recommendation: raw (see State of the Art).**
- **Exact release-asset naming scheme + GH Actions workflow file layout** under P6-D08's
  same-contract rule. → **Recommendation: `wez-<os>-<arch>` (matches the existing `download_release()`
  in build.sh — see Architecture Patterns + Pattern 6).**

### Deferred Ideas (OUT OF SCOPE)

- `brew` / `dmg` macOS WezTerm acquisition fallback → **Phase 7**.
- `apt` / `dnf` / `pacman` fallback → out of v1 (requires sudo, violates P6-D03).
- On-Mac *verification* of the macOS `wez` asset (Gatekeeper/quarantine/codesign runtime) →
  built here, **verified in Phase 7**.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INST-07 | Ergonomic one-line remote installer (`curl -fsSL <raw> \| bash` + `wget` variant): fetch repo to temp → install/update WezTerm sudo-free (INST-06) → download matching `wez` release binary → place via setup.sh → `wez doctor` → cleanup temp; README + trust model; interactive via `/dev/tty` | Pattern 1 (function-wrapped entry script), Pattern 2 (`/dev/tty` read), Pattern 3 (mktemp+trap cleanup), Pattern 5 (codeload tarball fetch), Trust Model section, Don't Hand-Roll (reuse `setup.sh`/`bootstrap-wezterm.sh`) |
| INST-08 | Cross-platform build-and-publish pipeline: GH Actions matrix per-OS/arch (`linux-x86_64`, `darwin-x86_64`, `darwin-aarch64`; Silicon ad-hoc-codesigned); local `make build/install/publish` from Linux OR macOS, same asset-naming contract as CI | Pattern 6 (GH Actions release matrix — **with the corrected Intel runner label**), Pattern 7 (ad-hoc codesign), Standard Stack (luastatic, `gh release`, `softprops/action-gh-release`), asset-naming contract (`wez-<os>-<arch>` + `SHA256SUMS`) |
| INST-09 | `wez update` subcommand: re-invokes the SAME GitHub launcher as the one-liner; sudo-free; never touches a system install; update-in-place only for the user-path managed install; completion-wired via spec (D-16) | Pattern 4 (self-replacing binary — download-temp-same-dir + atomic rename), Pattern 8 (datestamp version compare, reuse `wezterm_version_datestamp`/`wezterm_datestamp_ge`), spec.lua registration (already has `__complete`/category infra) |
</phase_requirements>

## Summary

Phase 6 is overwhelmingly an **integration + glue** phase, not a greenfield build. Nearly every
mechanism it needs already exists in the repo and is tested: `tools/setup.sh` sequences the whole
install, `tools/bootstrap-wezterm.sh` does the sudo-free WezTerm `.tar.xz` fetch with integrity
gates, `tools/build.sh` already contains a **dormant `WEZ_REMOTE_BOOTSTRAP=1` release-download
path** (`download_release()`) wired to the exact `wez-<os>-<arch>` + `SHA256SUMS` contract this
phase should ship, and `tools/lib/platform.sh` already gives `platform_os`/`platform_arch`. The new
artifacts are: a thin **remote-bootstrap entry script** (`tools/install.sh` or similar) that
fetches the repo to a temp dir and hands off to `setup.sh`; a **GitHub Actions release workflow**;
**Makefile `build`/`publish` targets**; a **`wez update`** Lua command; and a **README rewrite**.

The single most important research finding is a **stale locked decision**: P6-D01 names `macos-13`
as the Intel x86_64 runner, but GitHub **fully removed the `macos-13` image on 2025-12-04**. As of
June 2026 the Intel runner is **`macos-15-intel`** (supported through Aug 2027). This is a label
swap that preserves P6-D01's intent (native Intel build + ad-hoc-codesigned Silicon) — the planner
must apply it. The Apple Silicon side (`macos-14`, arm64-only) is still correct.

Three trust-model primitives are non-negotiable for a `curl|bash` installer and are cheap to add:
(1) **wrap the entire entry script in a function invoked only on the last line** so a truncated
download can never execute a half-command; (2) **read interactive prompts from `/dev/tty`**, not
stdin (the pipe owns stdin); (3) **fetch the repo via the codeload tarball** (no `git` dependency)
into a `mktemp -d` guarded by a `trap … EXIT` so cleanup is guaranteed. Binary integrity is already
solved — `download_release()` verifies SHA-256 against a published `SHA256SUMS` before `chmod +x`.

**Primary recommendation:** Treat this phase as "wire the dormant paths to real `castocolina` URLs +
add a function-wrapped tarball-fetch entry script + a CI release matrix (with `macos-15-intel`) +
`wez update` that delegates to the shared launcher." Do NOT re-implement fetch/verify/place logic —
it exists and is tested. The new code is glue (D-01) plus one thin Lua command.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| One-liner entry (fetch repo→temp, hand off) | Remote bootstrap glue (`tools/install.sh`) | — | D-01: pure glue, zero decisions; just fetch+exec setup.sh |
| OS/arch asset selection | `tools/lib/platform.sh` (glue) | — | Detection only; already sourceable |
| `wez` binary download + SHA verify | `tools/build.sh` `download_release()` (glue) | — | Already exists; verifies before chmod (T-01-01) |
| WezTerm emulator fetch/extract/symlink | `tools/bootstrap-wezterm.sh` (glue) | — | Already tested on Linux; macOS unpack = Phase 7 |
| Asset placement (config/scenes/completions) | `tools/setup.sh` (glue) | — | Already sequences all of it |
| "Is there an update? newer nightly?" decision | Lua `wez` (`cli/commands/update.lua`) | bootstrap glue | D-01/P6-D11: decision in Lua, fetch/place delegated |
| Self-replace the running `wez` binary | bootstrap glue (download-temp + atomic mv) | Lua `wez update` triggers it | P6-D11 self-replacement gotcha; rename() is the safe primitive |
| Pipe-time interactive prompts | bootstrap glue reading `/dev/tty` | — | P6-D04; stdin owned by the pipe |
| Build/sign/publish per-OS/arch asset | GitHub Actions + `make build/publish` glue | luastatic, `codesign`, `gh release` | P6-D01/D08; native per-runner |
| Trust model (inspect-before-run, pinning) | README + entry-script structure | — | P6-D05; documentation + function-wrap |

## Standard Stack

### Core

| Library / Tool | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `luastatic` | latest (LuaRocks) `[ASSUMED]` | Bundle `cli/wez.lua` + all `cli/**/*.lua` + Lua interpreter into one static binary | Already the project's shipping artifact (D-02); `build.sh` `build_with_luastatic()` is implemented |
| `lua5.4` + dev headers | 5.4.x | luastatic needs the interpreter + `lua5.4` headers (`pkg-config --variable=includedir lua5.4`) | Already required by `build.sh` |
| C compiler (`cc`/`gcc`; `clang` on macOS) | system | luastatic links the bundle into a native binary | Standard; macOS runners ship Xcode `clang` |
| `gh` CLI / `softprops/action-gh-release` | gh 2.94.0 `[VERIFIED: local]`; action latest `[CITED: github.com/softprops/action-gh-release]` | Publish per-OS/arch assets to a GitHub Release on tag push (CI) and from `make publish` (local) | `gh release upload` is the canonical local-publish primitive; `softprops/action-gh-release` is the de-facto CI release action |
| `codesign` (macOS, Xcode CLT) | system | Ad-hoc-sign the Apple Silicon binary: `codesign --force --sign - <bin>` | Apple's tool; ad-hoc (`-`) needs no Developer ID |
| `curl` / `wget` | system | Fetch repo tarball + assets (installer ships both code paths) | Already the project's fetch helpers |
| `tar` | system | Unpack the codeload `.tar.gz` (and the WezTerm `.tar.xz` — already handled) | Universal; no `git` dependency |
| `sha256sum` (Linux) / `shasum -a 256` (macOS) | system | Generate + verify `SHA256SUMS` | Both present locally `[VERIFIED: local]`; **macOS needs `shasum -a 256`** (no `sha256sum`) — Phase 7 gap already tracked |

### Supporting

| Tool | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `mktemp -d` | system | Temp checkout dir for the remote bootstrap (P6-D02) | Always; pair with `trap 'rm -rf "$tmp"' EXIT` |
| `codeload.github.com` tarball endpoint | n/a (GitHub service) | Fetch the repo without `git` | Default repo-fetch (Pattern 5) — verified HTTP 200 from this host |
| `xattr -d com.apple.quarantine` | macOS | (Phase 7) strip the quarantine bit on the downloaded macOS `wez` binary if Gatekeeper blocks it | Phase 7 on-Mac verification only |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| codeload tarball fetch | `git clone --depth 1` | clone needs `git` installed (extra dependency the user may lack on a fresh box); tarball needs only curl/wget+tar which the installer already requires. **Tarball wins** (P6-D02 discretion). |
| `softprops/action-gh-release` (CI) | raw `gh release create/upload` in a `run:` step | `gh` works identically locally and in CI (shared mental model, satisfies the "same contract" rule); the action is slightly more declarative. Either is fine — recommend **`gh release upload` in both** so `make publish` and CI are literally the same command. |
| raw binary asset | `.gz`-compressed asset | A luastatic `wez` is tiny; `.gz` adds an unpack step in the installer for ~no size win. **Raw wins** (P6-D01). |
| `macos-15-intel` Intel runner | `macos-13-large` / `macos-14-large` | `macos-15-intel` is the explicitly-supported forward Intel label (through Aug 2027); the `-large` variants are paid larger runners. **`macos-15-intel` wins** for a solo-dev project on the free tier where available. |

**Installation (CI runners + local dev):**
```bash
# Lua toolchain + luastatic (Linux runner / local Linux)
sudo apt-get install -y lua5.4 liblua5.4-dev luarocks   # or distro equivalent
luarocks install luastatic
# macOS runner / local macOS
brew install lua luarocks && luarocks install luastatic
```

**Version verification (run at plan time, do not trust this doc's versions blindly):**
```bash
luarocks show luastatic        # confirm luastatic is installable on each runner
gh --version                   # local publish tool — 2.94.0 confirmed on dev host
```
> luastatic version is `[ASSUMED]` — it was NOT installed on the dev host at research time
> (`command -v luastatic` → not found; the dev build currently uses the source-launcher path).
> The planner MUST gate the CI build on a real luastatic install per runner and capture the
> version. See Package Legitimacy Audit.

## Package Legitimacy Audit

> This phase installs **luastatic** (LuaRocks) on the CI runners and dev machines. All other
> "packages" are system tools (`curl`, `tar`, `codesign`, `gh`, `sha256sum`) shipped by the OS or
> already required. slopcheck targets language-registry packages (npm/PyPI/crates); LuaRocks is
> outside its ecosystem coverage, so luastatic is treated `[ASSUMED]` and gated by a real install
> on the runner (which is the verification).

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `luastatic` | LuaRocks | mature (already adopted in D-02 / `build.sh`) | n/a (LuaRocks has no public count) | github.com/ers35/luastatic (well-known) `[ASSUMED]` | n/a (not an npm/PyPI/crates pkg) | **Approved (already the project's chosen build tool, D-02)** — but planner verifies a real install per runner |
| `softprops/action-gh-release` | GitHub Actions Marketplace | mature, widely used `[CITED]` | n/a | github.com/softprops/action-gh-release | n/a | Approved (optional — `gh release` is the no-dependency alternative) |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

*slopcheck does not cover LuaRocks or GitHub Actions; luastatic is already the project's locked
build tool (D-02) and is verified by actually building a working binary in CI, which is the real
legitimacy gate here. Pin the `action-gh-release` to a tag/SHA if used.*

## Architecture Patterns

### System Architecture Diagram

```
                      ┌─────────────────────── SUPPLY SIDE (INST-08) ───────────────────────┐
   git tag push  ──►  │  GitHub Actions release.yml (matrix)                                 │
                      │    ubuntu-latest ─► luastatic ─► wez-linux-x86_64                     │
                      │    macos-15-intel ─► luastatic ─► wez-darwin-x86_64   (CORRECTED)     │
                      │    macos-14 (arm64) ─► luastatic ─► codesign --sign - ─► wez-darwin-aarch64
                      │    ─► sha256 each ─► SHA256SUMS ─► gh release upload (per tag)         │
                      └──────────────────────────────┬──────────────────────────────────────┘
                                                      │ GitHub Release assets
                                                      ▼
   user pastes one-liner                  ┌─────────── github.com/castocolina/wezterm-setup ──────────┐
   curl -fsSL <raw>/tools/install.sh ──►  │ raw.githubusercontent.com/.../tools/install.sh             │
        | bash                            └──────────────────────────────┬────────────────────────────┘
                                                                         │ (whole script wrapped in main(); runs only on last line)
                                                                         ▼
   ┌──────────────────── CONSUME SIDE (INST-07) — tools/install.sh ─────────────────────────────────┐
   │ 1. mktemp -d  (+ trap 'rm -rf' EXIT)                                                            │
   │ 2. fetch repo: codeload.github.com/.../tar.gz/refs/heads/<ref>  ─► tar -xzf  (no git needed)    │
   │ 3. exec  WEZ_REMOTE_BOOTSTRAP=1  <temp>/tools/setup.sh  "$@"   ──────────────┐                  │
   └─────────────────────────────────────────────────────────────────────────────┼──────────────────┘
                                                                                  ▼
   ┌──────────────────── tools/setup.sh (EXISTING, reused) ──────────────────────────────────────────┐
   │ STEP2 bootstrap-wezterm.sh ─► reuse-if-≥nightly OR fetch .tar.xz (sudo-free, system install untouched, P6-D09)
   │ STEP3 build.sh (WEZ_REMOTE_BOOTSTRAP=1) ─► download_release(): wez-<os>-<arch> + SHA256SUMS verify ─► chmod +x ─► ~/.local/bin
   │ STEP4/4b place config + seed scenes        STEP5/5b register OSC7 + completions                  │
   │ STEP6 wez install-state (reads /dev/tty for re-install prompt, P6-D04)                           │
   │ ─► wez doctor (pass/fail)                                                                        │
   └─────────────────────────────────────────────────────────────────────────────────────────────────┘
                                                                                  ▲
   wez update (INST-09) ── Lua: compare datestamp, decide ──► re-invokes the SAME launcher ──────────┘
                           (download wez to temp in ~/.local/bin, chmod +x, atomic mv over live binary)
```

### Recommended Project Structure (new/changed files)

```
tools/
├── install.sh          # NEW — the one-liner target: mktemp → codeload tarball → exec setup.sh. PURE glue (D-01).
├── setup.sh            # CHANGED minimally — already accepts WEZ_REMOTE_BOOTSTRAP; no structural change needed
├── build.sh            # CHANGED — repoint WEZ_RELEASE_BASE (you/...) → castocolina; keep download_release() contract
└── lib/platform.sh     # UNCHANGED — already powers P6-D07
.github/workflows/
└── release.yml         # NEW — tag-triggered matrix: linux-x86_64, darwin-x86_64 (macos-15-intel), darwin-aarch64 (macos-14)
cli/
├── spec.lua            # CHANGED — register `update` (+ category) so completion picks it up (D-16); add to allow-list
└── commands/update.lua # NEW — thin Lua: decide-if-update + delegate fetch/place to the shared launcher
Makefile                # CHANGED — add build / install / publish targets (thin glue → tools/*)
README.md               # REWRITTEN — real castocolina URLs, curl|bash + wget + bash <(curl) forms, trust model
```

### Pattern 1: Function-wrapped entry script (partial-download safety)

**What:** Wrap the *entire* body of `tools/install.sh` in a function and call it only on the final
line. If the `curl` stream is truncated mid-download, bash executes only complete function
definitions — it never reaches the final `main "$@"`, so no half-command runs.
**When to use:** Any script delivered over `curl … | bash`. **Mandatory** for INST-07 (P6-D05).
**Example:**
```bash
#!/usr/bin/env bash
# Source: https://macarthur.me/posts/curl-to-bash/  [CITED]
# tools/install.sh — pipe-safe remote bootstrap (D-01 glue only).
set -euo pipefail

main() {
  # ... entire installer body here: mktemp, fetch tarball, exec setup.sh ...
  :
}

main "$@"   # <- a truncated download never reaches this line; nothing partial executes.
```
> The existing `tools/build.sh`, `setup.sh`, and `bootstrap-wezterm.sh` already use a
> `main()`/`[ "${BASH_SOURCE[0]}" = "${0}" ] && main` shape — the new entry script just makes the
> invocation the literal last line so truncation safety is explicit.

### Pattern 2: Reading interactive prompts from `/dev/tty` under a pipe

**What:** Under `curl … | bash`, stdin is the script text (the pipe), so `read` from stdin returns
the *script*, not the user. Read from `/dev/tty` instead, and detect its absence (CI) to fall back
to the non-interactive abort (D-03).
**When to use:** Every interactive prompt the remote path hits — the re-install decision (INST-03)
and the WezTerm version selector (D-08). Satisfies P6-D04.
**Example:**
```bash
# Source: portable /dev/tty pattern, bash on Linux + macOS bash 3.2  [VERIFIED: shell semantics]
if [ -e /dev/tty ] && [ -r /dev/tty ]; then
  printf 'Choice [1-%d]: ' "$n" > /dev/tty
  read -r reply < /dev/tty            # reads the human, not the piped script
else
  # genuinely headless (CI, no controlling terminal) — keep D-03's non-zero abort,
  # instruct: re-run with  curl … | bash -s -- --force|--restore|--skip
  err "no controlling terminal; pass an explicit flag (--force/--restore/--skip)"
  exit 3
fi
```
> **Important seam:** `bootstrap-wezterm.sh`'s `select_release()` and `setup.sh`'s delegation to
> `wez install-state` currently key interactivity off `[ -t 0 ]` (stdin is a TTY). Under the pipe,
> stdin is NOT a TTY even when a terminal is attached, so those checks would force the
> non-interactive path. **The fix:** the remote entry script should make `/dev/tty` available to
> the children. The cleanest portable approach is to redirect the child's stdin from `/dev/tty`
> when it exists: `WEZ_REMOTE_BOOTSTRAP=1 "$tmp/tools/setup.sh" "$@" < /dev/tty` (so the existing
> `[ -t 0 ]` checks light up correctly), and pass flags through `"$@"` for the headless case. This
> is the **least invasive** way to keep the existing TTY logic working under the pipe — verify on a
> real terminal at plan time (it's a known-good idiom but the project's `[ -t 0 ]` seams must be
> re-checked). The `bash <(curl …)` process-substitution form sidesteps the problem entirely
> because stdin stays the terminal — document it in the README as the "I want full interactivity"
> variant (P6-D04).

### Pattern 3: Temp checkout with guaranteed cleanup

**What:** `mktemp -d` + a `trap` that removes it on ANY exit (success, failure, Ctrl-C).
**When to use:** The remote bootstrap's temp repo (P6-D02 SC#3 — "nothing left behind").
**Example:**
```bash
tmp="$(mktemp -d "${TMPDIR:-/tmp}/wezterm-setup.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT     # fires on success, error, and signals → SC#3 guaranteed
```
> `bootstrap-wezterm.sh`'s `install_linux()` already uses `trap "rm -rf '${tmpdir}'" RETURN` for
> its download dir — same idiom, proven in-repo. Use `EXIT` (not `RETURN`) at the top-level script
> scope.

### Pattern 4: Self-replacing the running `wez` binary (INST-09)

**What:** A running binary cannot be safely truncated/overwritten in place. The safe POSIX move:
download the new binary to a **temp file in the same directory** as the live binary (same
filesystem → `rename()` is atomic and cross-device `EXDEV` is impossible), `chmod +x`, then
`mv -f` (atomic `rename(2)`) over the live path. `rename()` only swaps the directory entry to the
new inode; the old inode stays valid for the still-running process until it exits. **Never**
`rm` then write — that leaves a window with no binary and risks `ETXTBSY`.
**When to use:** `wez update` replacing `~/.local/bin/wez` while `wez update` itself is running.
**Example:**
```bash
# Source: rename(2) atomicity + ETXTBSY discussion  [CITED: man7.org/linux/man-pages/man2/rename.2.html]
dest="${BIN_DIR}/wez"                 # the live, possibly-running binary
new="${dest}.new.$$"                  # SAME directory → same filesystem → rename() is atomic
download_release_to "$new"            # reuse build.sh's verified download (SHA before chmod)
chmod +x "$new"
mv -f "$new" "$dest"                  # atomic swap; old inode survives for the running process
```
> Platform notes: on **Linux**, replacing a running binary via `rename()` works (the open
> text-image keeps the old inode; you do NOT hit `ETXTBSY` because you're renaming over it, not
> writing into it). On **macOS** the same `rename()` semantics hold. The dangerous pattern is
> `cp`/`>` *into* the running binary's path (can give `ETXTBSY` / corrupt the image) — avoid it.
> Because `wez update` is a thin Lua command (P6-D11 / D-01), the actual swap should live in the
> **shared bootstrap glue**, which `wez update` re-invokes — not re-implemented in Lua.

### Pattern 5: Fetch repo to temp via codeload tarball (no `git`)

**What:** Download a repo snapshot without requiring `git`:
`https://codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/<branch>` (or `…/tar.gz/refs/tags/<tag>`
for a pinned tag, or `…/tar.gz/<sha>` for a commit). Pipe straight into `tar`.
**When to use:** The remote bootstrap repo fetch (P6-D02; resolves the git-clone-vs-tarball
discretion in favor of tarball).
**Example:**
```bash
# Source: verified live from this host — HTTP 200, filename=wezterm-setup-main.tar.gz  [VERIFIED: local curl]
ref="${WEZ_REF:-main}"                 # README documents pinning: WEZ_REF=v1.0.0 curl … | bash
url="https://codeload.github.com/castocolina/wezterm-setup/tar.gz/refs/heads/${ref}"
curl -fsSL "$url" | tar -xzf - -C "$tmp" --strip-components=1
#   (wget variant:  wget -qO- "$url" | tar -xzf - -C "$tmp" --strip-components=1 )
#   --strip-components=1 drops the top-level "wezterm-setup-<ref>/" dir GitHub wraps the tarball in.
```
> **Pinning seam:** the entry script should accept a ref (env var or `-s -- --ref <x>`) so the
> README's pin-to-tag/commit trust guidance (P6-D05) is actionable. Default `main` (P6-D09 says
> default WezTerm = nightly; the *repo* default is `main` per ROADMAP). For a tag use
> `…/tar.gz/refs/tags/<tag>`; for a commit `…/tar.gz/<full-sha>`.

### Pattern 6: GitHub Actions release matrix (INST-08) — with corrected runners

**What:** A tag-triggered (`on: push: tags: ['v*']`) workflow with a 3-leg matrix. Each leg builds
luastatic natively, names the asset `wez-<os>-<arch>`, generates a per-asset sha, and uploads to
the Release. A final/join step (or per-leg) writes `SHA256SUMS` (the contract `download_release()`
already verifies).
**When to use:** INST-08 supply side.
**Example (skeleton — exact YAML is the planner's to author):**
```yaml
# Source: corrected runner labels per actions/runner-images  [VERIFIED: github.com/actions/runner-images#13046, #13045]
name: release
on: { push: { tags: ['v*'] } }
permissions: { contents: write }     # required for gh release upload
jobs:
  build:
    strategy:
      matrix:
        include:
          - { runner: ubuntu-latest,    os: linux,  arch: x86_64  }
          - { runner: macos-15-intel,   os: darwin, arch: x86_64  }   # ⚠ NOT macos-13 (removed 2025-12-04)
          - { runner: macos-14,         os: darwin, arch: aarch64 }   # arm64-only image
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4
      - name: install lua + luastatic  # apt on linux, brew on macos
        run: ./tools/ci-setup-toolchain.sh   # (planner: small helper, or inline)
      - name: build
        run: ./tools/build.sh                # produces dist/wez via build_with_luastatic()
      - name: ad-hoc codesign (apple silicon only)
        if: matrix.os == 'darwin' && matrix.arch == 'aarch64'
        run: codesign --force --sign - dist/wez
      - name: name + checksum asset
        run: |
          asset="wez-${{ matrix.os }}-${{ matrix.arch }}"
          cp dist/wez "$asset"
          if command -v sha256sum >/dev/null; then sha256sum "$asset" > "$asset.sha256";
          else shasum -a 256 "$asset" > "$asset.sha256"; fi   # macOS has no sha256sum
      - uses: softprops/action-gh-release@v2   # or: gh release upload "$GITHUB_REF_NAME" wez-* --clobber
        with: { files: "wez-*" }
```
> **Same-contract rule (P6-D08):** `make publish` must produce a byte-identical-named asset
> (`wez-<os>-<arch>`) and upload it with `gh release upload <tag> wez-<os>-<arch> --clobber`. The
> asset name is computed from `platform_os`/`platform_arch` in BOTH places so local and CI never
> drift. **`SHA256SUMS` assembly:** the simplest contract is one combined `SHA256SUMS` file at the
> release containing all three lines (what `download_release()` greps). Since matrix legs run
> independently, either (a) each leg uploads its own `wez-<os>-<arch>.sha256` and a tiny join job
> concatenates them into `SHA256SUMS`, or (b) keep per-asset `.sha256` files and adapt
> `download_release()` to fetch `<asset>.sha256` instead of a combined `SHA256SUMS`. **Recommend
> (b)** — it removes the cross-job join entirely and matches `make publish` (one platform at a
> time) perfectly. This is a small, deliberate change to `build.sh`'s `sums_url`/grep logic; call
> it out in the plan.

### Pattern 7: Ad-hoc codesign the Apple Silicon binary

**What:** `codesign --force --sign - dist/wez` applies an **ad-hoc** signature (the `-` identity)
— no Apple Developer ID needed. Apple Silicon refuses to run *unsigned* arm64 Mach-O binaries at
all; an ad-hoc signature satisfies the loader. It does **not** clear Gatekeeper/quarantine for
downloaded files (that's the Phase 7 `xattr`/notarization concern).
**When to use:** The `darwin-aarch64` CI leg + `make publish` on Apple Silicon (P6-D01).
**Example:**
```bash
# Source: Apple codesign ad-hoc semantics  [CITED: developer.apple.com/forums/thread/703523]
codesign --force --sign - dist/wez          # ad-hoc; arm64 won't exec without at least this
codesign --verify --verbose dist/wez        # sanity check in CI
```
> Phase 7 owns the *runtime* verification (does the downloaded, quarantined binary actually launch
> on a real Mac, or does Gatekeeper need `xattr -d com.apple.quarantine`?). Phase 6 only ensures
> the asset is *built and ad-hoc-signed*.

### Pattern 8: Datestamp version comparison for update-in-place (reuse existing helpers)

**What:** WezTerm nightly versions are date-stamped (`YYYYMMDD-HHMMSS-shortsha`); the leading
8-digit date is the monotonic comparator. The repo **already has** `wezterm_version_datestamp()`
and `wezterm_datestamp_ge()` in `bootstrap-wezterm.sh`, and `detect_and_reuse()` already decides
reuse-vs-fetch. Update-in-place for `nightly` (P6-D09) is the same logic with the "minimum" set to
"latest available nightly datestamp" instead of the pinned baseline.
**When to use:** `wez update`'s "is WezTerm newer available?" check + the installer's P6-D09 update path.
**Example:**
```bash
# reuse existing helpers; only the "want" target changes from pinned → latest-nightly
have="$(wezterm_version_datestamp "$(wezterm --version)")"
want="$(latest_nightly_datestamp)"          # NEW small helper (see Open Questions Q1)
if wezterm_datestamp_ge "$have" "$want"; then : ; else fetch_and_swap_wezterm; fi
# HARD: only do this when the resolved wezterm is the user-path one (~/.local/bin/wezterm);
# a system install (e.g. /usr/bin, apt wezterm-nightly) is NEVER touched (P6-D09).
```

### Anti-Patterns to Avoid

- **Reading prompts from stdin under the pipe.** Stdin is the script; you'll read garbage or block.
  Use `/dev/tty` (Pattern 2).
- **`rm`-then-write to self-replace a running binary.** Leaves a no-binary window and risks
  `ETXTBSY`/corruption. Use download-temp-then-atomic-`mv` (Pattern 4).
- **Silent fallback to a wrong-arch binary** when no asset matches. P6-D07 mandates a clear,
  actionable error.
- **Touching a system WezTerm install.** P6-D09 is a hard constraint — the verified real case is
  `/usr/bin` apt `wezterm-nightly` (root-owned). Place a user-path copy that wins on PATH instead.
- **A second, divergent update path.** P6-D11: `wez update` re-invokes the SAME launcher; do not
  re-implement fetch/place logic in Lua.
- **Trusting `git` is installed.** Use the codeload tarball (Pattern 5) so the only fetch
  dependency is curl/wget + tar.
- **Using `macos-13` (Intel) in CI.** Removed by GitHub 2025-12-04 — the job will hard-fail.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Download `wez` binary + verify integrity | New download+sha logic | `tools/build.sh` `download_release()` (`WEZ_REMOTE_BOOTSTRAP=1`) | Already verifies SHA-256 before `chmod +x` (T-01-01); just repoint `WEZ_RELEASE_BASE` → castocolina |
| OS/arch detection + asset name | New uname parsing | `tools/lib/platform.sh` `platform_os`/`platform_arch` | Sourceable, already powers the dormant path; `wez-<os>-<arch>` already computed there |
| WezTerm fetch/extract/symlink (Linux) | New tarball handling | `tools/bootstrap-wezterm.sh` | Integrity-gated (xz magic, size, no-`..` members), tested; reuse-if-≥ already implemented |
| Asset placement (config/scenes/completions/OSC7) | New copy/register code | `tools/setup.sh` STEP 4–5b | Idempotent, marker-guarded, dogfood-tested |
| Re-install decision (override/restore/skip) | New prompt logic | `wez install-state` (Lua) via `setup.sh` STEP 6 | Owns the D-03 abort + the decision (D-01) |
| Datestamp version compare | New version math | `wezterm_version_datestamp`/`wezterm_datestamp_ge` | Already the comparator; just change the "want" target |
| Repo fetch without git | git-detection + clone fallback | codeload `tar.gz` + `tar --strip-components=1` | No git dependency; verified working from this host |
| Partial-download safety | Checksum-of-self gymnastics | Function-wrap + call on last line | Standard, zero-dependency idiom |
| Publish a release asset | Custom GitHub API uploads | `gh release upload` (local + CI) / `softprops/action-gh-release` | `gh` is installed (2.94.0) and identical local/CI |

**Key insight:** Phase 6's "build" is ~80% wiring existing, tested glue to real URLs. The genuinely
new code is: `tools/install.sh` (function-wrapped tarball fetch + `/dev/tty` hand-off), one CI
workflow, three Makefile targets, one thin Lua `update` command, and a README. Resist re-writing the
fetch/verify/place machinery — re-use is the whole point of the D-01 boundary.

## Common Pitfalls

### Pitfall 1: `macos-13` Intel runner no longer exists
**What goes wrong:** The CI matrix leg for `darwin-x86_64` uses `runs-on: macos-13` (per the
literal P6-D01 text) and every release build hard-fails — GitHub terminates the job because the
image was removed 2025-12-04.
**Why it happens:** P6-D01 was locked at discuss-phase before the upstream removal landed.
**How to avoid:** Use `runs-on: macos-15-intel` (supported through Aug 2027). Confirm the label
swap with the user (it preserves P6-D01's intent).
**Warning signs:** CI error "The macos-13 image is deprecated and unsupported."

### Pitfall 2: Prompts read the piped script, not the user
**What goes wrong:** Under `curl|bash`, `read` (or the existing `[ -t 0 ]`-gated `select_release`)
sees the pipe as stdin → the re-install prompt and version selector silently take the
non-interactive branch (or read script bytes).
**Why it happens:** The pipe owns stdin; `bootstrap-wezterm.sh`/`install-state` key off `[ -t 0 ]`.
**How to avoid:** Make `/dev/tty` the children's stdin in the remote entry script
(`… setup.sh "$@" < /dev/tty` when `/dev/tty` exists), and document `bash <(curl …)` as the
full-interactivity variant. Headless (no `/dev/tty`) keeps the D-03 abort.
**Warning signs:** Version selector never appears under the one-liner; re-install always aborts/forces.

### Pitfall 3: Overwriting a system WezTerm
**What goes wrong:** Update-in-place logic fetches a newer nightly and clobbers a root-owned
`/usr/bin/wezterm` (apt `wezterm-nightly`), needing sudo or corrupting a managed install.
**Why it happens:** Treating "a WezTerm exists" as "our WezTerm exists."
**How to avoid:** P6-D09 — only update when the resolved binary is the user-path
`~/.local/bin/wezterm`; otherwise place a user-path copy that wins on PATH. `detect_and_reuse()`
already logs "reused install is outside BIN_DIR" — branch on that.
**Warning signs:** Permission-denied writing `/usr/bin`; the installer tries to `sudo`.

### Pitfall 4: macOS has no `sha256sum`
**What goes wrong:** `make publish` / CI checksum generation on a Mac calls `sha256sum` → command
not found; the asset ships without (or with a missing) checksum, breaking `download_release()`.
**Why it happens:** macOS ships `shasum`, not `sha256sum` (already a tracked macOS gap).
**How to avoid:** `command -v sha256sum >/dev/null && sha256sum … || shasum -a 256 …` in both the
publish path and `download_release()`'s verify step.
**Warning signs:** `sha256sum: command not found` on the macOS runner.

### Pitfall 5: Truncated `curl|bash` runs a half-command
**What goes wrong:** Network blip cuts the download; bash executes a partial line (`rm -rf /tmp/x`
→ `rm -rf /`).
**Why it happens:** Bash executes a piped stream line-by-line as it arrives.
**How to avoid:** Wrap everything in `main()`, call `main "$@"` on the last line (Pattern 1).
**Warning signs:** Any top-level executable statement in `tools/install.sh` outside `main()`.

### Pitfall 6: Tarball top-level directory
**What goes wrong:** codeload tarballs unpack into `wezterm-setup-<ref>/…`; without
`--strip-components=1`, `setup.sh` is at `$tmp/wezterm-setup-main/tools/setup.sh`, not
`$tmp/tools/setup.sh`, and the hand-off path is wrong.
**Why it happens:** GitHub wraps the archive in a single ref-named top dir.
**How to avoid:** `tar -xzf - --strip-components=1 -C "$tmp"`.
**Warning signs:** "No such file or directory: tools/setup.sh" after extract.

### Pitfall 7: `set -e` + `pipefail` masking under the pipe
**What goes wrong:** `curl … | bash` — if curl fails mid-stream, bash may have already started
executing; or a failing command in a pipeline isn't caught.
**Why it happens:** The outer `curl | bash` pipeline's exit status is bash's, not curl's; inside
the script, missing `set -euo pipefail` hides partial failures.
**How to avoid:** `set -euo pipefail` at the top of `install.sh` (matches the other tools/ scripts);
function-wrap (Pattern 1) handles the truncation half.
**Warning signs:** Installer "succeeds" after a failed fetch.

## Code Examples

### Repoint the dormant release base to the real remote (build.sh)
```bash
# tools/build.sh — change ONLY the placeholder base (the contract stays).
# Source: existing build.sh download_release()  [VERIFIED: local file]
WEZ_RELEASE_TAG="${WEZ_RELEASE_TAG:-v0.1.0}"   # planner: bump to the first real tag
WEZ_RELEASE_BASE="${WEZ_RELEASE_BASE:-https://github.com/castocolina/wezterm-setup/releases/download}"
#   asset = wez-$(platform_os)-$(platform_arch)         (e.g. wez-linux-x86_64)
#   verify <asset>.sha256 (Pattern 6b) before chmod +x  (T-01-01 holds)
```

### The one-liner the README ships (curl + wget + process-substitution)
```sh
# Source: ROADMAP real URLs + P6-D04/D05  [CITED: .planning/ROADMAP.md]
# default (main):
curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash
# wget variant:
wget -qO- https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash
# full-interactivity variant (stdin stays the terminal):
bash <(curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh)
# inspect-before-run (P6-D05 trust guidance):
curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh -o install.sh
less install.sh && bash install.sh
# pin to a tag (P6-D05):
WEZ_REF=v1.0.0 curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/v1.0.0/tools/install.sh | bash
```

### Makefile targets (thin glue — P6-D08; ≤5 lines each per the Makefile R3 rule)
```make
# Source: existing Makefile R3 thin-glue convention  [VERIFIED: local Makefile]
build:    ; @./tools/build.sh
publish:  ; @./tools/publish.sh        # NEW glue: build → name wez-<os>-<arch> → sha → gh release upload --clobber
# `install` already exists (→ tools/setup.sh); local dogfood install reuses it.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `macos-13` Intel CI runner | **`macos-15-intel`** (last x86_64 image, through Aug 2027) | Removed 2025-12-04 `[VERIFIED: actions/runner-images#13046]` | **P6-D01 label MUST change**; functionally identical native Intel build |
| `macos-12`/`macos-13` arm64 confusion | `macos-14` is **arm64-only** (clean Apple Silicon target) | macos-14 GA | P6-D01's `macos-14` Silicon choice is correct as-is |
| `git clone` to fetch repo | codeload `tar.gz` (no git dependency) | n/a (long-standing) | Smaller fetch surface; matches the installer's curl/wget+tar deps |
| `wget you/...` placeholder release base | real `castocolina` release base | this phase | Activates the dormant `download_release()` path |
| Combined `SHA256SUMS` only | per-asset `<asset>.sha256` (no cross-job join) | recommend this phase | Simpler matrix + identical to single-platform `make publish` |

**Deprecated/outdated:**
- **`macos-13` GitHub Actions runner** — removed 2025-12-04; brownouts began Nov 2025. Do not use.
- The README's current `…/tools/setup.sh | sh` one-liner is **non-working** (placeholder `you/`
  owner, `setup.sh` expects a repo checkout, `| sh` not `| bash`) — fully replaced this phase.
- The `WEZ_RELEASE_BASE` placeholder `github.com/you/wezterm-setup` in `build.sh` — repoint.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `luastatic` is installable via LuaRocks on `ubuntu-latest`, `macos-15-intel`, and `macos-14` runners | Standard Stack | CI build fails per-runner; mitigate by a real install step gated at plan time (it's the project's locked build tool, D-02, so low risk) |
| A2 | `macos-15-intel` is available on the project's GitHub Actions plan (free tier where applicable) | Pattern 6 | If the free tier excludes it, fall back to `macos-13-large`/`macos-14-large` (paid larger runners) or drop Intel to a best-effort leg — confirm with user |
| A3 | luastatic version (`[ASSUMED]` latest) — not installed on dev host at research time | Standard Stack | Version drift; planner captures the real version when CI installs it |
| A4 | The macOS `wez` arm64 binary runs after only ad-hoc codesign (no notarization) for a downloaded file | Pattern 7 | Gatekeeper/quarantine may still block on first run → Phase 7 verifies; may need documented `xattr -d com.apple.quarantine` |
| A5 | Redirecting children's stdin from `/dev/tty` revives the existing `[ -t 0 ]` interactivity under the pipe | Pattern 2 | If the seam interacts badly with `wez install-state`'s own TTY check, may need an explicit `--tty`/`WEZ_TTY` signal — verify on a real terminal at plan time |
| A6 | WezTerm's nightly rolling tag asset names are stable (`WezTerm-macos-nightly.zip`, generic Linux `.Ubuntu<base>.tar.xz`) | Open Q1 | Asset-name drift breaks fetch; bootstrap already pins the Linux name via probe-02; macOS name verified this session |

## Open Questions

1. **Cheapest "latest nightly datestamp" query (for P6-D09 newer-than-installed).**
   - What we know: `WezTerm-macos-nightly.zip` lives at the rolling `nightly` tag
     `github.com/wez/wezterm/releases/download/nightly/…` `[VERIFIED: WebSearch + homebrew cask]`.
     The Linux nightly asset is `wezterm-nightly.Ubuntu<base>.tar.xz` on the same `nightly` tag.
     The repo already has `wezterm_release_list` hitting the GitHub releases API.
   - What's unclear: the rolling `nightly` tag does NOT carry a datestamp in its *name* (it's
     literally `nightly`); the datestamp lives in the *binary's* `--version`. So "is the available
     nightly newer than installed?" needs either (a) the nightly Release's published/updated
     timestamp from the API (`/releases/tags/nightly` → `published_at`/asset `updated_at`), or
     (b) a HEAD on the asset's `last-modified`, compared to the installed binary's build date.
   - Recommendation: query `api.github.com/repos/wez/wezterm/releases/tags/nightly` for the asset
     `updated_at`, map to a date, compare against the installed binary's datestamp. Keep it
     best-effort (degrade to "offer update" or "assume current" on API failure, matching the
     existing graceful-degradation pattern in `wezterm-release.sh`). Spike this in `.tmp/` per the
     hypothesis rule before wiring.

2. **`SHA256SUMS` (combined) vs per-asset `.sha256`.**
   - What we know: `download_release()` currently fetches a combined `SHA256SUMS` and greps the
     asset line. A matrix produces assets in independent jobs.
   - What's unclear: whether to add a join job (combined file) or switch to per-asset `.sha256`.
   - Recommendation: **per-asset `.sha256`** — no cross-job coordination, identical to single-
     platform `make publish`. Requires a small `build.sh` change (`sums_url` → `<asset>.sha256`,
     parse the single line). Call it out explicitly in the plan as a deliberate contract change.

3. **First real release tag + `M.VERSION` stamping.**
   - What we know: `build.sh` pins `WEZ_RELEASE_TAG=v0.1.0`; `spec.lua` has `M.VERSION = "0.1.0"`.
   - What's unclear: the v1 tag to cut and whether CI stamps the version into the binary.
   - Recommendation: planner picks the first tag (e.g. `v1.0.0`), and the CI build stamps it
     (env → `spec.lua`/`version.lua`) so `wez version` matches the release. Low risk; decide at plan.

## Environment Availability

| Dependency | Required By | Available (dev host) | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `lua5.4` | luastatic build | ✓ | 5.4.6 | — |
| `luastatic` | shipping binary build | ✗ (dev uses source-launcher) | — | dev source-launcher for local verify; CI/`make build` installs luastatic |
| `gh` | `make publish` / CI upload | ✓ | 2.94.0 | `softprops/action-gh-release` in CI; manual upload locally |
| `sha256sum` | checksum (Linux) | ✓ | coreutils | `shasum -a 256` (macOS) |
| `shasum` | checksum (macOS path) | ✓ | present | — |
| `curl` / `wget` | fetch tarball + assets | ✓ (assumed; project requires) | — | the other of the two |
| `tar` | unpack codeload tarball | ✓ (assumed) | — | — |
| `codesign` | ad-hoc sign arm64 | ✗ on Linux (macOS-only) | — | only runs on the `darwin-aarch64` runner / Apple Silicon dev |
| `codeload.github.com` | repo tarball fetch | ✓ (HTTP 200 verified) | — | `git clone --depth 1` (needs git) |

**Missing dependencies with no fallback:** none on the install path (the user only needs
curl/wget + tar + a shell). **`luastatic`/`codesign`** are *build/publish*-side, present on the
appropriate CI runner.

**Missing dependencies with fallback:** `luastatic` (dev source-launcher locally; CI installs it);
`sha256sum` on macOS (`shasum -a 256`).

## Validation Architecture

> nyquist_validation is not disabled in config; section included.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bespoke Lua test runner — `*_test.lua` files run under `lua5.4`, co-located with source (`tools/run-tests.sh`) |
| Config file | none — discovery is convention (`find tests cli config -name '*_test.lua'`) |
| Quick run command | `./tools/run-tests.sh` (also `make test`) |
| Full suite command | `WEZTERM_INTEGRATION=1 ./tools/run-tests.sh` (adds live WezTerm tests) |

**Project test conventions (critical for testable acceptance criteria):**
- Lua units assert pure-function behavior + script TEXT (e.g. generated completion scripts).
- Shell glue is verified with `bash -n` (and `zsh -n` where relevant) for syntax + `shellcheck -x`.
- Install/uninstall paths **dogfood against a scratch HOME** (copy the real `wezterm.lua`, run the
  installer with `WEZ_BIN_DIR`/`WEZTERM_CONFIG_DIR`/`WEZTERM_SETUP_DIR`/`WEZTERM_BOOTSTRAP_PREFIX`
  overrides). The remote bootstrap should be testable the same way: scratch HOME + a local
  `file://` or a fixture tarball instead of the network.
- `lua5.4` has no `os.setenv`; env-dependent FS tests use a child `lua5.4 -e` with env set.

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INST-07 | `install.sh` is pipe-safe (function-wrapped, last-line call) + valid shell | unit (text+syntax) | `bash -n tools/install.sh` + grep the `main "$@"`-last-line shape | ❌ Wave 0 |
| INST-07 | tarball fetch unpacks to `$tmp/tools/setup.sh` (`--strip-components=1`) | integration (scratch, fixture tarball) | dogfood: tar a repo snapshot → install.sh against a `file://`/local tarball → assert setup ran | ❌ Wave 0 |
| INST-07 | temp checkout removed after run (SC#3) | integration | assert `$tmp` gone after `install.sh` exits (trap EXIT) | ❌ Wave 0 |
| INST-07 | headless run keeps D-03 abort; flags pass through | integration | `install.sh` with no `/dev/tty` + existing block → exit 3; `-s -- --force` → re-yields one block | ❌ Wave 0 (extends existing install-state tests) |
| INST-08 | asset name contract `wez-<os>-<arch>` identical local vs CI | unit | assert `tools/publish.sh` computes `wez-$(platform_os)-$(platform_arch)` | ❌ Wave 0 |
| INST-08 | `release.yml` is valid + uses `macos-15-intel` (not `macos-13`) | static (lint) | `actionlint .github/workflows/release.yml`; grep absence of `macos-13` | ❌ Wave 0 |
| INST-08 | `download_release()` verifies sha before chmod (still holds after repoint) | unit/integration | existing T-01-01 coverage + a fixture `<asset>.sha256` mismatch → abort non-zero | partial (build.sh logic exists) |
| INST-09 | `wez update` registered in spec + completes | unit | `spec_test` asserts `update` in SUBCOMMANDS + CATEGORIES; `completions` includes it | ❌ Wave 0 (extends spec_test/completions_test) |
| INST-09 | self-replace uses temp-same-dir + atomic mv (no rm-then-write) | unit (text) + integration | grep the swap glue for `mv -f` over `rm`; scratch-bin swap leaves a runnable `wez` | ❌ Wave 0 |
| INST-09 | no-op when current (clear message) | integration | `wez update` against an up-to-date scratch install → "already current", exit 0 | ❌ Wave 0 |
| INST-09 | never touches a system install (P6-D09) | unit (decision) | Lua decision returns "place user-path copy" when resolved wezterm is outside `~/.local` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `./tools/run-tests.sh` (+ `bash -n`/`shellcheck -x` on any touched script).
- **Per wave merge:** full `./tools/run-tests.sh` green + `actionlint` on the workflow.
- **Phase gate:** dogfood the remote bootstrap end-to-end against a scratch HOME (fixture tarball,
  no network) → `wez doctor` exits 0; full suite green before `/gsd-verify-work`. Real-network
  one-liner + real CI release verified manually (R2 evidence) once the first tag is cut.

### Wave 0 Gaps
- [ ] `tools/install_test.lua` (or a shell harness) — `bash -n` + function-wrap + `--strip-components` assertions (INST-07)
- [ ] Fixture-tarball dogfood harness — scratch HOME + local tarball, asserts cleanup + `wez doctor` (INST-07)
- [ ] `tools/publish.sh` + its asset-name test (INST-08)
- [ ] `actionlint` availability (install if absent) for `release.yml` linting (INST-08)
- [ ] `cli/commands/update_test.lua` — decision purity (update?/no-op/system-install-skip) (INST-09)
- [ ] Extend `spec_test`/`completions_test` to cover `update` (INST-09)
- [ ] macOS checksum branch test (`sha256sum`→`shasum -a 256`) — shareable with Phase 7

## Security Domain

> `security_enforcement` not disabled in config; section included. This phase ships a remote code
> execution surface (`curl|bash`) and a self-updating binary, so the trust model IS the security
> work (P6-D05 — formal threat model authored by the planner).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture | yes | Documented trust model: single entry point, single update path (P6-D11), D-01 glue boundary |
| V5 Input Validation | yes | Asset name built from a closed `platform_os`/`platform_arch` set, never raw input; archive member validation already in `bootstrap-wezterm.sh` (no absolute/`..`) |
| V6 Cryptography / Integrity | yes | SHA-256 verify of the `wez` asset BEFORE `chmod +x` (T-01-01, existing); xz magic+size pre-extract gate (existing). Do NOT hand-roll crypto — use `sha256sum`/`shasum -a 256` |
| V10 Malicious Code / Supply Chain | yes | Function-wrap against truncated execution; pin-to-tag/commit guidance; fetch ONLY over HTTPS from `raw.githubusercontent.com`/`github.com`/`codeload.github.com`; ad-hoc codesign the arm64 asset |
| V12 Files & Resources | yes | `mktemp -d` + `trap EXIT` cleanup; user-path only (sudo-free); never write outside `~/.local`/`~/.config`; system installs untouched (P6-D09) |
| V2/V3/V4 (auth/session/access) | no | No auth, sessions, or multi-user access surface |

### Known Threat Patterns for a curl|bash installer + self-updater

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Truncated download executes a half-command | Tampering/DoS | Function-wrap; `main "$@"` on the last line (Pattern 1) |
| MITM / server-side script swap | Tampering | HTTPS-only; inspect-before-run + pin-to-tag/commit guidance (HTTPS ≠ content authenticity — document the residual trust) |
| Wrong/malicious binary served for arch | Tampering | SHA-256 verify against published `<asset>.sha256` before chmod; closed arch set; clear no-asset error (no silent fallback) |
| Self-update corrupts the running binary | DoS/Tampering | Download-temp-same-dir + atomic `mv` (Pattern 4); never rm-then-write |
| Privilege escalation via sudo path | Elevation | Hard sudo-free invariant (P6-D03); system installs never modified (P6-D09) |
| Unsigned arm64 binary won't run / Gatekeeper | Repudiation/availability | Ad-hoc codesign in CI (Pattern 7); Phase 7 verifies quarantine handling |
| Supply-chain (compromised dependency/tag) | Tampering | Pin the release tag in `build.sh`; pin GitHub Action to a SHA; ship only from the official upstream hosts |

## Sources

### Primary (HIGH confidence)
- **Live repo files** `[VERIFIED: local]` — `tools/{setup,build,bootstrap-wezterm,run-tests}.sh`,
  `tools/lib/{platform,wezterm-release}.sh`, `Makefile`, `README.md`, `cli/spec.lua`,
  `.planning/phases/{06-installer,01-foundation}/*-CONTEXT.md`, `.planning/{REQUIREMENTS,ROADMAP,STATE}.md`,
  `.planning/MACOS-PARITY-AND-FOLLOWUPS.md` — the authoritative integration seams + locked decisions.
- **Live tool/network probes** `[VERIFIED: local]` — `gh 2.94.0`, `lua5.4 5.4.6`, `sha256sum`+`shasum`
  present, `luastatic` absent on dev host; `codeload.github.com/castocolina/wezterm-setup/tar.gz/refs/heads/main`
  → HTTP 200 `filename=wezterm-setup-main.tar.gz`; `origin = git@github.com:castocolina/wezterm-setup.git`.
- github.com/actions/runner-images#13046 — `[VERIFIED]` macos-13 removed 2025-12-04; migration to
  `macos-15-intel`/`macos-14`/`macos-15`.
- github.com/actions/runner-images#13045 + GitHub changelog 2025-09-19 — `[VERIFIED]` `macos-15-intel`
  is the last x86_64 image, supported through Aug 2027; `macos-14` is arm64-only.
- man7.org/linux/man-pages/man2/rename.2.html — `[CITED]` rename() atomicity / running-binary inode semantics.
- developer.apple.com/forums (codesign threads) — `[CITED]` ad-hoc `--sign -` semantics; quarantine/Gatekeeper.

### Secondary (MEDIUM confidence)
- macarthur.me/posts/curl-to-bash/ — `[CITED]` function-wrap partial-download protection; HTTPS≠authenticity.
- github.com/wezterm/homebrew-wezterm Casks/wezterm-nightly.rb + wezterm.org/install/macos.html —
  `[CITED]` `WezTerm-macos-nightly.zip` at the rolling `nightly` tag.
- gist.github.com/btm/6700524, joyfulbikeshedding.com (curl best practices) — `[CITED]` `-fsSL` flag rationale.

### Tertiary (LOW confidence)
- LuaRocks `luastatic` version — `[ASSUMED]`, not installed on dev host; verify per-runner at plan time.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools either present locally or already adopted (D-02); luastatic version `[ASSUMED]`.
- Architecture / integration seams: HIGH — read directly from the live, tested repo files.
- Runner labels (macos-13 correction): HIGH — verified against two upstream issues + the changelog.
- Self-replace / rename semantics: HIGH — man page + kernel-list corroboration.
- WezTerm nightly asset names: MEDIUM-HIGH — macOS name verified this session; Linux name pinned in-repo (probe-02).
- "Latest nightly datestamp" query: MEDIUM — approach is sound but unspiked (Open Q1).

**Research date:** 2026-06-14
**Valid until:** 2026-09-14 for the integration findings (stable repo); **2026-07-14 for the GitHub
Actions runner labels** (the runner-image lifecycle moves fast — re-verify `macos-15-intel`
availability and any new Intel sunset before cutting the first release).
</content>
</invoke>
