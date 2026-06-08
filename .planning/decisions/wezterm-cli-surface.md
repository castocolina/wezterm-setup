# Reference: `wezterm cli` command surface (audited)

**WezTerm version:** `20260604-145453-eeb80972`
**Audited:** 2026-06-07 on Linux (Pop!_OS 24.04). **macOS column pending the batched Mac pass**
(D-04/D-05). Full raw `--help` capture: `.tmp/probes/phase-0/05-wezterm-cli-help-surface.md` (gitignored).

This is the durable catalogue (ROADMAP Phase 0 Success Criterion 3 — full sweep). Bounded by what
`wezterm cli --help` enumerates. Every later phase issues `wezterm cli` calls; this is the shared reference.

## Global options
`--no-auto-start` · `--prefer-mux` (connect to background mux vs gui) · `--class <CLASS>` (match a
`--class`-launched gui) · `-h/--help`.

## Subcommands

| Subcommand | Purpose | Key flags / args | Linux | macOS |
|---|---|---|:---:|:---:|
| `list` | list windows/tabs/panes | `--format json\|table` | ✓ | pending |
| `list-clients` | list connected clients | `--format` | ✓ | pending |
| `proxy` | start rpc proxy pipe | — | ✓ | pending |
| `tlscreds` | obtain TLS credentials | — | ✓ | pending |
| `move-pane-to-new-tab` | move a pane into a new tab | `--pane-id`, `--window-id`, `--new-window` | ✓ | pending |
| `split-pane` | split a pane (prints new pane-id) | `--pane-id`, `--left/right/top/bottom/horizontal`, `--top-level`, `--cells`, `--percent`, `--cwd`, `--move-pane-id`, `-- PROG` | ✓ | pending |
| `spawn` | spawn into new window/tab (prints new pane-id) | `--pane-id`, `--window-id`, `--new-window`, `--cwd`, `--workspace`, `--domain-name`, `-- PROG` | ✓ | pending |
| `send-text` | send text to a pane (as paste) | `--pane-id`, `--no-paste`, `[TEXT]` | ✓ | pending |
| `get-text` | read a pane's textual content | `--pane-id`, `--start-line`, `--end-line`, `--escapes` | ✓ | pending |
| `activate-pane-direction` | focus adjacent pane | `--pane-id`, `<DIRECTION>` | ✓ | pending |
| `get-pane-direction` | resolve adjacent pane id | `--pane-id`, `<DIRECTION>` | ✓ | pending |
| `kill-pane` | kill a pane | `--pane-id` | ✓ | pending |
| `activate-pane` | focus a pane | `--pane-id` | ✓ | pending |
| `adjust-pane-size` | resize a pane directionally | `--pane-id`, `--amount`, `<DIRECTION>` | ✓ | pending |
| `activate-tab` | activate a tab | `--tab-id`, `--tab-index`, `--pane-id`, `--no-wrap` | ✓ | pending |
| `set-tab-title` | set a tab's title | `--tab-id`, `--pane-id`, `<TITLE>` | ✓ | pending |
| `set-window-title` | set a window's title | `--window-id`, `--pane-id`, `<TITLE>` | ✓ | pending |
| `rename-workspace` | rename a workspace | `--workspace`, `--pane-id`, `<NEW_NAME>` | ✓ | pending |
| `zoom-pane` | zoom/unzoom/toggle a pane | `--pane-id`, `--zoom/--unzoom/--toggle` | ✓ | pending |

## Known gaps & workarounds

- **`set-user-var` does NOT exist as a CLI subcommand.** (Confirmed — not in the surface above.)
  Pane-level user vars (e.g. `WEZTERM_TAB_COLOR` for per-pane color) must be set via the **OSC 1337
  `SetUserVar` escape sequence** written to the pane's TTY, not via `wezterm cli`. This is the proven
  path already in PROJECT.md. Any phase needing per-pane user vars uses the OSC escape.
- **No direct "set tab color" command.** Tab accent color is encoded in the **tab title prefix**
  (`"color:title"`) via `set-tab-title` — see `tab-title-format.md`. There is no dedicated color API.
- **cwd inheritance** is WezTerm-default on `split-pane`/`spawn` (no `--cwd` needed); `--cwd` is an
  override. See `cwd-mechanism.md`.

## How this was driven
Audited against an isolated headless `wezterm-mux-server` (`XDG_RUNTIME_DIR=/tmp/wez-spike`), no GUI,
no sudo — the same technique usable in CI for the macOS pass.
