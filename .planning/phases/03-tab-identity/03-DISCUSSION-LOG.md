# Phase 3: Tab Identity - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-11
**Phase:** 3-tab-identity
**Areas discussed:** Merge vs clobber, tab title command, Reset / clear, Target tab

---

## Merge vs clobber

| Option | Description | Selected |
|--------|-------------|----------|
| Preserve title (merge) | Read current tab title, swap only the requested half (read-modify-write) → `green:api` + `wez tab color blue` = `blue:api` | ✓ |
| Replace (clobber) | `wez tab color blue` → `blue`, drops the title; simpler, no read step | |

**User's choice:** Preserve title (merge).
**Notes:** Drove D-01. `set-tab-title` writes the whole string, so preservation requires reading current state via `wezterm cli list --format json`.

### Follow-up: title-without-color encoding

| Option | Description | Selected |
|--------|-------------|----------|
| Always write the colon | `wez tab title "api"` (no color) writes `":api"` — empty color prefix, explicit title | ✓ |
| Formatter heuristic | Writer emits bare `api`; formatter guesses color vs title by known-profile-name match | |
| Always carry a color | Every write includes a color (default sentinel) so form is always `color:title` | |

**User's choice:** Always write the colon.
**Notes:** Drove D-02. The locked parse rule treats a no-colon token as a *color*, so the colon is the unambiguous structural marker; `:title` / `color:` / `color:title` are the three forms.

---

## tab title command

| Option | Description | Selected |
|--------|-------------|----------|
| Yes + icon parity | Ship standalone `wez tab title` + accept Phase 2's icon-name map (docker→🐳, ~40 names) | ✓ |
| Yes, text only | Ship `wez tab title` but plain text + emoji only, no icon shortcuts | |
| Only via --title flag | No standalone command; titles only via `wez tab color <name> --title` | |

**User's choice:** Yes + icon parity.
**Notes:** Drove D-03. Factor the Phase 2 icon resolver into a shared lib so `tab.lua` and `pane.lua` share one map.

---

## Reset / clear

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror pane | `wez tab color reset` (keeps title), empty `wez tab title` (keeps color); per-attribute via read-modify-write | ✓ |
| Single clear-all | One `wez tab reset` wipes both color and title | |
| Both | Per-attribute + a `wez tab reset` convenience | |

**User's choice:** Mirror pane.
**Notes:** Drove D-04. Same verbs/muscle memory as Phase 2; per-attribute only, no clear-all.

---

## Target tab

| Option | Description | Selected |
|--------|-------------|----------|
| Current tab, --tab-id-ready | Act on active tab now; design internals for a future `--tab-id` (Phase 4 scenes), mirror Phase 2 D-05 | ✓ |
| Surface --tab-id now | Ship `wez tab color blue --tab-id <id>` this phase | |

**User's choice:** Current tab, --tab-id-ready.
**Notes:** Drove D-05. No scene caller exists yet; speculative surface avoided. Keep tab-id resolution separate from the write logic.

---

## Claude's Discretion

- Exact CLI arg shape (positional vs flag), shared icon-resolver lib location, read-modify-write parse helper placement, completion wiring into `cli/spec.lua` (D-16), and whether `wez tab color` accepts raw hex/rgba beyond named profiles (D-06).

## Deferred Ideas

- `--tab-id` / arbitrary-tab targeting → Phase 4 (Ad-hoc Scenes).
- Single coarse `wez tab reset` clear-all → rejected (D-04), not deferred.
- `wez tab` styling beyond color + title → not requested, out of scope.
