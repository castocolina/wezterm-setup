# Plan 00-01 Summary — CLI Language Spike

**Status:** Complete
**Date:** 2026-06-07
**Outcome:** Companion CLI language locked to **Lua 5.4**.

## What was decided

The `wez` companion CLI will be written in **Lua 5.4** (not Python/uv). Full rationale and evidence
in [`.planning/decisions/cli-language.md`](../../decisions/cli-language.md).

## How (evidence-driven)

- Decision criterion was **revised mid-spike** (CONTEXT D-02): from "distribution simplicity" to
  **code ergonomics + stack coherence**, after recognizing the CLI is out-of-process to WezTerm
  (so "native integration" is near-empty for the CLI layer).
- Built two prototypes against an **isolated headless `wezterm-mux-server`** (no GUI, no sudo,
  `XDG_RUNTIME_DIR=/tmp/wez-spike`), identical proof-scope (arg parse + `wezterm cli` + JSON + I/O):
  both produced identical output, exit 0. Lua = 20 logic lines vs Python = 31.
- Proved Lua's dependency + packaging story **sudo-free, end-to-end**:
  - pure-Lua deps (`dkjson`, `argparse`) vendored as single files — no luarocks/compiler/sudo.
  - built Lua 5.4.7 from source in `/tmp` (no sudo) → `liblua.a`.
  - `luastatic` → a **368 KB single binary** running standalone (`ldd`: only libc/libm; interpreter
    baked in). This is the `make build` → `curl | bash` → `~/.local/bin` model, zero sudo for users.

## Deliverable

- `.planning/decisions/cli-language.md` — committed decision record (criterion, evidence, packaging
  model for Phase 1).

## Deferred

- **macOS verification** (build on a Mac runner; `lipo` universal) — batched Mac pass before Phase 1
  closes, per CONTEXT D-04/D-05.
- **musl-static Linux build** in CI for full cross-distro portability (spike binary was glibc-dynamic;
  fine for mainstream distros).

## Scratch (gitignored `.tmp/`, deleted on promotion per playbook R5)

`.tmp/h01-cli-lang-lua/` (run.lua, vendor/, bootstrap.sh, lua-manifest.lua, build/run),
`.tmp/h02-cli-lang-python/run.py`, `.tmp/probes/phase-0/01-wezterm-cli-list-json.md`.

## ROADMAP Success Criterion 1

✅ Satisfied: a decision is recorded for CLI language with working prototype(s) demonstrating
viability (two prototypes + a built single binary).
