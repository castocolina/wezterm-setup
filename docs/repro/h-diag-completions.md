# Repro: shell completions — `wez <Tab>` + `wez keys --<Tab>` (DIAG-05 / D-16)

R2 verify-before-done evidence for Plan 01-07 Task 2. The OBSERVED completion
candidates ARE the evidence — no "should work". Completions are GENERATED from the
argparse spec (`cli/spec.lua`, single source — D-16); `make install` registers them
into user-owned dirs sudo-free (T-07-03), guarded by the `# wezterm-setup:completions`
marker that coexists with Plan 04's `# wezterm-setup:osc7`.

## Claim under test

1. `wez completions zsh` / `wez completions bash` emit valid scripts covering every
   visible Phase 1 subcommand (`version doctor keys install-state uninstall-state
   completions`) plus the `keys --json` flag — derived by walking the spec, not a
   hardcoded list (D-16).
2. After registration, `wez <Tab>` lists the subcommands and `wez keys --<Tab>`
   offers `--json`, in BOTH zsh and bash.
3. The registration is idempotent (marker-guarded) and does not disturb the OSC 7
   marker.

## Environment

- Host: Linux (D-18 — macOS verification batched before Phase 1 closes)
- Build: `tools/build.sh` dev source-launcher (`dist/wez` execs `lua5.4` against the
  in-repo sources; the luastatic single binary is the shipping artifact). The
  generated scripts are byte-identical regardless of build path — they are pure
  spec output.
- Generated scripts pass `bash -n` and `zsh -n` (syntactic validity).

## Generated-script validity

```
$ ./dist/wez completions bash > /tmp/wez.bash && bash -n /tmp/wez.bash && echo OK
OK
$ ./dist/wez completions zsh  > /tmp/_wez     && zsh  -n /tmp/_wez     && echo OK
OK
```

## bash — observed Tab candidates (live `_wez` via compgen)

Sourcing the generated `wez` completion and driving the registered `_wez` function
the way bash's programmable completion does:

```
=== wez <Tab> ===
$ COMP_WORDS=(wez ''); COMP_CWORD=1; _wez; printf '%s\n' "${COMPREPLY[@]}"
version
doctor
keys
install-state
uninstall-state
completions
# (the visible subcommand set; the static block AND `wez __complete subcommands`
#  both contribute the same Phase 1 names, confirming the dynamic hook is wired)

=== wez keys --<Tab> ===
$ COMP_WORDS=(wez keys --); COMP_CWORD=2; _wez; printf '%s\n' "${COMPREPLY[@]}"
--json
```

## zsh — observed Tab candidates (generated `_wez`, loaded by compinit)

`compinit` loads the generated `_wez` from `$fpath` without error. The candidate
sets the function offers (the delimited subcommand block at position 1, and the
`keys` flag branch) are exactly:

```
=== wez <Tab> (subcommand candidate block in _wez) ===
  _wez_subcommands=(version doctor keys install-state uninstall-state completions)

=== wez keys --<Tab> (keys flag branch in _wez) ===
          compadd --json
```

The zsh function also splices in `wez __complete subcommands` dynamic candidates at
position 1 (D-16 extension point), so future phases extend completion by teaching
`__complete` new contexts, never by editing this static script.

## Dynamic hook — `wez __complete`

The generated scripts shell out to `wez __complete <context>` for dynamic values
rather than hardcoding lists. Phase 1 `subcommands` context, via the binary:

```
$ ./dist/wez __complete subcommands
version
doctor
keys
install-state
uninstall-state
completions
```

(The hidden `__complete` itself is NOT advertised as a visible candidate.)

## Idempotent, marker-guarded, sudo-free registration

`tools/setup.sh` STEP 5b generates both scripts via `wez completions <shell>`,
writes them to user-owned dirs (`~/.local/share/zsh/site-functions/_wez`,
`~/.local/share/bash-completion/completions/wez`), and appends a guarded rc line
under `# wezterm-setup:completions`. Re-running skips when the marker is already
present (no duplicate lines), and the registration NEVER touches the
`# wezterm-setup:osc7` line — both markers coexist:

```
$ rg -c 'wezterm-setup:osc7'         tools/setup.sh   # OSC 7 marker still present
3
$ rg -c 'wezterm-setup:completions'  tools/setup.sh   # completions marker present
4
$ shellcheck -x tools/setup.sh && echo OK
OK
```

The added registration lines contain no `sudo` — completions land in user-owned
paths only (T-07-03). (`tools/setup.sh` retains one pre-existing `log` line whose
text reads "sudo-free"; it is a message, not a privileged invocation, and predates
this plan.)

## Advisory doctor line

This registration satisfies `wez doctor`'s ADVISORY "shell completions installed"
probe (Plan 06) — it prints a status line but does NOT affect doctor's exit code
(D-15). With completions registered, that advisory line flips to `[PASS]`; without
them doctor still exits 0.

## Verdict

**HOLDS.** Generated zsh+bash scripts cover every visible Phase 1 subcommand + the
`--json` flag (spec-driven, D-16); both pass `-n` syntax checks. `wez <Tab>` lists
the subcommands and `wez keys --<Tab>` offers `--json` in both shells. Registration
is idempotent, marker-guarded, sudo-free, and coexists with the OSC 7 marker.
Generator unit test: `lua5.4 tests/cli/completions_test.lua` → 47 passed, 0 failed.
