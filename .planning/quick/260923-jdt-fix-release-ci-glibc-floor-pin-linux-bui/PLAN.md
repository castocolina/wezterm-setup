---
quick_id: 260923-jdt
slug: fix-release-ci-glibc-floor-pin-linux-bui
status: planned
---

# Fix release CI glibc floor: pin linux build leg to ubuntu-22.04

## Problem (validated locally, not from a CI failure)

`.github/workflows/release.yml`'s `build linux-x86_64` matrix leg runs on
`ubuntu-latest`, which currently resolves to Ubuntu 24.04 (glibc 2.39). The
`tools/build.sh` luastatic build dynamically links glibc at build time with no
floor control, so the published `wez-linux-x86_64` asset silently requires
GLIBC_2.38+.

Confirmed by downloading the real `v1.0.0` `wez-linux-x86_64` release asset and
running it via podman across target distros:

| Target | Result |
|---|---|
| debian:12 (stable) | FAIL — `GLIBC_2.38' not found` |
| debian:11 | FAIL — `GLIBC_2.38'`/`GLIBC_2.34' not found` |
| ubuntu:22.04 (LTS) | FAIL — `GLIBC_2.38' not found` |
| fedora:42 | OK |
| archlinux | OK |

CI itself stays green forever regardless, because the only verification is
running the binary on the exact same runner that built it — the floor-creep
is invisible to CI and only surfaces for a real user on a non-bleeding-edge
distro.

## Fix, already validated locally

Rebuilt the identical source (`tools/ci-setup-toolchain.sh`'s `install_linux()`
+ `tools/build.sh`) inside an `ubuntu:22.04` podman container instead of
`ubuntu:24.04`/latest (confirmed `lua5.4`/`liblua5.4-dev`/`luarocks`/`luastatic`
all install cleanly there). The resulting binary requires only GLIBC_2.34,
confirmed via the same podman cross-test matrix:

| Target | Result (ubuntu-22.04 build) |
|---|---|
| debian:12 | OK |
| ubuntu:22.04 | OK |
| fedora:42 | OK |
| archlinux | OK |
| debian:11 / ubuntu:20.04 | still FAIL (GLIBC_2.34) — explicitly out of scope per user decision; both aging/EOL-ish, and ubuntu:20.04's apt has no `lua5.4` package at all |

Confirmed via GitHub's own `actions/runner-images` repo README that
`ubuntu-22.04` is a currently valid, non-deprecated hosted runner label (both
x64 and arm64) — safe to pin explicitly.

User's stated priority order: macOS + Bazzite/Fedora critical, Debian/Ubuntu
nice-to-have, oldest releases explicitly out of scope. This fix covers
everything in scope.

## Task

Change `.github/workflows/release.yml`'s `build linux-x86_64` matrix leg's
`runs-on` from `ubuntu-latest` to `ubuntu-22.04`. Leave the two macOS legs
(`macos-15-intel`, `macos-14`) untouched — unaffected, Linux-only issue.

Check `tools/ci-setup-toolchain.sh`'s `install_linux()` and any other
release.yml step for a hardcoded `ubuntu-latest` assumption that would need the
same pin (e.g. a comment or conditional keyed off the runner name rather than
`matrix.runs-on`).

## Verify

- `grep -n "ubuntu-latest\|ubuntu-22.04" .github/workflows/release.yml` shows
  the Linux leg now reads `ubuntu-22.04`, and the two macOS legs are
  unchanged.
- YAML stays syntactically valid (`actionlint` if available, else a YAML
  parse check).
- No other file references `ubuntu-latest` in a way that assumes the Linux
  release build runner specifically (grep tools/ci-setup-toolchain.sh and
  release.yml comments).
- Do NOT re-run the actual GH Actions workflow to "prove" this — the fix was
  already validated locally via podman before this task started (rebuilding
  on ubuntu:22.04 and cross-testing the result). State this in the SUMMARY.
