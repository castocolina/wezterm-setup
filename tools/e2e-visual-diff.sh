#!/usr/bin/env bash
# tools/e2e-visual-diff.sh
#
# Dimension/decode-checked RMSE comparator for Tier 4 visual diffs (D-05).
#
# Usage:
#   tools/e2e-visual-diff.sh <fresh.png> <baseline.png> [threshold]
#
# RMSE (Root Mean Squared Error) is resolution-independent and tolerates
# anti-aliasing/font-hinting noise between runs on the SAME machine better
# than pixel-exact AE. Default threshold 0.05 (5%). Override via the optional
# third argument or WEZ_E2E_VISUAL_THRESHOLD (the third argument wins).
#
# BASH-3.2 SAFE (macOS ships bash 3.2): only POSIX builtins; no bash-4-only
# array-read builtins (mapfile/readarray), no associative arrays (declare -A),
# no in-place case-expansion (${var^^}). Clean under `bash -n` and
# `shellcheck -x`.
#
# Exit 0 when the parsed RMSE is <= threshold (similar enough — PASS).
# Exit 1 otherwise (FAIL), including decode failure and dimension mismatch.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}" || exit 1

usage() {
  echo "usage: tools/e2e-visual-diff.sh <fresh.png> <baseline.png> [threshold]" >&2
  exit 1
}

[ $# -ge 2 ] || usage

FRESH=$1
BASELINE=$2
if [ $# -ge 3 ]; then
  THRESHOLD=$3
elif [ -n "${WEZ_E2E_VISUAL_THRESHOLD:-}" ]; then
  THRESHOLD=$WEZ_E2E_VISUAL_THRESHOLD
else
  THRESHOLD=0.05
fi

# Paths may be absolute (typical) or relative to the caller's original CWD.
# After cd'ing to REPO_ROOT above, re-anchor non-absolute paths against OLDPWD.
if [ -n "${OLDPWD:-}" ]; then
  case "$FRESH" in
    /*) ;;
    *) FRESH="${OLDPWD}/${FRESH}" ;;
  esac
  case "$BASELINE" in
    /*) ;;
    *) BASELINE="${OLDPWD}/${BASELINE}" ;;
  esac
fi

cannot_decode() {
  _file=$1
  if [ ! -e "$_file" ]; then
    echo "cannot decode: $_file (missing)" >&2
    return 1
  fi
  if ! identify "$_file" >/dev/null 2>&1; then
    echo "cannot decode: $_file" >&2
    return 1
  fi
  return 0
}

cannot_decode "$FRESH" || exit 1
cannot_decode "$BASELINE" || exit 1

FRESH_DIM=$(identify -format '%wx%h' "$FRESH")
BASELINE_DIM=$(identify -format '%wx%h' "$BASELINE")
if [ "$FRESH_DIM" != "$BASELINE_DIM" ]; then
  echo "dimension mismatch: fresh=${FRESH_DIM} baseline=${BASELINE_DIM}" >&2
  exit 1
fi

# Probe 01 (ImageMagick 7.1.2-27 on this box, .tmp/probes/06.9-tier4-visual/01-imagemagick-rmse.md):
# `compare -metric RMSE a.png b.png null:` writes `<raw> (<normalized>)` to
# STDERR with NO trailing newline. Identical 100x100 PNGs: `0 (0)` exit 0.
# Solid-color mismatch of the same size: `53509.1 (0.816497)` exit 1.
# compare's own exit 1 means "images differ", not "command failed" — parse the
# parenthesized normalized (0..1) value and ignore that exit code.
CMP_OUT=$(compare -metric RMSE "$FRESH" "$BASELINE" null: 2>&1) || true
NORMALIZED=$(printf '%s\n' "$CMP_OUT" | sed -n 's/.*(\([0-9.][0-9.]*\)).*/\1/p' | awk 'END { print }')
if [ -z "$NORMALIZED" ]; then
  echo "cannot decode: compare did not print a parenthesized RMSE value: ${CMP_OUT}" >&2
  exit 1
fi

echo "rmse=${NORMALIZED} threshold=${THRESHOLD} dimensions=${FRESH_DIM}"

awk -v rmse="$NORMALIZED" -v th="$THRESHOLD" 'BEGIN { exit (rmse + 0 <= th + 0) ? 0 : 1 }'
