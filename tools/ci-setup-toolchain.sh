#!/usr/bin/env bash
# tools/ci-setup-toolchain.sh
#
# Per-runner Lua build-toolchain installer for the INST-08 release CI
# (.github/workflows/release.yml). Pure CI provisioning GLUE (D-01): it installs
# `lua5.4` (+ dev headers) + `luastatic` + a C compiler so the SUBSEQUENT
# `tools/build.sh` step takes path 1 (the luastatic single-binary build) instead
# of the dev source-launcher. It embeds NO update/version/decision logic — the
# only branch is "which package manager does this OS use" (apt vs brew), keyed off
# tools/lib/platform.sh `platform_os`.
#
# WHY a real install per runner IS the legitimacy gate: `luastatic` is the
# project's locked build tool (D-02) but is `[ASSUMED]` in RESEARCH (it was not
# present on the dev host, and slopcheck does not cover the LuaRocks ecosystem).
# Actually installing it on each runner and capturing its real version closes
# RESEARCH assumption A3 — a broken/absent toolchain fails the leg LOUDLY here
# rather than silently degrading build.sh to the non-shippable dev launcher.
#
# SUDO SCOPE NOTE (P6-D03 not violated): this script runs on a GitHub Actions
# RUNNER, where `sudo apt-get` is the sanctioned way to provision build deps. That
# is a DIFFERENT context from the sudo-free USER install invariant (P6-D03), which
# governs how an end user installs WezTerm + wez on their own machine via
# tools/setup.sh. Provisioning a CI runner's build toolchain with apt-sudo does
# NOT relax the user-facing no-sudo guarantee — no end-user install path runs this
# script.
#
# Usage (CI step):
#   ./tools/ci-setup-toolchain.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=tools/lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"

log() { printf '[ci-toolchain] %s\n' "$*"; }
err() { printf '[ci-toolchain] ERROR: %s\n' "$*" >&2; }

# --- per-OS toolchain install ------------------------------------------------

install_linux() {
  # GitHub Actions ubuntu-latest: apt with sudo is the runner's sanctioned
  # provisioning path (see SUDO SCOPE NOTE above — not the user install path).
  log "linux runner -> apt-get install lua5.4 + headers + luarocks, then luastatic"
  sudo apt-get update
  sudo apt-get install -y lua5.4 liblua5.4-dev luarocks
  # --local installs into the runner user's tree (no extra sudo for the rock).
  luarocks install --local luastatic
  # luarocks --local puts binaries under ~/.luarocks/bin — make them findable for
  # the version capture below and the subsequent build step in the same job.
  if [ -d "${HOME}/.luarocks/bin" ]; then
    PATH="${HOME}/.luarocks/bin:${PATH}"
    export PATH
    # Persist onto the job PATH for the following steps when running under Actions.
    if [ -n "${GITHUB_PATH:-}" ]; then
      printf '%s\n' "${HOME}/.luarocks/bin" >>"${GITHUB_PATH}"
    fi
  fi
}

install_macos() {
  # GitHub Actions macos-* runners ship Homebrew + Xcode clang.
  #
  # PIN lua@5.4 — NEVER bare `lua`: Homebrew's `lua` formula is now 5.5
  # (Pitfall 1), and luastatic must bundle a Lua 5.4 interpreter to match the
  # project's locked runtime (D-02). `lua@5.4` is KEG-ONLY, so Homebrew does NOT
  # symlink its bin onto the default PATH (Pitfall 2) — we resolve the keg prefix
  # and prepend it ourselves so `lua5.4`/`luarocks` are findable both for the
  # version-capture gate below and for the SUBSEQUENT build.sh step in the job.
  log "macos runner -> brew install lua@5.4 + luarocks, then luastatic"
  brew install lua@5.4 luarocks
  luarocks install luastatic

  # Keg-only lua@5.4 is not auto-on-PATH (Pitfall 2): prepend its bin so the
  # version capture + the next build step resolve lua5.4 (not the bare 5.5 lua).
  PREFIX="$(brew --prefix lua@5.4)"
  PATH="${PREFIX}/bin:${PATH}"
  export PATH
  # Persist the keg bin onto the job PATH so the following steps (build.sh) find
  # lua5.4 without re-resolving the keg.
  if [ -n "${GITHUB_PATH:-}" ]; then
    printf '%s\n' "${PREFIX}/bin" >>"${GITHUB_PATH}"
  fi
  # NOTE: if the macOS leg later surfaces a luastatic link error for the keg-only
  # headers, the documented fix is the keg link flags
  # `${PREFIX}/lib/liblua5.4.a -I${PREFIX}/include/lua5.4` — build.sh's macOS
  # keg-only cflags/liblua fallback (build_with_luastatic) already resolves these.
}

# --- toolchain assertion + version capture (the legitimacy gate) -------------

assert_and_capture() {
  # CAPTURE the real versions (closes RESEARCH A3). luastatic has no stable
  # --version flag across releases, so fall back to `luarocks show` for its
  # version string; either way we echo a real, installed version.
  log "lua5.4 version: $(lua5.4 -v 2>&1 || echo 'lua5.4 -v failed')"
  if luastatic --version >/dev/null 2>&1; then
    log "luastatic version: $(luastatic --version 2>&1 | head -1)"
  else
    log "luastatic version (via luarocks show): $(luarocks show luastatic 2>&1 | head -1 || echo 'luarocks show luastatic failed')"
  fi

  # FAIL LOUDLY if luastatic is absent post-install: without it, build.sh would
  # silently fall back to the dev source-launcher and ship a non-static, wrong
  # artifact (T-06-03-02). A missing toolchain must fail the leg, not degrade it.
  if ! command -v luastatic >/dev/null 2>&1; then
    err "luastatic not on PATH after install — refusing to proceed (build.sh would"
    err "fall back to the dev launcher and publish a non-shippable asset)."
    return 1
  fi
  if ! command -v lua5.4 >/dev/null 2>&1; then
    err "lua5.4 not on PATH after install — luastatic cannot bundle the interpreter."
    return 1
  fi
  log "toolchain ready: luastatic + lua5.4 present"
}

# ---------------------------------------------------------------------------
main() {
  local os
  os="$(platform_os)"
  case "${os}" in
    linux) install_linux ;;
    macos) install_macos ;;
    *)
      err "unsupported runner OS '${os}' — no toolchain install path"
      return 1
      ;;
  esac
  assert_and_capture
}

# Run only when executed, not when sourced (partial-stream safety + testability).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
