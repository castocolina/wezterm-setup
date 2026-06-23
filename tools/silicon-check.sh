#!/usr/bin/env bash
# tools/silicon-check.sh
#
# Apple-Silicon (arm64 / aarch64) END-USER first-launch self-check (INST-08).
#
# This is the single remaining NON-gating macOS item (D-06/D-07). The project's
# agents have NO Apple-Silicon hardware, so this kit is run by a real end-user on
# a real Mac: it downloads the published v1.0.0 `wez-macos-aarch64` asset + its
# `.sha256`, verifies the checksum BEFORE making the binary executable or running
# it, OBSERVES (never mutates) the Gatekeeper/quarantine + ad-hoc codesign state,
# runs the binary for real evidence (`wez version`, `wez doctor`), and prints a
# copy-pasteable REPORT block. The user pastes that report into the
# "Apple-Silicon first-launch (INST-08)" landing spot in docs/macos-verification.md;
# filling that landing spot is what flips INST-08's macOS status from deferred to
# verified.
#
# Security / design invariants (mirror tools/build.sh + tools/verify-macos.sh):
#   * VERIFY-BEFORE-RUN — `shasum -a 256` the asset against its `.sha256` BEFORE
#     `chmod +x` / running it. Exit non-zero on mismatch; never run an unverified
#     binary (build.sh:488-506 idiom, T-07.1-06).
#   * Sudo-free, user-path only — everything lands in a scratch `mktemp -d` that a
#     RETURN/EXIT trap removes. No `sudo`, no `hdiutil`, no system `/Applications`,
#     no write outside the scratch dir (T-07.1-09).
#   * OBSERVE-ONLY quarantine — `xattr -p com.apple.quarantine` is REPORTED, never
#     stripped (no `xattr -d` / `xattr -c`). curl/gh downloads do not set the
#     quarantine xattr; only browser downloads do (RESEARCH Pitfall 2 / §C-1, D-07).
#   * Evidence is `codesign --verify` + the binary RUNNING — NOT `spctl`. `spctl`
#     ALWAYS rejects ad-hoc signatures (Pitfall 1 / build.sh:250-259), so its
#     rejection is meaningless here; we intentionally do NOT call it.
#
# Usage:  bash tools/silicon-check.sh
#         WEZ_CHECK_TAG=v1.0.0 bash tools/silicon-check.sh   # pin a different tag
#
# Run this ON real Apple Silicon. On any other machine it will still download +
# verify, but the binary will not run (wrong arch) — that is expected.

set -euo pipefail

REPO="${WEZ_CHECK_REPO:-castocolina/wezterm-setup}"
TAG="${WEZ_CHECK_TAG:-v1.0.0}"
ASSET="wez-macos-aarch64"
SUMS="${ASSET}.sha256"

log() { printf '\033[36m[silicon-check]\033[0m %s\n' "$*"; }
err() { printf '\033[31m[silicon-check] ERROR:\033[0m %s\n' "$*" >&2; }

# Scratch dir with trap cleanup — nothing is left on the user's disk.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/wez-silicon-check.XXXXXX")"
# shellcheck disable=SC2329  # invoked indirectly by the trap below
cleanup() { rm -rf "${WORK}"; }
trap cleanup RETURN EXIT

ARCH="$(uname -m)"
OS="$(uname -s)"
log "machine: ${OS} ${ARCH}  (expecting Darwin arm64 for a real Apple-Silicon check)"

# ---------------------------------------------------------------------------
# 1. Download the published asset + its checksum (prefer gh/curl to AVOID the
#    browser quarantine xattr — Pitfall 2). gh first, curl fallback on the
#    release-download URL.
# ---------------------------------------------------------------------------
download() { # remote-asset-name  ->  ${WORK}/<name>
  local name="$1" dest="${WORK}/$1"
  if command -v gh >/dev/null 2>&1; then
    if gh release download "${TAG}" --repo "${REPO}" -p "${name}" --dir "${WORK}" --clobber 2>/dev/null; then
      return 0
    fi
    log "gh release download failed for ${name}; falling back to curl"
  fi
  local url="https://github.com/${REPO}/releases/download/${TAG}/${name}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${dest}" "${url}"
  else
    err "neither gh nor curl is available — cannot download ${name}"
    return 1
  fi
}

log "downloading ${ASSET} + ${SUMS} from ${REPO}@${TAG}"
download "${ASSET}"
download "${SUMS}"

ASSET_PATH="${WORK}/${ASSET}"
SUMS_PATH="${WORK}/${SUMS}"

# ---------------------------------------------------------------------------
# 2. VERIFY the checksum BEFORE chmod +x / running it (build.sh idiom). The
#    per-asset `.sha256` is a single line; take field 1. macOS has no
#    `sha256sum`, only `shasum -a 256`.
# ---------------------------------------------------------------------------
want="$(awk '{print $1}' "${SUMS_PATH}")"
if [ -z "${want}" ]; then
  err "no checksum found in ${SUMS} — refusing to run an unverified binary"
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  got="$(sha256sum "${ASSET_PATH}" | awk '{print $1}')"
else
  got="$(shasum -a 256 "${ASSET_PATH}" | awk '{print $1}')"
fi
if [ "${want}" != "${got}" ]; then
  err "checksum MISMATCH for ${ASSET} (want ${want}, got ${got}) — aborting before run"
  exit 1
fi
CHECKSUM_RESULT="OK (${got})"
log "checksum verified: ${got}"

# ---------------------------------------------------------------------------
# 3. NOW it is safe to make the verified asset executable.
# ---------------------------------------------------------------------------
chmod +x "${ASSET_PATH}"

# ---------------------------------------------------------------------------
# 4. OBSERVE (report only — never mutate). Quarantine + ad-hoc codesign.
# ---------------------------------------------------------------------------
# Quarantine: absent on curl/gh downloads (clean); present only on browser
# downloads. We REPORT it and document the user-side fallback; we do NOT strip
# it here (D-07 — observe only, no `xattr -d`/`xattr -c`).
if quarantine="$(xattr -p com.apple.quarantine "${ASSET_PATH}" 2>/dev/null)"; then
  QUARANTINE_RESULT="PRESENT (${quarantine}) — browser download? to clear, see the runbook fallback (xattr delete, or right-click -> Open once)"
else
  QUARANTINE_RESULT="absent (clean — gh/curl download sets no quarantine)"
fi

# Codesign: ad-hoc signature MUST verify. We intentionally do NOT use `spctl`:
# Gatekeeper assessment ALWAYS rejects ad-hoc signatures (Pitfall 1 /
# build.sh:250-259), so an spctl rejection is meaningless here. `codesign
# --verify --verbose` success + the binary running is the real evidence.
if command -v codesign >/dev/null 2>&1; then
  if codesign --verify --verbose "${ASSET_PATH}" >/dev/null 2>&1; then
    CODESIGN_RESULT="OK (codesign --verify passed — ad-hoc signature valid)"
  else
    CODESIGN_RESULT="FAILED (codesign --verify — investigate; a Gatekeeper-assessment rejection alone is EXPECTED for ad-hoc signatures and is NOT a failure)"
  fi
else
  CODESIGN_RESULT="SKIPPED (no codesign — not on macOS?)"
fi

# ---------------------------------------------------------------------------
# 5. Run-the-binary evidence: version (expect a v1.0.0 / nightly string) and
#    doctor (expect exit 0). On non-arm64 hardware these may fail — that is
#    expected and reported, not fatal to the report block.
# ---------------------------------------------------------------------------
if VERSION_OUT="$("${ASSET_PATH}" version 2>&1)"; then
  VERSION_RESULT="${VERSION_OUT}"
else
  VERSION_RESULT="DID NOT RUN (exit $?) — wrong arch? run this on real Apple Silicon. Output: ${VERSION_OUT}"
fi

DOCTOR_OUT="$("${ASSET_PATH}" doctor 2>&1)" && DOCTOR_EXIT=0 || DOCTOR_EXIT=$?
DOCTOR_TAIL="$(printf '%s\n' "${DOCTOR_OUT}" | tail -3)"

# ---------------------------------------------------------------------------
# 6. Print a clearly delimited, copy-pasteable REPORT block.
# ---------------------------------------------------------------------------
cat <<REPORT

===== wezterm-setup Apple-Silicon first-launch report (INST-08) =====
machine arch     : ${ARCH}  (${OS})
release          : ${REPO}@${TAG}  asset=${ASSET}
checksum verify  : ${CHECKSUM_RESULT}
quarantine       : ${QUARANTINE_RESULT}
codesign verify  : ${CODESIGN_RESULT}
wez version      : ${VERSION_RESULT}
wez doctor exit  : ${DOCTOR_EXIT}  (expect 0)
wez doctor tail  : ${DOCTOR_TAIL}
=====================================================================
Paste this block into docs/macos-verification.md (Apple-Silicon first-launch
(INST-08) -> "paste the report here"). A clean report (checksum OK, codesign
verify OK, version v1.0.0, doctor exit 0) is what flips INST-08's macOS status
from deferred to verified.

REPORT

# Exit non-zero only on the hard security failure (checksum) — already handled
# above. A non-zero doctor on the wrong arch is reported, not fatal, so the user
# always gets a pasteable block.
exit 0
