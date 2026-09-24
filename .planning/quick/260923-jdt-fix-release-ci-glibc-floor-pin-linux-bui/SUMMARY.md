---
quick_id: 260923-jdt
slug: fix-release-ci-glibc-floor-pin-linux-bui
status: complete
commit: c7b79a8a447aa16c67109d1e2402b9d9871f1fa2
---

# Fix release CI glibc floor: pin linux build leg to ubuntu-22.04 -- Summary

## What changed

`.github/workflows/release.yml`'s `build linux-x86_64` matrix leg's `runs-on`
was changed from `ubuntu-latest` (currently resolves to Ubuntu 24.04, glibc
2.39) to `ubuntu-22.04` (glibc 2.34), per the problem/fix already validated
locally in PLAN.md.

Files touched:

1. **`.github/workflows/release.yml`**
   - `runs-on: ubuntu-latest` -> `runs-on: ubuntu-22.04` for the
     `build linux-x86_64` matrix entry, with an inline comment explaining the
     glibc-floor rationale. The two macOS legs (`macos-15-intel`, `macos-14`)
     are untouched.
   - **Bug found and fixed (Rule 1 -- directly caused by this change):** the
     "Prune old nightly releases (D-06)" step's leg-identity guard was
     `if: matrix.runs-on == 'ubuntu-latest' && ...`. Left as-is, this literal
     string comparison would have silently stopped matching once the matrix
     value became `ubuntu-22.04` -- meaning the prune step would never run on
     any leg again (functionally deleting the old-nightlies retention logic
     without any error or CI failure). Updated to
     `matrix.runs-on == 'ubuntu-22.04'`.
   - Updated two stale comments that named `ubuntu-latest` for consistency
     (the leg summary in the job header comment, and the prune step's
     "Leg-scoped to ubuntu-latest ONLY" comment).

2. **`tools/ci-setup-toolchain.sh`**
   - `install_linux()`'s leading comment named `ubuntu-latest` specifically.
     Updated to describe the runner generically and note it is pinned to
     `ubuntu-22.04` for the release build leg (cross-referencing
     `release.yml`), for consistency. No functional change -- apt/sudo
     provisioning behavior is identical on both runner labels.

No other file was touched. `.github/workflows/ci.yml` and
`tools/ci-install-wezterm-runtime-deps.sh` also reference `ubuntu-latest`,
but those govern the unrelated test/e2e CI workflow, not the release build
runner this task's problem statement is scoped to -- left alone per the
plan's explicit scope (release.yml's Linux build leg + anything hardcoding
that same runner assumption).

## Verify (real output)

```
$ grep -n "ubuntu-latest\|ubuntu-22.04" .github/workflows/release.yml
49:  # place, so this is a real 3-leg strategy.matrix: ubuntu-22.04 (linux-x86_64,
61:            # Pinned to ubuntu-22.04 (NOT ubuntu-latest/24.04): building on
66:            # already OK either way). ubuntu-22.04 is a currently valid,
68:            runs-on: ubuntu-22.04
225:      # Leg-scoped to ubuntu-22.04 ONLY (D-08 / D-12): this is a global action
232:        if: ${{ matrix.runs-on == 'ubuntu-22.04' && env.CHANNEL == 'nightly' && steps.nightly_guard.outputs.unchanged != 'true' }}
```

Linux leg reads `ubuntu-22.04`; the two macOS legs (`macos-15-intel`,
`macos-14`) are unchanged (confirmed via `yq '.jobs.build.strategy.matrix.include'`
below).

```
$ yq '.jobs.build.strategy.matrix.include' .github/workflows/release.yml
- name: build linux-x86_64
  ...
  runs-on: ubuntu-22.04
- name: build macos-x86_64
  runs-on: macos-15-intel
- name: build macos-aarch64
  runs-on: macos-14
```

YAML validity -- `actionlint` (found at `/var/home/bazzite/go/bin/actionlint`,
not on PATH by default) run against the file:

```
$ /var/home/bazzite/go/bin/actionlint .github/workflows/release.yml
(no output, exit=0)
```

`yq eval '.'` on the file also parsed cleanly ("YAML valid per yq").
`bash -n tools/ci-setup-toolchain.sh` confirmed the shell script's syntax is
still valid after the comment edit.

Grep for other `ubuntu-latest` references tied to this same release build
runner:

```
$ grep -n "ubuntu-latest" tools/ci-setup-toolchain.sh
(none -- the only prior reference, in install_linux()'s comment, was updated)
```

No remaining `ubuntu-latest` string in `release.yml` refers to the actual
runner selection -- the sole remaining occurrence (`.github/workflows/release.yml:61`)
is inside the new explanatory comment itself ("Pinned to ubuntu-22.04 (NOT
ubuntu-latest/24.04)..."), which is intentional prose, not a stale
assumption.

**Live CI validation was intentionally NOT run.** Per the plan's explicit
instruction, this task did not trigger an actual GitHub Actions workflow run
to "prove" the fix. The substance of the fix (does building on ubuntu-22.04
actually produce a binary with a lower/more-portable glibc floor) was
already fully validated locally by the orchestrator before this task was
created, via podman: the real v1.0.0 `wez-linux-x86_64` asset was downloaded
and cross-tested against debian:12, debian:11, ubuntu:22.04, fedora:42, and
archlinux (only the ubuntu-24.04-built asset failed on debian/ubuntu
targets); then the identical source was rebuilt inside an `ubuntu:22.04`
podman container and the resulting binary was re-tested against the same
matrix, passing on debian:12, ubuntu:22.04, fedora:42, and archlinux (only
debian:11/ubuntu:20.04 -- explicitly out of scope -- still failed). This
task was scoped to the mechanical YAML/comment edit reflecting that
already-validated fix, plus the leg-identity bug it would otherwise have
introduced.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `matrix.runs-on == 'ubuntu-latest'` leg-identity guard would break silently**
- **Found during:** applying the `runs-on` pin itself.
- **Issue:** the "Prune old nightly releases (D-06)" step gates on
  `matrix.runs-on == 'ubuntu-latest'` to scope a global action (release
  pruning) to exactly one matrix leg. Once the Linux leg's `runs-on` value
  changed to `ubuntu-22.04`, this literal string comparison would never
  match again on any leg -- silently disabling nightly pruning with no
  error, no CI failure, and no visible symptom until old nightly releases
  piled up unbounded.
- **Fix:** updated the condition to `matrix.runs-on == 'ubuntu-22.04'`, kept
  in sync with the new `runs-on` value.
- **Files modified:** `.github/workflows/release.yml`
- **Commit:** c7b79a8

**2. [Rule 2 - Consistency, plan-directed] Stale `ubuntu-latest` comments**
- **Found during:** the plan's explicit instruction to check for other
  hardcoded `ubuntu-latest` assumptions/comments.
- **Issue:** two comments in `release.yml` (job header leg summary, prune
  step's "Leg-scoped to ubuntu-latest ONLY" note) and one comment in
  `tools/ci-setup-toolchain.sh` (`install_linux()`'s leading comment) still
  named `ubuntu-latest` after the pin, which would read as incorrect/stale
  documentation of the actual runner in use.
- **Fix:** updated all three comments to name `ubuntu-22.04` / describe the
  pin, with a cross-reference from `ci-setup-toolchain.sh` to `release.yml`.
- **Files modified:** `.github/workflows/release.yml`, `tools/ci-setup-toolchain.sh`
- **Commit:** c7b79a8

## Self-Check

- FOUND: `.github/workflows/release.yml` contains `runs-on: ubuntu-22.04` for the Linux leg
- FOUND: commit `c7b79a8a447aa16c67109d1e2402b9d9871f1fa2` on branch `worktree-agent-ab305d889467f12dc`
- FOUND: `actionlint` exit code 0 against the modified file
- FOUND: `yq` structural check confirms exactly 3 matrix legs with the expected `runs-on` values

## Self-Check: PASSED
