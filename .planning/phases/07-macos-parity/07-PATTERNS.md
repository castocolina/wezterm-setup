# Phase 7: macOS Parity Pass (D-18) - Pattern Map

**Mapped:** 2026-06-20
**Files analyzed:** 9 (7 modified, 0 net-new source, 2 new tests)
**Analogs found:** 9 / 9 (every change has an in-repo analog — Phase 7 is wiring existing primitives into a macOS branch, not net-new architecture)

> **Key insight (carried from RESEARCH):** there is essentially **no net-new pattern** here. Every gap closes by mirroring an existing function in the same file or a sibling tool. The planner should treat each row below as "copy the cited analog, swap the OS/asset specifics."

## File Classification

| New/Modified File / Symbol | Role | Data Flow | Closest Analog | Match Quality |
|----------------------------|------|-----------|----------------|---------------|
| `install_macos()` in `tools/bootstrap-wezterm.sh` | bootstrap glue | file-I/O (fetch→unzip→place) | `install_linux()` same file (lines 403-466) | exact (sibling, same entry, OS-switched body) |
| `wezterm_macos_asset_url()` in `tools/lib/wezterm-release.sh` | utility | transform (tag→URL) | `wezterm_release_asset_url()` same file (lines 137-142) | exact |
| macOS asset name in `latest_nightly_datestamp()` | utility | transform | existing `macos) asset_name=...` branch (bootstrap-wezterm.sh:107) | exact (branch already present) |
| build-time codesign in `tools/build.sh` | build glue | transform (sign in place) | `publish.sh` arm64 codesign (lines 54-59) | exact (lift + widen) |
| `sha256sum`→`shasum` on build.sh remote path | build glue | transform | `build.sh` `download_release()` already branches (lines 393-397); `publish.sh:65-68` | exact (idiom already in repo) |
| `mapfile`→bash-3.2 loop in `tools/run-tests.sh` (line 50) | test harness | batch (array fill) | `while IFS= read -r` loops same file (lines 70-76, 93-95); `build.sh:137-138` | exact |
| `ci-setup-toolchain.sh` `install_macos()` lua@5.4 fix (lines 61-66) | CI glue | request-response (provision) | `install_linux()` same file (lines 41-59) + `assert_and_capture()` gate (70-94) | role-match (apt vs brew keg-only) |
| macOS legs in `.github/workflows/release.yml` (re-introduce matrix) | config (CI) | event-driven (tag/cron) | the existing single `build` job (lines 51-229) | exact (was a 3-leg matrix; restore it) |
| conditional `xattr` strip in `tools/install.sh` (D-07, only-if-blocked) | installer glue | file-I/O | `install.sh` `/dev/tty` usable-probe idiom (lines 123-130); BSD-aware notes | partial (verify-then-decide; may be no-op) |
| `tests/cli/bootstrap_macos_test.lua` (NEW) | test | transform (pure url/path) | `tests/cli/bootstrap_update_test.lua` (sourced no-run + TEXT asserts) | exact |
| `codesign --verify` assertion (build + CI evidence) | test/smoke | transform | `verify-macos.sh` env-probe block (lines 48-60); build.sh smoke (465-471) | role-match |

## Pattern Assignments

### `install_macos()` — `tools/bootstrap-wezterm.sh` (bootstrap glue, file-I/O)

**Analog:** `install_linux()` in the **same file**, lines 403-466. The current `install_macos()` (lines 474-480) is the **design-only stub to replace**. The `main()` dispatch already routes `macos) install_macos "${tag}"` (line 496) — no caller change needed.

**Mirror these load-bearing pieces of `install_linux`:**
- **mktemp + RETURN-trap cleanup** (lines 411-413):
  ```bash
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmpdir}'" RETURN
  ```
- **fetch via the shared helper** (`fetch_to`, lines 339-349 — DO NOT add a new fetcher): `fetch_to "${url}" "${archive}" || return 1`
- **integrity gate BEFORE extract** — `install_linux` calls `verify_tarxz` + `assert_safe_members` (lines 421-423). For the `.zip`, mirror the *spirit*: non-empty/size floor + PK magic (`504b0304`) check (model on `verify_tarxz`, lines 304-325) and reject `..`/absolute members before copying `WezTerm.app` (model on `assert_safe_members`, lines 329-336). This satisfies the Security Domain "`.zip` path-traversal" mitigation.
- **fresh dir + rm -rf then place** (lines 425-428): `rm -rf "${app_dir}/WezTerm.app"; cp -R .../WezTerm.app "${app_dir}/WezTerm.app"`. Use `ditto -x -k "${zip}" "${unzipped}"` (Apple-native, preserves bundle attrs) for extraction; fall back to `unzip` only if absent.
- **run-the-binary evidence** (lines 455-460 — exit code is the proof): `"${app_dir}/WezTerm.app/Contents/MacOS/wezterm" --version >/dev/null 2>&1`.
- **D-05 version selection:** reuse `resolve_want_datestamp()` (lines 139-147) + `select_release()` (lines 250-297) exactly as the Linux path does — both OSes track the same nightly contract.
- **D-07:** do NOT pre-strip quarantine inside `install_macos`.
- Target dir is `${HOME}/Applications` (user-path, never `/Applications`, never sudo).

### `wezterm_macos_asset_url()` — `tools/lib/wezterm-release.sh` (utility, transform)

**Analog:** `wezterm_release_asset_url()` in the **same file**, lines 137-142:
```bash
wezterm_release_asset_url() {
  local tag="${1:?...}" base="${2:?...}"
  printf '%s/%s/releases/download/%s/wezterm-%s.Ubuntu%s.tar.xz\n' \
    "${WEZTERM_RELEASE_HOST}" "${WEZTERM_RELEASE_REPO}" "$tag" "$tag" "$base"
}
```
New helper mirrors the shape, official-host HTTPS only (`${WEZTERM_RELEASE_HOST}`/`${WEZTERM_RELEASE_REPO}` = `wez/wezterm`), emitting the macOS `.zip` asset name. **Open Q2 / A3:** confirm the exact dated-tag asset filename against the wez/wezterm releases API before finalizing — the design-only string today is `WezTerm-macos-nightly.zip` (referenced at bootstrap-wezterm.sh:107).

### build-time ad-hoc codesign — `tools/build.sh` (build glue, transform)

**Analog:** `tools/publish.sh` lines 54-59 (the existing arm64-only codesign):
```bash
if [ "${os}" = "macos" ] && [ "${arch}" = "aarch64" ]; then
  log "macOS arm64 -> ad-hoc codesign dist/wez"
  codesign --force --sign - "${REPO_ROOT}/dist/wez"
fi
```
**D-06 change:** widen to BOTH macOS arches (sign x86_64 too — harmless, uniform) and add it to `build.sh` so CI and `make publish` both produce signed assets (same-contract rule). Add `codesign --verify --verbose dist/wez` as the **evidence line** right after signing. **Pitfall 4 / Anti-pattern:** do NOT gate on `spctl --assess` — ad-hoc signatures are always rejected by `spctl`; that rejection is expected. Place the signing in `build_with_luastatic()` (after line 156 `chmod +x`) guarded by `[ "$(platform_os)" = macos ]`.

### `sha256sum`→`shasum` portability — `tools/build.sh` (build glue, transform)

**Already solved idiom — replicate it, don't invent.** `build.sh` `download_release()` lines 393-397 and `publish.sh` lines 65-68 already do:
```bash
if command -v sha256sum >/dev/null 2>&1; then
  got="$(sha256sum "${tmp}" | awk '{print $1}')"
else
  got="$(shasum -a 256 "${tmp}" | awk '{print $1}')"
fi
```
Any remaining bare `sha256sum` on a macOS-reachable path uses this `command -v` branch (D-08, Claude's-discretion: branch on availability, not OS). `release.yml` lines 138-142 already carry the same branch.

### `mapfile`→bash-3.2 loop — `tools/run-tests.sh` (test harness, batch)

**Replace line 50** (`mapfile -t ALL_TESTS < <(...)` — bash 4+, breaks on stock macOS bash 3.2.57).
**Analog: the same file already uses the safe idiom** at lines 70-76 and 93-95:
```bash
SHELL_SCRIPTS=()
while IFS= read -r s; do
  [ -f "$s" ] && SHELL_SCRIPTS+=("$s")
done < <(find tools -maxdepth 1 -type f -name '*.sh' | sort)
```
Apply identically to `ALL_TESTS`:
```bash
ALL_TESTS=()
while IFS= read -r f; do ALL_TESTS+=("$f"); done \
  < <(find "${TEST_ROOTS[@]}" -type f -name '*_test.lua' | sort)
```
(Claude's discretion: inline vs shared helper — the repo inlines this idiom three times already, so inline is consistent.) NOTE: `release.yml:210` also uses `mapfile` but runs Linux-only — harmless; consider for uniformity only.

### `ci-setup-toolchain.sh` `install_macos()` lua@5.4 fix (CI glue, request-response)

**Analog:** `install_linux()` in the **same file**, lines 41-59 (apt provision + `--local` PATH persistence + `$GITHUB_PATH` echo), and the `assert_and_capture()` gate, lines 70-94 (fail-loud if `lua5.4`/`luastatic` absent).
**The latent bug (Pitfall 1):** current `install_macos()` (lines 61-66) runs `brew install lua` → Homebrew `lua` is now **5.5**. Fix:
```bash
brew install lua@5.4 luarocks
luarocks install luastatic
PREFIX="$(brew --prefix lua@5.4)"          # keg-only: NOT on PATH
export PATH="${PREFIX}/bin:${PATH}"        # provides lua5.4 for have_luastatic()
[ -n "${GITHUB_PATH:-}" ] && printf '%s\n' "${PREFIX}/bin" >> "${GITHUB_PATH}"
```
Keep the existing `assert_and_capture()` gate unchanged — it already fails loud if `lua5.4` is missing (Pitfall 1/2 warning signs). Pass `${PREFIX}/lib/liblua5.4.a -I${PREFIX}/include/lua5.4` to the link step if `build.sh`'s pkg-config probe (lines 109-128) can't find keg-only headers — verify on the macOS leg.

### macOS legs in `.github/workflows/release.yml` (config, event-driven)

**Analog:** the existing single `build` job, lines 51-229 (every step: checkout → resolve-channel → nightly-guard → ci-setup-toolchain → build.sh → name+checksum → ensure-release → upload → prune).
**Change:** re-introduce `strategy.matrix` over the three runners (the comment at lines 45-50 documents that this was a 3-leg matrix collapsed to Linux-only, deferred here):
- `ubuntu-latest` → `linux-x86_64`
- `macos-15-intel` → `darwin-x86_64` (Pitfall 7: NEVER `macos-13` — removed 2025-12-04)
- `macos-14` → `darwin-aarch64`

Keep prune as its **own factored step** (lines 204-228) so the matrix wraps build/publish without touching prune (the comment at line 203 explicitly anticipates this). On the `macos-14` (arm64) leg, add a free in-build smoke: `codesign --verify dist/wez` + `./dist/wez version` (the runner IS arm64) — captures arm64 evidence via `gh run watch` without local Silicon (Open Q3 recommendation). Asset names stay `wez-macos-<arch>` (platform_os returns `macos`; matrix `os` field only selects runners — see comment lines 129-132).

### conditional `xattr` strip — `tools/install.sh` (installer glue, file-I/O) — D-07, MAY BE NO-OP

**Analog:** the usable-tty open-probe idiom at lines 123-130 (`{ : < /dev/tty; } 2>/dev/null` — verify-then-act, don't assume).
**D-07 is verify-then-decide:** do NOT add an unconditional `xattr -dr com.apple.quarantine` (Pitfall 5 / Anti-pattern). On the Mac, probe `xattr -p com.apple.quarantine ~/.local/bin/wez`; only IF present AND Gatekeeper blocks, add a guarded strip and document why. Otherwise the runbook keeps the manual `xattr -d` / right-click-open fallback note. **The default outcome is no code change to install.sh.**

### `tests/cli/bootstrap_macos_test.lua` (NEW test, transform) — Wave 0

**Analog:** `tests/cli/bootstrap_update_test.lua` (read lines 1-55). The pattern:
- Resolve `repo_root` from `arg[0]` (lines 23-24).
- `read_file` the target `.sh` once (lines 40-47), assert on TEXT substrings via `has()` (lines 48-50).
- For behavior, **source the script no-run** (the `BASH_SOURCE/$0` guard at bootstrap-wezterm.sh:508-510 means sourcing does NOT run `main`) and assert exit-code behavior of the pure functions.
Test the NEW `install_macos`/`wezterm_macos_asset_url` **url/path logic only** (pure, headless — no live download), mirroring how `bootstrap_update_test` exercises `wezterm_install_is_user_path` / `resolve_want_datestamp`. Register nothing — `run-tests.sh` auto-discovers `*_test.lua` under `tests/`. Siblings worth glancing at for shape: `tests/cli/build_channel_test.lua`, `tests/cli/publish_test.lua`, `tests/cli/install_sh_test.lua`.

## Shared Patterns

### Sourcing guard (testability + partial-stream safety)
**Source:** every `tools/*.sh` — e.g. bootstrap-wezterm.sh:508-510, build.sh:477-479, publish.sh:80-82, ci-setup-toolchain.sh:112-114.
**Apply to:** every script touched. Keep `if [ "${BASH_SOURCE[0]}" = "${0}" ]; then main "$@"; fi` so unit tests can source + exercise functions without running.
```bash
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
```

### Shared curl-or-wget fetcher (NEVER add a third)
**Source:** `fetch_to` (bootstrap-wezterm.sh:339-349), `_wezterm_fetch` (wezterm-release.sh:39-48), `_api_fetch` (build.sh:165-174).
**Apply to:** `install_macos`'s zip download — reuse `fetch_to`, do not write a new downloader.

### Portable SHA-256 branch
**Source:** build.sh:393-397, publish.sh:65-68, release.yml:138-142.
**Apply to:** any macOS-reachable checksum site. `command -v sha256sum` → else `shasum -a 256`.

### Run-the-binary evidence (exit code is the proof — CLAUDE.md "verify before declaring done")
**Source:** install_linux (bootstrap-wezterm.sh:455-460), build.sh smoke (465-471).
**Apply to:** `install_macos` (`wezterm --version`), codesign (`codesign --verify`), CI arm64 leg (`./dist/wez version`). No "should work on macOS."

### Stdout = value, stderr = logs (picker/resolver contract)
**Source:** select_release (bootstrap-wezterm.sh:250-297), resolve_channel_tag (build.sh:249-334).
**Apply to:** `wezterm_macos_asset_url` and any new resolver — keep stdout the bare value.

### User-path-only, sudo-free invariant (project rule)
**Source:** PREFIX/BIN_DIR under `${HOME}` (bootstrap-wezterm.sh:62-64); `wezterm_install_is_user_path` gate (158-168).
**Apply to:** `install_macos` → `${HOME}/Applications` only. Never `/Applications`, never `hdiutil`/DMG (locked out by D-05), never sudo.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | — | — | Every Phase 7 change maps to an existing in-repo analog. The only MEDIUM-confidence unknowns are *external facts* (exact WezTerm macOS asset filename — Open Q2/A3; whether curl downloads carry quarantine — D-07/A4), resolved empirically on the Mac, not new code patterns. |

## Metadata

**Analog search scope:** `tools/`, `tools/lib/`, `.github/workflows/`, `tests/cli/`, `Makefile`, phase CONTEXT/RESEARCH.
**Files scanned (read in full or targeted):** bootstrap-wezterm.sh, build.sh, publish.sh, run-tests.sh, ci-setup-toolchain.sh, release.yml, lib/wezterm-release.sh, setup.sh (cp/quarantine region), verify-macos.sh (head), install.sh (grep), Makefile, bootstrap_update_test.lua.
**Pattern extraction date:** 2026-06-20
