# Plan 02-01 Summary — Opacity Spike

**Phase:** 02-pane-identity
**Plan:** 02-01 (opacity feasibility spike, hypothesis-first)
**Status:** Complete
**Requirements touched:** PANE-01 (opacity dimension, D-03/D-06)

## Goal

Decide, with evidence, whether per-pane background opacity is achievable in WezTerm before any CLI
wiring (02-03/02-04) depends on it — and lock the downstream behavior.

## Method

Driven autonomously from the agent shell (no manual hand-off needed): a GUI WezTerm instance was
spawned on the session display (`DISPLAY=:1` / `WAYLAND_DISPLAY=wayland-1`) and driven via
`wezterm cli` against its socket; API scope was confirmed against authoritative WezTerm docs
(wezterm.org, via context7). Per-pane opacity is an API-surface question — whether the mechanism
exists — so it is answered from the documented config/CLI/Lua surface, not from a pixel observation
(there is no API to render or query per-pane opacity to observe).

WezTerm version under test: **20260604-145453-eeb80972** (the project's pinned known-good build).

## Verdict

**NO — per-pane opacity is NOT achievable in WezTerm.**

| Candidate | Finding | Scope |
|-----------|---------|-------|
| `window_background_opacity` | "Sets the alpha channel for the window background" (docs) | window-level |
| `window:set_config_overrides({ window_background_opacity })` | "override configuration on a per-window basis ... options that apply to the GUI window" (docs); no pane parameter | window-level |
| Mux per-pane opacity field | `wezterm cli list --format json` pane records: **no** opacity/alpha field (empirical) | absent |
| `inactive_pane_hsb` | brightness/saturation dim of ALL inactive panes; not alpha, not per-pane-selectable | n/a |

The only opacity control is GUI-window-scoped; applying it would dim every pane and tab in the
window — the exact side effect D-03 rejects.

## Locked decision for 02-03 / 02-04 (NOT ACHIEVABLE branch, D-06)

- **`M.OPACITY_SUPPORTED = false`** in `cli/commands/pane.lua`.
- Accept opacity input (alpha in `rgba`/`#rrggbbaa`, and the `--opacity` flag) but **strip the
  alpha** before emitting OSC 11; render the pane background SOLID with the muted hex.
- On any alpha/opacity input, print once to stderr and exit `0` (soft-degrade):
  `warning: per-pane opacity is not supported by your WezTerm version — color applied without transparency`
- **OS-window-scoped opacity is permanently REJECTED** for `wez pane` (D-03) — it dims siblings.

## Artifacts

- `.tmp/h04-perpane-opacity/` (gitignored, throwaway): `HYPOTHESIS.md`, `probe.lua`, `RESULTS.md`,
  `FINDINGS.md`. Retained for the consuming plan's manual-promotion step (R5); not deleted here.
- This SUMMARY is the durable record 02-03 reads to set `M.OPACITY_SUPPORTED`.

## Verification

- C3 confirmed empirically against a live mux: no per-pane opacity field in the pane record.
- C1/C2 scope confirmed against authoritative WezTerm docs: opacity is GUI-window-level, no
  per-pane parameter exists.
- Verdict is evidence-based (docs + live CLI), not assumed.

## Notes / follow-ups

- If a future WezTerm release adds a per-pane opacity API, re-open this spike and flip
  `M.OPACITY_SUPPORTED` — the CLI already accepts the input, so only the rendering branch changes.
