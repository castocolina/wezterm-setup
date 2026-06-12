# Phase 3 — Plan Review Feedback

**Source:** `/review-spec` (reviewing-specs skill, gsd · plan archetype) — fresh-context reviewer, grounded against the live codebase + LOCKED `tab-title-format.md` + approved `03-UI-SPEC.md`.
**Date:** 2026-06-11
**Verdict:** Issues Found — replan to address CRITICAL + HIGH + MEDIUM below.
**Scope:** Surgical edits only. The plans are otherwise verified coherent (requirement coverage TAB-01..05 complete, waves acyclic, threat models present, grounding accurate). Do NOT restructure the 4-plan / 4-wave decomposition; fix only the findings below.

---

## CRITICAL-1 — no-colon parse return contradicts the LOCKED spec + approved UI-SPEC (affects 03-01 AND 03-02)

**Where:**
- `03-01-PLAN.md` Task 1 — `M.parse_tab_title("myshell")` / no-colon case currently specified to return `(nil, nil)`.
- `03-02-PLAN.md` Task 1 — `M.parse_stored("blue")` / no-colon case currently specified to return `(nil, nil)`.

**Problem:** The LOCKED `tab-title-format.md` states the encoding is `"<color>:<title>"`, "with no title: `"<color>"`", and the parse rule is "split on the first `:`; left = color". A bare no-colon token is therefore a **color name with no title**, not "neither". The approved `03-UI-SPEC.md` rendering-states matrix has an explicit row: stored `"blue"` (no colon) → parsed `("blue", "")` → renders the blue accent. The plans' `(nil, nil)` makes an externally-set bare color title (e.g. `wezterm cli set-tab-title blue`) render the DEFAULT accent instead of blue — directly contradicting both the locked decision and the approved UI contract.

**Required fix (both plans):** Specify the **no-colon, non-empty** case to return `(color, nil)` — e.g. `parse_tab_title("blue")` → `("blue", nil)`, `parse_stored("blue")` → `("blue", nil)`. The unknown-color → default mapping is then handled downstream by `resolve_profile` (exactly as the UI-SPEC matrix tabulates: a bare unknown word → default accent; a bare known color → that accent). Keep the **empty-string and nil** inputs returning `(nil, nil)` (the `parse_tab_title("")` / nil-guard cases are correct — only the genuine no-colon-non-empty branch changes). Update the matching `<behavior>` cases AND the `<acceptance_criteria>` in both plans. Remove the "defensive `(nil,nil)` avoids misreading WezTerm default titles" rationale — it is incorrect: WezTerm's own auto-titles live in `active_pane.title`, while `tab.tab_title` is `""` (not a bare word) when unset, so the no-colon branch only ever sees externally-set titles that the locked spec defines as colors.

## HIGH-1 — icon-map size "~40 names" is overstated (~22 actual)

**Where:** `03-03-PLAN.md` `<objective>` and `<must_haves><truths>` ("~40 names"). Same wording echoed from `03-CONTEXT.md` D-03 and `03-UI-SPEC.md`.

**Problem:** The actual `cli/commands/pane.lua` `M.ICONS` table being lifted has ~22 entries (node, python, rust, go, docker, k8s, server, db, ssh, deploy, git, build, test, debug, edit, log, shell, config, search, ai, fire, alert), not ~40.

**Required fix:** In `03-03-PLAN.md`, reword to "the existing icon-name map, lifted verbatim" (drop the asserted count) or state ~22. The lift-verbatim action is unaffected; only the count claim is wrong. (Note for the human: the same "~40" error exists in the already-committed 03-CONTEXT.md and 03-UI-SPEC.md — correct at source separately to stop propagation; not the planner's job in this pass.)

## MEDIUM-1 — 03-02 `depends_on: ["03-01"]` is not load-bearing for 03-02's own verification

**Where:** `03-02-PLAN.md` frontmatter `depends_on: ["03-01"]` + `<verify>` blocks.

**Problem:** 03-02's automated tests (validate_color / parse_stored / merge_title + spec-parse) and its manual repro (`wezterm cli list --format json | grep tab_title`) are all formatter-independent — 03-02 can execute and pass its own verification with 03-01 unimplemented. A stated `depends_on` implies the dependent plan's verification exercises the dependency, which it does not.

**Required fix:** Add one clarifying line to 03-02's `<objective>` (or a frontmatter comment) stating the dependency is **end-to-end observability ordering** (so the accent is visually confirmable via 03-01's formatter), NOT a build/test dependency. Keep `depends_on: ["03-01"]` (it is correct for execution sequencing) — just document why. Do not weaken it to `[]`.

---

## Verified CLEAN — do NOT change (recorded so the replan does not "fix" non-issues)
- `merge_title` already supports both `set_color` and `set_title` present (combined `--title`, 03-03) — algebraically correct, no helper change.
- `set_color=""` → `":title"` reset semantics (03-02) — correct under Lua truthiness.
- `tab` namespace additions across 03-02/03-03 — structurally additive, no conflict.
- 03-01 line-grounding (format-tab-title.lua handler range, stale line-68 comment, test structure) — accurate.
- 03-04 grounding (complete.lua CONTEXTS, completions.lua zsh/bash dispatch) and `type: execute` — accurate + consistent with the 02-05 precedent.
- Requirement coverage TAB-01..05, wave/depends ordering 01→02→03→04 — complete and acyclic.
