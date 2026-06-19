# Scenes — full TOML reference

A **scene** is a layout plus a set of styled panes, opened in a single tab. You build one
two ways:

- **Ad-hoc**, from the command line: `wez scene new --layout tall --pane shell --pane shell`
- **Saved recipe**, a TOML file under `~/.config/wezterm/wezterm-setup/scenes/<name>.toml`,
  launched by name: `wez scene launch dev`

A recipe and the equivalent `wez scene new` invocation describe the same thing — this page is
the complete field reference for both. The installer seeds a few example recipes
(`wez seed-scenes`, copy-if-absent), and recipe names tab-complete in bash and zsh.

---

## Tab-level fields

These sit at the top of a recipe (before any `[[panes]]` table) and apply to the whole tab.
On the command line they map to `wez scene new` flags.

| Field | Recipe key | CLI flag | Meaning / accepted values |
|-------|-----------|----------|---------------------------|
| Layout | `layout` | `--layout` | **Required.** One of `tall`, `tall:mirrored`, `grid`, `horizontal` (see *Layouts* below). |
| Tab color | `color` | `--color` | Tab accent color. One of the 10 named profiles (see *Colors*). Scene colors are **names only** — hex is not accepted here. |
| Tab title | `title` | `--title` | Tab title text. |
| Tab icon | `icon` | — | Tab icon, set as its own attribute (an icon name like `node`/`python`, or a literal glyph). Not baked into the title. |
| Default cwd | `cwd` | `--cwd` | Default working directory every pane inherits unless it sets its own `cwd` (see *The cwd grammar*). |
| Follow pane color | `follow_pane_color` | — | `true` makes a **colorless** tab track its active pane's color. Default **off** (omit, or `false`). When a tab color is set, this has no effect. |

---

## Pane fields (`[[panes]]`)

Each `[[panes]]` table is one pane, created in declaration order according to the layout.

| Field | Recipe key | Meaning / accepted values |
|-------|-----------|---------------------------|
| Command | `command` (alias `cmd`) | The command to run in the pane. Special value `shell` (or omit the field) for a plain interactive shell — see below. |
| Pane color | `color` | Pane background tint + tab accent contribution. One of the 10 named profiles. |
| Pane title | `title` | Pane / tab title text for this pane. |
| Pane icon | `icon` | Pane icon as its own attribute (name or glyph), not baked into the title. |
| Working dir | `cwd` | This pane's working directory (overrides the tab-level default; same grammar). |
| Focus | `focus` | `true` selects this pane as the active one on spawn. At most one pane may set it. |
| Size | `size` | Split size as an integer percent `1`–`100` for this pane's split step. |

### The plain-shell pane

A pane with no command is a plain interactive shell — nothing is sent to it. Three equivalent
forms:

- Omit `command` entirely in a `[[panes]]` table.
- Set `command = "shell"`.
- On the command line, the bare spec `--pane shell`.

This is the form the seeded scenes use for a working shell pane. A shell pane may still carry
styling (`color`, `cwd`, `focus`, `size`) — e.g. a teal-tinted working shell — and the styling
is applied without sending any command.

---

## Layouts

The four layouts, exactly as the tool defines them:

| Layout | Shape |
|--------|-------|
| `tall` | One main pane on the left, the rest stacked on the right. |
| `tall:mirrored` | `tall` with the main pane on the **right**. |
| `grid` | An even grid (`ceil(sqrt(n))` columns, row-major). |
| `horizontal` | Equal-width columns, left to right. |

On the command line: `wez scene new --layout grid --pane shell --pane shell --pane shell`.

---

## Colors

Scene `color` accepts these 10 named profiles (and only these — names, not hex, in scenes):

`red` · `orange` · `yellow` · `green` · `teal` · `cyan` · `blue` · `navy` · `purple` · `pink`

### Hex and `#RRGGBBAA` alpha (standalone color commands)

The standalone `wez pane color` / `wez tab color` commands accept a named profile **or** hex
(`#rgb`, `#rrggbb`, `#rrggbbaa`). The 8-digit `#RRGGBBAA` form carries an alpha channel that is
preserved end to end; the alpha only renders visibly when the window has transparency enabled.
Scene panes are names-only by design (each named profile maps to a precomputed muted background
tint), so use the named profiles inside recipes.

---

## The cwd grammar

`cwd` (tab-level default or per-pane) accepts:

| Form | Meaning |
|------|---------|
| `/abs/path` | A literal absolute path. |
| `~` or `~/sub` | Home directory (and a subpath under it). |
| `$ENV` / `$HOME/sub` | An environment variable reference, expanded at launch. |
| relative (e.g. `src`, `..`) | Relative to the launch directory — `.` is the launch dir, `..` its parent. |

Shell command substitution (`$(...)`) is **not** supported — `cwd` is a path, not a shell
expression.

> **v1 grammar limit:** a field value must not contain a `,` (the pane-spec segment separator).
> Recipe loading rejects a comma-bearing value with a clear error.

---

## Worked examples

### `dev` — editor + git, tall layout

```toml
layout = "tall"
color  = "green"
title  = "dev"

[[panes]]
command = "nvim ."
focus   = true

[[panes]]
command = "lazygit"
```

### `docker` — a working shell + a live stats pane

```toml
layout = "tall"
title  = "docker"

[[panes]]
command = "shell"
color   = "teal"
cwd     = "~/work/services"

[[panes]]
command = "docker stats"
title   = "stats"
icon    = "docker"
size    = 40
```

Launch either by name:

```sh
wez scene launch dev
wez scene launch docker
```

Or build the same shape ad-hoc without saving a file:

```sh
wez scene new --layout tall --color green --title dev --pane "cmd=nvim ., focus=true" --pane lazygit
```

See [cli.md](cli.md) for the full `wez scene` command guide and [keybindings.md](keybindings.md)
for the pane/tab chords you'll use inside a scene.
