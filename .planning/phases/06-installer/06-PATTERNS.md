# Phase 6: Ergonomic Installer - Pattern Map

**Mapped:** 2026-06-14
**Files analyzed:** 7 (3 new, 4 modified)
**Analogs found:** 7 / 7

Phase 6 is ~80% wiring existing, tested glue. Every new file has a close in-repo analog. The
overriding project rule is **D-01: bash/Lua boundary** — shell scripts and Makefile targets are
decision-free glue; all decisions live in the Lua `wez` binary. Every excerpt below is chosen to
keep new files on the correct side of that boundary.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `tools/install.sh` (NEW) | remote-bootstrap glue | file-I/O (fetch+exec) | `tools/setup.sh` + `tools/bootstrap-wezterm.sh` | exact (role) |
| `.github/workflows/release.yml` (NEW) | CI config | batch/build matrix | none in repo | **no analog** |
| `Makefile` (MODIFIED) | build config | request-response (dispatch) | existing `Makefile` targets | exact |
| `tools/build.sh` (MODIFIED) | build glue | file-I/O (download+verify) | itself (`download_release()`) | exact (self) |
| `cli/commands/update.lua` (NEW) | Lua command | request-response (decide+delegate) | `cli/commands/seed_scenes.lua`, `install_state.lua` | exact (role) |
| `cli/spec.lua` (MODIFIED) | spec/registry | n/a (declarative) | itself (existing registrations) | exact (self) |
| `README.md` (MODIFIED) | docs | n/a | existing README install section | role-match |

## Pattern Assignments

### `tools/install.sh` (NEW — remote-bootstrap glue, file-I/O)

**Analogs:** `tools/setup.sh` (header + log helpers + delegation), `tools/bootstrap-wezterm.sh`
(`trap` cleanup, `select_release()` TTY seam), `tools/build.sh` `download_release()` (curl/wget fetch).

**Script header — replicate verbatim** (`tools/setup.sh:32-41`):
```bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/lib/platform.sh"
log() { printf '[install] %s\n' "$*"; }
err() { printf '[install] ERROR: %s\n' "$*" >&2; }
```
> NOTE: `install.sh` is fetched STANDALONE over `curl|bash`, so `SCRIPT_DIR`/`. lib/platform.sh`
> are NOT available at the entry point (there is no repo yet). Keep the `set -euo pipefail` +
> `log`/`err` prefix convention, but source `platform.sh` only AFTER the tarball is unpacked, from
> `"$tmp/tools/lib/platform.sh"`. This is the one deviation from the setup.sh header shape.

**Function-wrap for partial-download safety** (Pattern 1, RESEARCH §262). The repo already uses the
`main()` + `[ "${BASH_SOURCE[0]}" = "${0}" ] && main "$@"` shape (`bootstrap-wezterm.sh:282`); for the
piped entry script make `main "$@"` the literal LAST line so a truncated stream never executes:
```bash
main() {
  # ... entire body: mktemp, fetch tarball, exec setup.sh ...
  :
}
main "$@"
```

**Temp checkout + guaranteed cleanup** — reuse the in-repo `trap` idiom (`bootstrap-wezterm.sh:194-196`
uses `trap "rm -rf '${tmpdir}'" RETURN`; at top-level script scope use `EXIT`):
```bash
tmp="$(mktemp -d "${TMPDIR:-/tmp}/wezterm-setup.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
```

**Fetch helper — curl-or-wget pattern, copy from** `tools/build.sh:112-119`:
```bash
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO "$2" "$1"; }
else
  err "neither curl nor wget available"; exit 1
fi
```
Codeload tarball fetch (Pattern 5) — pipe straight to tar with `--strip-components=1`:
```bash
ref="${WEZ_REF:-main}"
url="https://codeload.github.com/castocolina/wezterm-setup/tar.gz/refs/heads/${ref}"
curl -fsSL "$url" | tar -xzf - -C "$tmp" --strip-components=1   # wget: wget -qO- "$url" | tar ...
```

**Hand-off to setup.sh with TTY revived** (RESEARCH §286 Pattern 2 + Pitfall 2). `setup.sh` STEP 6
and `bootstrap-wezterm.sh select_release()` (lines 97-132) gate interactivity on `[ -t 0 ]` / `test -t 0`;
under the pipe stdin is the script, so redirect the child's stdin from `/dev/tty` to re-light those seams:
```bash
if [ -e /dev/tty ] && [ -r /dev/tty ]; then
  WEZ_REMOTE_BOOTSTRAP=1 "$tmp/tools/setup.sh" "$@" < /dev/tty
else
  WEZ_REMOTE_BOOTSTRAP=1 "$tmp/tools/setup.sh" "$@"   # headless (CI): flags via bash -s -- --force
fi
```
> `install_state.lua:380` `stdin_is_tty()` runs `test -t 0` — the `< /dev/tty` redirect above is what
> keeps its D-03 prompt interactive under the pipe (A5 to verify on a real terminal at plan time).

---

### `tools/build.sh` (MODIFIED — build glue, file-I/O)

**Analog:** itself — `download_release()` already exists and is the WHOLE download+verify mechanism.

**Change ONLY the placeholder base** (`tools/build.sh:49-50`), do not re-implement:
```bash
WEZ_RELEASE_TAG="${WEZ_RELEASE_TAG:-v0.1.0}"   # planner: bump to first real tag (Open Q3)
WEZ_RELEASE_BASE="${WEZ_RELEASE_BASE:-https://github.com/castocolina/wezterm-setup/releases/download}"
```

**Checksum contract change (per-asset `.sha256`, RESEARCH Open Q2).** `download_release()` currently
fetches a combined `SHA256SUMS` and greps the asset line (`build.sh:108,131-148`). Switch to per-asset:
```bash
# build.sh:108  was: sums_url=".../SHA256SUMS"
sums_url="${WEZ_RELEASE_BASE}/${WEZ_RELEASE_TAG}/${asset}.sha256"
# then parse the single line (no grep-for-asset needed) and keep the existing
# "verify BEFORE chmod +x, abort on mismatch" structure at build.sh:136-148 unchanged (T-01-01).
```

**macOS sha256 portability** (Pitfall 4). `build.sh:143` hardcodes `sha256sum`. Make it portable since
`make publish`/verify must run on macOS too:
```bash
if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "${tmp}" | awk '{print $1}')";
else got="$(shasum -a 256 "${tmp}" | awk '{print $1}')"; fi
```

---

### `cli/commands/update.lua` (NEW — Lua command, decide+delegate)

**Analogs:** `cli/commands/seed_scenes.lua` (thinnest command, pure-core/IO-shell split, env seams,
`io.popen` + `shquote`), `cli/commands/install_state.lua` (atomic-write + TTY detection + `run()` shape).

**Module shape — copy from** `seed_scenes.lua:25-51,149`:
```lua
local install_state = require("cli.commands.install_state")  -- reuse shquote / atomic_write
local M = {}
-- PURE decision (fixture-testable, no FS) — mirror plan_seed / decide:
function M.decide_update(have_datestamp, want_datestamp) -- -> "update" | "current"
  -- ... pure comparator; this is the only logic allowed in Lua (P6-D11/D-01) ...
end
function M.run(args) ... end   -- wires the decision to the shared launcher
return M
```

**D-01 boundary (CRITICAL):** the version comparison MAY live in Lua, but fetch/unpack/place/self-replace
MUST delegate to the shared bootstrap glue (`tools/install.sh`) — do NOT re-implement download logic in
Lua. `update.lua` shells out to the SAME launcher the one-liner uses (P6-D11, single entry point).
Mirror how `setup.sh` delegates decisions to `wez install-state` (`setup.sh:184`) — inverted direction
here, but the same "glue does IO, the other layer owns its job" split.

**TTY detection — reuse** `install_state.lua:380-384`:
```lua
local function stdin_is_tty()
  local ok = os.execute("test -t 0")
  return ok == true or ok == 0
end
```

**Shell-quote any path reaching a shell — reuse** `install_state.shquote` (`install_state.lua:111-113`):
```lua
io.popen("... " .. install_state.shquote(path) .. " ...")  -- CR-02, as seed_scenes does
```

**Self-replacement (Pattern 4) lives in the GLUE, not here.** `update.lua` triggers it; the atomic
`mv -f new dest` swap is performed by the launcher in the same dir as the live binary (RESEARCH §332).
The Lua-side analog for the safe-rename principle is `install_state.atomic_write` (`install_state.lua:149-159`)
— write-temp-then-`os.rename` — but for the binary the swap is in shell.

**Datestamp comparison — reuse the existing shell helpers** (do not re-derive in Lua):
`wezterm_version_datestamp` / `wezterm_datestamp_ge` (`bootstrap-wezterm.sh:55-62`), `detect_and_reuse`
(`:68-91`). HARD CONSTRAINT (P6-D09): only update the user-path `~/.local/bin` install; never a system
install — `detect_and_reuse:83` already logs "reused install is outside BIN_DIR"; branch on that.

---

### `cli/spec.lua` (MODIFIED — register `update` for completion, D-16)

**Analog:** itself. Adding `update` to THREE places makes `wez <Tab>` complete it with zero script edits
(completions are generated by walking this parser — `completions.lua:6-12`).

1. **CATEGORIES** (`spec.lua:39-51`) — add `["update"] = "install"` (or a new category).
2. **SUBCOMMANDS allow-list** (`spec.lua:54-66`) — append `"update"` (the closed dispatch set, T-01-02).
3. **build_parser()** (`spec.lua:96-121`) — register the command exactly like `seed-scenes` (`:121`):
```lua
parser:command("update", "Self-update wez, managed config, and WezTerm (newer nightly)")
```
> `tests/cli/spec_test.lua:56-61` asserts every name in `subcommand_names()` is registered — add
> `update` to that test's expected set so the interface-first contract stays green.

---

### `Makefile` (MODIFIED — add `build` / `publish` targets)

**Analog:** existing targets (`Makefile:19-32`). R3 rule (file header): each target ≤5 lines, dispatches
into `tools/`. `install` already exists and reuses `setup.sh` (so `make install` dogfoods). Add:
```make
.PHONY: ... build publish        # extend the existing .PHONY line (Makefile:6)
build:
	@./tools/build.sh
publish:
	@./tools/publish.sh          # NEW thin glue: build -> name wez-<os>-<arch> -> sha -> gh release upload --clobber
```
Add matching `help:` echo lines (`Makefile:8-17` style). The asset name in `tools/publish.sh` MUST be
computed from `platform_os`/`platform_arch` (`lib/platform.sh:19,30`) so local + CI never drift (P6-D08).

---

### `.github/workflows/release.yml` (NEW — CI matrix) — NO IN-REPO ANALOG

No GitHub Actions workflow exists in this repo. Use RESEARCH Pattern 6 (§378) as the source skeleton —
key contract points the executor must honor:
- Matrix runners: `ubuntu-latest` (linux/x86_64), **`macos-15-intel`** (darwin/x86_64 — NOT `macos-13`,
  removed 2025-12-04), `macos-14` (darwin/aarch64).
- Build step calls `./tools/build.sh` (the SAME build path as local — produces `dist/wez`).
- Asset name `wez-<os>-<arch>` computed from `platform_os`/`platform_arch` (same contract as `make publish`).
- Per-asset `.sha256` (Open Q2): `command -v sha256sum && sha256sum ... || shasum -a 256 ...`.
- Apple Silicon leg only: `codesign --force --sign - dist/wez` (Pattern 7).
- `permissions: { contents: write }`; publish via `gh release upload "$GITHUB_REF_NAME" wez-* --clobber`
  (identical command to `make publish` — the "same contract" rule).

### `README.md` (MODIFIED) — role-match analog: current install section

Replace the non-working `…/tools/setup.sh | sh` one-liner. Authored with the `crafting-effective-readmes`
skill (P6-D06). Ship the exact one-liners from RESEARCH §574 (curl, wget, `bash <(curl …)`,
inspect-before-run, `WEZ_REF=` pin). Document the trust model (P6-D05).

## Shared Patterns

### Pure-core / IO-shell split (D-01) — every Lua command
**Source:** `cli/commands/install_state.lua` (`decide`/`inject_into_text` pure; `run` wires FS+TTY),
`cli/commands/seed_scenes.lua` (`plan_seed` pure; `run` wires FS).
**Apply to:** `cli/commands/update.lua` — keep `decide_update` pure (fixture-testable autonomous gate),
`run()` delegates IO to the shared launcher.

### Shell-glue script skeleton
**Source:** `tools/setup.sh:32-41`, `tools/bootstrap-wezterm.sh:29-49`.
**Apply to:** `tools/install.sh`, `tools/publish.sh` — `set -euo pipefail`, `SCRIPT_DIR`/`REPO_ROOT`,
`[label]`-prefixed `log()`/`err()`, source `lib/platform.sh`, `main()` + run-only-when-executed guard.

### Atomic write / atomic swap (never corrupt the live target)
**Source:** `install_state.lua:149-159` (`atomic_write` = write-temp-then-`os.rename`);
`setup.sh:144-145` (completion script temp-then-`mv -f`).
**Apply to:** the `wez update` binary self-replace (shell `mv -f new dest`, Pattern 4) and any managed-asset
rewrite.

### Marker-guarded idempotent rc registration
**Source:** `setup.sh:106-118` (`register_osc7`) + `:153-166` (`register_completions_rc`) — distinct
literal markers, `grep -qF` before append.
**Apply to:** any rc/file edit the remote path makes (currently delegated to `setup.sh`, so reuse, do not
re-implement).

### Datestamp version comparison + system-install protection (P6-D09)
**Source:** `bootstrap-wezterm.sh:55-62` (`wezterm_version_datestamp`/`wezterm_datestamp_ge`),
`:68-91` (`detect_and_reuse`, including the "outside BIN_DIR -> leave intact" branch at :83).
**Apply to:** `wez update`'s WezTerm-newer check + the installer's update-in-place path. NEVER touch a
system install.

### Curl-or-wget fetch
**Source:** `build.sh:112-119`. **Apply to:** `tools/install.sh`, `tools/publish.sh` (if fetching).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `.github/workflows/release.yml` | CI config | build matrix | No GitHub Actions workflow exists in the repo. Use RESEARCH Pattern 6 (corrected `macos-15-intel` runner) + the asset-name/sha256/codesign contract above. |

## Test Pattern Note (gap for the planner)

Existing tests are **Lua `assert`/`check`-based** unit tests under `tests/cli/*_test.lua`, discovered by
`tools/run-tests.sh` (globs `*_test.lua` under `tests cli config`, runs each under `lua5.4`). There is
currently **NO shell-script linting test** (`bash -n` / `zsh -n`) and **no dogfood-scratch-HOME shell
test** in the suite — the closest is `tests/integration/install_config_load_integration_test.lua` (gated
by `WEZTERM_INTEGRATION=1`).

**Implication for acceptance criteria:**
- `cli/commands/update.lua` → testable in the established style: a `tests/cli/update_test.lua` that
  fixture-tests `M.decide_update` (mirror `seed_scenes_test.lua` / `install_state_test.lua`), plus the
  `spec_test.lua` registration assertion.
- `tools/install.sh` / `tools/publish.sh` / `release.yml` shell+CI glue have **no existing test harness**.
  The planner should either (a) add a `bash -n`/`shellcheck` syntax gate to `run-tests.sh`, or (b) rely on
  the project's hypothesis/manual-repro rule (`.tmp/h<NN>-…/` + recorded `wez doctor` evidence,
  verify-before-done) — consistent with how the existing shell glue (`bootstrap-wezterm.sh`) is verified.

## Metadata

**Analog search scope:** `tools/`, `tools/lib/`, `cli/commands/`, `cli/`, `tests/`, `Makefile`, `README.md`
**Files scanned:** setup.sh, build.sh, bootstrap-wezterm.sh, lib/platform.sh, run-tests.sh, Makefile,
install_state.lua, seed_scenes.lua, spec.lua, completions.lua, doctor_test.lua, spec_test.lua
**Pattern extraction date:** 2026-06-14
