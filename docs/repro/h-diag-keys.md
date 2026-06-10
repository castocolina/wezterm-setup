# Repro: `wez keys` — grouped 3-way keybinding classification (DIAG-02/03/04)

Promoted repro for `cli/commands/keys.lua` + `cli/lib/showkeys.lua`. Records the
observed Linux evidence (R2) that `wez keys` satisfies Phase 1 success criterion #4
(the `wez keys` half): it lists every active binding grouped by category, performs a
real 3-way classification (wezterm-setup / WezTerm-default / user-defined) against the
live effective table, flags conflicts/who-wins (D-13/D-14), and supports `--json`.

## Behavior under test

`wez keys` must, in order:

1. **Gather** the live EFFECTIVE key table via `wezterm show-keys --lua`, the
   NO-CONFIG BASELINE via `wezterm -n show-keys --lua`, and OUR declared set from the
   installed `~/.config/wezterm/wezterm-setup/keybindings.lua` (D-13).
2. **Classify** every effective binding (D-14): `setup` = ours ∩ baseline ∩ effective;
   `default` = baseline ∩ effective, not ours; `user` = effective only; `conflict` =
   any of OUR bindings absent from effective (overridden) or same key+mods → different
   action.
3. **Group** bindings into named categories (Tabs, Panes, Navigation, Font, Other).
4. **Render** a human grouped table by default, or a jq-valid JSON document with
   `--json` (DIAG-04).

`copy_mode` / `search_mode` modal bindings are excluded from the parse (D-13).

## Manual repro steps

```sh
# 0. Build the bundle AFTER adding the new modules (the bundle only contains
#    modules present at build time).
bash tools/build.sh

# 1. Grouped table output (DIAG-02): bindings grouped by category, each labeled
#    setup/default/user with a conflict marker.
./dist/wez keys

# 2. Machine-readable output (DIAG-04): must be valid JSON parseable by jq.
./dist/wez keys --json | jq .
```

> Requires a running WezTerm session (for `wezterm show-keys --lua`). For full
> setup-vs-default divergence the config must be installed first (Plan 04). On an
> un-installed host every live binding classifies as `default`/`user`, which is the
> correct, truthful result (see note below).

## Observed Linux evidence (R2)

Host: Linux, `wezterm 20260604-145453-eeb80972`. Bundle built via the dev
source-launcher path of `tools/build.sh` (no luastatic toolchain on this host).

### `./dist/wez keys` (grouped table)

```
== Tabs ==
  CTRL+Tab           [default] act.ActivateTabRelative(1)
  SHIFT|CTRL+Tab     [default] act.ActivateTabRelative(-1)
  SUPER+1            [default] act.ActivateTab(0)
  ...
== Panes ==
  ALT|CTRL+"         [default] act.SplitVertical{ domain =  'CurrentPaneDomain' }
  ...
== Navigation ==
  CTRL+LeftArrow     [default] act.ActivatePaneDirection 'Left'
  ...
== Font ==
  SUPER+-            [default] act.DecreaseFontSize
  ...
```

`./dist/wez keys | rg -c 'Tabs|Panes|Navigation'` → **3** (the three category
headers are present).

Label distribution on this (un-installed) host: **132 `[default]` + 4 `[user]`**, 0
`[setup]` — expected, because our config is not installed, so the live effective table
equals the WezTerm baseline (e.g. `k SUPER` resolves to the default
`ClearScrollback 'ScrollbackOnly'`, not our `ClearScreenAndScrollback`). When the
config is installed (Plan 04) and a session reloads, the matching bindings flip to
`[setup]`. The classification is therefore TRUTHFUL against ground truth, not a static
guess (DIAG-03 / D-14).

### `./dist/wez keys --json | jq .` (jq-valid)

`./dist/wez keys --json | jq .` exits 0 (json valid). Document shape:

```json
{
  "bindings": [
    {
      "category": "Tabs",
      "bindings": [
        { "key": "Tab", "mods": "CTRL", "action": "act.ActivateTabRelative(1)", "label": "default" }
      ]
    }
  ],
  "conflicts": []
}
```

`jq 'keys'` → `["bindings", "conflicts"]`; `jq '[.bindings[].category]'` →
`["Tabs","Panes","Navigation","Font","Other"]`; `jq '.conflicts | length'` → `0`
(no overridden-ours conflicts on the un-installed host, as expected).

When the keybindings file is absent, `wez keys` prints a clean stderr hint
(`keybindings.lua not found at … run the installer (install-state) first.`) and still
emits the (default/user) classification — it never crashes on the missing install.

## Autonomous gate vs. manual gate

- **Autonomous** (`lua5.4 tests/cli/keys_test.lua`, run by `tools/run-tests.sh`): the
  parser record count + copy_mode/search_mode exclusion + all four D-14 classification
  cases + the `--json` dkjson round-trip, all fixture-driven (no live session). 21/21
  assertions pass.
- **Manual / integration** (the two commands above): require a running WezTerm session
  and, for `[setup]` labels, an installed config (Plan 04). Captured here on Linux
  (D-18); macOS re-verification deferred to the batched Mac pass.

## Verdict

**HOLDS.** `wez keys` groups every active binding by category, labels each
setup/default/user from the live effective table vs the baseline vs our keybindings
(D-13/D-14), flags overridden-ours conflicts, and emits jq-valid JSON with `--json`.
Verified on Linux.
