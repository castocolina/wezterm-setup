# Plan 02-04 Summary — `wez pane title`

**Phase:** 02-pane-identity
**Plan:** 02-04
**Status:** Complete
**Requirements:** PANE-03 (custom title in tab bar when focused), PANE-04 (persistence)

## What shipped

- **`cli/commands/pane.lua`** (MODIFIED) — adds the `title` surface:
  - `M.ICONS` — icon-name → glyph map (22 entries: docker→🐳, rust→🦀, git→🔀, …).
  - `M.resolve_title(words)` — pure: first token is an icon name → glyph + rest; emoji/freeform
    pass through verbatim (original case); empty / `reset` → `""` (clear).
  - `M.run_title` — emits OSC 1337 `SetUserVar=WEZTERM_TAB_TITLE` via the shared `emit` sink and
    `build_osc1337` (base64) reused from 02-03 (D-05 seam preserved).
  - `M.run` now branches `color` | `title`.
- **`cli/spec.lua`** (MODIFIED) — `pane title <words...>` registered as a sibling of `pane color`
  (variadic positional `:args("*")` so `wez pane title docker "compose up"`, `wez pane title ""`,
  and `wez pane title` all parse).
- **`cli/commands/pane_test.lua`** (MODIFIED) — extended to 49 assertions.

## Verification (autonomous — against a real WezTerm)

- **49/49 fixture assertions pass**: `resolve_title` (icon+text, freeform, emoji passthrough,
  icon-only, empty/reset clear, case-insensitive icon, empty-string arg), title emission via
  `M.run`, and the escape-injection guard (a raw `\27` in the title is base64-encoded — it never
  appears literally in the emitted OSC).
- **Dispatcher path**: `wez pane title docker "compose up"` → OSC 1337 whose payload base64-decodes
  to `🐳 compose up`; `wez pane title` (no args) → empty-payload clear.
- **Live end-to-end:** ran the real commands inside a spawned WezTerm pane with a
  `user-var-changed` logger; the log recorded `WEZTERM_TAB_TITLE=🐳 compose up` then `=` (clear) —
  proving the icon-resolved, emoji-bearing title reaches WezTerm intact through base64, and the
  clear path works. 02-02's `format-tab-title` reads this var to override the displayed tab title
  while the pane is focused.

## Artifacts this phase produces

- `cli/commands/pane.lua` — `ICONS`, `resolve_title`, `run_title`; `run` branches color|title
- `cli/spec.lua` — `pane title <words...>`
- User-var produced: `WEZTERM_TAB_TITLE` (consumed by 02-02)
- CLI surface: `wez pane title <text | icon-name text | "" | reset>`

## Notes

- Escape-injection is structurally prevented: the title payload is base64-encoded before emission,
  so control bytes in user input cannot terminate or inject into the OSC sequence (verified by t10
  + the byte-level dispatcher check).
