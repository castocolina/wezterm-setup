# Repro: sudo-free WezTerm emulator bootstrap (INST-06)

Promoted repro for `tools/bootstrap-wezterm.sh`. Records the manual steps and the
observed Linux evidence that the bootstrap satisfies Phase 1 success criterion #6
(D-04..D-08): detect-and-reuse an adequate WezTerm untouched, otherwise download the
generic `.tar.xz` sudo-free into `~/.local` — no AppImage, no FUSE, no sudo.

## Behavior under test

On a Linux host the bootstrap must, in order:

1. **DETECT / REUSE** — if `wezterm --version` parses to a date stamp `>=` the pinned
   minimum (`20260604-145453`), reuse it untouched and exit 0, never downloading
   (D-07 detection-first / non-destructive).
2. **SELECT** — only when missing/below-minimum: with a TTY, offer `nightly` + the
   last 5 dated releases; without a TTY, use the pinned known-good release
   `20260604-145453` (D-08).
3. **FETCH / EXTRACT / SYMLINK** — download `wezterm-<tag>.Ubuntu<base>.tar.xz`,
   integrity-check it (T-02-01), extract into a fresh per-release dir under
   `~/.local/opt/wezterm/<tag>/` (T-02-02), and symlink the in-archive binary
   `wezterm/usr/bin/wezterm` into `~/.local/bin` (T-02-03 user-path only).

## Manual repro steps

```sh
# 1. Non-interactive run (pinned selection / reuse path).
bash tools/bootstrap-wezterm.sh < /dev/null
echo "exit=$?"

# 2. Confirm the resolved emulator runs and reports its version (R2 evidence).
command -v wezterm >/dev/null && wezterm --version || "$HOME/.local/bin/wezterm" --version

# 3. Confirm the script body has no sudo / AppImage / FUSE (T-02-03; grep over
#    non-comment lines must return zero).
rg -v '^\s*#' tools/bootstrap-wezterm.sh | rg -ci 'sudo|appimage|fuse'   # expect 0
```

For a TTY run, invoke without redirecting stdin; the version selector lists `nightly`
plus the last 5 dated releases and reads a numeric pick (default 1).

## Observed evidence (Linux)

Host already had an adequate system WezTerm at the pinned minimum, so the DETECT/REUSE
branch fired — no download, system install left untouched (D-07):

```
$ bash tools/bootstrap-wezterm.sh < /dev/null
[bootstrap] existing WezTerm 'wezterm 20260604-145453-eeb80972' meets minimum 20260604-145453 — reusing it untouched (D-07)
[bootstrap] note: reused install is outside /home/user-zero/.local/bin (likely a system/managed install); leaving it intact
exit=0

$ wezterm --version
wezterm 20260604-145453-eeb80972
```

`command -v wezterm` -> `/usr/bin/wezterm` (system install, untouched). The bootstrap
made no write under `~/.local` on this run, as expected for an adequate-reuse host.

Forbidden-reference gate (T-02-03):

```
$ rg -v '^\s*#' tools/bootstrap-wezterm.sh | rg -ci 'sudo|appimage|fuse'
0
```

Static analysis is clean (`shellcheck -x tools/bootstrap-wezterm.sh` reports no
findings).

## Fetch-path coverage (probe-backed)

The fetch/extract/symlink branch is not exercised on a reuse host, but its external
shapes are pinned by the R6 probes rather than guessed:

- **Probe 01** (`.tmp/probes/phase-1/01-wezterm-tarball-layout.md`, verdict `holds`):
  the real `.tar.xz` has a single top-level `wezterm/` dir and the executable lives
  at the fixed relative path `wezterm/usr/bin/wezterm` (the symlink target). No
  absolute / `..` members -> safe to extract with `--no-absolute-names`. The xz magic
  header `fd 37 7a 58 5a 00` is the cheap pre-extract integrity sanity (T-02-01).
- **Probe 02** (`.tmp/probes/phase-1/02-wezterm-releases-api.md`): the releases API
  shape and the `.Ubuntu<base>.tar.xz` asset-name pattern that
  `wezterm_release_asset_url` builds, with graceful degradation to the pinned default
  when the API is unavailable (T-02-04).

These probe verdicts are encoded as `Why:` comments at the dependent call sites in
`tools/lib/wezterm-release.sh` and `tools/bootstrap-wezterm.sh`.

## macOS (deferred)

The `install_macos` branch is present for cross-platform shape but is DESIGN-ONLY /
deferred to the Mac pass (D-06, D-18). It is not exercised on Linux and logs that it is
skipped.

## Verdict

`holds` on Linux: the non-interactive bootstrap reuses an adequate WezTerm untouched and
the resolved `wezterm --version` exits 0. No sudo / AppImage / FUSE. The fresh-install
fetch path is probe-backed and shellcheck-clean, to be re-verified on a host without an
adequate WezTerm and in the deferred Mac pass.
