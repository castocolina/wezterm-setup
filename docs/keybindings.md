# Keybindings — essential chords

These are the chords you reach for daily. All bindings use `Super` on Linux and `Cmd` on
macOS; everything else is identical across platforms. Bindings fire by the **produced
character**, so they work the same across keyboard layouts (US-ANSI, ES, …).

| Action | Linux | macOS |
|--------|-------|-------|
| Clear screen + scrollback | `Super+K` | `Cmd+K` |
| New tab | `Super+T` | `Cmd+T` |
| Close tab | `Ctrl+Shift+W` | `Ctrl+Shift+W` |
| Next tab | `Ctrl+Tab` | `Ctrl+Tab` |
| Previous tab | `Ctrl+Shift+Tab` | `Ctrl+Shift+Tab` |
| Split horizontal | `Alt+Shift+H` | `Alt+Shift+H` |
| Split vertical | `Alt+Shift+V` | `Alt+Shift+V` |
| Zoom pane (toggle) | `Alt+Shift+Z` | `Alt+Shift+Z` |
| Close pane | `Alt+Shift+X` | `Alt+Shift+X` |
| Rotate panes (clockwise) | `Alt+Shift+R` | `Alt+Shift+R` |
| Rotate panes (counter) | `Alt+Shift+E` | `Alt+Shift+E` |
| Word left / right | `Alt+←` / `Alt+→` | `Alt+←` / `Alt+→` |

> **Why `Ctrl+Shift+W` and `Ctrl+Shift+K`?** Many Linux desktops (e.g. Pop!_OS, GNOME) grab the
> Super key for window management, so close-tab and clear also ship a Ctrl+Shift variant that
> always reaches the terminal. Both chords are real and listed by `wez keys`.

This table is deliberately short. For the complete, always-current curated list — including
font zoom, tab movement, and directional pane navigation, grouped by category with any conflicts
flagged — run:

```sh
wez keys
```

`wez keys --platform linux` (or `macos`, or `all`) renders the labels for a specific platform,
and `wez keys --json` emits the same data machine-readably.
