# Contributing to wezterm-setup

This is the contributor-facing guide. For using the tool, start at the
[README](README.md) and the focused pages under [`docs/`](docs/).

## The hypothesis-first loop

Every shipped behavior starts as a **hypothesis** in `.tmp/h<NN>-<slug>/` (gitignored) —
a repro doc, a run script that drives a *real* WezTerm session, and the actual output
captured on the last green run. Code only lands in `config/`, `cli/`, or `tests/` after
that run script passes against a live session. Promotion is a manual rewrite, never a
copy or symlink, and the experiment directory is deleted afterward.

The full operating manual — R1…Rn, the promotion ritual, and the probe-before-assume
rules — lives in [docs/agent-iteration.md](docs/agent-iteration.md). Read it before
opening a plan or picking up the next item from
[.planning/REQUIREMENTS.md](.planning/REQUIREMENTS.md).

## Make targets

```sh
make doctor   # run wez doctor health check
make test     # run the full test suite (set WEZTERM_INTEGRATION=1 for live GUI tests)
make clean    # wipe .tmp/ scratch
make install  # local/development install from a cloned repo
```

`make test` is the verification backbone: it discovers every co-located `*_test.lua`
under `tests/`, including the documentation drift-check that asserts every documented
command/flag/keybinding/scene-field exists in source. Keep it green.

## Working agreements

- **Verify before declaring done.** A behavior is ready only when its verifying command
  (e.g. `wez doctor` exiting 0) is captured with its output — "should work" / "looks
  right" is not evidence.
- **Commit discipline — group by logical work unit.** Granular commits are fine while
  working, but before closing a phase or session, compact them into cohesive logical
  units (typically one commit per plan / self-contained change-set) — neither a trail of
  WIP commits nor one monolithic phase commit. Amend to fold in closely related follow-ups.
- **English only.** All content — code, comments, docs, commit messages — is written in
  English, regardless of the language a discussion happens in.

See [CLAUDE.md](CLAUDE.md) for the complete agent/contributor rule set.
