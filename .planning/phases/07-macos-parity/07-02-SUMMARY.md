# 07-02 SUMMARY — real luastatic Mach-O build on macOS

Both tasks done. Task 2 required a follow-up fix beyond what the cross-AI
(opencode/xai-grok-4.6) executor delivered — documented honestly below,
including the gap it left.

## Task 1 — Homebrew lua@5.4 keg resolution in `have_luastatic()` / `build_with_luastatic()`

Dispatched via cross-AI execution (`opencode run --model xai/grok-4.6`), commit
`0facaeb`. `have_luastatic()` and the cflags probe in `build_with_luastatic()`
now try the Homebrew keg (`brew --prefix lua@5.4`) before falling back to a
generic `pkg-config`/`lua` on PATH, so a keg-only `lua@5.4` install (this Mac's
actual configuration) is correctly detected as a usable static-build toolchain.

### Task 1 verify (actual)

```
$ command -v lua5.4  # absent — keg-only, matches Task 1's stated environment
$ have_luastatic()    # now returns 0 via the keg branch
```

## Task 2 — Install luastatic, produce a real Mach-O `dist/wez`

**Cross-AI execution installed `luarocks`/`luastatic` via `luarocks install --local
luastatic` but stopped mid-task** (`opencode run` exited 0 without completing
the build/verify/commit/summary steps — a real gap: a clean exit code is not
proof of a finished task, `luastatic` is not on PATH by default from
`~/.luarocks/bin`, and no SUMMARY.md was written). Resumed and completed
manually.

**Second bug found and fixed beyond the plan's own scope** (`fc01c56`): after
exporting `~/.luarocks/bin` onto PATH and re-running `./tools/build.sh`, the
build reached `build_with_luastatic()` but failed to link:

```
Undefined symbols for architecture x86_64:
  "_luaL_openlibs", referenced from: _main in wez-95e02e.o
ld: symbol(s) not found for architecture x86_64
```

Root cause: the *library* resolution loop (as opposed to the *header* cflags
probe Task 1 already fixed) still checked the generic `/usr/local/lib/liblua.a`
candidate before any keg-specific fallback. On this Mac that generic path is a
symlink into Homebrew's plain `lua` formula (5.5.1), whose static archive is
missing `luaL_openlibs` under that name (confirmed via `nm /usr/local/lib/liblua.a
| grep luaL_openlibs` → 0 matches, vs. 1 match against
`$(brew --prefix lua@5.4)/lib/liblua.a`). Fixed by applying the same
keg-before-generic ordering to the library lookup that Task 1 already applied
to the header lookup.

### Task 2 verify (actual, after both fixes)

```
$ export PATH="$HOME/.luarocks/bin:$PATH"
$ rm -f dist/wez && ./tools/build.sh
[build] luastatic toolchain present -> static single-binary build
cc -Os wez.luastatic.c  /usr/local/opt/lua@5.4/lib/liblua.a -rdynamic -lm -ldl -o wez -I/usr/local/opt/lua@5.4/include/lua
[build] built static binary: /Users/ramon/git/personal/wezterm-setup/dist/wez
[build] verify: '/Users/ramon/git/personal/wezterm-setup/dist/wez version' OK (wez 0.1.0)

$ file dist/wez
dist/wez: Mach-O 64-bit executable x86_64

$ ./dist/wez version
wez 0.1.0

$ bash tools/verify-macos.sh   # full auto-gate, PATH still includes ~/.luarocks/bin
PASS=30  FAIL=0  SKIP=8   (up from PASS=29 FAIL=0 SKIP=9 after 07-01 alone —
                            the "luastatic present" check flipped SKIP->PASS)
```

## Deviations from plan

- Cross-AI dispatch did not finish Task 2 end-to-end despite exiting 0 — no
  error surfaced, it simply stopped after the `luarocks install` step. Resumed
  manually rather than re-dispatching, since the remaining work (export PATH,
  run build, diagnose the link failure, fix it, verify, commit) was already
  in progress and diagnosed with hard evidence.
- Found and fixed a second, closely-related keg-ordering bug in the library
  resolution loop that neither the original plan nor the cross-AI executor's
  Task 1 fix addressed — the review that shaped this plan only flagged the
  *header* (cflags) ordering, not the *library* (liblua.a) ordering, and both
  needed the identical fix.

## MACOS-PARITY-AND-FOLLOWUPS.md §C-1

luastatic Mach-O item closed with recorded evidence above. Requires
`~/.luarocks/bin` on PATH for the local dev build (matches Linux CI's own
`luarocks install --local` + PATH-export pattern in
`tools/ci-setup-toolchain.sh`), not a permanent system change.
