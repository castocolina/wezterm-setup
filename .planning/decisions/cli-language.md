# Decision: Companion CLI language

**Decision:** The `wez` companion CLI will be written in **Lua 5.4**.

**Status:** Locked 2026-06-07 (Phase 0 spike). Linux-proven; macOS verification deferred to the
batched Mac pass before Phase 1 closes (per CONTEXT D-04/D-05).

**Phase 0 plan:** `00-01-PLAN.md`. Criterion: CONTEXT `D-02 (revised)` — **code ergonomics + stack
coherence** as primary; performance explicitly a non-factor; distribution a minor, neutralized axis.

---

## Why (rationale)

1. **Stack coherence.** The WezTerm config layer is already pure Lua. One language across config +
   CLI lowers cognitive load and context-switching across all five phases.
2. **Native scene recipes.** Scene recipes (SCEN-03, "TOML or Lua") can be **native Lua files**
   loaded with `dofile`/`require` — zero parser, zero dependency. Python would need `tomllib` or an
   out-of-process Lua eval. This is a concrete coherence + ergonomics win unique to Lua.
3. **Ergonomics parity (proven).** Once Lua uses real libraries, it is on par with Python for the
   CLI's actual work — even slightly more concise.
4. **Packaging fits the distribution goal better than Python (proven).** The shipping model is
   `make build` → single binary → GitHub Releases → `curl | bash` → `~/.local/bin`, sudo-free for
   the end user (kitty-setup style). Lua + `luastatic` produces a ~368 KB self-contained binary;
   Python's equivalents (PyInstaller/Nuitka) are 10–50 MB with slow startup, and `uv` needs the uv
   binary + network at install. For a single-binary-via-curl goal, Lua is the better fit.

## What "native integration" does and does NOT mean (key finding)

The `wez` CLI is an **external process** to WezTerm — it talks via `wezterm cli` (IPC) and OSC
escapes; it does **not** run inside WezTerm's in-process Lua VM. So "Lua integrates natively with
the emulator" is a near-empty argument **for the CLI layer** — both languages just spawn
`wezterm cli` and parse output. Lua's win is coherence (one language) + native recipes, not
privileged in-process access. This corrected an early bias toward distribution-simplicity.

---

## Evidence

Both prototypes exercised an identical fixed proof-scope (CONTEXT D-03): argument parsing, one real
`wezterm cli list --format json` call, JSON decode, and file I/O — run against an isolated headless
`wezterm-mux-server` (WezTerm `20260604-145453`).

| | Python/uv (`run.py`) | Lua 5.4 (`run.lua`, vendored deps) |
|---|---|---|
| Output | `panes=1 requested_pane_id=0 matched_cwd=file://pop-os/home/user-zero/`, exit 0 | identical, exit 0 |
| Logic lines | 31 | 20 |
| JSON | `json` (stdlib) | `dkjson` (vendored pure-Lua, 1 line) |
| Args | `argparse` (stdlib) | `argparse` (vendored pure-Lua, declarative) |
| Startup | ~60 ms (uv overhead) | ~6 ms |

**Dependency story (sudo-free, proven):** Lua's JSON/arg libs are **pure-Lua single files**
(`dkjson` 714 lines, `argparse` 1527 lines) — vendored directly into the repo. No luarocks, no C
compiler, no sudo, no network at install. (`lua-cjson`/`lua-argparse` also exist via apt/luarocks
if ever preferred.)

**Single-binary build (sudo-free, proven end-to-end):**
1. Built Lua 5.4.7 from source in `/tmp` (`make posix`, no apt/sudo) → `liblua.a` (522 KB).
2. `luastatic run.lua dkjson.lua argparse.lua liblua.a -I<src>` → one binary.
3. Result: **368 KB ELF**, runs standalone from an empty dir (no repo, no `vendor/`, no system
   Lua, no `LUA_PATH`); `ldd` shows only `libc`/`libm` — **the Lua interpreter is baked in**.

Output of the standalone binary: `panes=1 requested_pane_id=0 matched_cwd=file://...`, exit 0.

---

## Packaging model (for Phase 1 installer/build design)

- **Dev/CI worries about the toolchain; the end user never does.**
- **`make build`** — `luastatic` bundles the `wez` Lua sources + vendored pure-Lua deps + the Lua
  interpreter into one static binary.
- **Cross-platform matrix (CI / GitHub Actions):**
  - Linux: link **static against musl** so one binary runs on every distro (Ubuntu/Fedora/Arch/
    Alpine). (The spike's binary was glibc-dynamic on libc/libm — fine for mainstream distros;
    musl-static is the full-portability step, deferred to CI.)
  - macOS: build on a macOS runner (arm64 + x86_64; `lipo` for universal). **Deferred** to the
    batched Mac pass (D-04/D-05).
  - Upload artifacts to GitHub Releases.
- **`curl | bash` installer** — detect `uname -s`/`-m`, download the matching release binary,
  `chmod +x`, drop in `~/.local/bin` (or a PATH dir). **Zero sudo, zero deps for the end user.**
- **Lua interpreter provisioning** — for source builds, the installer/`make` builds Lua from source
  (no sudo) or uses a system package; end users get the prebuilt binary and need neither.
  (Supersedes the earlier "installer must apt-install Lua" idea — the binary removes that need
  entirely for end users; only dev/CI provisions the Lua SDK.)

## Scratch artifacts (gitignored, `.tmp/` — deleted on promotion per playbook R5)

- `.tmp/h01-cli-lang-lua/run.lua` + `vendor/{dkjson,argparse}.lua` — Lua prototype + vendored deps
- `.tmp/h01-cli-lang-lua/bootstrap.sh` + `lua-manifest.lua` — pkg-manager-detecting dep bootstrap
- `.tmp/h01-cli-lang-lua/build/run` — the 368 KB single binary (luastatic)
- `.tmp/h02-cli-lang-python/run.py` — Python prototype (proof-scope parity reference)
- `.tmp/probes/phase-0/01-wezterm-cli-list-json.md` — R6 probe of the `wezterm cli` JSON shape
