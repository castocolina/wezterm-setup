---
phase: 01-foundation
reviewed: 2026-06-09T18:45:09Z
depth: standard
files_reviewed: 30
files_reviewed_list:
  - cli/commands/complete.lua
  - cli/commands/completions.lua
  - cli/commands/doctor.lua
  - cli/commands/install_state.lua
  - cli/commands/keys.lua
  - cli/commands/uninstall_state.lua
  - cli/commands/version.lua
  - cli/lib/showkeys.lua
  - cli/spec.lua
  - cli/wez.lua
  - config/wezterm-setup/cwd.lua
  - config/wezterm-setup/init.lua
  - config/wezterm-setup/keybindings.lua
  - config/wezterm-setup/shell-integration/osc7.sh
  - config/wezterm-setup/shell-integration/osc7.zsh
  - tests/cli/completions_test.lua
  - tests/cli/doctor_test.lua
  - tests/cli/install_state_test.lua
  - tests/cli/keys_test.lua
  - tests/cli/spec_test.lua
  - tests/cli/uninstall_state_test.lua
  - tests/config/apply_test.lua
  - tests/config/keybindings_test.lua
  - tools/bootstrap-wezterm.sh
  - tools/build.sh
  - tools/lib/platform.sh
  - tools/lib/wezterm-release.sh
  - tools/run-tests.sh
  - tools/setup.sh
  - tools/uninstall.sh
findings:
  critical: 3
  warning: 7
  info: 4
  total: 14
status: issues_found
---

# Phase 1: Code Review Report

**Reviewed:** 2026-06-09T18:45:09Z
**Depth:** standard
**Files Reviewed:** 30
**Status:** issues_found

## Summary

Reviewed the pure-Lua WezTerm config layer, the `wez` companion CLI, and the
sudo-free bash install/bootstrap tooling at standard depth, with focused tracing
of the threat surfaces called out in the brief: untrusted-input parsing, atomic
writes + backup integrity, tarball path-traversal, and shell injection.

The architecture is disciplined (closed allow-list dispatch, pure/injectable
decision cores, no `load()` of untrusted text — the showkeys parser is genuinely
pattern-based and never evals). However, three correctness/security defects are
demonstrable and reproducible:

1. **`--force` re-install corrupts a Shape-B user config** — the override path
   strips the managed block (which, for non-identifier returns, *contains* the
   `return` statement) and writes that broken file BEFORE re-injection fails.
   The user is left with a `wezterm.lua` that has no `return` — a broken config.
2. **Single-quote / shell-metacharacter injection** into `ls` and `rm -rf`
   shell-outs built by string-concatenating user-controlled paths
   (`newest_backup`, `remove_backups`, `remove_config_tree`).
3. **Tarball symlink members bypass the path-traversal guard** — `assert_safe_members`
   only greps for absolute paths and `..`; a symlink member escapes it.

Findings 1 and 2 were confirmed by direct reproduction (see each finding). The
remaining items are robustness/quality issues that should be addressed.

## Critical Issues

### CR-01: `--force` / override re-install corrupts a Shape-B config (no `return` left)

**File:** `cli/commands/install_state.lua:355-382` (override path) + `:166-186` (find_final_return) + `:207-225` (inject Shape B)
**Issue:** When the user's config returns a non-identifier expression (e.g.
`return wezterm.config_builder()`), the first install uses **Shape B**, which
emits a block whose body *includes* the `return` statement:

```
-- >>> wezterm-setup managed block >>>
local __wezterm_setup_config = (wezterm.config_builder())
require('wezterm-setup').apply(__wezterm_setup_config)
return __wezterm_setup_config
-- <<< wezterm-setup managed block <<<
```

On a subsequent `--force`/override, `run()` strips the block **markers-inclusive**
(lines 357-368), which deletes the only `return` line, then calls
`atomic_write(target, stripped)` (line 369) — **persisting the broken, return-less
file** — and only afterward calls `M.inject(..., { skip_backup = true })`, which
fails at `find_final_return` with "no top-level `return` found" (line 204-206).
Net result: the user's live `wezterm.lua` is left with no `return` statement →
WezTerm config is broken. Reproduced:

```
=== after override strip ===
[[local wezterm = require("wezterm")
]]
re-inject after strip ok:  false   no top-level `return` found in ...
```

**Fix:** Build the post-strip text and the re-injected text in memory and write
**once**, only after a successful inject — never persist the intermediate
stripped state. Alternatively, parse the existing managed block to recover the
original returned expression before stripping, and re-inject against that. At
minimum, wrap strip+inject so a failed inject leaves the original (managed) file
untouched:

```lua
-- compute stripped text, then inject into the stripped TEXT (not the file)
local stripped = text:sub(1, open_at - 1) .. text:sub(stop + 1)
local rebuilt = M.inject_into_text(stripped)   -- pure, returns text|nil,err
if not rebuilt then
  io.stderr:write("wez install-state: override aborted; config left unchanged\n")
  return 1                      -- original file never modified
end
M.backup(target)
M.atomic_write(target, rebuilt) -- single write of the final good content
```

### CR-02: Shell injection via unsanitized paths in `ls` / `rm -rf` shell-outs

**File:** `cli/commands/install_state.lua:112` (`newest_backup`), `cli/commands/uninstall_state.lua:127` (`remove_config_tree`), `cli/commands/uninstall_state.lua:142` (`remove_backups`)
**Issue:** All three build a shell command by concatenating a path inside single
quotes, e.g.:

```lua
local p = io.popen("ls -1 '" .. dir .. "' 2>/dev/null")   -- install_state:112
os.execute("rm -rf '" .. setup_dir .. "'")                -- uninstall_state:127
```

The path derives from user-controlled inputs (`WEZTERM_CONFIG_FILE`,
`WEZTERM_SETUP_DIR`, `WEZ_BIN`, `$HOME`). A single quote (or any shell
metacharacter) terminates the quoting and is interpreted by `/bin/sh`. Confirmed
with a directory named `d'ir`:

```
sh: 1: Syntax error: Unterminated quoted string
newest_backup result:  nil
```

Two harms: (a) **silent failure** — `newest_backup` returns `nil`, so `--restore`
reports "no backup found" and doctor's GATE 4 falsely fails on a perfectly healthy
install whose path contains a quote; (b) **`rm -rf` injection** —
`remove_config_tree` runs `rm -rf` on attacker-influenced text. The basename guard
(`:match("/wezterm%-setup/?$")`) does not neutralize a quote that appears *earlier*
in the path; a crafted `WEZTERM_SETUP_DIR` ending in `/wezterm-setup` but
containing `'$(...)'` upstream both passes the guard and breaks out of the quoting.

**Fix:** Do not shell out for directory listing/removal. Lua has no native
`readdir`, but you can either (a) vendor a minimal `posix`/`luafilesystem`-free
directory walk via `io.popen` with **argument-safe quoting** (replace every `'`
with `'\''`), or (b) preferably avoid the shell entirely:

```lua
-- quote helper if a shell-out is unavoidable:
local function shq(s) return "'" .. tostring(s):gsub("'", [['\'']]) .. "'" end
io.popen("ls -1 " .. shq(dir) .. " 2>/dev/null")
os.execute("rm -rf -- " .. shq(setup_dir))   -- also add `--`
```

For `remove_config_tree`, prefer recursive removal in Lua or pass the path as a
single argv element to a non-shell exec wrapper; the `'\''`-escaping fix is the
minimum bar.

### CR-03: Backup write integrity is unverified — truncated/failed writes report success

**File:** `cli/commands/install_state.lua:81-87` (`write_all`)
**Issue:** `write_all` ignores the return values of both `fh:write(data)` and
`fh:close()`:

```lua
local function write_all(path, data)
  local fh, err = io.open(path, "wb")
  if not fh then return nil, err end
  fh:write(data)   -- return value ignored
  fh:close()       -- return value ignored (this is where buffered-write errors surface)
  return true
end
```

On a full disk or a write error, `fh:write` returns `nil, errmsg` and/or
`fh:close` returns `nil, errmsg`, but `write_all` still returns `true`. Because
`backup()` and `atomic_write()` both build on `write_all`, the installer can
believe a **timestamped backup was written when it was truncated or empty**, then
proceed to overwrite the user's real config — defeating the entire
"backup-before-write" safety property (INST-02 / T-04-01). This is a data-loss
risk on the exact failure path backups exist to cover.

**Fix:** Check both calls and fsync-equivalent before declaring success:

```lua
local function write_all(path, data)
  local fh, err = io.open(path, "wb")
  if not fh then return nil, err end
  local wok, werr = fh:write(data)
  local cok, cerr = fh:close()        -- close reports deferred write errors
  if not wok then return nil, werr end
  if not cok then return nil, cerr end
  return true
end
```

## Warnings

### WR-01: Tarball symlink members bypass the path-traversal guard

**File:** `tools/bootstrap-wezterm.sh:164-171` (`assert_safe_members`)
**Issue:** The guard only rejects members matching `^/` (absolute) or `..`:

```bash
tar -tJf "${file}" | grep -Eq '^/|(^|/)\.\.(/|$)'
```

It does NOT inspect **symlink/hardlink members or their targets**. A malicious
archive can ship `evil -> /tmp/outside` (a symlink whose name is relative and
contains no `..`) followed by `evil/payload`, and extraction writes through the
symlink, escaping `release_dir`. Confirmed: such a member is NOT flagged by the
grep. `--no-absolute-names` does not prevent symlink-directory traversal. Risk is
bounded by the source being the official `wez/wezterm` GitHub host over HTTPS with
size + xz-magic checks, so this is defense-in-depth rather than a live exploit —
but the file's own comment claims T-02-02 path-traversal is handled, and it is not.
**Fix:** Reject link members and use the safe extractor flag:

```bash
# reject any symlink/hardlink member up front
if tar -tvJf "${file}" | grep -Eq '^[lh]'; then
  err "archive contains link members — refusing to extract"; return 1
fi
# and/or extract with traversal protection (GNU tar >= 1.32 default, be explicit):
tar -xJf "${archive}" --no-absolute-names --no-overwrite-dir -C "${release_dir}"
```
(Consider a freshly-created empty `release_dir` per run — already done — plus
post-extraction validation that no symlink in the tree points outside it.)

### WR-02: Override path persists the stripped file before re-injecting (data-at-risk window)

**File:** `cli/commands/install_state.lua:368-379`
**Issue:** Even for the Shape-A case where CR-01 does not corrupt the file, the
override path performs **two separate `atomic_write` calls** — one for the
stripped intermediate (line 369), one inside `inject` (line 228). A crash or
inject failure between them leaves the user at the stripped (no-managed-block)
state, not the original managed state. The backup mitigates total loss but the
live file is transiently/erroneously in a half-applied state.
**Fix:** Same as CR-01 — compute the final text and write exactly once.

### WR-03: `find_final_return` heuristic can match a `return` that is not top-level

**File:** `cli/commands/install_state.lua:166-186`
**Issue:** The function scans bottom-up for the last line matching
`^%s*return%s+(.-)%s*$`. This is line-pattern parsing of Lua, not structural. A
config whose final `return <expr>` lives inside a function body, or that has a
later non-top-level `return`, will be matched and have the managed block injected
in the wrong scope, breaking the config. There is no guard that the matched return
is at indentation level 0 / module scope.
**Fix:** At minimum require the return to be unindented
(`^return%s+(.-)%s*$`) for the primary match, and/or verify nothing but comments
and blank lines follow it. Document the assumption and fail loudly when the final
return is indented.

### WR-04: Dead/no-op code block in `find_final_return`

**File:** `cli/commands/install_state.lua:177-181`
**Issue:** The `if line:match("%S") and not line:match("^%s*return%s*$") then ... end`
block contains only a comment — it computes a condition and does nothing with it.
It misleads the reader into thinking it affects the scan (it does not) and is
effectively dead code.
**Fix:** Remove the empty conditional, or implement the intended "a non-return
line below the return means this isn't the last statement" logic it gestures at.

### WR-05: Predictable, unseeded temp-file names for atomic writes

**File:** `cli/commands/install_state.lua:136`
**Issue:** `math.random` is never seeded, so `atomic_write`'s temp suffix
(`.tmp.<ts>.<math.random(1,1e6)>`) is **deterministic across process runs** and
predictable. The temp file is created as a sibling of the target with default
`io.open` permissions. In a shared/predictable directory this enables a
pre-created-symlink race (attacker pre-creates the temp name as a symlink). Low
likelihood here (sibling of the user-owned config), but trivially avoidable.
**Fix:** Seed once (`math.randomseed(os.time() ~ os.clock()*1e6)`), or better,
derive the temp name from `os.tmpname()` in the same directory, or open with
`O_EXCL` semantics if a binding is available.

### WR-06: `os.remove` failures swallowed in uninstall (cli + backups)

**File:** `cli/commands/uninstall_state.lua:132-135` (`remove_cli`), `:144-148` (`remove_backups`)
**Issue:** `remove_cli` and `remove_backups` call `os.remove(...)` and
unconditionally `return true`, discarding the `nil, errmsg` a failed removal
returns. The run() output then reports "removed wez binary" / "removed
timestamped backups" even when removal failed (e.g. permission/readonly). The
user is told uninstall succeeded when artifacts remain.
**Fix:** Capture and surface removal errors; downgrade the success message to a
warning when `os.remove` returns falsy.

### WR-07: `bootstrap` reuse decision treats unparseable version as below-minimum but still proceeds to fetch on unknown OS only at the end

**File:** `tools/bootstrap-wezterm.sh:268-275` and `tools/lib/wezterm-release.sh:137-142`
**Issue:** `wezterm_release_asset_url` interpolates `$tag` (the release tag) and
`$base` directly into a URL with no validation that `tag` matches an expected
`YYYYMMDD-...`/`nightly` shape. In the TTY path the tag comes from
`wezterm_release_list` (API/parsed), and in the non-TTY path from the pinned
constant, so today it is not attacker-controlled — but the asset URL is then
fetched and extracted. If the releases-API parsing (`_wezterm_parse_dated_tags`)
ever returns a tag containing shell-unsafe or URL-injection characters from a
compromised/spoofed API response, it flows unvalidated into `fetch_to`. Defense
relies entirely on the host being pinned (`WEZTERM_RELEASE_HOST`).
**Fix:** Validate selected tags against a strict allow-pattern
(`^(nightly|[0-9]{8}-[0-9]{6}(-[0-9a-f]+)?)$`) in `select_release` before they
reach `wezterm_release_asset_url`, rejecting anything else.

## Info

### IN-01: `keybindings.lua` defines `mapped()` helper but inlines `"SUPER"` literals inconsistently

**File:** `config/wezterm-setup/keybindings.lua:58,61-66,82-84`
**Issue:** `M.super_mod = "SUPER"` is introduced as the documented cross-platform
constant, but most bindings use the bare string `"SUPER"` (lines 61-66, 82-84)
while only line 58 uses `M.super_mod`. The constant's documented intent (single
point of platform truth) is undercut by the inconsistency.
**Fix:** Use `M.super_mod` consistently for every Super/Cmd chord, or drop the
constant and document the WezTerm-native mapping once.

### IN-02: `load_our_bindings` comment references `disabled_defaults` handling it does not perform

**File:** `cli/commands/keys.lua:227-231`
**Issue:** The comment says disabled defaults "inform conflict reasoning if needed
later" but the function only returns `mod.keys`; `disabled_defaults` is never read
here. The comment describes intent, not behavior, and may mislead future
maintainers into assuming disabled defaults are already factored into conflict
detection.
**Fix:** Either consume `disabled_defaults` in classification or trim the comment
to state plainly that they are intentionally ignored in Phase 1.

### IN-03: `is_main()` heuristic matches any script path ending in `wez.lua`

**File:** `cli/wez.lua:132-138`
**Issue:** `is_main()` returns true whenever `arg[0]` ends with `wez.lua`,
including if a *different* `wez.lua` (e.g. a test harness or a same-named file in
another project) is the launched script while this module is required. It would
then call `os.exit`. Narrow risk given the bundle/layout, but the heuristic is
fragile.
**Fix:** Compare against the resolved path of this file, or guard on the absence
of an enclosing `require` more robustly (e.g. a sentinel the bundle sets).

### IN-04: `verify_tarxz` minimum-size magic number (1000000) is an unexplained literal

**File:** `tools/bootstrap-wezterm.sh:147`
**Issue:** The `1000000`-byte floor is a bare magic number; the rationale lives in
a comment but the value is not a named constant, so adjusting the threshold means
editing an inline literal.
**Fix:** Hoist to a named readonly (`MIN_ARCHIVE_BYTES=1000000`) for auditability.

---

_Reviewed: 2026-06-09T18:45:09Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
