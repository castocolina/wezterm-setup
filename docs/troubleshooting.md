# Troubleshooting

Start with the health check — it diagnoses install state and config health and points at the
exact problem:

```sh
wez doctor
```

---

## Doctor gate: "no shadowing tab-bar handler"

`wez doctor` runs a **core** gate that fails loudly (non-zero exit) when it detects a tab-bar
handler in your `wezterm.lua` that shadows the one wezterm-setup manages.

### Symptoms

When a shadowing handler is present you may see one or more of:

- a literal `<name>:` prefix (e.g. `cyan:`) printed in the tab title,
- the tab accent color never applying even though `wez tab color` reports success,
- a pane that does not open in its expected directory.

### Cause

WezTerm's `wezterm.on` **appends** handlers — there is no "replace". So an inline
`format-tab-title` registration (or a duplicate keybinding block) sitting **outside** the
wezterm-setup managed block shadows the managed tab-bar renderer, producing the symptoms above.
Duplicate keybindings that re-bind keys the managed block already owns shadow it the same way.

### Fix

Open your `wezterm.lua` and:

1. **Delete the inline `wezterm.on("format-tab-title", ...)` registration** (single- or
   double-quoted) that lives **outside** the
   `>>> wezterm-setup managed block >>>` … `<<< wezterm-setup managed block <<<` markers.
   wezterm-setup's managed block renders the tab bar — your inline handler shadows it.
2. **Remove any duplicate keybindings** that re-bind keys the managed block already manages. Keep
   your genuine personal settings; only the duplicates that shadow the managed block need to go.
3. Keep everything else (fonts, colors, personal options) untouched.

Re-run `wez doctor` to confirm the gate passes.

### Recovery

The installer wrote a timestamped backup (`wezterm.lua.bak.<timestamp>`) before injecting the
managed block, so your original `wezterm.lua` is always recoverable. A clean reinstall is also an
acceptable reset — it re-copies the managed config and writes a fresh timestamped backup first.
See [install.md](install.md) for install and uninstall details.

---

## `wez` command not found

Ensure `~/.local/bin` is on your `PATH` (that is where the CLI installs), then restart your shell
so the updated `PATH`, OSC 7 integration, and tab-completions load.
