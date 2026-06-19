# wezterm-setup

A WezTerm config distribution and companion CLI (`wez`) that ships daily-friction fixes,
rich visual identity at the pane and tab level, and a named workspace launcher — installed
non-destructively via a single injected line. Built for a solo developer daily-driving
WezTerm as a full multiplexer on Linux (Wayland + X11) and macOS, with parity on both and
no `sudo`, ever.

## Quickstart

One line, nothing replaced — it bootstraps WezTerm sudo-free, installs the `wez` CLI,
injects a single guarded block into your `wezterm.lua` (backing up the original), then
verifies the result:

```sh
curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash
wez doctor   # confirm a healthy install
```

This is `curl | bash` — see [docs/install.md](docs/install.md) for the full trust model
(inspect-before-run, pin via `WEZ_REF`, SHA-256-before-`chmod`), the `WEZ_CHANNEL`
version selector (`nightly` / `stable` / `<vX.Y.Z>`), `wez update`, and `wez uninstall`.

## What it delivers

Color, title, and **icon** are three independent attributes — setting one never overwrites
the others, and an icon is never baked into a title.

| Feature | Command | Guide |
|---------|---------|-------|
| Tab accent color (+ optional title) | `wez tab color navy --title infra` | [cli.md](docs/cli.md) |
| Per-pane background color | `wez pane color purple` | [cli.md](docs/cli.md) |
| Pane title + icon as own attributes | `wez pane title api --icon python` | [cli.md](docs/cli.md) |
| Ad-hoc multi-pane scene | `wez scene new --layout tall --pane shell --pane shell` | [scenes.md](docs/scenes.md) |
| Named workspace launch | `wez scene launch dev` | [scenes.md](docs/scenes.md) |
| Install health check | `wez doctor` | [troubleshooting.md](docs/troubleshooting.md) |
| Keybinding introspection | `wez keys` | [keybindings.md](docs/keybindings.md) |

**10 named color profiles:** `red` `orange` `yellow` `green` `teal` `cyan` `blue` `navy`
`purple` `pink`. The standalone color commands also take hex (`#rrggbb` / `#rrggbbaa` with
alpha). A pane color takes priority over its tab's color; a colorless tab can track its
active pane with `--follow-pane-color`. Scenes add per-pane `cwd`, `focus`, and `size`, and
a tab-level `follow_pane_color` — the full TOML reference is in [scenes.md](docs/scenes.md).

## Essential keybindings

`Super` on Linux, `Cmd` on macOS; everything else is identical, and bindings fire by the
produced character so they survive keyboard-layout changes.

| Action | Chord |
|--------|-------|
| Clear screen + scrollback | `Super+K` (also `Ctrl+Shift+K`) |
| Close tab | `Ctrl+Shift+W` |
| Next / previous tab | `Ctrl+Tab` / `Ctrl+Shift+Tab` |
| Split horizontal / vertical | `Alt+Shift+H` / `Alt+Shift+V` |
| Zoom / close pane | `Alt+Shift+Z` / `Alt+Shift+X` |
| Rotate panes (clockwise / counter) | `Alt+Shift+R` / `Alt+Shift+E` |

WezTerm's scrollback search overlay is kept as-is. Run `wez keys` for the complete,
always-current curated list (the trustworthy source of truth) — see
[keybindings.md](docs/keybindings.md) for the short table and the per-platform / `--json`
options.

## Documentation

- [docs/install.md](docs/install.md) — install, channels, trust model, update, uninstall
- [docs/cli.md](docs/cli.md) — the `wez` CLI guide (pane, tab, scene, doctor, keys, update)
- [docs/scenes.md](docs/scenes.md) — full scene TOML field reference + worked recipes
- [docs/keybindings.md](docs/keybindings.md) — essential chords + `wez keys`
- [docs/troubleshooting.md](docs/troubleshooting.md) — `wez doctor` gates and fixes
- [CONTRIBUTING.md](CONTRIBUTING.md) — the hypothesis-first dev loop and make targets

## Why not a WezTerm plugin?

WezTerm has no traditional plugin system. This is a config *distribution* — a Lua file tree
you opt into via one `dofile()` line. You keep full control of your `wezterm.lua`; we only
add to it between sentinel comments, never replace it.
