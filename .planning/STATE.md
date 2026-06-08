# Project State: wezterm-setup

## Project Reference

**Core Value**: A working WezTerm install that is easy to understand, audit, and extend — where every shipped behavior is verified against a real running session before it integrates.

**Project file**: `.planning/PROJECT.md`  
**Roadmap**: `.planning/ROADMAP.md`  
**Requirements**: `.planning/REQUIREMENTS.md`

---

## Current Position

**Current Phase**: Phase 0 — Spikes & Alignment (Complete) → next: Phase 1 Foundation  
**Current Plan**: None — Phase 0 closed  
**Status**: Phase 0 complete (Linux); macOS verification deferred to batched Mac pass before Phase 1 closes (D-04/D-05)

### Progress Bar

```
Phase 0  [██████████]  Complete (2026-06-07)
Phase 1  [░░░░░░░░░░]  Not started
Phase 2  [░░░░░░░░░░]  Not started
Phase 3  [░░░░░░░░░░]  Not started
Phase 4  [░░░░░░░░░░]  Not started
Phase 5  [░░░░░░░░░░]  Not started
```

**Overall**: 1/6 phases complete

---

## Phase Status

| Phase | Name | Status | Completed |
|-------|------|--------|-----------|
| 0 | Spikes & Alignment | Complete | 2026-06-07 |
| 1 | Foundation | Pending | - |
| 2 | Pane Identity | Pending | - |
| 3 | Tab Identity | Pending | - |
| 4 | Ad-hoc Scenes | Pending | - |
| 5 | Named Scenes | Pending | - |

---

## Performance Metrics

**Plans executed**: 4 (Phase 0)  
**Plans verified**: 4 (goal-backward against ROADMAP Success Criteria 1–4)  
**Requirements delivered**: 0/29 (Phase 0 produces decisions, no REQUIREMENTS items)  
**Phases complete**: 1/6

---

## Accumulated Context

### Key Decisions (from PROJECT.md)

| Decision | Status |
|----------|--------|
| Tab color stored in tab title prefix (`"color:title"`) | Proven 2026-06-07 |
| Pane-level color via OSC 1337 `SetUserVar` | Proven 2026-06-07 |
| Companion CLI language: Lua preferred, Python/uv fallback | Pending — Phase 0 spike |
| Bash excluded as CLI language | Confirmed |
| Hypothesis-first development | Active policy |
| Non-destructive install via sentinel blocks | Active policy |

### Validated Capabilities (pre-Phase 0)

- Tab-level persistent color via `set-tab-title` prefix convention (`"color:title"` or `"color"`)
- Pane-level color override via `WEZTERM_TAB_COLOR` user var (OSC 1337 escape)
- Active tab visual differentiation (indicator + bold text)
- Color profiles: red, orange, yellow, green, teal, cyan, blue, navy, purple, pink

### Active Todos

*(None yet — roadmap just created)*

### Blockers

*(None)*

### Discoveries

- `wezterm cli set-user-var` does NOT exist — pane user vars must use OSC 1337 escape
- WezTerm hot-reloads `~/.config/wezterm/wezterm.lua` on file save; no restart needed during development
- Active config is `~/.config/wezterm/wezterm.lua`; repo config will live under `~/.config/wezterm/wezterm-setup/` post-install

---

## Session Continuity

**Last session**: 2026-06-07 — Phase 0 executed: CLI language (Lua 5.4), CWD mechanism (OSC 7), `wezterm cli` audit, tab-title format lock; decisions promoted to PROJECT.md  
**Next action**: Discuss/plan Phase 1 Foundation (`/gsd-discuss-phase 1`) — and schedule the batched macOS verification pass before Phase 1 closes (D-04/D-05)

**Key Phase 0 outcomes (for Phase 1):**
- CLI = **Lua 5.4**; packaging = vendored pure-Lua deps + `luastatic` single binary + `curl|bash` installer (sudo-free for users); dev/CI provisions Lua SDK + musl (Linux) + Mac runner
- CWD = OSC 7 (ship shell integration emitting it for zsh+bash) + WezTerm OS read backstop
- `wezterm cli` surface catalogued in `.planning/decisions/wezterm-cli-surface.md` (no `set-user-var` → OSC 1337)
- Tab color = `"color:title"` title prefix; pane color = OSC 1337 `WEZTERM_TAB_COLOR`

---

*State initialized: 2026-06-07*  
*Last updated: 2026-06-07 after Phase 0 completion*
