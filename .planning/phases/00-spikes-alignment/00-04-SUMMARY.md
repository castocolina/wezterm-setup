# Plan 00-04 Summary — Tab-Title Format Lock + Decision Promotion

**Status:** Complete
**Date:** 2026-06-07
**Outcome:** Tab-title format locked; all four Phase 0 decisions promoted to PROJECT.md.

## What was done

1. **Tab-title format locked** (document-and-lock, no re-prove) →
   [`.planning/decisions/tab-title-format.md`](../../decisions/tab-title-format.md): `"color:title"`
   prefix, first-`:`-split parse rule, 10 color profiles, OSC 1337 pane override companion.
2. **Promoted all four Phase 0 decisions into PROJECT.md "Key Decisions"** (ROADMAP Criterion 4):
   - CLI language: flipped from "Pending" → **Lua 5.4** (with link + macOS-deferred note).
   - Added CWD mechanism, `wezterm cli` surface audit, and tab-title format rows — each linking its
     decision record.

## Verification
- `PROJECT.md` references all four decision records (cli-language, cwd-mechanism, wezterm-cli-surface,
  tab-title-format).
- The "Companion CLI language … Pending" row is gone — outcome now Lua 5.4.

## ROADMAP Success Criterion 4
✅ Satisfied: all Phase 0 decisions written to PROJECT.md Key Decisions before Phase 1 planning.
