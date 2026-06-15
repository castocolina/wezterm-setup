#!/usr/bin/env bash
# tools/publish.sh
#
# Publish glue ONLY (D-01): build this platform's `wez`, name it under the
# `wez-<os>-<arch>` contract, emit its per-asset `<asset>.sha256`, and upload
# both to the pinned GitHub release with `--clobber`. The only decision this
# script makes is "which platform am I on" (delegated to lib/platform.sh) — it
# embeds NO update/version/decision logic (that lives in the Lua `wez` binary).
#
# The asset name is computed from platform_os/platform_arch BYTE-IDENTICALLY to
# tools/build.sh download_release() (build.sh:104-106) so a maintainer-published
# asset and a CI-published asset never drift (P6-D08, same-contract rule). The
# `gh release upload ... --clobber` invocation is the SAME command CI's
# release.yml uses (Pattern 6).
#
# Apple Silicon (macOS + aarch64) ad-hoc-codesigns the binary before checksum so
# the published asset loads on a real arm64 host (Pattern 7); other platforms
# skip that step. Gatekeeper/quarantine handling is Phase 7.
#
# Usage:
#   ./tools/publish.sh                       # build + upload wez-<os>-<arch> to WEZ_RELEASE_TAG
#   WEZ_RELEASE_TAG=v1.0.0 ./tools/publish.sh # publish to a specific release tag
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# shellcheck source=tools/lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"

log() { printf '[publish] %s\n' "$*"; }
err() { printf '[publish] ERROR: %s\n' "$*" >&2; }

# Pinned release tag the asset uploads to. Default matches tools/build.sh so a
# local publish and the download fallback agree on the tag (overridable).
WEZ_RELEASE_TAG="${WEZ_RELEASE_TAG:-v0.1.0}"

main() {
  # (1) Build dist/wez via the SAME path CI uses — no separate build logic here.
  log "building dist/wez via tools/build.sh…"
  "${SCRIPT_DIR}/build.sh"
  if [ ! -f "${REPO_ROOT}/dist/wez" ]; then
    err "build did not produce dist/wez"
    return 1
  fi

  # (2) Asset name — byte-identical to build.sh download_release() (build.sh:104-106).
  local os arch asset
  os="$(platform_os)"
  arch="$(platform_arch)"
  asset="wez-${os}-${arch}"

  # (3) Apple Silicon only: ad-hoc-codesign so the binary loads on arm64 macOS
  # (Pattern 7). Guarded by BOTH platform_os=macos AND platform_arch=aarch64.
  if [ "${os}" = "macos" ] && [ "${arch}" = "aarch64" ]; then
    log "macOS arm64 -> ad-hoc codesign dist/wez"
    codesign --force --sign - "${REPO_ROOT}/dist/wez"
  fi

  # (4) Name the asset from the build output.
  cp "${REPO_ROOT}/dist/wez" "${asset}"

  # (5) Per-asset checksum (Plan 01 Open Q2), portable: macOS has no sha256sum.
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${asset}" >"${asset}.sha256"
  else
    shasum -a 256 "${asset}" >"${asset}.sha256"
  fi
  log "wrote ${asset} + ${asset}.sha256"

  # (6) Upload BOTH to the pinned release with --clobber — the SAME command CI
  # uses (release.yml, Pattern 6 same-contract rule). gh owns its own auth.
  log "uploading ${asset} (+ .sha256) to release ${WEZ_RELEASE_TAG}…"
  gh release upload "${WEZ_RELEASE_TAG}" "${asset}" "${asset}.sha256" --clobber
  log "published ${asset} to ${WEZ_RELEASE_TAG}"
}

# Run only when executed, not when sourced (partial-stream safety + testability).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
