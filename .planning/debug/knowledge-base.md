# GSD Debug Knowledge Base

Resolved debug sessions. Used by `gsd-debugger` to surface known-pattern hypotheses at the start of new investigations.

---

## scene-launch-motd-race — send-text race against a slow/multi-burst shell startup (MOTD banner) leaks literal unexecuted setup text into panes
- **Date:** 2026-09-08
- **Error patterns:** literal unexecuted printf/OSC-octal text in pane, garbled setup line above MOTD banner, wez scene launch, send-text race, readiness heuristic false positive, silence-based polling, two-identical-samples heuristic, wait_for_pane_ready, scene.lua Phase B, libtinfo warning startup burst, echo marker active probe
- **Root cause(s):** cli/commands/scene.lua sent the per-pane setup escape sequence via `wezterm cli send-text --no-paste` synchronously right after pane creation with zero readiness wait for the shell to reach an interactive prompt; the first readiness-gate attempt (`wait_for_pane_ready`'s "two consecutive identical non-blank get-text samples") was itself unsound because it infers an internal shell state (readline is live and reading stdin) from an external, uncontrolled signal (screen silence) — a quiet gap between two startup output bursts (e.g. a library-load warning, then a pause, then the MOTD banner) is indistinguishable from silence at a settled prompt using passive observation alone
- **Fix:** replaced the passive silence-based heuristic with an active echo-marker probe in `wait_for_pane_ready`: send `echo <unique marker>\n` via send-text and poll `wezterm cli get-text` for a screen line that, once trimmed, is EXACTLY the marker — proof the shell actually EXECUTED the probe (its own stdout), not merely that the pty echoed the typed command text back (which happens immediately regardless of readiness). The probe is resent periodically within the same bounded poll window to guard against the probe itself being queued-but-never-delivered.
- **Files changed:** cli/commands/scene.lua, tests/e2e/lib/mux.lua, tests/e2e/tier2/scene_motd_race_e2e_test.lua
- **Why not caught:** no existing gate covered this class — the e2e battery's existing scene/pane tests all use `bash --norc` isolated shells with no MOTD/startup banner, so nothing ever exercised a real, multi-burst shell startup racing send-text. Code review also would not have caught it: the original code's missing readiness wait reads as ordinary sequential pane setup, and the first readiness-gate attempt passed a regression test whose initial draft only snapshotted the final settled screen (not the full race window) — a test-design gap that let a false-positive heuristic look correct until an independent re-run exposed it.
- **Recurrence guard:** regression test `tests/e2e/tier2/scene_motd_race_e2e_test.lua` (polls the pane's visible text throughout the race window, not just at settle-time; verified 15/15 clean with the fix applied and 1/1 + 8/8 failing when the fix is reverted via `git stash`) — plus this knowledge-base entry, so any future readiness/polling logic that infers state from output silence gets challenged against an active-probe alternative at Phase 0 recall.
---

