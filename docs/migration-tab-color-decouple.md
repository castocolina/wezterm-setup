# Migration: tab color decoupled from tab title

Phase 6.1 stops encoding the tab's accent color inside the tab **title** string and moves it onto a
dedicated user var. This note tells you exactly what to remove from a hand-edited (prototype)
`wezterm.lua` so the managed tab bar renders correctly. It is intentionally short — this is a solo
daily-driver setup, not a mass-market product, so **a clean reinstall is always an acceptable reset**
(see "The reset option" below).

## What changed

- **Before:** `wez tab color <name>` wrote a combined `"<color>:<title>"` value through
  `set-tab-title`. The tab bar then split that string on the first `:` to recover the color
  (`parse_stored` / `merge_title`).
- **After:** tab color rides the **`WEZTERM_TAB_COLOR`** user var — the same OSC 1337 `SetUserVar`
  channel panes already use (D-02 / D-03 / D-04). The tab **title** is now pure text via
  `set-tab-title`, and `format-tab-title` reads the accent from the **active pane's**
  `WEZTERM_TAB_COLOR` user var (active pane wins). The legacy `"<color>:<title>"` prefix is read
  once for migration and then dropped from the steady-state path.

## The symptom

You may see one or more of:

- a literal **`cyan:`** (or any `<name>:`) prefix printed in the tab title,
- the tab **accent color never applies** even though `wez tab color` reports success,
- a pane that does not open in its expected directory (no `cwd`).

## The root cause — a shadowing handler

The prototype `wezterm.lua` defined its **own** inline tab-bar handler:

```lua
wezterm.on("format-tab-title", function(tab) ... end)
```

`wezterm.on` **appends** handlers — there is no "replace". A user-defined `format-tab-title`
registration (or a duplicate keybinding block) sitting **outside** the wezterm-setup managed block
therefore **shadows** the managed renderer, producing the symptoms above. Duplicate keybindings that
re-bind the same keys the managed block manages have the same shadowing effect.

## The fix — what to remove

`wez doctor` now **fails loudly** (a non-zero-exit **core** gate, D-11) when it detects an inline
`format-tab-title` handler outside the managed block. Run it:

```sh
wez doctor
```

If the **"no shadowing tab-bar handler"** gate fails, open your `wezterm.lua` and:

1. **Delete the inline `wezterm.on("format-tab-title", ...)` registration** (single- or double-quoted)
   that lives **outside** the `>>> wezterm-setup managed block >>>` … `<<< wezterm-setup managed block <<<`
   markers. wezterm-setup's managed block renders the tab bar — your inline handler shadows it.
2. **Remove any duplicate keybindings** that re-bind keys the managed block already manages (keep your
   genuine, personal settings — only the *duplicates that shadow the managed block* need to go).
3. Keep everything else (fonts, colors, personal options) untouched.

The installer already wrote a **timestamped backup** (`wezterm.lua.bak.<timestamp>`, INST-02) before
it injected the managed block, so the original is always recoverable.

The doctor gate's failure detail says the same thing this section does — there is a **single source of
guidance**: remove the inline `format-tab-title` handler (and any duplicate keybindings) from your
`wezterm.lua`.

## The reset option

Because this is a solo setup (D-10), a **clean reinstall** of the wezterm-setup config tree is always
an acceptable reset — re-running the installer re-copies the managed config and writes a fresh
timestamped backup of your current `wezterm.lua` first. (A dedicated `wez uninstall` that removes the
managed config dir is **deferred** to a later phase; until then, reinstall + the backup is the reset
path.)

## Live tabs reset on the next recolor / restart

Already-running tabs may still carry an old `"<color>:<title>"` title from before the upgrade. These
live in the running mux, not on disk, and **reset on the next `wez tab color` / `set-tab-title`, or on
the next WezTerm restart**. No action is required — the new code only changes future writes.
