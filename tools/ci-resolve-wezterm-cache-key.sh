#!/usr/bin/env bash
# tools/ci-resolve-wezterm-cache-key.sh
#
# D-01 (corrected, 06.8): resolve the WezTerm nightly-asset cache key. Sources
# tools/bootstrap-wezterm.sh's own `latest_nightly_datestamp` VERBATIM (never
# re-implemented — the BASH_SOURCE-vs-$0 guard in that script means `main`
# never runs when it is SOURCED, the exact property tests/cli/bootstrap_update_test.lua
# already relies on). Falls back to today's UTC date when that resolution comes
# back empty (a degraded/unreachable upstream API — T-06-06-01-style graceful
# degradation; never a forced/fabricated datestamp).
#
# This is the ONLY place this resolution logic (including the UTC-date
# fallback) lives — never duplicated inline in .github/workflows/ci.yml again
# (cycle-2 MEDIUM-5, the project's existing thin-glue boundary per
# 06.8-CONTEXT.md's "Established Patterns" section).
#
# The resulting guarantee is reproducible-WITHIN-a-UTC-day (an unchanged UTC day
# never re-downloads and always reuses byte-identical bits) — NOT a cryptographic
# pin to an immutable artifact, because no such artifact is fetchable for this
# asset upstream (06.8-CONTEXT.md D-01, corrected).
#
# Stdout contract: prints exactly ONE line — the resolved 8-digit YYYYMMDD cache
# key. Stderr: which resolution branch was taken (visible in the job log instead
# of invisible forever — cycle-3 MEDIUM-1).
#
# Usage:  tools/ci-resolve-wezterm-cache-key.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=tools/bootstrap-wezterm.sh
# Sourcing (never executing) — the BASH_SOURCE[0]-vs-$0 guard at the bottom of
# bootstrap-wezterm.sh means `main` does not run here.
. "${SCRIPT_DIR}/bootstrap-wezterm.sh"

datestamp="$(latest_nightly_datestamp || true)"

if [ -n "${datestamp}" ]; then
  echo "resolved via latest_nightly_datestamp" >&2
else
  datestamp="$(date -u +%Y%m%d)"
  echo "resolved via UTC-date fallback" >&2
fi

printf '%s\n' "${datestamp}"
