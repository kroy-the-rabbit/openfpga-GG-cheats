#!/usr/bin/env bash
# rtl/upstream/ is vendored verbatim from MiSTer-devel/SMS_MiSTer and is never
# edited in place (docs/PROVENANCE.md). This checks every file under it against
# docs/upstream.sha256: changed, added and missing files all fail.
#
#   tools/check/provenance.sh          check, exit 1 on drift
#   tools/check/provenance.sh --regen  rewrite the manifest after a sync
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT/docs/upstream.sha256"
cd "$ROOT"

listed() { find rtl/upstream -type f | LC_ALL=C sort; }

if [[ "${1:-}" == "--regen" ]]; then
  listed | xargs sha256sum > "$MANIFEST"
  echo "wrote $(wc -l < "$MANIFEST") entries to docs/upstream.sha256"
  exit 0
fi

test -f "$MANIFEST" || { echo "no $MANIFEST; run with --regen once" >&2; exit 1; }

rc=0
if ! sha256sum -c --quiet "$MANIFEST"; then
  echo "FAIL: rtl/upstream differs from docs/upstream.sha256" >&2
  rc=1
fi
extra=$(comm -13 <(awk '{print $2}' "$MANIFEST" | LC_ALL=C sort) <(listed))
if [[ -n "$extra" ]]; then
  echo "FAIL: files under rtl/upstream not in the manifest:" >&2
  printf '  %s\n' $extra >&2
  rc=1
fi
[[ $rc -eq 0 ]] && echo "provenance ok: $(wc -l < "$MANIFEST") upstream files unchanged"
exit $rc
