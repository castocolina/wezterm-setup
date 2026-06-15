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

One line, no `sudo`, nothing replaced — the installer fetches this repo to a temp dir,
bootstraps WezTerm sudo-free, installs the `wez` CLI, injects a single guarded block into
your `wezterm.lua`, and verifies with `wez doctor`:

```sh
curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash
```

Prefer `wget`? Same result:

```sh
wget -qO- https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh | bash
```

If a previous install already exists, or you want the WezTerm version selector, use the
process-substitution form so the prompts stay interactive (`curl … | bash` consumes stdin,
so the re-install / version prompts only appear with this form or a real terminal):

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh)
```

### Requirements

- `curl` **or** `wget`, plus `tar` (all standard on Linux + macOS)
- Linux (Wayland + X11) or macOS — every feature ships with parity on both
- No `sudo`, ever — everything lands under `~/.local` and `~/.config`

### What it does

1. Fetches this repo into a `mktemp -d` temp dir (cleaned up on exit — nothing left behind).
2. Bootstraps or reuses WezTerm **sudo-free**, targeting the rolling `nightly` by default.
   A behind-the-latest install **in your user path** is updated in place; a **system**
   WezTerm install (e.g. from `apt`) is **never touched**.
3. Downloads the matching `wez-<os>-<arch>` release binary, **SHA-256 verified before it is
   made executable**.
4. Injects a single `dofile(...)` line into your `~/.config/wezterm/wezterm.lua` between
   sentinel comments — your config is backed up (timestamped) and only added to, never replaced.
5. Places config, example scenes, and shell completions, then runs `wez doctor`.

Re-running detects the existing managed block and asks: override / restore backup / skip
(or pass `--force` / `--restore` / `--skip`).

### After installing

- Ensure `~/.local/bin` is on your `PATH` so `wez` resolves.
- Restart your shell (or `source` your rc) so the OSC 7 integration and tab-completions load.
- Run `wez doctor` to confirm a healthy install.

### Trust model

This is `curl | bash` — you are running a script fetched over the network. HTTPS guarantees the
*transport*, not that the content is what the author published. Two cheap habits make this safe:

**Inspect before you run:**

```sh
curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh -o install.sh
less install.sh        # read it — the whole body is one main(), called on the last line
bash install.sh
```

**Pin to a tag or commit instead of `main`** (so the byte you read is the byte you run):

```sh
WEZ_REF=v1.0.0 bash <(curl -fsSL https://raw.githubusercontent.com/castocolina/wezterm-setup/main/tools/install.sh)
# WEZ_REF also accepts a full commit SHA. The installer fetches the matching snapshot from
#   https://codeload.github.com/castocolina/wezterm-setup/tar.gz/refs/tags/<tag>   (tag)
#   https://codeload.github.com/castocolina/wezterm-setup/tar.gz/<sha>             (commit)
```

The downloaded `wez` binary is **SHA-256 verified before `chmod +x`** (a wrong or tampered binary
aborts the install). Pinning + inspection close the residual content-authenticity gap that HTTPS
alone leaves open.

### Local / development install

Already have the repo cloned? Run the local installer directly:

```sh
git clone https://github.com/castocolina/wezterm-setup
cd wezterm-setup
make install
```

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

Named recipe in `~/.config/wezterm/wezterm-setup/scenes/dev.toml`:

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
