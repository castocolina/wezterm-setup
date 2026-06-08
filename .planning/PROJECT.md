# wezterm-setup

## What This Is

A WezTerm config distribution and companion CLI (`wez`) that ships daily-friction fixes, rich visual
identity at the pane and tab level, and a named workspace launcher — all installed non-destructively
via a single injected `require` line. Targets a solo developer on Linux and macOS daily-driving
WezTerm as a full multiplexer.

## Core Value

A working WezTerm install that is easy to understand, audit, and extend — where every shipped
behavior is verified against a real running session before it integrates.

## Requirements

### Validated

- ✓ Tab-level persistent color via `set-tab-title` prefix convention (`"color:title"` or `"color"`)
- ✓ Pane-level color override via `WEZTERM_TAB_COLOR` user var (OSC 1337 escape)
- ✓ Active tab visual differentiation (indicator + bold text)
- ✓ Color profiles: red, orange, yellow, green, teal, cyan, blue, navy, purple, pink

### Active

- [ ] F-01 — Non-destructive install (sentinel-block injection, timestamped backup)
- [ ] F-02 — Granular uninstall (`--keep-config`, `--keep-backup`, `--keep-cli`)
- [ ] F-03 — CWD inheritance for new tabs and panes (Linux + macOS)
- [ ] F-04 — Instant clear keybinding (`Super+K` Linux / `Cmd+K` macOS)
- [ ] F-05 — Curated, conflict-free, cross-platform keybinding set
- [ ] D-01 — `wez doctor` health check
- [ ] D-02 — `wez keys` keybinding introspection
- [ ] P-01 — Per-pane background color via companion CLI
- [ ] P-02 — Per-pane title via companion CLI
- [ ] T-01 — Per-tab accent color via companion CLI
- [ ] T-02 — Per-tab title via companion CLI
- [ ] S-01 — Ad-hoc scene launch (`wez scene new`)
- [ ] S-02 — Layout support for scenes
- [ ] N-01 — Declarative recipe files for named scenes
- [ ] N-02 — `wez scene launch <name>`
- [ ] N-03 — Bundled example scenes (seeded on install)

### Out of Scope

- Status bar widgets (clock, git branch) — not requested; adds complexity with low daily value
- Workspace/session persistence — out of WezTerm's config layer scope; separate tool territory
- SSH domain integration — not part of local terminal identity
- Broadcast input — niche use case; not in any user scenario
- WezTerm kitten/plugin packaging — this is a config distribution, not a WezTerm plugin
- GUI configuration tool — CLI-first, no GUI

## Context

- **Prior bash attempt** at `~/git/cco/wezterm-setup_/` partially works but doesn't scale
  cross-platform. Reference only for escape sequences and color-setting patterns.
- **Reference project**: `kitty-setup` (Python CLI + hypothesis-driven development). Established
  methodology: prove each capability as a standalone script before integrating.
- **Proven today (2026-06-07)**: Tab-level color via `set-tab-title` prefix works. Pane-level
  `WEZTERM_TAB_COLOR` user var set via OSC 1337 escape works. Both are in the active
  `~/.config/wezterm/wezterm.lua`.
- **WezTerm config file split**: `~/.config/wezterm/wezterm.lua` is the ACTIVE config.
  `~/git/cco/wezterm-setup_/config/wezterm.lua` is legacy reference. The repo config will live
  under `~/.config/wezterm/wezterm-setup/` once the managed install is set up.
- **Hot-reload**: WezTerm hot-reloads `~/.config/wezterm/wezterm.lua` on file save — no restart
  needed during development.
- **`wezterm cli set-user-var` does NOT exist** — use OSC 1337 escape for pane user vars.

## Constraints

- **Runtime (config layer)**: Pure Lua inside WezTerm — zero external dependencies
- **Runtime (companion CLI)**: TBD via spike — Lua 5.4 standalone preferred; Python/uv as fallback
  (proven in kitty-setup); Bash explicitly excluded for cross-platform reasons
- **Platform**: Linux (Wayland + X11) + macOS parity for every shipped feature
- **Install**: Must work without `sudo` on both platforms
- **Philosophy**: No vi-modal bindings, no `less`-style search overlays anywhere in the shipped UX
- **Hypothesis-driven**: Every capability in Phase 2+ starts as a hypothesis in
  `.tmp/h<NN>-<slug>/` with a manual repro before integration (see `docs/agent-iteration.md`)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Tab color stored in tab title prefix (`"color:title"`) | `tab.tab_title` survives pane switches; pane user vars don't | ✓ Good — proven today |
| Pane-level color via OSC 1337 `SetUserVar` | `wezterm cli set-user-var` doesn't exist; OSC escape is the correct path | ✓ Good — proven today |
| Companion CLI language: **Lua 5.4** | Ergonomics parity + stack coherence + native Lua scene recipes; single-binary packaging (luastatic) fits the curl\|bash goal better than Python | ✓ Locked Phase 0 — see [decisions/cli-language.md](decisions/cli-language.md); macOS build deferred to Mac pass (D-05) |
| Bash excluded as CLI language | Unstructured bash doesn't scale across platforms — proven by `wezterm-setup_` | ✓ Good |
| CWD inheritance: OSC 7 (primary) + WezTerm OS read (backstop) | Split/new-tab cwd inheritance is WezTerm default; OSC 7 is the portable, immediate mechanism | ✓ Locked Phase 0 (Linux) — see [decisions/cwd-mechanism.md](decisions/cwd-mechanism.md); macOS verify deferred (D-05) |
| Full `wezterm cli` surface audited | Shared reference prevents rework (e.g. non-existent `set-user-var`); 19 subcommands catalogued | ✓ Locked Phase 0 (Linux) — see [decisions/wezterm-cli-surface.md](decisions/wezterm-cli-surface.md); macOS column pending |
| Tab-title color-prefix format (`"color:title"`) locked | Document-and-lock the proven format + parse rule + 10 color profiles | ✓ Locked Phase 0 — see [decisions/tab-title-format.md](decisions/tab-title-format.md) |
| Hypothesis-first development | kitty-setup proved that integrating unverified capabilities causes rework | ✓ Good |
| Non-destructive install via sentinel blocks | User trust depends on zero-surprise install; kitty-setup confirmed this pattern | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-07 after project initialization*
