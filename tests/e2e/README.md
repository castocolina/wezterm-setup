# `tests/e2e/` — WezTerm E2E Battery

End-to-end battery for the shipped `wez` CLI and the live WezTerm session,
layered into tiers by what each one needs (headless subcommands → live mux →
input injection → visual baselines).

The assertion logic is Lua (zero runtime deps, identical on macOS and Linux);
the orchestration that must shell out (`tools/run-e2e.sh`) is **bash-3.2-safe**.
Each test file prints TAP-ish `  ok   - …` / `  FAIL - …` lines and exits `0`
iff every check passed, so results aggregate uniformly the way `make test` does.

## Running

```sh
make e2e          # run the whole battery (everything available locally)
make e2e-setup    # install test-only tools + print the macOS permission steps
```

- **`WEZ_BIN` override** — `make e2e` defaults `WEZ_BIN=./dist/wez` (the in-repo
  dev launcher that execs the live `cli/` sources). CI **overrides** `WEZ_BIN` to
  point at the freshly built luastatic binary (the SAME path `tools/build.sh`
  writes locally, `dist/wez` — there is no per-platform-named build output):
  `WEZ_BIN=./dist/wez make e2e` (see `.github/workflows/ci.yml`, the live
  consumer of this convention).
- **Tier 1 targets `dist/wez` locally** so a change to `cli/` is exercised
  immediately without a rebuild.

## `make e2e` vs `make test` — the boundary

**The E2E battery runs ONLY under `make e2e`.** `make test` (`tools/run-tests.sh`)
explicitly **excludes** `*_e2e_test.lua` / `tests/e2e/` from its discovery, so the
unit suite never double-runs the battery — and never runs it against the **stale
PATH `wez`** instead of `WEZ_BIN=./dist/wez`. That stale-binary footgun is exactly
what the battery exists to catch, so keeping the two suites separate protects the
unit/battery boundary (and Plan 04's `make test exits 0` acceptance).

## Tier matrix

| Tier | Name | Needs | Class | Phase |
|------|------|-------|-------|-------|
| 1 | Subcommands | nothing (deterministic, headless) | M (must-pass) | 06.6 |
| 2 | Scenes | live mux | M | **06.7 (landed)** |
| 3 | Registration | live mux | M | **06.7 (landed)** |
| 3 | Firing | OS input injection (`WEZ_E2E_INPUT=1`) | B (best-effort, self-skip) | **06.9 (landed)** |
| 4 | Visuals | screenshot + vision (`WEZ_E2E_VISUAL=1`) | B (best-effort, self-skip) | 06.9 |

`M` = must-pass (gates CI — wired in `.github/workflows/ci.yml`, 06.8). `B` = best-effort: self-skips
**loudly and logged** when its dependency (mux / input tool / permission) is
absent — never a silent pass, never a hang. On a host that DOES have the
dependency, a skip is a **failure** (the gate prints a `LIVE-ASSERTED` marker).

Linux Firing uses a forced-XWayland (`enable_wayland = false`) `--class`-tagged
window that loads the real product config, then `xdotool windowactivate` /
`getactivewindow` focus-verify before AND after every `xdotool key` — see
`tests/e2e/lib/gui.lua`. ydotool is never used for firing: it has no
window-targeting concept on Wayland.

### Tier 2 mux gate

Tier 2 (and Tier 3) need a **live headless multiplexer**. Each case spins a
**FRESH, isolated** `wezterm-mux-server` under a scratch `HOME` /
`XDG_RUNTIME_DIR` / `XDG_CONFIG_HOME` / `WEZTERM_CONFIG_FILE` (so the mux socket
lives in a throwaway dir and the user's **real running WezTerm GUI session is
never touched**), drives the launcher against it, then tears it down (kill +
`rm -rf`) even on assertion failure. The whole tier **self-skips loudly** via
`skip.require_tool` when no `wezterm-mux-server` is resolvable — it is looked up
on `PATH` first, then as a **sibling next to the resolved `wezterm` binary** (the
nightly bundle ships `wezterm-mux-server` beside `wezterm` but off `PATH`). On a
host that DOES resolve a mux, the gate prints `LIVE-ASSERTED` and a skip becomes a
failure.

## Layout

| Path | Role |
|------|------|
| `tests/e2e/lib/harness.lua` | shared TAP-ish helpers (`check` / `run_capture` / `run_capture_all` / `shquote` / `scratch_dir` / `footer` / `WEZ`; optional `M.new()` instance) |
| `tests/e2e/lib/skip.lua` | self-skip gate (`require_env` / `require_tool` / `soft_skip`) |
| `tests/e2e/lib/mux.lua` | headless `wezterm-mux-server` lifecycle helper (`probe` / `spin` / `poll_until` / `cli_list` / `get_text` / `send_marker` / `spawn_pane` / `split_pane` / `teardown`) — the shared Tier 2 foundation |
| `tests/e2e/platform.lua` | platform-expectations table (single source of legitimate Mac↔Linux deltas) |
| `tests/e2e/tier1/*_e2e_test.lua` | Tier 1 subcommand contracts (Plan 02/03) |
| `tests/e2e/tier2/*_e2e_test.lua` | Tier 2 live-mux scene drivers — reuse + new-tab mode (06.7); `scene_motd_race_e2e_test.lua` is the scene-launch-motd-race regression (a slow-starting `bash --rcfile` pane, driving the readiness-gate fix) |
| `tests/e2e/tier3/*_e2e_test.lua` | Tier 3 live-mux registration contracts (06.7) |

## Per-platform tools / permissions (Firing landed in 06.9 — Screenshot: see 06.9-04)

Tier 1 needs none of these. Input-injection and OS-permission rows are filled
for the landed Firing path; Screenshot stays Plan 04.

| Concern | macOS | Linux |
|---------|-------|-------|
| Input injection | `cliclick` | `xdotool` (firing, forced-XWayland windows only; `enable_wayland = false`) + `ydotool`/`ydotoold` (provisioned by `make e2e-setup` for completeness/future compositor coverage per D-08, but **not** the mechanism Tier 3 Firing fires through today — ydotool has no Wayland window-targeting, which is why xdotool+forced-XWayland is used instead) |
| Screenshot | _TBD (06.9-04)_ | _TBD (06.9-04)_ |
| OS permission | Accessibility + Screen Recording grant, documented manual step (D-09) | `/dev/uinput` access via `make e2e-setup`: systemd-udev uaccess ACL check first, allowlisted group + udev-rule second (never an unsafe root-group grant, D-08); honest re-login-required report when a fresh grant is needed. No manual permission dialog on Linux. |

## Manual visual-baseline approval flow (placeholder — 06.9)

Tier 4 visual baselines require a one-time **manual approval** of each new/changed
baseline before it gates. The approval flow (capture → human review → commit the
approved baseline) is defined in **06.9**; this section is a placeholder until then.
