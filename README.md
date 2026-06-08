# wezterm-setup

A WezTerm config distribution and companion CLI (`wez`) that ships daily-friction fixes,
rich visual identity at the pane and tab level, and a named workspace launcher — all installed
non-destructively via a single injected line. Built for a solo developer on Linux and macOS
daily-driving WezTerm as a full multiplexer.

---

## What it delivers

| Feature | Command |
|---------|---------|
| Tab accent color | `wez tab color green` |
| Tab accent + title in one shot | `wez tab color navy --title "infra"` |
| Per-pane background color | `wez pane color purple` |
| Per-pane custom title | `wez pane title "🔥 build"` |
| Ad-hoc scene (N styled panes + layout) | `wez scene new --layout tall --panes 2` |
| Named workspace launch | `wez scene launch dev` |
| Install health check | `wez doctor` |
| Keybinding introspection | `wez keys` |

**10 named color profiles:** `red` `orange` `yellow` `green` `teal` `cyan` `blue` `navy` `purple` `pink`

Tab color persists when the active pane switches within the tab. Pane-level color takes
priority over tab-level color when both are set.

---

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/you/wezterm-setup/main/tools/setup.sh | sh
```

Or clone and run locally:

```sh
git clone https://github.com/you/wezterm-setup
cd wezterm-setup
make install
```

What `install` does:
1. Injects a single `dofile(...)` line in your `~/.config/wezterm/wezterm.lua` between
   sentinel comments — nothing else is touched.
2. Creates a timestamped backup of your original config.
3. Installs the `wez` CLI to `~/.local/bin/wez`.

Re-running install detects the existing block and asks: override / restore backup / skip.

### Uninstall

```sh
make uninstall                # remove everything
make uninstall KEEP_CONFIG=1  # keep ~/.config/wezterm/wezterm-setup/, remove CLI
make uninstall KEEP_CLI=1     # keep wez binary, remove config block
make uninstall KEEP_BACKUP=1  # keep wezterm.lua.bak.*, remove the rest
```

---

## Keybindings

All bindings use `Super` on Linux and `Cmd` on macOS.

| Action | Linux | macOS |
|--------|-------|-------|
| Clear screen + scrollback | `Super+K` | `Cmd+K` |
| Split horizontal | `Alt+Shift+\` | `Alt+Shift+\` |
| Split vertical | `Alt+-` | `Alt+-` |
| Zoom pane | `Ctrl+Shift+Z` | `Ctrl+Shift+Z` |
| Close pane | `Ctrl+Shift+W` | `Ctrl+Shift+W` |
| Next tab | `Ctrl+Tab` | `Ctrl+Tab` |
| Previous tab | `Ctrl+Shift+Tab` | `Ctrl+Shift+Tab` |
| Word left / right | `Alt+←` / `Alt+→` | `Alt+←` / `Alt+→` |

`wez keys` lists all active bindings grouped by category and flags conflicts.

---

## Scenes

Ad-hoc scene (open and forget):

```sh
wez scene new --layout tall --panes 2 --color navy --title "deploy"
```

Named recipe in `~/.config/wezterm-setup/scenes/dev.toml`:

```toml
layout = "tall"
color  = "green"
title  = "dev"

[[panes]]
command = "nvim ."

[[panes]]
command = "lazygit"
```

Launch it:

```sh
wez scene launch dev
```

Scene names tab-complete in zsh and bash. The installer seeds example scenes
(`ai`, `docker`, `dev`) using copy-if-absent — your edits survive reinstall.

---

## Status

> **Pre-release — nothing is installable yet.**

| Phase | Scope | Status |
|-------|-------|--------|
| 0 — Spikes | CLI language decision, CWD mechanism, remote control surface | In progress |
| 1 — Foundation | Install, keybindings, `wez doctor`, `wez keys` | Pending |
| 2 — Pane identity | `wez pane color / title` | Pending |
| 3 — Tab identity | `wez tab color / title` | Pending |
| 4 — Scenes | `wez scene new`, layouts | Pending |
| 5 — Named scenes | Recipe files, `wez scene launch`, tab-complete | Pending |

See [.planning/ROADMAP.md](.planning/ROADMAP.md) for full phase detail.

---

## Development

Every shipped behavior starts as a hypothesis in `.tmp/h<NN>-<slug>/` — a repro doc,
a run script that drives a real WezTerm session, and the actual output captured on the
last green run. Promotion to `config/` only happens after the run script passes on both
Linux and macOS. See [docs/agent-iteration.md](docs/agent-iteration.md) for the full loop.

```sh
make doctor   # health check
make test     # run test suite (WEZTERM_INTEGRATION=1 for live tests)
make clean    # wipe .tmp/ scratch
```

---

## Why not a WezTerm plugin?

WezTerm doesn't have a plugin system in the traditional sense. This is a config
*distribution* — a Lua file tree you opt into via one `dofile()` line. You keep full
control of your `wezterm.lua`; we only add to it, never replace it.

## Platform

Linux (Wayland + X11) and macOS. Every feature ships with parity on both platforms.
`sudo` is never required.
