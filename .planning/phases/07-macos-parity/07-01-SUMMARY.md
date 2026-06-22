---
phase: 07-macos-parity
plan: 01
subsystem: build-toolchain-and-harness
tags: [macos, toolchain, luastatic, bash-3.2, harness-portability, sudo-free]
requires:
  - "stock macOS bash 3.2 + BSD userland (no extra installs)"
  - "Homebrew on PATH; Xcode Command Line Tools present"
provides:
  - "tools/setup-dev.sh — sudo-free macOS dev compile-toolchain (lua@5.4 keg + luarocks + --local luastatic)"
  - "make setup target"
  - "bash-3.2-safe tools/run-tests.sh (mapfile removed)"
  - "tools/build.sh macOS keg-only cflags/liblua fallback (real Mach-O dist/wez on macOS)"
  - "tests/cli/setup_dev_test.lua auto-discovered unit gate"
affects:
  - "all later Phase 7 waves (Wave 0 unblock: harness runnable + binary buildable on Intel Mac)"
tech-stack:
  added:
    - "Homebrew lua@5.4 (5.4.8, keg-only)"
    - "luarocks 3.13.0"
    - "luastatic 0.0.12 (installed --local into ~/.luarocks)"
  patterns:
    - "detect-then-instruct (Xcode CLT) — never auto-sudo"
    - "bash-3.2-safe while IFS= read -r array fill (no mapfile)"
    - "branch-on-availability keg-only header/lib resolution (not OS hard-coding)"
key-files:
  created:
    - tools/setup-dev.sh
    - tests/cli/setup_dev_test.lua
  modified:
    - tools/run-tests.sh
    - Makefile
    - tools/build.sh
decisions:
  - "luastatic installed via `luarocks install --local` (sudo-free ~/.luarocks), not the system tree"
  - "build.sh resolves lua@5.4 keg cflags/liblua directly when pkg-config is absent or keg-only .pc is off-path"
metrics:
  duration: ~25min
  completed: 2026-06-22
  tasks: 2
  files: 5
requirements: [DIAG-05, SCEN-03, SCEN-04, SCEN-05, SCEN-06]
---

# Phase 7 Plan 01: Wave-0 Toolchain + Harness Portability Summary

Closed the Wave-0 gaps that blocked every other Phase 7 step on this Intel Mac: stock bash 3.2.57 had no `mapfile` (suite couldn't run) and there was no lua5.4/luastatic (CLI couldn't build). Both are now fixed and live-verified on the real machine.

## What shipped

**Task 1 — `tools/run-tests.sh` bash-3.2-safe (commit `d58f9b0`):**
Replaced the bash-4-only `mapfile -t ALL_TESTS < <(...)` with the repo's bash-3.2-safe `ALL_TESTS=(); while IFS= read -r f; do ALL_TESTS+=("$f"); done < <(...)` idiom (same shape as the existing `SHELL_SCRIPTS` loop). `tools/build.sh`'s remote-path checksum was already correctly guarded by `command -v sha256sum … else shasum -a 256` (line 393-397) — verified, no change needed.

**Task 2 — sudo-free macOS dev toolchain (commit `4fdfc9b`):**
- `tools/setup-dev.sh`: detect-then-instruct Xcode CLT (`xcode-select -p`; on absence, instruct `xcode-select --install`, never auto-sudo); `brew install lua@5.4` (keg-only) + `luarocks`; `luarocks install --local luastatic`; export `$(brew --prefix lua@5.4)/bin` + `~/.luarocks/bin` onto PATH (and `$GITHUB_PATH` when set); fail-loud assert if `lua5.4`/`luastatic` absent; sourcing guard for unit testing. Linux delegates to `ci-setup-toolchain.sh`.
- `Makefile`: new `setup` target + help line.
- `tests/cli/setup_dev_test.lua`: 18 TEXT + sourced-no-run behavior assertions, including the bare-`brew install lua` (Lua 5.5) regression guard and the sudo-free invariant.
- `tools/build.sh`: macOS keg-only fallback in `build_with_luastatic` — resolves cflags/liblua from the lua@5.4 keg prefix when present (branch-on-availability).

## Verification (real Intel Mac, bash 3.2.57)

- `make setup` completes sudo-free; `lua5.4 -v` = `Lua 5.4.8`; `luastatic` at `~/.luarocks/bin/luastatic`.
- `make build` takes the luastatic path (`luastatic toolchain present -> static single-binary build`) and produces a runnable `dist/wez` = **Mach-O 64-bit x86_64** (NOT the dev launcher); `./dist/wez version` → `wez 0.1.0` (exit 0); build.sh smoke OK.
- `/bin/bash tools/run-tests.sh` → **all 29 files passed** (exit 0), including the new `setup_dev_test.lua` (18/18).
- `bash -n` clean on `tools/setup-dev.sh`, `tools/run-tests.sh`, `tools/build.sh`.
- Source gates: `grep -c mapfile run-tests.sh`=0; `grep -c lua@5.4 setup-dev.sh`=7 (≥2); no non-comment bare `brew install lua`; no non-comment `sudo`; `brew --prefix lua@5.4`, `GITHUB_PATH`, `xcode-select` all present; Makefile `setup` target present.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `luarocks install luastatic` is not sudo-free**
- **Found during:** Task 2, first live `make setup` run.
- **Issue:** A bare `luarocks install luastatic` targets the system rocks tree (`/usr/local`), which is not writable without sudo → `make setup` failed with `requires exclusive write access to /usr/local`. This violates the sudo-free invariant (D-08).
- **Fix:** Switched to `luarocks install --local luastatic` (installs into `~/.luarocks`, mirroring `ci-setup-toolchain.sh`'s Linux `--local` leg) and prepend `~/.luarocks/bin` to PATH (+ `$GITHUB_PATH`). Updated the test assertion to match the `--local` form and added a `~/.luarocks/bin` PATH assertion.
- **Files modified:** tools/setup-dev.sh, tests/cli/setup_dev_test.lua
- **Commit:** 4fdfc9b

**2. [Rule 1 - Bug] build.sh links the wrong Lua (5.5) on macOS keg-only**
- **Found during:** Task 2 END-STATE verify (`make build`).
- **Issue:** `pkg-config` is absent on this Mac (and lua@5.4's `.pc` is keg-only / off the default path), so build.sh's Debian-oriented probes fell back to `-I/usr/include/lua5.4` (nonexistent on macOS) and matched `/usr/local/lib/liblua.a` → the bare `lua` **5.5** formula. Result: `fatal error: 'lauxlib.h' file not found`, build aborted. This is exactly the keg-only header/lib resolution that PATTERNS §lua@5.4 (line 110) and Pitfall 2 anticipated.
- **Fix:** Added a macOS keg-only fallback in `build_with_luastatic`: when `platform_os`=macos and the lua@5.4 keg's `include/lua5.4/lauxlib.h` + `lib/liblua.a` exist, set `lua_cflags="-I${keg}/include/lua5.4"` and `liblua="${keg}/lib/liblua.a"`. Branch on availability, not OS hard-coding (D-08 discretion); the Linux/Debian path is untouched.
- **Files modified:** tools/build.sh
- **Commit:** 4fdfc9b
- **Note:** The plan listed `tools/build.sh` under `files_modified` only for the sha256 sweep (which turned out to be a no-op — already guarded). This keg fallback is an additional in-scope fix to the same file, required to satisfy Task 2's END-STATE criterion ("`bash tools/build.sh` … produces a runnable `dist/wez`").

### Latent-bug guard outcome

The plan's anti-pattern target (`brew install lua` = Lua 5.5) is correctly avoided: `setup-dev.sh` only ever installs `lua@5.4`. The bare `lua` 5.5 formula DID get pulled in transitively as `luarocks`'s own runtime dependency (Homebrew installs it + unlinks the keg-only lua@5.4 symlinks) — this is harmless because lua@5.4 stays in the Cellar and we add its keg bin to PATH explicitly; documented inline in `install_macos`. The build.sh keg fallback (deviation #2) ensures the build never links that transitive 5.5 lib.

## Authentication / Setup Gates

None required at runtime. Xcode CLT was already present (`/Library/Developer/CommandLineTools`); the detect-then-instruct branch was not triggered. No sudo, no interactive prompt.

## Known Stubs

None. All shipped behavior is wired and live-verified.

## Self-Check: PASSED

- tools/setup-dev.sh — FOUND
- tests/cli/setup_dev_test.lua — FOUND
- tools/run-tests.sh — FOUND (modified)
- Makefile — FOUND (modified, `setup` target present)
- tools/build.sh — FOUND (modified, keg fallback present)
- Commit d58f9b0 — FOUND (Task 1)
- Commit 4fdfc9b — FOUND (Task 2)
