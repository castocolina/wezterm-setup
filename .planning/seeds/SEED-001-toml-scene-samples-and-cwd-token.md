---
id: SEED-001
status: dormant
planted: 2026-06-13
planted_during: v1.0 / Phase 4 (ad-hoc-scenes)
trigger_when: when the scenes-from-TOML milestone is scoped (named recipe scenes / scene config files)
scope: medium
---

# SEED-001: Ship dashboard sample scenes + a native `{cwd}` title token for scenes-from-TOML

## Why This Matters

Phase 4 shipped `wez scene new` (ad-hoc scenes from CLI flags). The next milestone is
**scenes-from-TOML** (named, reusable scene recipes in a config file). Two things surfaced
while demoing Phase 4 that belong to that milestone:

1. **Sample scenes.** The dashboards we built during the Phase 4 e2e are the natural
   starting library of *sample/template* scenes to ship with the TOML feature — they give
   users a working example to copy instead of a blank file. Concretely:
   - **"dev dashboard"**: `docker stats` + `docker ps -a` + `htop`, `tall` or `grid` layout,
     per-pane muted bg colors (blue/teal/purple) and icon titles (`docker`/`server`/`ai`).
   - Variants per layout (`tall`, `tall:mirrored`, `grid`, `horizontal`).

2. **A native `{cwd}` title token.** In the CLI you can do
   `title=docker stats @ $(basename "$PWD")` because the shell expands it. **That does NOT
   work in a TOML** — it is static config, no shell runs over it, so `$(...)` would be a
   literal string. The TOML scene parser needs template tokens that **`wez` itself** expands:
   - `{cwd}` → basename of the cwd (e.g. `wezterm-setup`)
   - `{cwd_path}` → full path
   - `{cwd_parent}` → parent dir basename

## When to Surface

**Trigger:** when the scenes-from-TOML milestone is scoped (named/recipe scenes, scene
config files). Surface this seed during `/gsd-new-milestone` so both items land in scope.

## Scope Estimate

**Medium.** Sample scenes are cheap (author a few TOML files). The `{cwd}` token is a small
parser feature, BUT it carries a **hard design constraint** (see breadcrumbs): `wez scene new`
(CLI) and the TOML parser **must share the same title resolver**, so `{cwd}` expansion and the
icon-name-first-word behavior are identical across both surfaces. Build the resolver once,
call it from both. Getting this wrong = two drifting title implementations.

## Breadcrumbs

- `cli/lib/title.lua` — the shared title resolver (`resolve_title_str`, `ICONS` map). This is
  the single source of truth the TOML parser must reuse; add `{cwd}`-token expansion HERE so
  CLI + TOML both get it. Icon-name-first-word rule lives here too.
- `cli/commands/scene.lua` (Phase 4) — calls `titlelib.resolve_title_str` for per-pane titles
  (D-07) and per-pane styling; the TOML scene runner should funnel through the same code path.
- `cli/commands/pane.lua`, `cli/commands/tab.lua` — also consume the resolver (icons/titles),
  confirming it is already the shared surface to extend.
- Phase 4 artifacts: `.planning/phases/04-ad-hoc-scenes/` (CONTEXT D-06/D-07 grammar + icon
  behavior the TOML form must mirror).

## Notes

Captured during the Phase 4 ad-hoc-scenes demo; user explicitly asked to capture this for the
TOML milestone. The Phase 4 `--pane` grammar (`cmd=`/`color=`/`title=`, icon-name first word,
whitespace-trimmed, comma-separated) is the de-facto schema the TOML `[[pane]]` table should
mirror key-for-key so the two surfaces stay 1:1.
