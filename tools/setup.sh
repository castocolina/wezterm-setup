#!/usr/bin/env bash
# tools/setup.sh
#
# The wezterm-setup INSTALLER — bootstrap/glue ONLY (D-01). It makes NO
# install-state decisions itself: every override/restore/skip decision and all
# sentinel parsing/injection live in the Lua `wez` binary
# (cli/commands/install_state.lua). This script just sequences the steps and
# surfaces `wez install-state`'s exit code as its own (so a no-TTY re-install
# correctly aborts non-zero, D-03).
#
# Sequence:
#   1. source tools/lib/platform.sh                       (shared detection)
#   2. tools/bootstrap-wezterm.sh                          (sudo-free WezTerm, Plan 02)
#   3. tools/build.sh -> install dist/wez to ~/.local/bin  (the wez CLI, Plan 01)
#   4. copy config/wezterm-setup/ -> ~/.config/wezterm/wezterm-setup/   (Plan 03)
#   5. register the OSC 7 shell integration into .bashrc/.zshrc,
#      idempotently, guarded by the literal marker `# wezterm-setup:osc7`
#   5b. generate + register zsh/bash shell completions FROM the spec
#      (`wez completions <shell>`, D-16) into user completion dirs, idempotently,
#      guarded by the DISTINCT marker `# wezterm-setup:completions` (Plan 07)
#   6. wez install-state (passing through --force/--restore/--skip): timestamped
#      backup + single managed-block injection / re-install decision (Plan 04)
#
# Sudo-free + cross-platform (uses platform.sh; no /proc, no sudo — D-18, T-04-04).
# Dogfood (R4): run against a COPY of the real wezterm.lua in a scratch HOME.
#
# Usage:
#   ./tools/setup.sh                 # clean install / TTY re-install prompt
#   ./tools/setup.sh --force         # override an existing managed block
#   ./tools/setup.sh --restore       # reinstate the newest timestamped backup
#   ./tools/setup.sh --skip          # leave an existing block untouched
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=tools/lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"

log() { printf '[setup] %s\n' "$*"; }
err() { printf '[setup] ERROR: %s\n' "$*" >&2; }

# User-path destinations (sudo-free — T-04-04). Overridable for dogfood/testing.
BIN_DIR="${WEZ_BIN_DIR:-${HOME}/.local/bin}"
CONFIG_DIR="${WEZTERM_CONFIG_DIR:-${HOME}/.config/wezterm}"
SETUP_DIR="${CONFIG_DIR}/wezterm-setup"

# The OSC 7 rc marker. MUST differ from `# wezterm-setup:completions` (Plan 07)
# so the two registrations never collide.
OSC7_MARKER="# wezterm-setup:osc7"

# The shell-completions rc marker (Plan 07). DISTINCT from OSC7_MARKER above so the
# two guarded registrations coexist — registering completions must never remove or
# overwrite the OSC 7 line, and vice versa.
COMPLETIONS_MARKER="# wezterm-setup:completions"

# User-owned completion destinations (sudo-free — T-07-03). XDG-friendly, created
# on demand. Overridable for dogfood/testing.
ZSH_COMPLETION_DIR="${WEZ_ZSH_COMPLETION_DIR:-${HOME}/.local/share/zsh/site-functions}"
BASH_COMPLETION_DIR="${WEZ_BASH_COMPLETION_DIR:-${HOME}/.local/share/bash-completion/completions}"

# --- STEP 1: detection already sourced above ---------------------------------
OS="$(platform_os)"
log "platform: os=${OS} arch=$(platform_arch)"

# --- STEP 2: bootstrap the WezTerm emulator (Plan 02) ------------------------
log "bootstrapping WezTerm (sudo-free)…"
"${SCRIPT_DIR}/bootstrap-wezterm.sh"

# --- STEP 3: build + place the wez CLI (Plan 01) -----------------------------
log "building wez CLI…"
"${SCRIPT_DIR}/build.sh"
mkdir -p "${BIN_DIR}"
if [ ! -x "${REPO_ROOT}/dist/wez" ]; then
  err "build did not produce ${REPO_ROOT}/dist/wez"
  exit 1
fi
# Atomic install: stage into a temp in the SAME dir, then mv -f over the target.
# Replacing a RUNNING wez (e.g. `wez update` shelling back through here) must not
# truncate the live binary's inode in place (`ETXTBSY` / a torn binary) — a rename
# swaps the directory entry atomically and the running process keeps its old inode.
# Matches the temp-then-mv idiom already used for the managed config files below.
install -m 0755 "${REPO_ROOT}/dist/wez" "${BIN_DIR}/wez.tmp.$$"
mv -f "${BIN_DIR}/wez.tmp.$$" "${BIN_DIR}/wez"
log "installed wez -> ${BIN_DIR}/wez"
case ":${PATH}:" in
  *":${BIN_DIR}:"*) : ;;
  *) log "note: ${BIN_DIR} is not on PATH — add it so 'wez' resolves" ;;
esac

# --- STEP 4: place the managed config tree (Plan 03) -------------------------
log "placing managed config -> ${SETUP_DIR}"
mkdir -p "${SETUP_DIR}"
cp -R "${REPO_ROOT}/config/wezterm-setup/." "${SETUP_DIR}/"

# --- STEP 4b: seed example scene recipes (copy-if-absent, SCEN-06) ------------
# Decision-free delegation mirroring STEP 6's `wez install-state` invocation: ALL
# copy/keep decisions live in `wez seed-scenes` (cli/commands/seed_scenes.lua,
# D-01/D-07); this script adds NO copy/keep branching. The seeds live at the repo
# TOP LEVEL (${REPO_ROOT}/scenes), OUTSIDE config/wezterm-setup/, so STEP 4's
# wholesale `cp -R` above never places or clobbers a recipe (D-06 INVARIANT) — the
# seeder is the ONLY writer of ${SETUP_DIR}/scenes and never overwrites a user
# edit. WEZ_SEED_SRC_DIR points the (possibly bundled) binary at the repo seeds;
# WEZTERM_SETUP_DIR (already the seeder's dest resolver) targets ${SETUP_DIR}.
log "seeding example scene recipes (copy-if-absent)…"
WEZ_SEED_SRC_DIR="${REPO_ROOT}/scenes" WEZTERM_SETUP_DIR="${SETUP_DIR}" \
  "${BIN_DIR}/wez" seed-scenes

# --- STEP 5: register OSC 7 shell integration (idempotent, marker-guarded) ----
# Append a guarded source line to the user's rc once. Re-running checks for the
# EXACT marker before appending so no duplicates are added (T-04-03).
register_osc7() {
  local rc="$1" integration="$2"
  [ -f "${rc}" ] || return 0   # only touch rc files the user already has
  if grep -qF "${OSC7_MARKER}" "${rc}" 2>/dev/null; then
    log "OSC 7 already registered in ${rc} (marker present) — skipping"
    return 0
  fi
  {
    printf '\n%s\n' "${OSC7_MARKER}"
    printf '[ -f "%s" ] && . "%s"\n' "${integration}" "${integration}"
  } >>"${rc}"
  log "registered OSC 7 in ${rc}"
}
register_osc7 "${HOME}/.bashrc" "${SETUP_DIR}/shell-integration/osc7.sh"
register_osc7 "${HOME}/.zshrc"  "${SETUP_DIR}/shell-integration/osc7.zsh"

# --- STEP 5b: register shell completions (DIAG-05, idempotent, marker-guarded) -
# Generate the zsh + bash completion scripts FROM the spec via the just-installed
# `wez completions` (D-16 single source) and write them into user-owned completion
# dirs (sudo-free — T-07-03). Then ensure each shell's rc loads them, guarded by
# the DISTINCT marker `# wezterm-setup:completions` so re-install never duplicates
# and never disturbs the `# wezterm-setup:osc7` line. This satisfies `wez doctor`'s
# ADVISORY "completions installed" line (Plan 06) — it does not affect doctor's
# exit code (D-15).
WEZ_BIN="${BIN_DIR}/wez"

write_completion_script() {
  # write_completion_script <label> <dest-path> -- <wez-args...>
  # Generates a completion script by running `wez <args...>` and writing stdout to
  # <dest-path> atomically (temp then rename). The wez invocation is passed
  # explicitly so the exact command (`completions zsh` / `completions bash`) is
  # visible at the call site.
  local label="$1" dest="$2"
  shift 2
  [ "$1" = "--" ] && shift
  local dir
  dir="$(dirname "${dest}")"
  mkdir -p "${dir}"
  if "${WEZ_BIN}" "$@" >"${dest}.tmp" 2>/dev/null; then
    mv -f "${dest}.tmp" "${dest}"
    log "wrote ${label} completion -> ${dest}"
  else
    rm -f "${dest}.tmp"
    err "failed to generate ${label} completion (continuing — advisory)"
  fi
}

register_completions_rc() {
  # register_completions_rc <rc> <line-to-source>
  local rc="$1" line="$2"
  [ -f "${rc}" ] || return 0   # only touch rc files the user already has
  if grep -qF "${COMPLETIONS_MARKER}" "${rc}" 2>/dev/null; then
    log "completions already registered in ${rc} (marker present) — skipping"
    return 0
  fi
  {
    printf '\n%s\n' "${COMPLETIONS_MARKER}"
    printf '%s\n' "${line}"
  } >>"${rc}"
  log "registered completions in ${rc}"
}

# zsh: file MUST be named `_wez` on $fpath; add the dir to fpath and re-init compinit.
write_completion_script "zsh" "${ZSH_COMPLETION_DIR}/_wez" -- completions zsh
register_completions_rc "${HOME}/.zshrc" \
  "fpath=(\"${ZSH_COMPLETION_DIR}\" \$fpath); autoload -Uz compinit && compinit"

# bash: file named `wez` under the bash-completion completions dir; source it.
write_completion_script "bash" "${BASH_COMPLETION_DIR}/wez" -- completions bash
register_completions_rc "${HOME}/.bashrc" \
  "[ -f \"${BASH_COMPLETION_DIR}/wez\" ] && . \"${BASH_COMPLETION_DIR}/wez\""

# --- STEP 6: delegate the install-state DECISION to the Lua binary (D-01) ------
# Pass through any --force/--restore/--skip the user supplied. ALL sentinel
# parsing, backup, injection, and the override/restore/skip decision live in
# `wez install-state`; this script adds NO branching of its own. Surface its
# exit code as ours so a no-TTY re-install aborts non-zero (D-03).
log "delegating install-state decision to wez install-state…"
"${BIN_DIR}/wez" install-state "$@"
exit $?
