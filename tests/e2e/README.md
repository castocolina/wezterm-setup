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
  point at the freshly built luastatic binary:
  `WEZ_BIN=./dist/wez-linux-x86_64 make e2e`.
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
| 1 | Subcommands | nothing (deterministic, headless) | M (must-pass) | **06.6 (this phase)** |
| 2 | Scenes | live mux | M | 06.7 |
| 3 | Registration | live mux | M | 06.7 |
| 3 | Firing | OS input injection (`WEZ_E2E_INPUT=1`) | B (best-effort, self-skip) | 06.9 |
| 4 | Visuals | screenshot + vision (`WEZ_E2E_VISUAL=1`) | B (best-effort, self-skip) | 06.9 |

`M` = must-pass (gates CI once 06.8 lands). `B` = best-effort: self-skips
**loudly and logged** when its dependency (mux / input tool / permission) is
absent — never a silent pass, never a hang. On a host that DOES have the
dependency, a skip is a **failure** (the gate prints a `LIVE-ASSERTED` marker).

## Layout

| Path | Role |
|------|------|
| `tests/e2e/lib/harness.lua` | shared TAP-ish helpers (`check` / `run_capture` / `run_capture_all` / `shquote` / `scratch_dir` / `footer` / `WEZ`; optional `M.new()` instance) |
| `tests/e2e/lib/skip.lua` | self-skip gate (`require_env` / `require_tool` / `soft_skip`) |
| `tests/e2e/platform.lua` | platform-expectations table (single source of legitimate Mac↔Linux deltas) |
| `tests/e2e/tier1/*_e2e_test.lua` | Tier 1 subcommand contracts (Plan 02/03) |

## Per-platform tools / permissions (placeholder — wired in 06.9)

Tier 1 needs none of these. Filled in when Tier 3 (firing) / Tier 4 (visuals)
land in **06.9**.

| Concern | macOS | Linux |
|---------|-------|-------|
| Input injection | `cliclick` | `xdotool` (X11) / `ydotool` (Wayland) |
| Screenshot | _TBD (06.9)_ | _TBD (06.9)_ |
| OS permission | Accessibility + Screen Recording grant | _TBD (06.9)_ |

## Manual visual-baseline approval flow (placeholder — 06.9)

Tier 4 visual baselines require a one-time **manual approval** of each new/changed
baseline before it gates. The approval flow (capture → human review → commit the
approved baseline) is defined in **06.9**; this section is a placeholder until then.
