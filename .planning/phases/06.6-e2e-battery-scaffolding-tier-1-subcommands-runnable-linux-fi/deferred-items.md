# Deferred Items — Phase 06.6

Tracked work intentionally NOT completed in this phase, with the phase that owns it.

## D-06.6-01 — keys-siblings macOS install fix (4c765e1) → Phase 7

**Origin:** Plan 06.6-04, Task 2 (Migration & Reset reuse).

**What was deferred:** The archived fix `4c765e1`
(`fix(07.1-keys-siblings): symlink all WezTerm bundle binaries on macOS`) and the
full archived `tests/cli/bootstrap_macos_test.lua` were NOT cherry-picked forward.

**Why:** `4c765e1` patches a fully-implemented `install_macos` body (fetch →
integrity-gate `504b0304` → `ditto -x -k` extract → `cp -R` → sibling-symlink
loop) plus a `wezterm_macos_asset_url()` helper in `tools/lib/wezterm-release.sh`.
On the Linux mainline NONE of that exists: `install_macos` (tools/bootstrap-wezterm.sh)
is a DESIGN-ONLY stub (D-06/D-18, macOS deferred to Phase 7), `wezterm-release.sh`
has no macOS asset-url helper, and `tests/cli/bootstrap_macos_test.lua` was never
created here (it asserts ~15 macOS-installer symbols absent from main). Bringing the
whole macOS installer forward would be a major scope expansion that contradicts D-18
(macOS deferred to Phase 7). Decision: do NOT bring the installer forward; do NOT
pure-defer with no test either.

**What landed INSTEAD (Plan 06.6-04, Task 2 — verifiable on Linux today):**
- `tests/e2e/tier1/keys_siblings_e2e_test.lua` (NEW): two-layer OS-detect + skip-gate.
  - Cross-platform layer (always runs, green on Linux): asserts `tests/e2e/platform.lua`'s
    `bundle_siblings` parity row names the three siblings `wez keys` needs
    (`wezterm-gui`, `wezterm-mux-server`, `strip-ansi-escapes`) + that Linux needs none.
  - macOS-specific layer: skip.lua `require_tool(os == "macos")` — prints a loud
    `SKIPPED (reason=macOS — deferred to Phase 7 …)` on non-macOS (counts as PASS),
    shaped to FIRE on macOS once Phase 7's installer lands. Asserts ONLY the
    sibling-symlink contract, NOT the archived installer's fetch/extract symbols.
- A comment in the `install_macos` design-only stub (tools/bootstrap-wezterm.sh)
  recording the keys-siblings requirement, cross-referencing the platform.lua row.

**Owned by:** Phase 7 (macOS Parity Pass, D-18). When Phase 7 implements the real
`install_macos`, it MUST: (1) symlink all bundle siblings into `${BIN_DIR}` per the
`bundle_siblings` parity row, (2) bring forward `4c765e1` (or re-author equivalently),
(3) bring forward the full `tests/cli/bootstrap_macos_test.lua`. At that point
`keys_siblings_e2e_test.lua`'s macOS layer FIRES (stops skipping) on Mac hardware.
