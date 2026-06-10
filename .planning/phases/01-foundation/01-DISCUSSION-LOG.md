# Phase 1: Foundation — Discussion Log

**Date:** 2026-06-08
**Mode:** discuss (default, interactive)

> Human-reference record of the discussion. NOT consumed by downstream agents — they read
> `01-CONTEXT.md`. This captures the options presented, what was chosen, and the reasoning
> turns (including two technical corrections made mid-discussion).

## Areas selected

User selected all four offered, then explored two parked areas, and added one new
requirement mid-discussion. Seven areas total.

---

## Area 1 — Installer & bash boundary (INST-01..05)

- **Where is bash excluded?** Options: bash-for-installer-only / bash-fully-excluded / you-decide.
  → **You decide** → resolved to **bash for bootstrap only** (detect/fetch/build/place/inject);
  all logic in the Lua binary. Rationale: Makefile R3 "thin glue" + bootstrap chicken-and-egg.
  → **D-01**
- **`make install` build path?** Options: build-local-luastatic / download-release / both.
  → **Both: build local, fetch fallback.** → **D-02**
- **Re-install with no TTY?** Options: abort-require-flag / default-skip / you-decide.
  → **Abort safely, require a flag.** → **D-03**

## Area 2 — Keybinding scheme (FOUND-02..05)

- **Binding model?** Options: direct-combos / leader-prefix / hybrid.
  → User free-text: keep common things simple, US-ANSI keyboard, map the printed keys, nothing
  complicated, don't get stranded when switching to an ES layout.
- **Anchor?** Options: mirror-tmux/zellij / keep-wezterm-defaults / fresh-scheme.
  → **Fresh curated scheme** (WezTerm defaults judged "rebuscados").
- **Replaced defaults?** Options: disable / layer-on-top / you-decide.
  → **You decide** → resolved to **disable replaced defaults** (honest `wez keys`). → **D-12**

**Correction #1 (phys: → mapped:):** Claude initially recommended `phys:` (physical position).
User corrected: he wants the **printed/produced character** to fire the action across keyboards
and layouts, and `wez keys` to report a reproducible combo — the opposite of physical lock.
Verified against WezTerm docs (`config/keys.html`): `phys:` = physical position; `mapped:` =
layout-produced character; default follows `key_map_preference` (defaults to `"Mapped"`).
→ Locked **`mapped:` + `key_map_preference="Mapped"`** + layout-stable key restriction.
→ **D-09, D-10, D-11**

## Area 3 — `wez keys` / `wez doctor` introspection (DIAG-01..04)

- **`wez keys` data source?** Options: single-lua-source / generated-manifest / parse-config-text.
  → User: "combination of several things… wezterm cli has a subcommand for active keys… but
  there must be a way to see who wins." → Pointed at `wezterm show-keys`.
- **Classification depth?** Options: setup+conflict-static-defaults / full-live-3way / you-decide.
  → **You decide** → resolved to **full real 3-way + precedence** (achievable via live table).
  → **D-14**
- **`wez doctor` scope?** Options: install-integrity-core / core+live / you-decide.
  → **You decide** → resolved to **integrity core gates exit code, live checks advisory**.
  → **D-15**

**Verification:** Confirmed `wezterm show-keys` exists (top-level, not in the Phase 0
`wezterm cli` audit), `--lua` is machine-parseable, **merges user config** into the effective
table, and **distinguishes phys/mapped**. → Locked the combination source. → **D-13**

## Area 4 — macOS pass scope (D-04/D-05)

- **macOS in Phase 1 or Linux-first?** → **Linux-first, macOS tracked follow-up.**
- **Mac hardware now?** → **Intermittent / later.**
  → Design cross-platform, verify Linux; Mac pass before v1 done. → **D-18**

## Area 5 — Completions (DIAG-05)

- Options: generated-from-argparse+dynamic-hooks / hand-written-static / generate-at-install.
  → **Generated from argparse + dynamic hooks.** → **D-16**

## Area 6 — Sentinel block integration (INST-01)

- **Augment vs Own?** Options: augment-apply-to-config / own-return-config / you-decide.
  → **Augment** (`require('wezterm-setup').apply(config)` mutates the user's config object).
  R6 probe noted for referencing the user's config variable robustly. → **D-17**

## Area 7 — WezTerm bootstrap (NEW — INST-06), added by user mid-discussion

User: kitty-setup downloaded the binary locally per install; here we only place `wez`, not
WezTerm. Should also bootstrap WezTerm itself — nightly, sudo-free, user path
(macOS `~/Applications`).

- **Scope placement?** Options: new-INST-06-in-Phase-1 / new-req-separate-phase / deferred.
  → **New INST-06 in Phase 1** (with a caveat: prior AppImage failures on Pop!_OS).
- **Linux mechanism?** Options: AppImage / tar.xz / detect-reuse-warn.
  → User deferred to scope + flagged AppImage distrust.
- **Already installed?** Options: install-ours / reuse-if-min-version / you-decide.
  → **Reuse if meets minimum version.**
- **Version policy?** → User asked: can the version pick be interactive, listing the last 5?

**Correction #2 ("5 nightlies" → dated releases):** Verified against the wez/wezterm releases
API: `nightly` is a **single rolling tag** (`*-nightly-*` assets, overwritten) — there is no
list of 5 nightlies. **Dated releases** (`20260604-145453`, etc.) ARE retained and listable.
Also verified: WezTerm ships a generic **`wezterm-nightly.Ubuntu<base>.tar.xz`** (sudo-free,
no FUSE) — this resolves the user's Pop!_OS AppImage concern (Ubuntu 24.04 drops libfuse2).
macOS asset: `WezTerm-macos-nightly.zip`.

- **Corrected selector?** Options: interactive(nightly+last-5-dated)+pinned-no-TTY-default /
  interactive-only-fail-no-TTY / always-pin.
  → **Interactive: nightly + last 5 dated, pinned default when non-interactive.**
  → **D-04, D-05, D-06, D-07, D-08**

---

## Roadmap impact

INST-06 added to `REQUIREMENTS.md` and `ROADMAP.md` (Phase 1 requirements line + success
criterion #6; criterion #3 split Linux-now / macOS-deferred). v1 coverage 30 → 31.

## Deferred ideas

- macOS live verification (Mac pass) — tracked, before v1 done.
- musl-static Linux build of `wez` — CI step.
- Concrete keybinding chord table — produced at plan time.
