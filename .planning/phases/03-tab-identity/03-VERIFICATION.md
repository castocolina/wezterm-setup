# Phase 3 (Tab Identity) — Verification

**Date:** 2026-06-12
**Status:** passed (Linux; macOS deferred per D-18, consistent with Phase 2)
**Method:** goal-backward against the 5 ROADMAP success criteria + TAB-01..05, verified inline against
a real running WezTerm (`wezterm cli list` reachable) driven via `wezterm cli`, plus the Lua fixture
suites. Phase executed inline (sequential-on-main) after subagent dispatch proved non-functional in
this environment (context-compaction thrashing); each plan's RED→GREEN commits and live repros stand
as the evidence trail.

## Plans

| Plan | Status | Tests | Live repro |
|------|--------|-------|------------|
| 03-01 formatter (parse_tab_title + D-03a precedence) | Complete | format-tab-title_test 42/0 | (unit — render logic) |
| 03-02 `wez tab color` | Complete | tab_test 20/0 | docs/repro/h-tab-color.md |
| 03-03 `wez tab title` + shared cli/lib/title.lua | Complete | title_test 19/0, tab_test 23/0, pane_test 49/0 | h-tab-color.md |
| 03-04 tab completion | Complete | full suite 8/8 | docs/repro/h-tab-completion.md |

## Success criteria

### #1 — `wez tab color <name>` sets the accent (focused + unfocused); `--title` sets both in one command — PASS
- Live: `wez tab color blue` on stored `green:api` → `blue:api` (exit 0); `wez tab color green --title api`
  (fresh tab) → `green:api` in ONE `set-tab-title` write.
- Render: `format-tab-title.lua` `build_runs` applies `profile.bg` in BOTH the active and inactive
  branches (tests 8/9, 24, 28) — accent shows on focused and unfocused tabs.
- Covers TAB-01, TAB-03.

### #2 — Tab accent persists across active-pane switches within the tab — PASS (by mechanism)
- The accent is stored in `tab.tab_title` (`"<color>:<title>"`), NOT a pane user var; the formatter
  resolves the accent from `tab.tab_title` via `parse_tab_title`, which is pane-independent. Switching
  the active pane does not touch `tab.tab_title`, so the color cannot reset on pane switch.
- Verified at the logic level (handler tests 24–27) and via the persisted stored value in the live
  repro. A GUI multi-pane visual confirmation is listed under Recommended visual spot-check.
- Covers TAB-02.

### #3 — Pane color takes visual priority over tab color when both set — PASS
- Handler: `accent_color = (uv.WEZTERM_TAB_COLOR ~= "" and uv.WEZTERM_TAB_COLOR) or tabColor` — pane
  var wins, empty pane var treated as unset. Test 27: `tab_title="blue:api"` + pane `WEZTERM_TAB_COLOR=navy`
  → navy accent (`#1a2040`), tab-prefix title still applied.
- Covers TAB-04.

### #4 — Active tab visually distinct regardless of accent — PASS
- `build_runs(is_active=true)` always emits the bold green ` ●-> ` indicator + white label, independent
  of the accent profile (tests 8, 14, 28). Unchanged from Phase 2 (TAB-05).

### #5 — Completion: `wez tab color <Tab>` → profiles; `wez tab title`/`--title` → icons — PASS
- `wez __complete tab-colors` → 10 names + `reset` (11); `wez __complete tab-icons` → 22 icon names,
  byte-identical to `pane-icons` (shared `cli/lib/title.lua`, D-03).
- Generated zsh + bash scripts contain the `tab` nested dispatch; `zsh -n`/`bash -n` parse clean.
- Functional bash repro: `_wez`/`COMPREPLY` offers the profiles for `tab color` and icon names for
  `tab title`; `pane` completion unaffected.

## Requirement traceability

| REQ | Plans | Verified by |
|-----|-------|-------------|
| TAB-01 | 03-01, 03-02, 03-04 | live `wez tab color`; formatter render tests; completion repro |
| TAB-02 | 03-01, 03-02 | tab_title storage mechanism + handler tests 24–27 |
| TAB-03 | 03-03, 03-04 | live `wez tab title` + combined `--title`; completion repro |
| TAB-04 | 03-01 | handler precedence test 27 (pane overrides tab) |
| TAB-05 | 03-01 | active-indicator tests 8/14/28 |

All 5 requirements covered by ≥1 plan; all 5 success criteria met.

## Gates

- **Regression gate:** `./tools/run-tests.sh` → all 8 unit files pass. (`wez doctor` integrity gates
  report `wez`-not-installed in this dev sandbox — expected, pre-existing, NOT a Phase 3 regression.)
- **Schema drift:** N/A — pure Lua, no ORM/schema files.
- **Code review:** performed inline (the agent-based gsd-code-review is non-functional in this
  environment). Diff is +516/−34 across 10 files; every behavior is covered by a fixture suite and/or
  a live repro. No blocking issues found. The pane.lua refactor is byte-identical-behavior
  (pane_test 49/0). The one intentional plan deviation (`--title` is `:option`, not `:flag`, since a
  flag cannot carry the title value) is documented in 03-03-SUMMARY.md.

## Recommended visual spot-check (non-blocking)

Not required to pass, but a ~2-minute GUI confirmation closes the only gap not eyeballed headlessly:
1. `wez tab color blue` → the tab bar segment renders blue on the focused tab AND when the tab is
   unfocused.
2. Open a second pane in that tab, switch focus between panes → the blue accent stays (TAB-02 visual).
3. In a pane, `wez pane color navy` while the tab is `wez tab color blue` → navy wins visually (TAB-04).
4. The active tab keeps the bold ` ●-> ` indicator under any/no accent (TAB-05).

## Verdict

Phase 3 goal — "users can assign a persistent accent color and title to any tab via the CLI" — is
achieved and verified. All plans complete, all requirements covered, all success criteria met at the
logic + live-CLI level. Status: **passed**.
