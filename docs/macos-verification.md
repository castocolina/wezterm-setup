# macOS Verification Runbook — wezterm-setup

> A self-driven manual verification runbook for confirming **macOS parity** of every
> shipped wezterm-setup capability. Drive it top-to-bottom on a real Mac, ticking each
> `- [ ]` as you observe the stated result. Record outcomes in the
> [Results Table](#results-table) and log any macOS-specific divergence in
> [macOS Deviations](#macos-deviations-feed-back-into-the-parity-pass).

## Scope & status

- **Target:** macOS — both **Apple Silicon** (`arm64` → normalized `aarch64`) and **Intel**
  (`x86_64`). Where the architecture matters (binary download asset names, the luastatic C
  link step), it is called out inline.
- **Decision D-18:** macOS parity for every shipped feature is a **hard v1 requirement**, but
  the macOS verification work was deliberately **deferred to a single batched cross-platform
  pass**. Many feature commits are marked "Done (Linux); macOS deferred D-18" in
  `.planning/REQUIREMENTS.md` / `.planning/ROADMAP.md`. **This runbook IS that batched pass.**
- **Linux baseline:** every capability below is already verified on Linux (Wayland + X11).
  The goal here is to confirm the same observable behavior on macOS, and to capture any
  BSD-vs-GNU / `Cmd`-vs-`Super` / windowing divergence that the parity pass must fix.
- **Shipped (Linux-verified, to confirm on macOS):** `wez pane …` (Phase 2), `wez tab …`
  (Phase 3), and all of Phase 5 — `scene launch <name>`, copy-if-absent seeding, AND the
  dynamic `scene launch <Tab>` completion (SCEN-05, Plan 05-04 — now wired into `complete.lua`
  via the `scene-names` `__complete` context). See the Named Scenes section for the expected
  completion behavior.

### Known macOS risk areas (read before you start)

These are flagged at the relevant step as **⚠ macOS risk to confirm**. They come from reading
the actual scripts, not assumption:

| Risk | Where | Why it may break on macOS |
|------|-------|---------------------------|
| `sha256sum` | `tools/build.sh` `download_release()` | macOS ships **no `sha256sum`** by default — it has `shasum -a 256` (and `/sbin/md5`). The checksum-verified release-download path (`WEZ_REMOTE_BOOTSTRAP=1`) will fail at the verify step. Local source builds (luastatic / dev launcher) do NOT hit this. |
| `od` / `wc` / `tar -tJf` / `tar -xJf` | `tools/bootstrap-wezterm.sh` | BSD `tar` does accept `-J` (xz) on modern macOS, and `od -An -tx1` / `wc -c` are POSIX — but the **entire Linux fetch/extract branch is `.Ubuntu<base>.tar.xz`-specific** and is NOT taken on macOS. The macOS install branch (`install_macos`) is **design-only**: it logs and returns 0 without placing anything (D-06/D-18). |
| `mktemp` / `mktemp -d` | bootstrap + build | BSD `mktemp` requires a template (`-t`) in some invocations; the scripts use bare `mktemp` / `mktemp -d`, which works on macOS but creates files under `$TMPDIR`. Confirm no template error. |
| `install -m 0755` | `tools/setup.sh` STEP 3 | BSD `install` supports `-m`; confirm no flag drift. |
| `cp -R` | `tools/setup.sh` STEP 4 | `-R` is portable (BSD + GNU). `cp -R src/. dst/` "copy contents" trailing-dot semantics are GNU-friendly; **⚠ confirm BSD `cp` copies the directory *contents* and not a literal `.` entry.** |
| `ls -1 -- <dir>` | `seed_scenes.lua`, `scene.lua` | POSIX; works on macOS `ls`. Confirm. |
| Config path | resolvers in code | **CONFIRMED by reading the code:** wezterm-setup uses the **XDG-style `~/.config/wezterm/…`** path on BOTH platforms — it does NOT use `~/Library/Application Support/…`. WezTerm itself reads `~/.config/wezterm/wezterm.lua` on macOS, so this is correct. **Do not "fix" paths to `~/Library`.** |
| `Super` vs `Cmd` | `config/wezterm-setup/keybindings.lua` | Bindings are cross-platform-identical except the OS-native modifier: `Super+K` on Linux is `Cmd+K` on macOS (FOUND-02/05). Verify the modifier maps to the **Command** key. |
| Clipboard | WezTerm copy/paste bindings | macOS clipboard is `pbcopy`/`pbpaste`-backed inside WezTerm; confirm copy/paste bindings behave. |
| Windowing | scene materialization | The "reuse a 1-pane tab / spawn a new tab in the same window, never a new OS window" contract assumes WezTerm-as-multiplexer; confirm macOS WezTerm honors the same mux semantics (no Aqua window-per-tab surprise). |

---

## Prerequisites & environment

Assumptions and one-time setup. Tick each as you satisfy it.

- [ ] **macOS version:** macOS 12 (Monterey) or newer assumed. Record your exact version
      (`sw_vers -productVersion`) in the results notes.
- [ ] **Architecture noted:** run `uname -m`. `arm64` (Apple Silicon) or `x86_64` (Intel).
      Confirm `tools/lib/platform.sh` normalizes it: `bash tools/lib/platform.sh` should print
      `os=macos arch=aarch64` (Apple Silicon) or `os=macos arch=x86_64` (Intel).
- [ ] **No sudo:** every install step must succeed **without `sudo`** (hard constraint). If any
      step prompts for a password, that is a **failure** to record, not a workaround.
- [ ] **Xcode Command Line Tools / C compiler present:** the single-binary `wez` is produced by
      `luastatic`, which **links through a C compiler**. Confirm `cc --version` or
      `clang --version` works. Install with `xcode-select --install` if absent.
      **⚠ macOS risk to confirm:** the luastatic link step on macOS uses `clang` and the
      Homebrew/system `liblua5.4` — confirm it produces a runnable Mach-O binary, not just a
      Linux-tested path.
- [ ] **Lua 5.4 toolchain (for building + tests):** `lua5.4 --version` works (e.g.
      `brew install lua@5.4`; note Homebrew may install it as `lua` — set
      `LUA_BIN=lua` for the test harness if `lua5.4` is not on PATH).
- [ ] **luastatic present (for the shipping binary):** `command -v luastatic`. If absent, the
      build falls back to a **dev source-launcher** (a shim that execs `lua5.4` against the
      in-repo sources) — fine for running `wez`, but NOT the shipping artifact. Record which
      path you exercised.
- [ ] **WezTerm installed:** `wezterm --version` works and its date-stamp meets the pinned
      minimum (`20260604-145453` or newer). The bootstrap **reuses** an adequate existing
      install untouched (D-07).
      **⚠ macOS risk to confirm:** if WezTerm is **missing/outdated**, the macOS bootstrap
      branch (`install_macos` in `tools/bootstrap-wezterm.sh`) is **design-only** — it logs
      "would place WezTerm.app … under ~/Applications" and returns 0 **without downloading or
      placing anything** (D-06/D-18). So you MUST pre-install WezTerm (e.g.
      `brew install --cask wezterm` or download `WezTerm-macos-*.zip` → `~/Applications`)
      before running the installer, and record that the bootstrap auto-install path is a
      known macOS gap.
- [ ] **PATH:** `~/.local/bin` is on `PATH` (the installer places `wez` there). Add it if the
      installer prints the "not on PATH" note.
- [ ] **Gatekeeper / quarantine / codesign (macOS-ONLY — do this BEFORE the first `wez`/WezTerm
      launch).** Two distinct traps:
      - **Downloaded `WezTerm.app`** carries the `com.apple.quarantine` xattr → Gatekeeper blocks
        the first launch ("cannot be opened because the developer cannot be verified"). Clear it
        with `xattr -dr com.apple.quarantine /Applications/WezTerm.app` (or `~/Applications/…`),
        or right-click → Open once. Record whether the install flow hits this.
      - **Self-built `dist/wez` Mach-O (Apple Silicon):** an unsigned binary produced by
        `luastatic` may be SIGKILLed on first run on `arm64` ("killed: 9"). If so, ad-hoc sign it:
        `codesign -s - dist/wez` and confirm `./dist/wez version` then runs. Record whether the
        build output needs this on your machine.
      **⚠ macOS risk to confirm:** neither the installer nor `build.sh` currently strips quarantine
      or codesigns — if these are needed, that is a parity gap to fix
      (`.planning/MACOS-PARITY-AND-FOLLOWUPS.md` §C-1).
- [ ] **Repo checkout:** you are at the repo root (`git rev-parse --show-toplevel`).
- [ ] **Shells available:** both **zsh** (macOS default) and **bash** for the completion checks.
      Note: macOS bash is the old 3.2; the completion *scripts* are generated by `wez`, but
      `bash-completion` itself may need `brew install bash-completion@2`. Record if bash
      completion needs the Homebrew package.

---

## Unattended supply→consume loop evidence (Plan 07-04, D-09/D-10/D-11)

> Recorded by the autonomous executor on this Intel Mac (`uname -m` = `x86_64`,
> `os=macos arch=x86_64`). The loop dispatches the release workflow on the LIVING
> BRANCH, waits non-interactively for green, runs the real E2E install, probes
> quarantine (D-07), and green-gates the stable tag (D-10). `gh` 2.93 authed as
> `castocolina`.

### §A — Dispatch dry-run on the living branch (Task 1, D-09/D-11)

- **Living branch:** `gsd/phase-07-macos-parity` (dispatched via
  `gh workflow run release.yml --ref "$(git branch --show-current)"`).
- **Autonomous auto-fix loop (D-09):**
  - **Attempt 1 — run `27970794764` → `failure` (all 3 legs red).** `gh run view --log-failed`
    surfaced two distinct bugs: (1) the D-11 `cli/spec.lua` version stamp used a `RETURN`
    trap whose restore the luastatic `( )` subshell fired early
    (`mv: cannot stat '…/cli/spec.lua.bak.<pid>'`, hit on ubuntu + macos-14); (2) the
    Intel leg failed earlier in toolchain install —
    `luarocks install luastatic` could not write `/usr/local`
    (`install requires exclusive write access to /usr/local … Permission denied`, exit 4).
  - **Fix (commit `d85fa27`):** replaced the RETURN-trap restore with an explicit
    `mktemp` save + post-bundle restore; switched `install_macos` to
    `luarocks install --local luastatic` (+ `~/.luarocks/bin` on `$GITHUB_PATH`).
  - **Attempt 2 — run `27970971643` → `success`.** `gh run watch <id> --exit-status`
    returned **exit 0** (the dispatch dry-run is **green**). No further iteration; the
    same failure did NOT recur, so no human stop was triggered.
- **Branch-built version (D-11):** on this non-`main` branch the embedded version carries
  the `+<branchname>` suffix — build log line
  `[build] D-11: stamped version -> nightly-20260622+gsd-phase-07-macos-parity`, and the
  built binary reports `wez nightly-20260622+gsd-phase-07-macos-parity`. The GitHub
  release **tag** stays bare `nightly-20260622` (`+` is not tag-name-safe).
- **macOS assets published** to the `nightly-20260622` prerelease (`prerelease=true`):
  `wez-macos-x86_64`, `wez-macos-x86_64.sha256`, `wez-macos-aarch64`,
  `wez-macos-aarch64.sha256` (plus the linux pair). Confirmed via
  `gh release view nightly-20260622 --json assets`.
- **arm64 in-build smoke (macos-14 leg, Open Q3 / D-06 — no local Silicon needed):**
  `codesign --verify --verbose dist/wez` → `dist/wez: valid on disk` +
  `dist/wez: satisfies its Designated Requirement`; `./dist/wez version` →
  `wez nightly-20260622+gsd-phase-07-macos-parity`.
- **actionlint:** NOT re-run here — Plan 07-03 owns the static lint (it ran clean there);
  this task is the live dispatch run only.

### §B — Real E2E install of THIS branch's artifact (Task 2, D-07)

Run on this Intel Mac (`os=macos arch=x86_64`) from a truly clean state (no prior
`~/.config/wezterm/wezterm.lua`, no `~/.local/bin/wez`), against the rebuilt
branch-built nightly asset (the green run `27971403588` on HEAD `eddef2e`):

```
$ WEZ_REF=gsd/phase-07-macos-parity WEZ_CHANNEL=nightly bash tools/install.sh < /dev/null
[bootstrap] placed /Users/ramon/Applications/WezTerm.app
[bootstrap] installed: wezterm 20260622-120102-6ff54928
[build] Lua toolchain absent -> release-download fallback (channel=nightly, tag=nightly-20260622, wez-macos-x86_64)
[build] checksum verified for wez-macos-x86_64           # <-- integrity gate BEFORE chmod +x
[build] verify: '.../dist/wez version' OK (wez nightly-20260622+gsd-phase-07-macos-parity)
[setup] installed wez -> /Users/ramon/.local/bin/wez
[setup] delegating install-state decision to wez install-state…
wez install-state: managed block installed (new /Users/ramon/.config/wezterm/wezterm.lua)
```

- **Integrity gate (T-07-13):** `checksum verified for wez-macos-x86_64` printed BEFORE
  `chmod +x` — the per-asset SHA-256 gate passed; never an unverified install.
- **Branch-built artifact (D-11):** `wez version` → `wez nightly-20260622+gsd-phase-07-macos-parity`
  (matches the published nightly asset; carries the `+branchname` suffix → THIS branch's
  artifact, not main's).
- **`install_macos` placement (INST-06):** `~/Applications/WezTerm.app` placed (07-02 path),
  inner binary `wezterm 20260622-120102-6ff54928`.
- **`wez doctor` exits 0** (`doctor_exit=0`): all 5 core integrity gates PASS — including the
  fresh-install backup-gate exception (`[PASS] timestamped backup exists — fresh install (no
  prior wezterm.lua) — no backup needed`). The only `[FAIL]` is the **advisory** live-session
  probe (expected headless; never affects exit code).
- **Single managed block (INST-01):** the freshly-created `wezterm.lua` carries exactly one
  managed block wrapping `require('wezterm-setup').apply(config)` over a `config_builder()` base.
- **Gatekeeper clears:** `WezTerm.app/Contents/MacOS/wezterm --version` → exit 0 (no
  SIGKILL); the managed config loads cleanly (`show-keys --lua` succeeds, no error overlay).
- **D-07 quarantine probe (verify-then-decide):**
  `xattr -p com.apple.quarantine ~/.local/bin/wez` → **no quarantine** (curl download carries
  none, as RESEARCH Pitfall 5 / A4 predicted); `xattr -p com.apple.quarantine
  ~/Applications/WezTerm.app` → **no quarantine** either. Gatekeeper did NOT block first
  launch. **DECISION: install.sh is left UNCHANGED** (the D-07 default outcome) — no
  `xattr -dr com.apple.quarantine` strip is added; the runbook keeps its manual `xattr -d` /
  right-click-open fallback note for any future browser-download case. install.sh remains
  sudo-free.

**Live E2E bug fixed inline (Rule 2):** the first E2E run aborted at the final step —
`wez install-state: cannot read ~/.config/wezterm/wezterm.lua: No such file or directory`
(exit 1) — because on a clean machine there was no `wezterm.lua` to inject the managed block
into, and `wez doctor` then failed its core "timestamped backup exists" gate (a fresh creation
takes no backup). Both were fixed (commit `eddef2e`): install-state now SEEDS a minimal
config-builder base and CREATES the file on a fresh install; doctor's backup gate passes on a
fresh creation. The fixes were rebuilt into the nightly asset via the green re-dispatch
`27971403588` and re-verified end-to-end (the transcript above is the post-fix run).

### §C — Green-gated stable tag decision (Task 3, D-10)

_(filled by Task 3 below)_

---

## Section 1 — Build & test the CLI (no install side effects)

Run these first; they have no install side effects and gate everything below.

- [ ] **Run the unit suite.** `LUA_BIN=lua5.4 ./tools/run-tests.sh` (or `make test`). Expect
      `run-tests: all <N> file(s) passed` and exit 0. If `lua5.4` is the Homebrew `lua`, use
      `LUA_BIN=lua ./tools/run-tests.sh`.
      **⚠ macOS risk to confirm:** the harness uses `mapfile`/`find … -name`/`case` (bash);
      macOS `/bin/bash` is 3.2 and lacks `mapfile`. The script's shebang is `/usr/bin/env bash`
      — confirm it resolves to a bash that supports `mapfile` (Homebrew bash 4+), or the test
      discovery loop fails. Record which bash ran it.
- [ ] **Build the binary.** `./tools/build.sh`. With the luastatic toolchain present, expect
      `[build] built static binary: …/dist/wez` and `[build] verify: '…/dist/wez version' OK`.
      Without luastatic, expect `[build] built dev launcher: …` instead (record which).
- [ ] **Smoke the artifact.** `./dist/wez version` prints the version and exits 0.

---

## Section 2 — Install / uninstall (non-destructive)

Verifies INST-01..06. **Do this against a real `~/.config/wezterm/wezterm.lua`** (back it up
yourself first if precious, or point the install at a scratch `WEZTERM_CONFIG_DIR`).

- [ ] **Pre-state capture.** Note whether `~/.config/wezterm/wezterm.lua` exists and copy it
      aside (`cp ~/.config/wezterm/wezterm.lua /tmp/wezterm.lua.pre` if present).
- [ ] **Clean install.** `make install` (≡ `./tools/setup.sh`). Expect, on stdout:
      `[setup] platform: os=macos arch=…`, a bootstrap line (reusing existing WezTerm — see
      prereq risk if missing), `installed wez -> ~/.local/bin/wez`,
      `placing managed config -> ~/.config/wezterm/wezterm-setup`, seed-scenes lines (Section
      6), OSC 7 + completions registration lines, and finally the install-state result. Exit 0.
- [ ] **Single managed block (INST-01).** `grep -c 'wezterm-setup managed block' ~/.config/wezterm/wezterm.lua`
      returns exactly the sentinel pair (open `-- >>> wezterm-setup managed block >>>` and close
      `-- <<< wezterm-setup managed block <<<`), wrapping a `require('wezterm-setup').apply(config)`
      augment. Everything outside the block is byte-identical to your pre-state copy.
- [ ] **Timestamped backup (INST-02).** `ls ~/.config/wezterm/wezterm.lua.bak.*` shows a UTC-stamped
      backup whose contents equal your pre-state copy.
- [ ] **Config tree placed.** `ls ~/.config/wezterm/wezterm-setup/` shows `init.lua`,
      `keybindings.lua`, `cwd.lua`, `format-tab-title.lua`, `shell-integration/`.
      **⚠ macOS risk to confirm (`cp -R`):** confirm `cp -R config/wezterm-setup/. dst/` copied
      the *contents* (no stray `.` directory entry) on BSD `cp`.
- [ ] **Re-install prompt, TTY (INST-03).** Run `./tools/setup.sh` again **in an interactive
      terminal**. Expect a prompt offering override / restore / skip. Choose **skip**; confirm
      the block count stays 1 and nothing is rewritten.
- [ ] **Re-install abort, no TTY (INST-03 / D-03).** `./tools/setup.sh < /dev/null` (no TTY).
      Expect it to **abort non-zero** with explicit `--force` / `--restore` / `--skip` guidance.
      `echo $?` is non-zero (3).
- [ ] **Re-install `--force` (INST-01 idempotence).** `./tools/setup.sh --force < /dev/null`
      re-yields **exactly one** managed block (no duplicate sentinels).
- [ ] **WezTerm picks up the config.** Open a fresh WezTerm window; it loads without a config
      error (the GUI shows no red error overlay). WezTerm hot-reloads `wezterm.lua` on save.
- [ ] **Granular uninstall — keep config (INST-05).** `make uninstall KEEP_CONFIG=1`. Expect the
      managed block + `wez` binary removed but `~/.config/wezterm/wezterm-setup/` preserved.
- [ ] **Full uninstall (INST-04).** `make uninstall`. Expect the managed block excised so the
      surrounding user lines are **byte-identical** to your pre-state copy
      (`diff <(grep -v 'wezterm-setup' …) /tmp/wezterm.lua.pre` — or simpler: confirm no
      sentinel remains and user lines match), the `wez` binary gone, and backups removed
      (unless `KEEP_BACKUP=1`). Exit 0.
- [ ] **Reinstall for the rest of the runbook.** `./tools/setup.sh --force` so the remaining
      sections run against a live install.

---

## Section 3 — Foundation + `wez doctor`

Verifies FOUND-01..05 and DIAG-01.

- [ ] **`wez doctor` is green on a healthy install (DIAG-01).** `wez doctor; echo $?` exits **0**.
      The four core integrity gates pass: binary-on-PATH, sentinel well-formed, config dofiles
      cleanly, backup exists. Advisory lines (completions installed, live session) print but
      never flip the exit code (D-15).
- [ ] **`wez doctor` fails loudly when broken (DIAG-01).** Temporarily remove the managed block
      (or run after `make uninstall`); `wez doctor; echo $?` exits **non-zero** and names the
      failed gate. Restore with `./tools/setup.sh --force` afterward.
- [ ] **CWD inheritance (FOUND-01).** ⚠ This is the **headline macOS-deferred item**. In a
      WezTerm window: `cd ~/some/dir`, then split a pane (default `Cmd+Shift+"` / `Cmd+Shift+%`
      or the shipped split binding) and open a new tab (`Cmd+T`). The new pane/tab should start
      in `~/some/dir`, not `$HOME`. This relies on the shipped OSC 7 shell integration
      (`shell-integration/osc7.sh` / `.zsh`) being sourced by your `~/.zshrc` / `~/.bashrc`.
      **⚠ macOS risk to confirm:** open a NEW shell so the installer-added
      `# wezterm-setup:osc7` source line is active, then verify OSC 7 fires (cwd inherited).
      Record pass/fail per shell.
- [ ] **Clear screen + scrollback (FOUND-02).** Press **`Cmd+K`** (macOS native modifier; this
      is `Super+K` on Linux). The screen AND scrollback clear instantly. **⚠ confirm the
      binding maps to the Command key, not Control.**
- [ ] **Curated bindings present (FOUND-03).** Exercise a few: new tab, close tab, next/prev
      tab, split pane, zoom pane, font zoom, word navigation. Confirm each fires (full list via
      `wez keys`, Section 4).
- [ ] **Cross-platform parity except modifier (FOUND-05).** Spot-check that the macOS bindings
      match the Linux set with `Cmd` substituted for `Super`. Note any binding that is silently
      missing or remapped.

---

## Section 4 — Diagnostics (`wez keys`)

Verifies DIAG-02..05.

- [ ] **Grouped listing (DIAG-02).** `wez keys` prints active bindings grouped by category
      headers (Tabs, Panes, Navigation, …).
- [ ] **Conflict + source classification (DIAG-03).** `wez keys` flags any conflicts and labels
      each binding as `[setup]` (wezterm-setup), user-defined, or WezTerm default. On a clean
      install with the config applied, `[setup]` labels resolve (FOUND-04).
      **⚠ macOS risk to confirm:** `wez keys` reads `wezterm show-keys --lua`; confirm the
      macOS WezTerm emits the same show-keys text shape the parser expects (no macOS-only
      key-table noise leaks in).
- [ ] **JSON output (DIAG-04).** `wez keys --json | <json validator>` (e.g.
      `python3 -m json.tool`) parses cleanly and exits 0.
- [ ] **Completions installed (DIAG-05).** The installer wrote `_wez` to
      `~/.local/share/zsh/site-functions/` and `wez` to
      `~/.local/share/bash-completion/completions/`, and registered loader lines under
      `# wezterm-setup:completions` in `~/.zshrc` / `~/.bashrc`. Open a **new zsh**: `wez <Tab>`
      completes subcommands (`doctor`, `keys`, `scene`, `tab`, `pane`, …). `wez keys --<Tab>`
      offers `--json`.
      **⚠ macOS risk to confirm:** zsh `compinit` may warn about insecure directories under a
      Homebrew-owned `fpath`; confirm completion still loads (you may need `compinit -u`). For
      bash, confirm `bash-completion@2` is installed so `wez <Tab>` works in bash too.
- [ ] **Value completion for every context (DIAG-05).** In a new zsh, confirm each of these
      completes the right VALUES (not just flag names), driven by `wez __complete`:
  - [ ] `wez pane color <Tab>` → palette color names + `reset` (`wez __complete pane-colors`)
  - [ ] `wez pane title <Tab>` → icon names (`wez __complete pane-icons`)
  - [ ] `wez tab color <Tab>` → palette + `reset` (`wez __complete tab-colors`)
  - [ ] `wez tab title <Tab>` → icon names (`wez __complete tab-icons`)
  - [ ] `wez scene launch <Tab>` → recipe names (`wez __complete scene-names`)
        Sanity-check each context directly too: `wez __complete pane-colors`, `… tab-colors`,
        `… pane-icons`, `… tab-icons` print non-empty sorted token lists, exit 0.
      **Note (`bg` == `pane color`):** there is no separate `bg`/`opacity` command — a pane
      background is set via `wez pane color`. Don't look for a `bg` completion; it doesn't exist.

---

## Section 5 — Pane & Tab identity

Pane identity (PANE-01..04) and Tab identity (TAB-01..05) are implemented. Run inside a live
WezTerm session.

### Pane identity

- [ ] **Set pane color (PANE-01).** In a focused pane: `wez pane color blue` visibly changes the
      pane background. Try a hex value too: `wez pane color '#3366ff'`.
- [ ] **Reset pane color (PANE-02).** `wez pane color reset` restores the default background.
- [ ] **Pane title (PANE-03).** `wez pane title "api server"` shows that title in the tab bar
      when the pane is focused.
- [ ] **Persistence across focus (PANE-04).** Split into two panes, color/title one, switch focus
      away and back — the color/title persist with no flicker/reset.
      **⚠ macOS risk to confirm:** pane color uses an OSC 1337 `SetUserVar` escape; confirm the
      macOS WezTerm honors the user-var → background mapping identically to Linux.

### Tab identity

- [ ] **Set tab color (TAB-01).** `wez tab color green` sets the tab accent, visible on both the
      focused and an unfocused tab.
- [ ] **Color persists on pane switch (TAB-02).** Switch the active pane within the tab; the tab
      accent does not reset.
- [ ] **Combined color + title (TAB-03).** `wez tab color blue --title "api"` sets both at once.
- [ ] **Pane color wins over tab color (TAB-04).** With both set on the same tab, the pane-level
      color takes visual priority.
- [ ] **Active tab distinct (TAB-05).** The active tab is visually distinguishable from inactive
      tabs regardless of accent color.
      **⚠ macOS risk to confirm:** tab color rides the `set-tab-title` `"color:title"` prefix
      convention and the shipped `format-tab-title.lua`; confirm the macOS tab bar renders the
      accent + active indicator the same way (font/emoji glyph width can differ on macOS).

---

## Section 6 — Ad-hoc scenes (`wez scene new`)

Verifies SCEN-01..02. Run inside a live WezTerm session.

- [ ] **Build a tall 2-pane scene (SCEN-01).**
      `wez scene new --layout tall --pane shell --pane shell --color green --title dev`
      produces a correctly arranged tab: two panes, green accent, title `dev`. Silent on stdout
      on success.
- [ ] **All four layouts (SCEN-02).** Run once each and confirm the pane arrangement is correct:
  - [ ] `wez scene new --layout tall --pane shell --pane shell`
  - [ ] `wez scene new --layout tall:mirrored --pane shell --pane shell`
  - [ ] `wez scene new --layout grid --pane shell --pane shell --pane shell --pane shell`
  - [ ] `wez scene new --layout horizontal --pane shell --pane shell`
- [ ] **Per-pane startup commands.** `wez scene new --layout grid --pane 'cmd=top' --pane 'docker ps' --pane shell --pane shell`
      runs each pane's command.
- [ ] **Bad layout / color rejected before building (validate-before-emit).**
      `wez scene new --layout bogus --pane shell` exits non-zero with
      `unknown layout 'bogus' — expected one of: tall, tall:mirrored, grid, horizontal` and
      builds **zero** panes.
- [ ] **Layout completion (SCEN-02 completion).** `wez scene new --layout <Tab>` completes the
      four layout names `tall tall:mirrored grid horizontal` (driven by
      `wez __complete scene-layouts`). Fixed 2026-06-14 (was A-1); proven at runtime in bash.
      **⚠ macOS confirm (zsh):** the zsh value-after-flag arm uses `${words[CURRENT-1]}` under
      `_arguments`; bash uses `$prev` (proven). Confirm `wez scene new --layout <Tab>` actually
      lists the layouts in **zsh** on macOS (and bash), not just the flag names.
- [ ] **Scene accent-color completion.** `wez scene new --color <Tab>` completes the 10 palette
      colors (no `reset` — creation, not reset), driven by `wez __complete scene-colors`.
      **⚠ macOS risk to confirm:** materialization reuses a 1-pane tab or spawns a new tab in
      the **same window** — never a new OS window. Confirm macOS WezTerm does not pop a separate
      Aqua window per scene.

---

## Section 7 — Named scenes (`scene launch` + completion + seeding) — ACTIVE PHASE

This is the **most detailed** section because Phase 5 is the active phase. Expected copy and
exit codes below come **verbatim** from `.planning/phases/05-named-scenes/05-UI-SPEC.md` and the
shipped `cli/commands/scene.lua` / `cli/commands/seed_scenes.lua`.

> **Implementation status (Phase 5 complete on Linux):**
> `scene launch` (`run_launch`), the `scenes_dir` resolver, the `list_recipe_names` provider, the
> copy-if-absent seeder, AND the dynamic `scene-names` completion context are all **implemented**.
> Plan 05-04 wired the `scene-names` `__complete` context into `cli/commands/complete.lua` and the
> nested `scene)`→`launch)` arm into the generated zsh/bash scripts. The completion step below is
> a real check, not expected-absent.

### 7a — Install-time seeding (SCEN-06)

- [ ] **Fresh seed messaging.** On a fresh install (no `~/.config/wezterm/wezterm-setup/scenes/`),
      the installer (STEP 4b → `wez seed-scenes`) prints **one line per newly written recipe**,
      verbatim: `seeded scene recipe: ai`, `seeded scene recipe: dev`, `seeded scene recipe: docker`
      (alphabetical). The three files now exist:
      `ls ~/.config/wezterm/wezterm-setup/scenes/` → `ai.toml  dev.toml  docker.toml`.
- [ ] **Seeded content is correct (SCEN-06 table).** `cat ~/.config/wezterm/wezterm-setup/scenes/docker.toml`
      shows `layout = "grid"`, `color = "teal"`, and four `[[panes]]`:
      `docker stats`, `docker ps`, `docker compose logs -f`, `shell`. (`dev` = tall/green/2 shell;
      `ai` = tall/purple/2 shell.)
- [ ] **User edits survive reinstall (copy-if-absent, SCEN-06).** Edit `dev.toml` (e.g. change its
      title), then re-run `./tools/setup.sh --force` (or `wez seed-scenes` directly with the same
      `WEZTERM_SETUP_DIR`). Expect the seeder to print `kept existing scene recipe: dev`
      (and `kept existing scene recipe: ai` / `docker`) — **never "skipped", never "seeded"** for
      a file that exists — and your edit to `dev.toml` is **byte-identical** afterward.
- [ ] **Direct seeder run.** `WEZTERM_SETUP_DIR=$HOME/.config/wezterm/wezterm-setup wez seed-scenes`
      on an already-seeded dir prints three `kept existing scene recipe: …` lines and exits 0.
      **⚠ macOS risk to confirm:** the seeder lists dirs via `ls -1 -- <shquoted dir>` and copies
      bytes via Lua `io`; no GNU-only flags. Confirm `ls -1` and the path resolver behave on macOS
      (HFS+/APFS case-insensitivity should not matter for the lowercase basenames).

### 7b — `wez scene launch <name>` happy path (SCEN-03 / SCEN-04)

- [ ] **Launch a seeded recipe.** In a live WezTerm session, `wez scene launch dev` builds the
      same tab an equivalent `wez scene new --layout tall --pane shell --pane shell --color green`
      would (SCEN-04 equivalence): two panes, green accent. **Silent on stdout**, exit **0** — no
      `Launched scene 'dev'!` banner.
- [ ] **Launch `docker`.** `wez scene launch docker` builds the 4-pane grid running
      `docker stats` / `docker ps` / `docker compose logs -f` / shell (the `docker stats` panes
      may exit immediately if Docker is not running on the Mac — that is expected; the *layout*
      is what you are verifying).
      **⚠ macOS risk to confirm:** same windowing check as Section 6 — launched scene reuses a
      1-pane tab or a new tab in the same window, never a new OS window.

### 7c — `wez scene launch` error & empty states (exact UI-SPEC copy + exit codes)

- [ ] **No name given, recipes present → exit 2.** `wez scene launch; echo $?`. Expect to
      **stderr**, exit **2**:
      ```
      error: wez scene launch requires a recipe name (got none)
      available recipes:
        - ai
        - dev
        - docker
      try: wez scene launch ai
      ```
      (Indent is exactly two spaces + `- `; names sorted.)
- [ ] **Recipe not found → exit 1.** `wez scene launch nope; echo $?`. Expect **stderr**, exit
      **1**:
      ```
      error: no scene recipe named 'nope' in ~/.config/wezterm/wezterm-setup/scenes/
      available recipes:
        - ai
        - dev
        - docker
      try: wez scene launch ai
      ```
- [ ] **Malformed recipe → exit 1.** Create `~/.config/wezterm/wezterm-setup/scenes/broken.toml`
      with `color = "green"` (no `layout`), then `wez scene launch broken; echo $?`. Expect
      **stderr**, exit **1**:
      `error: scene recipe 'broken' is invalid: missing required field 'layout'`. Try also an
      unknown layout/color to confirm the enum wording matches Section 6's validate-before-emit
      strings. **Zero panes** are built. Remove `broken.toml` afterward.
- [ ] **No recipes at all → exit 2.** Move the scenes dir aside
      (`mv ~/.config/wezterm/wezterm-setup/scenes{,.bak}`), then `wez scene launch dev; echo $?`.
      Expect **stderr**, exit **2**:
      ```
      error: no scene recipes found in ~/.config/wezterm/wezterm-setup/scenes/
        create one, or reinstall to restore the seeded examples (ai, docker, dev)
      ```
      Restore: `mv ~/.config/wezterm/wezterm-setup/scenes{.bak,}`.
- [ ] **Name guard (path traversal blocked).** `wez scene launch ../../etc/passwd; echo $?`
      exits **1** with an `error: …` line and never touches a file outside the scenes dir.

### 7d — Dynamic recipe-name completion (SCEN-05)

- [ ] **Provider works.** `wez __complete scene-names` prints the recipe basenames **sorted**
      (`ai`, `dev`, `docker` after a fresh seed), exit 0. An empty/missing scenes dir prints
      **nothing** and still exits 0 (a Tab-time hook must never fail the shell).
- [ ] **Dynamic — no regeneration.** Add `~/.config/wezterm/wezterm-setup/scenes/zzz.toml`, re-run
      `wez __complete scene-names`: `zzz` appears with **no** completion-script regeneration.
      Remove it and confirm it disappears.
- [ ] **`scene launch <Tab>` completion.** In a new zsh (completion installed), `wez scene launch <Tab>`
      offers the recipe names. Confirm the nested `scene)`→`launch)` arm is present in the generated
      scripts and both pass `zsh -n` / `bash -n`.

---

## Results table

Fill in PASS / FAIL / N/A and notes as you go.

| Capability | Requirement(s) | Result | Notes (macOS specifics) |
|------------|----------------|--------|-------------------------|
| Prereqs / toolchain (Xcode CLT, lua5.4, luastatic, WezTerm) | — | PASS | E2E uses the prebuilt release asset (no local luastatic needed); CI builds the asset on macos-15-intel + macos-14 |
| Build CLI binary | — | PASS | E2E installs the CI-built `wez-macos-x86_64` (release-download path, checksum-verified); arm64 built+smoked on macos-14 |
| Unit test suite | — | PASS | install_state 70/70 + doctor 29/29 under Homebrew `lua` (5.5) on this Mac; 8 pre-existing unrelated Lua-5.5 failures logged in deferred-items.md |
| Clean install + single block | INST-01 | PASS | 07-04 Task 2: fresh `wezterm.lua` created with exactly one managed block over a `config_builder()` base |
| Timestamped backup | INST-02 | PASS (fresh-install exception) | a fresh creation takes no backup (nothing to back up); doctor gate passes via the `Created by wezterm-setup` marker |
| Re-install prompt / no-TTY abort | INST-03 | PASS | re-run over a present block, no TTY → abort exit 3 naming `--force/--restore/--skip` (verified from source) |
| Uninstall (full + granular) | INST-04, INST-05 | N/A (07-04) | not re-exercised in 07-04 (owned by the install/uninstall section; covered Linux-side) |
| WezTerm bootstrap / reuse | INST-06 | PASS | 07-04 Task 2: `install_macos` placed `~/Applications/WezTerm.app` sudo-free (auto-install gap CLOSED in 07-02) |
| CWD inheritance | FOUND-01 | | per-shell OSC 7 |
| Clear screen + scrollback (Cmd+K) | FOUND-02 | | Cmd vs Super |
| Curated bindings | FOUND-03 | | |
| Bindings runtime-verifiable | FOUND-04 | | |
| Cross-platform parity (Cmd vs Super) | FOUND-05 | | |
| `wez doctor` green / fails loudly | DIAG-01 | PASS | 07-04 Task 2: `doctor_exit=0`; all 5 core gates PASS on this Intel Mac (incl. fresh-install backup-gate exception) |
| `wez keys` grouped | DIAG-02 | | |
| `wez keys` conflict/source classify | DIAG-03 | | |
| `wez keys --json` | DIAG-04 | | |
| Completions installed (zsh + bash) | DIAG-05 | | bash-completion@2? compinit warnings? |
| Pane color set/reset | PANE-01, PANE-02 | | OSC 1337 user-var |
| Pane title + persistence | PANE-03, PANE-04 | | |
| Tab color / combined / priority / active | TAB-01..05 | | tab-bar glyph rendering |
| `wez scene new` layouts + commands | SCEN-01, SCEN-02 | | windowing (no new OS window) |
| Seed recipes (copy-if-absent) | SCEN-06 | | |
| `wez scene launch <name>` + equivalence | SCEN-03, SCEN-04 | | |
| `scene launch` error/empty states | SCEN-03/04 (UI-SPEC) | | exact copy + exit codes |
| Dynamic `scene launch <Tab>` completion | SCEN-05 | | provider sorted/dynamic; nested scene)->launch) arm; zsh -n/bash -n |

---

## macOS deviations (feed back into the parity pass)

Record every divergence from the Linux baseline here, with enough detail for the batched
cross-platform pass to act on it. One row per issue.

| # | Capability / step | Observed on macOS | Expected (Linux baseline) | Suspected cause (BSD flag / Cmd-vs-Super / clipboard / windowing / toolchain / path) | Proposed fix |
|---|-------------------|-------------------|---------------------------|--------------------------------------------------------------------------------------|--------------|
| 1 | CI dispatch — D-11 version stamp restore (07-04 Task 1) | Build step aborted `mv: cannot stat '…/cli/spec.lua.bak.<pid>'` on ubuntu + macos-14 | Build completes; source tree restored after the luastatic bundle | Not BSD-specific — a `RETURN` trap consumed early by the luastatic `( )` subshell | FIXED `d85fa27`: explicit `mktemp` save + post-bundle restore (no RETURN trap) |
| 2 | CI dispatch — Intel toolchain install (07-04 Task 1) | `macos-15-intel`: `luarocks install luastatic` → `install requires exclusive write access to /usr/local … Permission denied` (exit 4) | luastatic installs and is on PATH for the build step | Toolchain: the Intel Homebrew `/usr/local` luarocks tree is not user-writable without sudo | FIXED `d85fa27`: `luarocks install --local luastatic` (~/.luarocks) + `$GITHUB_PATH`, uniform across both arches |
| 3 | E2E quarantine probe (07-04 Task 2, D-07) | `xattr -p com.apple.quarantine` on both `~/.local/bin/wez` and `~/Applications/WezTerm.app` → **no quarantine**; Gatekeeper did not block first launch | (n/a — macOS-specific; Linux has no Gatekeeper) | curl/wget downloads do NOT set `com.apple.quarantine` (only browser downloads do) — RESEARCH Pitfall 5 / A4 | NONE — D-07 default: install.sh left unchanged (no `xattr -dr` strip); manual fallback note retained |
| 4 | Fresh install on a clean machine (07-04 Task 2, INST-01/06) | `wez install-state` aborted `cannot read … No such file or directory` (exit 1); `wez doctor` then failed the core backup gate | install creates `wezterm.lua` + exits 0; doctor exits 0 | Not BSD-specific — the injection model assumed a pre-existing `wezterm.lua`; a clean machine has none | FIXED `eddef2e`: install-state seeds a config-builder base + creates the file (no backup needed); doctor backup gate passes on a fresh creation |

**Candidate deviations to watch for (pre-identified from the code, confirm or clear each):**

- [x] **Gatekeeper quarantine on `WezTerm.app`** — CLEARED (07-04 Task 2, D-07): the curl-download
      install set NO `com.apple.quarantine` on either `wez` or `WezTerm.app`, and Gatekeeper did not
      block first launch on this Intel Mac. No installer change needed; the manual `xattr -d` /
      right-click-open note is kept as a fallback for browser-download cases.
- [ ] **Apple Silicon codesign of `dist/wez`** — unsigned Mach-O may be killed on first run;
      `codesign -s - dist/wez` needed; not handled by `build.sh` (§C-1).
- [ ] **`sha256sum` absent** — only bites the `WEZ_REMOTE_BOOTSTRAP=1` release-download path in
      `tools/build.sh`; replace with `shasum -a 256` for macOS. (Local source builds are unaffected.)
- [ ] **`scene new --layout <Tab>` / `--color <Tab>` value completion** (was A-1, FIXED 2026-06-14)
      — wired + proven at runtime in bash; **confirm it also fires in zsh on macOS** (the zsh arm
      uses `${words[CURRENT-1]}` under `_arguments`, not headlessly testable here).
- [x] **WezTerm auto-install on macOS** — RESOLVED: `install_macos` (implemented in 07-02) now
      really downloads the official nightly `.zip` and places `~/Applications/WezTerm.app`
      sudo-free; confirmed live in the 07-04 Task 2 E2E (`[bootstrap] placed
      /Users/ramon/Applications/WezTerm.app`, `wezterm 20260622-120102-6ff54928`). INST-06 macOS
      parity is met.
- [ ] **Test harness bash version** — `tools/run-tests.sh` uses `mapfile`; verify it runs under a
      bash that supports it (not stock macOS bash 3.2).
- [ ] **`cp -R src/. dst/` trailing-dot semantics** on BSD `cp` (STEP 4 config copy).
- [ ] **zsh `compinit` insecure-directory warnings** from Homebrew-owned `fpath` (completions).
- [ ] **bash completion** requires `bash-completion@2` on macOS.
- [ ] **`Cmd` vs `Super` mapping** for `Cmd+K` and all curated bindings.
- [ ] **Clipboard copy/paste** bindings backed by `pbcopy`/`pbpaste`.
- [ ] **OSC 7 cwd inheritance** firing on macOS shells after the installer's rc registration.
- [ ] **Scene windowing** — confirm no per-scene Aqua window; mux semantics match Linux.

---

## Appendix — exact commands referenced

Grounded in the real scripts/CLI (no invented commands):

```sh
# build + test
LUA_BIN=lua5.4 ./tools/run-tests.sh        # or: make test  (LUA_BIN=lua on Homebrew)
./tools/build.sh                            # luastatic -> dist/wez, else dev launcher
./dist/wez version

# install / uninstall
make install                                # ./tools/setup.sh
./tools/setup.sh --force                    # override existing managed block
./tools/setup.sh < /dev/null                # no-TTY (expect non-zero re-install abort)
make uninstall                              # full
make uninstall KEEP_CONFIG=1                # granular (also KEEP_CLI=1 / KEEP_BACKUP=1)

# diagnostics
wez doctor; echo $?
wez keys
wez keys --json | python3 -m json.tool

# identity
wez pane color blue ; wez pane color reset ; wez pane title "api"
wez tab color green ; wez tab color blue --title "api"

# scenes
wez scene new --layout tall --pane shell --pane shell --color green --title dev
wez scene launch dev
wez scene launch                            # exit 2 (no name)
wez scene launch nope                       # exit 1 (not found)
WEZTERM_SETUP_DIR=$HOME/.config/wezterm/wezterm-setup wez seed-scenes
wez __complete scene-names                  # sorted recipe names (ai dev docker); empty dir -> nothing, exit 0
```
