# Phase 4: Ad-hoc Scenes - Research

**Researched:** 2026-06-12
**Domain:** `wez scene new` — Lua 5.4 CLI orchestration of `wezterm cli` for multi-pane tab materialization
**Confidence:** MEDIUM (HIGH on wezterm-cli mechanics, MEDIUM/LOW on JSON schema and timing — flagged explicitly)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: `wez scene new` takes one or more repeated `--pane <spec>` flags; N = number of `--pane` entries. No fixed pane-count minimum/maximum.
- D-02: Layouts (`tall`, `tall:mirrored`, `grid`, `horizontal`) must scale to arbitrary N. Exact split-percentage geometry is left to research/planner — see Architecture Patterns below for the locked formula.
- D-03 through D-08: (per-pane spec syntax, color/title/command fields, tab color/title flags — carried forward from 04-CONTEXT.md verbatim; reproduced in 04-UI-SPEC.md and not re-derived here since they don't affect wezterm-cli sequencing)
- D-09: Non-active panes must remain VISUALLY CLEAN after styling injection — no visible OSC escape codes or stray output. Quiet `printf` (escape sequences) followed by `clear` is the required pattern.
- D-10: Materialization must detect the current tab's pane count. If the current tab already has exactly 1 pane AND the scene requests exactly 1 pane, reuse the current pane as pane 1 (no new tab spawned).
- D-11: For all other cases (current tab has >1 pane, or scene requests ≥2 panes), spawn a NEW tab in the SAME window and materialize the full layout there — never touch the user's current tab's existing pane arrangement destructively.
- D-12: No special-case override flag for degenerate layouts (e.g., `grid` collapsing to 1 column at small N) — accepted as a consequence of "layouts just scale" (D-02).

### Claude's Discretion
- Exact split-percentage math per layout — RESOLVED by this research using the "equal-share formula" (100/remaining) confirmed compatible with 04-UI-SPEC.md's Layout Geometry Contract.
- Order of operations: spawn/split first vs. style-then-split — this research recommends split-all-first, then style each pane (see Architecture Patterns).
- Whether to use `--cells` or `--percent` for split-pane — this research recommends `--percent` exclusively (cell-based sizing requires knowing current pane dimensions, adds a `list` round-trip per split with no benefit for equal-share layouts).

### Deferred Ideas (OUT OF SCOPE)
- SCEN-03 (TOML/Lua scene recipe files), SCEN-04 (`wez scene launch <name>`), SCEN-05 (recipe-name completion), SCEN-06 (installer-seeded example recipes) — all deferred to Phase 5. This research addresses ONLY `wez scene new` (SCEN-01, SCEN-02).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCEN-01 | `wez scene new` opens a new tab with a specified layout, N styled panes, per-pane startup commands, tab color, and tab title | Architecture Patterns (materialization pipeline), Code Examples (split sequencing, send-text injection, set-tab-title), Pitfall 1-4 |
| SCEN-02 | Supported layouts at minimum: `tall`, `tall:mirrored`, `grid`, `horizontal` | Architecture Patterns → "Layout Split Sequencing" (per-layout split algorithms with verified flag usage) |
</phase_requirements>

## Summary

`wez scene new` is achievable entirely through `wezterm cli` subcommands already audited in
`wezterm-cli-surface.md`, with no new external dependencies. The core mechanism — confirmed this
session via live `wezterm cli --help` output against the installed binary
(`20260604-145453-eeb80972`) — is:

1. `wezterm cli list --format json` to inventory the current window/tab/pane state and decide
   between D-10 (reuse current pane) and D-11 (spawn new tab).
2. `wezterm cli spawn` (no `--new-window`, no `--window-id` override) to create a new tab in the
   **current window** — this is the direct answer to D-11's "same window" requirement, confirmed
   from `spawn --help`.
3. `wezterm cli split-pane --pane-id <id> [direction] --percent <N>` repeated N-1 times to carve
   out the remaining panes. **`split-pane` and `spawn` both print the new pane-id to stdout on
   success** — this is the capture mechanism for chaining splits.
4. `wezterm cli send-text --pane-id <id> --no-paste` to inject OSC 11 (background color) + OSC
   1337 (`SetUserVar WEZTERM_TAB_COLOR` for pane-level tab-color override, per
   `tab-title-format.md`) + a quiet `printf`/`clear` sequence (D-09), followed by the per-pane
   startup command.
5. `wezterm cli set-tab-title --tab-id <id> "<color>:<title>"` to apply the D-locked
   `"color:title"` encoding (`tab-title-format.md`) to the new tab — confirmed this targets ANY
   tab by ID regardless of active state, no activation step needed.

**Primary recommendation:** Build the scene materializer as a strict pipeline —
**inventory → decide (D-10/D-11) → split-all (geometry first) → style-each (D-09 clean
injection) → tab-title → activate** — using `--percent`-only splits with the equal-share
formula `100/(remaining panes)`, and `--no-paste` for all `send-text` styling injections. The two
genuinely unverified areas (exact `list --format json` field names, and `send-text` timing
relative to shell-prompt readiness) are both low-risk and addressable via the project's mandatory
hypothesis-first repro (`.tmp/h<NN>-<slug>/`) before integration — flagged explicitly as OPEN
below.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Scene CLI argument parsing (`--layout`, `--pane`, `--title`, `--color`) | CLI / `cli/spec.lua` | — | Follows existing `pane`/`tab` nested-subcommand pattern; spec.lua is the single source of truth for surface + completion |
| Window/tab/pane inventory | CLI / `cli/commands/scene.lua` (via `wezterm cli list --format json`) | — | Read-only RPC to running mux server; no other component has this state |
| Layout geometry → split sequence | CLI / `cli/commands/scene.lua` (pure function, escape-build-style) | — | Pure computation: layout name + N → ordered list of `split-pane` invocations; testable in isolation (mirrors D-05 escape-build/write-sink separation) |
| Pane materialization (spawn/split RPC calls) | CLI / `cli/commands/scene.lua` (write-sink) | WezTerm mux server | CLI issues `wezterm cli spawn`/`split-pane`; mux server performs the actual window manipulation |
| Per-pane styling (OSC 11 bg color, OSC 1337 tab-color override) | CLI / `cli/commands/scene.lua` → `send-text` | WezTerm pane (terminal emulator) | CLI builds escape sequences (pure function, reuse Phase 2 `pane.lua` color-table); WezTerm pane interprets OSC codes on receipt |
| Per-pane startup command execution | Target pane's shell (bash/zsh) | CLI (`send-text`) | CLI injects the command text; the pane's own shell executes it — CLI has no visibility into success/failure |
| Tab accent color + title | CLI / `cli/commands/scene.lua` → `set-tab-title` | WezTerm tab bar (Phase 3 formatter) | CLI writes the `"color:title"` encoded string; Phase 3's `format-tab-title.lua` formatter (already shipped) renders it — no new formatter work needed |
| Dynamic `--layout` value completion | CLI / `cli/commands/complete.lua` (`wez __complete` hook) | `cli/spec.lua` (static layout list) | Mirrors Phase 2/3 color-name completion pattern — layout names are a small static set, likely simpler than color completion (no external state needed) |

## Standard Stack

### Core
No new libraries. This phase is pure orchestration of `wezterm cli` (already a runtime
dependency of the whole project) using the Lua 5.4 standard library (`os.execute`, `io.popen`)
and existing in-repo modules.

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `wezterm cli` | `20260604-145453-eeb80972` (locally installed, audited) | RPC interface to running WezTerm mux server — `list`, `spawn`, `split-pane`, `send-text`, `set-tab-title` | [VERIFIED: wezterm cli --help, live binary] Already the sole materialization mechanism for Phases 2-3; no alternative exists for controlling a running WezTerm instance from a CLI process |
| `cli/vendor/dkjson.lua` | in-repo (vendored) | Parse `wezterm cli list --format json` output | [VERIFIED: wezterm-cli-surface.md / cli/spec.lua] Already vendored for prior phases' JSON needs |
| `cli/vendor/argparse.lua` | in-repo (vendored) | Parse `wez scene new --layout ... --pane ...` argument syntax | [VERIFIED: cli/spec.lua] Same library powers `pane`/`tab` nested subcommands |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `cli/lib/title.lua` | in-repo | Color-name → hex palette resolution, icon map | Reuse for per-pane OSC 11 background colors (same 10-profile palette as Phase 2/3) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `wezterm cli split-pane --percent` | `--cells` (absolute cell count) | Requires querying current pane dimensions via `list` before each split — extra RPC round-trips with no benefit since target is always equal-share fractions. `--percent` is self-relative and matches the locked equal-share formula directly. |
| `send-text --no-paste` for styling injection | default (paste-mode) `send-text` | Default paste mode wraps text in bracketed-paste escapes if the target pane has bracketed paste enabled — risk of the shell echoing the literal escape bytes instead of executing/interpreting them. `--no-paste` sends as-typed, matching how a human would type OSC escapes + Enter. [VERIFIED: wezterm cli send-text --help] |
| Spawning new tab via `wezterm cli spawn` (no flags) | `wezterm cli spawn --new-window` | `--new-window` creates a separate OS window, violating D-11's "same window" requirement. Plain `spawn` (no `--new-window`/`--window-id`) defaults to a new tab in the current pane's window. [VERIFIED: wezterm cli spawn --help] |

**Installation:**
No new packages. All tooling (`wezterm`, Lua 5.4, vendored libs) is already present per Phase 1-3.

## Package Legitimacy Audit

Not applicable — this phase introduces zero new external packages (no npm/PyPI/cargo
dependencies). All components are either the existing `wezterm` binary (system-installed,
out of scope for package audit) or in-repo vendored Lua modules already audited in prior phases.

**Packages removed due to slopcheck [SLOP] verdict:** none (N/A — no new packages)
**Packages flagged as suspicious [SUS]:** none (N/A — no new packages)

## Architecture Patterns

### System Architecture Diagram

```
 wez scene new --layout tall --pane "color=blue,title=editor,cmd=nvim" --pane "color=green" \
                --tab-color purple --tab-title "Dev Session"
        |
        v
 [1] cli/spec.lua: scene:command_target("scene_cmd")
        |  result.command == "scene", result.scene_cmd == "new"
        v
 [2] cli/commands/scene.lua : new_handler(result)
        |
        |--> [3] INVENTORY: io.popen("wezterm cli list --format json")
        |        parse via dkjson -> { windows: [...], tabs: [...], panes: [...] }
        |        resolve: current_window_id, current_tab_id, current_pane_id (via $WEZTERM_PANE),
        |                 count of panes in current_tab_id
        |
        |--> [4] DECIDE (D-10 / D-11):
        |        N = #panes requested (--pane count)
        |        IF current_tab.pane_count == 1 AND N == 1:
        |            target_tab_id = current_tab_id
        |            first_pane_id = current_pane_id      (REUSE, no spawn)
        |        ELSE:
        |            spawn_out = os.execute/popen("wezterm cli spawn")  -- same window, new tab
        |            first_pane_id = <pane-id from spawn_out stdout>
        |            target_tab_id  = lookup via list --format json (pane_id -> tab_id)
        |
        |--> [5] SPLIT SEQUENCE (pure function, layout + N -> ordered split-pane calls)
        |        compute_splits(layout, N) -> [ {from_pane: "self"|idx, dir, percent}, ... ]
        |        for each step:
        |          out = os.execute/popen("wezterm cli split-pane --pane-id <id> <dir> --percent <p>")
        |          new_pane_id = <stdout>
        |          pane_ids[i] = new_pane_id
        |
        |--> [6] STYLE EACH PANE (D-09 clean injection, escape-build / write-sink, reuse Phase 2)
        |        for each pane_id, pane_spec:
        |          escape = build_osc11(bg_color) .. build_osc1337_tabcolor(pane_spec.color)
        |          inject = "printf '%s'; clear; " .. (pane_spec.cmd or "")
        |          os.execute("wezterm cli send-text --pane-id <id> --no-paste '" .. escape .. inject .. "\\n'")
        |
        |--> [7] TAB STYLING
        |        encoded = pane_spec_color_or_tab_color .. ":" .. tab_title   (D-locked "color:title")
        |        os.execute("wezterm cli set-tab-title --tab-id <target_tab_id> '" .. encoded .. "'")
        |
        |--> [8] ACTIVATE (optional, UX nicety)
                 os.execute("wezterm cli activate-pane --pane-id <first_pane_id>")
```

### Recommended Project Structure
```
cli/
├── spec.lua              # ADD: scene:command_target("scene_cmd"), "new" subcommand,
│                          #      --layout, --pane (repeatable), --tab-color, --tab-title
├── commands/
│   ├── scene.lua          # NEW: new_handler — inventory, decide, split, style, tab-title
│   ├── scene_test.lua      # NEW: unit tests for compute_splits() pure function (per layout)
│   └── pane.lua            # REUSE: color table / OSC 11 builder (export shared helper if needed)
└── lib/
    └── title.lua           # REUSE: color palette resolution for pane bg + tab color
```

### Pattern 1: Equal-Share Split Sequencing (all layouts)

**What:** Every layout reduces to a sequence of `split-pane --percent <100/remaining>` calls
where "remaining" is the count of panes still to be carved out of the CURRENT target area
(including the one about to be created).

**When to use:** Computing the split sequence for `tall`, `tall:mirrored`, `grid`, `horizontal`
— this single formula, applied with different direction flags and grouping, covers all four
layouts per 04-UI-SPEC.md's Layout Geometry Contract.

**Per-layout algorithms** (N = total panes requested):

- **`tall`** (1 main @ 50% left + N-1 stacked right, equal heights):
  1. If N == 1: no split (D-10 reuse path covers this).
  2. Split pane[0] `--left --percent 50` → creates pane[1] in the right 50%. (First split:
     `--percent 50` is a fixed value, NOT the equal-share formula — it defines the main/stack
     boundary, per 04-UI-SPEC.)
  3. For i = 2 to N-1: split the MOST RECENTLY CREATED right-side pane `--bottom --percent
     <100/(N-i+1)>` — e.g., N=4: splits are 50%, then 66% (1/1.5≈66 → leaves 2 of 3 remaining
     slots equal), then 50% (1 of 2 remaining). General term for the j-th stacking split (j=1..N-2):
     `percent = round(100 / (N - 1 - j + 1)) = round(100 / (N - j))`.
  4. Direction for stacking splits: `--bottom` (default direction per `split-pane --help`, so the
     flag can be omitted, but explicit `--bottom` is clearer in generated commands).

- **`tall:mirrored`**: identical sequence, swap `--left`→`--right` in step 2 (main pane on the
  right, stack on the left). Stacking splits unchanged.

- **`horizontal`** (N equal-width columns):
  1. If N == 1: no split.
  2. For j = 1 to N-1: split the most-recently-created pane `--right --percent
     <round(100/(N-j+1))>`. E.g. N=4: 75% (3 of 4 remaining... actually for equal columns the
     correct sequence is `100/N` of the ORIGINAL only for the first split when splitting
     left-to-right cumulatively — apply the standard "split off the right portion" recursion:
     splitting the current pane (which represents `k` remaining columns out of `k`) at
     `--percent (100 * (k-1) / k)` leaves a new pane representing 1 column and shrinks the
     original to `(k-1)/k`; repeating this on the ORIGINAL pane each time (not the new one)
     yields N equal columns. Concretely for N=4: split original at 75% (→ 1 col @ 25%, remaining
     3 cols @ 75%), split original again at 66.7% (→ another 1 col @ 25% of original, i.e. 1/4
     overall), then 50%. **This matches 04-UI-SPEC's stated invariant**
     `100/(remaining panes including this one)` when "remaining" is read as "columns not yet
     separated off," counted from the LAST split backward — i.e., compute the percent list as
     `[100/N, 100/(N-1), ..., 100/2]` and apply each split to the pane that still represents the
     "un-split remainder," in that order, splitting off the SMALLEST piece each time via
     `--right`.

- **`grid`** (`ceil(sqrt(N))` cols × `ceil(N/cols)` rows, row-major):
  1. Compute `cols = ceil(sqrt(N))`, `rows = ceil(N/cols)`.
  2. First, create `rows` horizontal bands using the `horizontal`-style equal-share recursion
     but with `--bottom` direction and `rows` instead of N (bands, not final panes).
  3. Then, for each band, apply the `horizontal` column-splitting recursion within that band
     using `--right`, with the column count for that band (`cols`, except possibly fewer for
     the last/partial row — per D-12, no placeholder panes, so the last row's column count =
     `N - cols*(rows-1)`).
  4. This is the most complex layout and the highest-value candidate for the hypothesis-first
     manual repro (`.tmp/h<NN>-grid-layout/`) before integration — verify the band-then-column
     ordering produces the expected visual grid for N=2,3,4,5 before committing the algorithm.

**Source for split mechanics (flags, stdout behavior):**
```bash
# Source: wezterm cli split-pane --help (live binary 20260604-145453-eeb80972)
wezterm cli split-pane --pane-id <PANE_ID> --bottom --percent 33
# stdout: prints the new pane's ID on success, e.g. "5"
```
[VERIFIED: wezterm cli --help, live binary]

The split-pane sequencing algorithms themselves (the specific order/grouping of splits per
layout) are this research's own derivation from the 04-UI-SPEC.md geometry contract — tag as
**[ASSUMED — derived from spec, verify via manual repro]**, particularly the `grid` band-ordering
and the `horizontal`/`tall` recursion direction (original-pane-recursion vs. newest-pane-recursion).
Both `horizontal` and `grid` algorithms above should get a `.tmp/h<NN>-<slug>/` manual repro
(per CLAUDE.md hypothesis-first rule) for N=2,3,4,5 before the `scene.lua` split-sequencer is
considered correct.

### Pattern 2: Inventory and Decision (D-10/D-11)

```bash
# Source: wezterm-cli-surface.md (audited 2026-06-07) + wezterm cli list --help
wezterm cli list --format json
```
[VERIFIED: wezterm-cli-surface.md confirms `list --format json|table` exists and is the
inventory mechanism]

The exact JSON field names (`window_id`, `tab_id`, `pane_id`, `is_active`, `is_zoomed`,
`title`, `cwd`, etc.) are **[ASSUMED]** based on common WezTerm mux-list schema conventions —
NOT directly confirmed by `--help` output (which only shows the `--format` flag, not the
schema). **OPEN — verify via manual repro**: run `wezterm cli list --format json | dkjson` (or
equivalent) in `.tmp/h<NN>-scene-inventory/` and record the actual top-level shape (is it a flat
array of pane-rows with embedded `window_id`/`tab_id`, or a nested
`{windows:[{tabs:[{panes:[...]}]}]}` structure?) before writing `scene.lua`'s parser.

For resolving the CURRENT pane: `$WEZTERM_PANE` environment variable is set by WezTerm inside
every pane it spawns — `[ASSUMED]` based on general WezTerm shell-integration conventions, used
as the lookup key into the `list --format json` output to find `current_pane_id`, then
`current_tab_id` and `current_window_id` by following the pane's row. **OPEN — verify**
`$WEZTERM_PANE` is actually exported (echo it from `.tmp/h<NN>-scene-inventory/`).

D-10/D-11 decision logic (count panes belonging to `current_tab_id` in the parsed list; compare
to N):

```lua
-- cli/commands/scene.lua (sketch)
local current_pane_id = tonumber(os.getenv("WEZTERM_PANE"))
-- ... parse `list --format json` into `panes` array ...
local current_tab_id, tab_pane_count = nil, 0
for _, p in ipairs(panes) do
  if p.pane_id == current_pane_id then current_tab_id = p.tab_id end
end
for _, p in ipairs(panes) do
  if p.tab_id == current_tab_id then tab_pane_count = tab_pane_count + 1 end
end

local first_pane_id, target_tab_id
if tab_pane_count == 1 and N == 1 then
  first_pane_id, target_tab_id = current_pane_id, current_tab_id  -- D-10 reuse
else
  local fh = io.popen("wezterm cli spawn 2>/dev/null")  -- D-11: same window, new tab
  first_pane_id = tonumber(fh:read("*l")); fh:close()
  -- re-list to find target_tab_id for first_pane_id
end
```

### Pattern 3: Clean Per-Pane Styling Injection (D-09)

```bash
# Source: wezterm cli send-text --help (live binary) + Phase 2 D-05 escape-build pattern
# OSC 11 (bg color) + OSC 1337 SetUserVar WEZTERM_TAB_COLOR (per tab-title-format.md), then
# a printf that emits ONLY escape bytes (no visible chars) followed by `clear` to scrub the
# pane of any echo artifacts, followed by the user's startup command + newline.
ESCAPES='\033]11;#1a3a5c\007\033]1337;SetUserVar=WEZTERM_TAB_COLOR=blue\007'
wezterm cli send-text --pane-id 5 --no-paste "printf '${ESCAPES}'; clear; nvim
"
```
[VERIFIED: wezterm cli send-text --help confirms `--no-paste` sends text directly/as-typed
rather than bracket-paste-wrapped — the mechanism is sound]
[VERIFIED: tab-title-format.md confirms OSC 1337 `SetUserVar=WEZTERM_TAB_COLOR=<value>` is the
pane-level tab-color override, since no `wezterm cli set-user-var` subcommand exists]
[VERIFIED: wezterm-cli-surface.md confirms OSC 11 is the background-color escape, reused from
Phase 2's pane-color implementation]

The COMBINATION — printf-escapes-then-clear-then-command as a SINGLE `send-text` payload — is
**[ASSUMED — derived pattern, verify via manual repro]**. Two specific risks:
1. **Timing/race**: if the target pane's shell prompt hasn't appeared yet (pane was JUST
   created by `split-pane`/`spawn` milliseconds ago), `send-text` may deliver the payload before
   the shell's readline/zle is ready to accept input, causing partial loss or visible
   reordering. **OPEN — verify via manual repro**: in `.tmp/h<NN>-scene-inject/`, measure whether
   a `send-text` immediately after `split-pane` (no delay) reliably executes vs. needs a small
   sleep or a shell-readiness signal (e.g., poll OSC 7 cwd-report via `list --format json` as a
   "shell is alive" proxy, since OSC 7 is already confirmed-working per `cwd-mechanism.md`).
2. **bash vs zsh settle**: `clear` behaves identically in both, but PRECMD/PROMPT_COMMAND hooks
   (if the user's shell config defines any) could re-print something after `clear` runs,
   reintroducing visible artifacts. **OPEN — verify via manual repro** with both bash and zsh as
   the target pane's shell.

### Pattern 4: Tab Styling on Non-Active Tab

```bash
# Source: wezterm cli set-tab-title --help (live binary)
wezterm cli set-tab-title --tab-id 3 "purple:Dev Session"
```
[VERIFIED: wezterm cli set-tab-title --help confirms `--tab-id <TAB_ID>` "Specify the target
tab by its id" — works regardless of whether that tab is currently active. No `activate-tab`
step required before styling.]

Resolving `target_tab_id` from the `spawn`/`split-pane` pane-id output requires a follow-up
`list --format json` lookup (pane_id → tab_id) — same `[ASSUMED]` schema caveat as Pattern 2.

### Anti-Patterns to Avoid
- **Using `--cells` for splits:** requires a `list` round-trip to learn current pane dimensions
  before every split; `--percent` is self-relative and matches the equal-share formula directly
  with zero extra RPC calls.
- **Activating each pane before styling it:** `send-text --pane-id` and `set-tab-title --tab-id`
  both target arbitrary panes/tabs directly (confirmed via `--help`) — there is no need to
  `activate-pane`/`activate-tab` mid-pipeline, which would also cause visible flicker/focus-jumps
  during materialization.
- **Splitting and styling interleaved:** splitting changes pane geometry; if styling (which may
  include a `clear`) runs between splits, a subsequent split could visually disrupt an
  already-styled pane. Split-all-first, then style-all, avoids this.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing of `wezterm cli list` output | Custom string-splitting/regex JSON parser | `cli/vendor/dkjson.lua` (already vendored) | Already proven in `tab.lua` (line 132: `io.popen("wezterm cli list --format json")`); reinventing risks subtle escaping bugs on titles/paths containing quotes |
| Color palette / hex resolution | New per-phase color table | `cli/lib/title.lua` `M.ICONS`/palette + Phase 2 `pane.lua` color table | The 10-profile palette is D-locked and shared across Phase 2/3/4 — a second table would drift |
| OSC escape construction | Inline string concatenation scattered across `scene.lua` | Reuse/extract Phase 2's escape-build pure functions from `pane.lua` (D-05 pattern) | Escape-build/write-sink separation is an established, tested pattern — extracting a shared helper avoids duplicating OSC 11/1337 byte sequences in two files |
| Argument parsing for `--pane` (repeatable, multi-field spec) | Custom split-on-comma parser | `cli/vendor/argparse.lua`'s repeatable-option support (`:count("*")` or equivalent, same as used for nested subcommands) | argparse.lua already handles repeatable flags elsewhere in spec.lua; a hand-rolled parser for `--pane "color=blue,title=editor,cmd=nvim"` risks edge cases with commas inside `cmd` values |

**Key insight:** Every primitive Phase 4 needs (JSON parsing, color resolution, escape building,
arg parsing) already exists in the repo from Phases 1-3. This phase is almost pure orchestration
— the risk is NOT "what library do I need" but "what order do I call these primitives in, and
does the WezTerm mux server behave as documented under rapid sequential RPC calls" (the timing
OPEN items above).

## Common Pitfalls

### Pitfall 1: Percent math drift across sequential splits
**What goes wrong:** Computing all split percentages against the ORIGINAL pane's size instead of
the CURRENT (already-shrunk) target pane's size produces panes of wildly unequal final size.
**Why it happens:** `--percent N` is relative to the pane being split AT THE TIME of that split
call, not the original tab.
**How to avoid:** Always use the "remaining count" formula (`100/remaining`) computed
incrementally — each split's percent is relative to its own immediate target, which the formula
already accounts for.
**Warning signs:** N=4 `horizontal` layout produces 3 nearly-equal panes and 1 tiny sliver — sign
that percentages were computed against N instead of decreasing "remaining."

### Pitfall 2: Styling before all splits complete
**What goes wrong:** A `send-text` with `clear` run on pane[1] before pane[2] is split off of it
can cause the `clear` to repaint a pane that's about to be resized, producing visible flicker or
a moment of incorrect-size rendering.
**Why it happens:** Split and style are both async-ish RPC calls to the mux server; interleaving
them couples two independently-timed operations.
**How to avoid:** Strict two-phase pipeline — Phase A: all `split-pane`/`spawn` calls (collect
all pane-ids). Phase B: all `send-text` styling calls. (See Architecture Patterns diagram steps
5 and 6.)
**Warning signs:** Intermittent visual glitches that don't reproduce consistently — classic
ordering/timing symptom.

### Pitfall 3: `send-text` immediately after pane creation (race condition)
**What goes wrong:** Text sent to a brand-new pane may arrive before the shell has initialized
its line editor, causing dropped characters or the command running in a "raw" pre-prompt state.
**Why it happens:** `split-pane`/`spawn` return as soon as the mux server creates the pane —
they do NOT wait for the shell process inside it to finish initialization (PS1, rc files, etc.).
**How to avoid:** **OPEN — verify via manual repro.** Candidate mitigations to test: (a) small
fixed delay (e.g. 100-200ms) before first `send-text` to a new pane; (b) poll
`list --format json` for the new pane's `cwd`/OSC7 state as a readiness proxy (cwd-mechanism.md
confirms OSC 7 is emitted by the shell on startup, which could double as a readiness signal).
**Warning signs:** Styling/commands work when run interactively (human types them) but fail or
arrive garbled when sent immediately after scene materialization in automated testing.

### Pitfall 4: Tab-id resolution after spawn
**What goes wrong:** `spawn` returns a PANE id, not a TAB id, but `set-tab-title` needs
`--tab-id`. If the code assumes pane-id == tab-id (true only for the very first pane in a tab),
styling will silently target the wrong tab (or fail) for any tab created via `spawn`.
**Why it happens:** WezTerm's id-namespaces for panes and tabs are distinct; a freshly-spawned
tab's first pane has BOTH a pane-id and a (different) tab-id, and only `list --format json`
exposes the mapping.
**How to avoid:** Always re-run `list --format json` after `spawn` to resolve
`new_pane_id → tab_id` before calling `set-tab-title`. `set-tab-title --pane-id` is ALSO an
option per `--help` (defaults to `$WEZTERM_PANE` but accepts an explicit pane-id) — **if
`set-tab-title --pane-id <new_pane_id>` works directly (resolving the tab internally), it
avoids the extra `list` round-trip entirely.** **OPEN — verify via manual repro**: test
`wezterm cli set-tab-title --pane-id <id-of-pane-in-non-active-tab> "..."` and confirm it
targets that pane's tab correctly — if so, prefer `--pane-id` over `--tab-id` throughout
`scene.lua` and skip the tab-id resolution step entirely.

## Code Examples

### Full single-pane reuse path (D-10), N=1, current tab already has 1 pane
```bash
# Source: derived from wezterm-cli-surface.md + live --help output
# No spawn, no split. Style the current pane directly.
CURRENT_PANE="$WEZTERM_PANE"
wezterm cli send-text --pane-id "$CURRENT_PANE" --no-paste \
  'printf "\033]11;#1a3a5c\007"; clear; nvim
'
wezterm cli set-tab-title --pane-id "$CURRENT_PANE" "blue:Solo Edit"
```

### Two-pane `horizontal` layout (D-11 path), N=2
```bash
# Source: derived; spawn + split mechanics [VERIFIED: wezterm cli --help, live binary]
NEW_PANE=$(wezterm cli spawn)              # new tab, same window; prints pane-id
SECOND_PANE=$(wezterm cli split-pane --pane-id "$NEW_PANE" --right --percent 50)
# Resolve tab-id for set-tab-title (Pitfall 4 — prefer --pane-id if it works):
wezterm cli set-tab-title --pane-id "$NEW_PANE" "teal:Build & Watch"
# Style + run commands (Phase B, after all splits):
wezterm cli send-text --pane-id "$NEW_PANE"    --no-paste 'printf "\033]11;#1a3a3a\007"; clear; npm run build -- --watch
'
wezterm cli send-text --pane-id "$SECOND_PANE" --no-paste 'printf "\033]11;#0d2a3a\007"; clear; tail -f build.log
'
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| N/A — Phase 4 is greenfield within this project | First use of `spawn`/`split-pane`/multi-pane orchestration | Phase 4 (this phase) | Phases 1-3 only used `set-tab-title`/`send-text` on a SINGLE existing pane/tab; Phase 4 introduces the spawn/split/inventory primitives for the first time |

**Deprecated/outdated:** none identified — `wezterm cli` surface audited 2026-06-07 against the
currently-installed binary is current.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `wezterm cli list --format json` top-level schema shape (flat pane-array with `window_id`/`tab_id`/`pane_id`/`is_active` fields vs. nested `windows[].tabs[].panes[]`) | Pattern 2 (Inventory) | Parser in `scene.lua` would need rewriting; blocks D-10/D-11 decision logic entirely — HIGH impact, but caught immediately by Wave-0 manual repro |
| A2 | `$WEZTERM_PANE` env var is exported in every pane WezTerm spawns | Pattern 2 (Inventory) | If absent, current-pane resolution needs an alternative (e.g., `is_active` field in `list` output) — moderate impact, alternative likely exists in the same JSON |
| A3 | printf-escapes + `clear` + command as single `send-text --no-paste` payload reliably executes without timing issues immediately after pane creation | Pattern 3, Pitfall 3 | Could require a delay/readiness-poll insertion — affects `scene.lua`'s Phase-B styling loop timing, not its structure |
| A4 | `set-tab-title --pane-id <id>` resolves the owning tab internally (vs. requiring `--tab-id` + separate lookup) | Pattern 4, Pitfall 4 | If `--pane-id` doesn't work for non-owning-pane-of-tab cases, an extra `list --format json` lookup step is needed per spawned tab — adds one RPC call, no structural change |
| A5 | `horizontal`/`grid` split-sequencing algorithms (recursion direction, band-then-column ordering) as derived from 04-UI-SPEC's equal-share invariant | Pattern 1 | If the derived sequence doesn't visually match the spec's intent for N≥3, `compute_splits()` needs algorithm correction — caught by the recommended `.tmp/h<NN>-grid-layout/` repro before integration |
| A6 | bash and zsh both leave the target pane visually clean after `printf`+`clear`, with no PROMPT_COMMAND/precmd re-print interference | Pattern 3, Pitfall 3 | If a shell config re-prints something post-`clear`, D-09's "visually clean" requirement could fail for users with elaborate prompt setups — low likelihood for default configs, but worth a repro check |

## Open Questions

1. **What is the exact JSON shape of `wezterm cli list --format json`?**
   - What we know: the flag exists and is documented as an alternative output format
     [VERIFIED: wezterm cli list --help]. Prior phases (`tab.lua` line 132) already call
     `io.popen("wezterm cli list --format json")` and parse it with dkjson — so a WORKING
     parser likely already exists in `tab.lua` that can be read directly for the actual field
     names, rather than guessing.
   - What's unclear: the specific field names needed for D-10/D-11 (`tab_id`, `pane_id`,
     `window_id`, `is_active`, pane-to-tab membership).
   - Recommendation: Before writing `scene.lua`'s inventory parser, READ `cli/commands/tab.lua`
     lines ~127-150 (the existing `list --format json` consumer) to extract the confirmed field
     names from a WORKING implementation — this is likely faster and more reliable than a fresh
     manual repro, though a repro is still worthwhile to confirm pane-to-tab membership fields
     specifically (tab.lua's existing usage may only need tab-level fields, not pane-level).

2. **Does `send-text` need a delay/readiness check after `spawn`/`split-pane`?**
   - What we know: `send-text --no-paste` sends text as-typed; `split-pane`/`spawn` return
     synchronously with the new pane-id on stdout.
   - What's unclear: whether the mux server's synchronous return guarantees the target pane's
     shell is ready to receive input, or merely that the PTY exists.
   - Recommendation: `.tmp/h<NN>-scene-inject/` manual repro — script `spawn` immediately
     followed by `send-text` with a recognizable command (e.g., `echo SCENE_READY`), check
     whether output appears correctly with zero delay vs. needing `sleep 0.1`.

3. **Best layout-split algorithm verification for `grid` and `horizontal` at N≥3**
   - What we know: the equal-share `100/remaining` formula is locked by 04-UI-SPEC; `tall`/
     `tall:mirrored` are relatively unambiguous (clear main+stack structure).
   - What's unclear: the precise recursion order for `horizontal` (split-off-smallest-from-original
     vs. split-off-largest-from-newest) and `grid`'s band-then-column ordering, both derived
     here without visual confirmation.
   - Recommendation: `.tmp/h<NN>-grid-layout/` manual repro for N=2,3,4,5,6 across both layouts,
     comparing actual WezTerm pane arrangement screenshots/`list` output against the intended
     "roughly square" / "N equal columns" descriptions.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `wezterm` CLI / mux server | All scene materialization (`list`, `spawn`, `split-pane`, `send-text`, `set-tab-title`) | ✓ | `20260604-145453-eeb80972` (confirmed responsive this session via live `--help` calls) | — |
| Lua 5.4 | CLI runtime | ✓ (assumed — Phases 1-3 already ship working `wez` binary built with luastatic) | — | — |
| `cli/vendor/dkjson.lua`, `cli/vendor/argparse.lua` | JSON parsing, arg parsing | ✓ (in-repo, used by `tab.lua`/`pane.lua`) | in-repo vendored | — |

**Missing dependencies with no fallback:** none.

**Missing dependencies with fallback:** none — all required tooling confirmed present.

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1` per `.planning/config.json`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | `wez scene new` is a local CLI talking to a local mux server over a Unix socket — no authentication boundary in scope |
| V3 Session Management | no | No session concept — each invocation is stateless RPC to the mux server |
| V4 Access Control | no | Single-user local tool; mux socket permissions are WezTerm's responsibility, out of scope |
| V5 Input Validation | yes | `--pane` spec parsing (color/title/cmd fields) and shell-command construction for `send-text`/`set-tab-title` — see Threat Patterns below |
| V6 Cryptography | no | No cryptographic operations in this phase |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Shell command injection via `--pane "cmd=..."` value passed to `os.execute("wezterm cli send-text ... '<cmd>'")` | Tampering | The per-pane `cmd` field is user-supplied (the SAME user running the CLI) and is intended to be executed in the target pane — this is the FEATURE, not a vulnerability, in a single-user local-CLI context. However, shell-quoting the `cmd` string when embedding it into the `os.execute()` call that invokes `wezterm cli send-text` MUST be correct (single-quote escaping for embedded single-quotes in the user's command) to avoid the CLI's OWN shell-out breaking on special characters — this is a correctness/robustness concern, not a privilege-escalation one, since the user already has shell access. |
| `--tab-title`/`--pane title` containing the `:` delimiter used by the D-locked `"color:title"` encoding | Tampering (data integrity, not security) | `tab-title-format.md`'s "split on FIRST `:`" rule already handles titles containing additional colons — no new validation needed, just confirm `scene.lua` reuses the same encode/decode helper as `tab.lua` rather than reimplementing |
| Malformed `--pane` spec (missing `=`, unknown field name) crashing the CLI with a raw Lua error | Denial of Service (local, low severity) | argparse-level validation should reject unrecognized `--pane` spec fields with a user-facing error message (consistent with existing `pane`/`tab` command error-handling conventions) rather than propagating a Lua traceback |

No new ASVS-relevant surface beyond input-parsing robustness — this phase does not introduce
network exposure, credential handling, or privilege boundaries beyond what Phases 1-3 already
established (local CLI ↔ local mux socket).

## Sources

### Primary (HIGH confidence)
- `wezterm cli split-pane --help`, `wezterm cli spawn --help`, `wezterm cli send-text --help`,
  `wezterm cli list --help`, `wezterm cli set-tab-title --help` — live output from installed
  binary `20260604-145453-eeb80972`, captured this session
- `.planning/decisions/wezterm-cli-surface.md` — audited 2026-06-07 on Linux Pop!_OS 24.04 via
  headless `wezterm-mux-server`
- `.planning/decisions/tab-title-format.md` — D-locked `"color:title"` encoding spec
- `.planning/decisions/cwd-mechanism.md` — OSC 7 cwd-inheritance mechanism (confirms split/spawn
  inherit cwd by default)
- `cli/spec.lua` (lines 20, 46-47, 59-60, 118-145) — existing `pane`/`tab` nested-subcommand
  pattern, template for `scene` command
- `cli/commands/tab.lua` (lines 127-154) — existing working `list --format json` consumer via
  `io.popen` + `dkjson`, and `set-tab-title` invocation pattern

### Secondary (MEDIUM confidence)
- `.planning/phases/04-ad-hoc-scenes/04-CONTEXT.md` — D-01 through D-12 locked decisions
- `.planning/phases/04-ad-hoc-scenes/04-UI-SPEC.md` — Layout Geometry Contract (equal-share
  formula invariant, per-layout split-direction descriptions)
- `.planning/REQUIREMENTS.md` (SCEN-01, SCEN-02) — requirement text

### Tertiary (LOW confidence)
- `list --format json` field-name schema — not directly observed this session; recommended to
  resolve via reading `tab.lua`'s existing parser rather than fresh research (see Open Question 1)
- Layout split-sequencing algorithms for `horizontal`/`grid` at N≥3 — derived from 04-UI-SPEC's
  stated invariant, not visually verified

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies, all primitives confirmed present and working in
  prior phases or via live `--help` output this session
- Architecture: MEDIUM — core pipeline (inventory → decide → split → style → tab-title) is
  well-grounded in confirmed `wezterm cli` mechanics, but the JSON schema and exact split
  sequencing algorithms for `horizontal`/`grid` remain derivations pending manual repro
- Pitfalls: MEDIUM — timing/race pitfall (Pitfall 3) and tab-id resolution (Pitfall 4) are
  identified and have concrete repro plans, but their actual resolutions are unverified

**Research date:** 2026-06-12
**Valid until:** 30 days (stable local-CLI surface, low churn expected — re-verify if
`wezterm cli` binary version changes)

## RESEARCH COMPLETE
