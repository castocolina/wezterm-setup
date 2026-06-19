# `wez` CLI guide

A task-oriented tour of the `wez` companion CLI. This page covers the common workflows and the
flags that matter; it is **not** an exhaustive flag list. Every command accepts `--help`, and
shell tab-completion knows every subcommand, flag, and value — those are the exhaustive
reference:

```sh
wez pane --help
wez scene new --help
```

Color, title, and icon are **three independent attributes**. Setting one never overwrites the
others, and an icon is never baked into a title string.

---

## `wez pane` — pane identity

Style the current pane: a background color, a title, and an icon, each on its own.

```sh
wez pane color purple          # background tint + tab accent contribution
wez pane color "#1b9e77"       # hex; #rrggbb or #rrggbbaa (alpha) also accepted
wez pane color reset           # clear the pane color

wez pane title api             # set the pane/tab title text
wez pane icon python           # set the pane icon as its own attribute
wez pane title api --icon python   # title + icon in one call
```

The `--icon` value is an icon name (e.g. `node`, `python`) or any literal glyph. To clear the
icon, run `wez pane icon reset`.

---

## `wez tab` — tab identity

The tab mirrors the pane surface: `color`, `title`, `icon`, each independent.

```sh
wez tab color navy                       # tab accent color
wez tab color navy --title infra         # accent + title together
wez tab title api --icon node            # title + icon together
wez tab icon node                        # icon on its own

wez tab color blue --follow-pane-color   # opt in: a colorless tab tracks its active pane
```

`--follow-pane-color` is opt-in and off by default. When a tab has **no** explicit color, it then
tracks its active pane's color; with an explicit tab color set, the tab color wins.

When both a pane color and a tab color are set, the pane color takes priority.

---

## `wez scene` — multi-pane scenes

Build a styled, multi-pane tab ad-hoc, or launch a saved recipe by name. The full TOML field
reference lives in [scenes.md](scenes.md).

```sh
wez scene new --layout tall --pane shell --pane shell --color navy --title deploy
wez scene launch dev            # launch a saved recipe (tab-completes)
```

`wez seed-scenes` copies the example recipes into your scenes dir (copy-if-absent, so your edits
survive).

---

## `wez doctor` — health check

Diagnoses install state and config health, including the "no shadowing tab-bar handler" gate. If
it reports a problem, see [troubleshooting.md](troubleshooting.md).

```sh
wez doctor
```

---

## `wez keys` — keybinding introspection

Lists the active keybindings, grouped by category, with conflicts flagged. This is the
always-current source of truth — see [keybindings.md](keybindings.md) for the short essential
table.

```sh
wez keys                        # curated list for the host OS
wez keys --platform linux       # render labels for a specific platform (linux | macos | all)
wez keys --json                 # machine-readable output
```

---

## `wez update` — self-update

Updates the `wez` binary, the managed config, and WezTerm (to a newer nightly when one exists).

```sh
wez update
```

See [install.md](install.md) for install channels and how updates relate to `WEZ_CHANNEL`.

---

## `wez uninstall` — remove everything

The front door for removal — works even from a binary-only install with no repo checkout. It
confirms before removing on a terminal and requires `--yes` when run from a non-interactive pipe.

```sh
wez uninstall                                   # confirm, then remove block + config + binary + backups
wez uninstall --yes                             # skip the prompt (required on a non-TTY pipe)
wez uninstall --keep-config                     # keep ~/.config/wezterm/wezterm-setup/
wez uninstall --keep-cli                        # keep the wez binary
wez uninstall --keep-backup                     # keep wezterm.lua.bak.* backups
```

The `--keep-*` flags combine. See [install.md](install.md) for the `make uninstall` equivalents.
