#!/usr/bin/env bash
# The APF manifests under pkg/ decide whether the Pocket lists the core, starts
# it, and hands it the right files. Every rule here is one the sibling forks
# paid for; pocket-pcengine/tools/cheats/check-manifests.sh is the original.
#
#   tools/check/manifests.sh     check, exit 1 on any failure
#
# grep, not rg: the CI runner has no ripgrep.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

rc=0
fail() { echo "FAIL: $*" >&2; rc=1; }

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

CORE_DIRS=(pkg/Cores/*/)
[[ ${#CORE_DIRS[@]} -eq 1 ]] || fail "expected exactly one core under pkg/Cores, found ${#CORE_DIRS[@]}"
CORE_DIR="${CORE_DIRS[0]%/}"
CORE_NAME="$(basename "$CORE_DIR")"

# ---- every manifest is valid JSON ------------------------------------------
for f in "$CORE_DIR"/*.json pkg/Platforms/*.json; do
  jq -e . "$f" >/dev/null 2>&1 || fail "$f is not valid JSON"
done

CORE_JSON="$CORE_DIR/core.json"

# ---- the core directory must be <author>.<shortname> ------------------------
# A mismatch produces a core the Pocket lists and then refuses to start, with
# "error in core setup" and nothing else to go on.
author=$(jq -r '.core.metadata.author' "$CORE_JSON")
short=$(jq -r '.core.metadata.shortname' "$CORE_JSON")
[[ "$CORE_NAME" == "$author.$short" ]] || fail "core directory is '$CORE_NAME', core.json says '$author.$short'"
case "$CORE_NAME" in
  *" "*) fail "core directory name contains a space: '$CORE_NAME'" ;;
esac
case "$CORE_NAME" in
  kroy.*) ;;
  *) fail "core directory is not a kroy.* fork name: '$CORE_NAME'" ;;
esac

# ---- the bitstream must be named, and named consistently --------------------
# dist.sh writes the reversed bitstream to whatever this says.
bit=$(jq -r '.core.cores[0].filename' "$CORE_JSON")
[[ -n "$bit" && "$bit" != "null" ]] || fail "core.json names no bitstream"

# ---- no chip32 program -----------------------------------------------------
# A chip32 program IS the loader: declaring one makes APF load only the slots
# the program asks for, so any slot it does not name is never delivered.
jq -e '.core.framework | has("chip32_vm")' "$CORE_JSON" >/dev/null 2>&1 \
  && fail "core.json declares framework.chip32_vm; this core ships no chip32 program"

# ---- version, held at 0.9999 -----------------------------------------------
ver=$(jq -r '.core.metadata.version' "$CORE_JSON")
[[ "$ver" == "0.9999" ]] || fail "core.json version is '$ver', every project in this tree sits at 0.9999"

# ---- platform ids match the Platforms/ entries ------------------------------
for pid in $(jq -r '.core.metadata.platform_ids[]' "$CORE_JSON"); do
  [[ -f "pkg/Platforms/$pid.json" ]] || fail "core.json claims platform '$pid' with no pkg/Platforms/$pid.json"
  [[ -f "pkg/Platforms/_images/$pid.bin" ]] || fail "no platform image pkg/Platforms/_images/$pid.bin"
  [[ -d "pkg/Assets/$pid/common" ]] || fail "no pkg/Assets/$pid/common for ROMs to live in"
done

# ---- data slots ------------------------------------------------------------
DATA_JSON="$CORE_DIR/data.json"
if [[ -f "$DATA_JSON" ]]; then
  dupe=$(jq -r '.data.data_slots[].id' "$DATA_JSON" | sort | uniq -d)
  [[ -z "$dupe" ]] || fail "duplicate data slot id: $dupe"

  # Two slots sharing an address prefix means two data_loader instances would
  # answer the same bridge writes.
  dupe=$(jq -r '.data.data_slots[] | select(.address != null) | .address[0:4]' "$DATA_JSON" | sort | uniq -d)
  [[ -z "$dupe" ]] || fail "two data slots share an address prefix: $dupe"

  # A nonvolatile slot is written back to the card when the core exits. If
  # nothing in the core drives the datatable size for it, APF writes back
  # whatever the bridge happens to return, over a real save file.
  nv=$(jq -r '[.data.data_slots[] | select(.nonvolatile == true)] | length' "$DATA_JSON")
  if [[ "$nv" != "0" ]]; then
    grep -q 'datatable_wren <= 1' target/pocket/core_top.v \
      || fail "data.json declares $nv nonvolatile slot(s) but core_top.v never writes the datatable size"
  fi
fi

# ---- interact variables ----------------------------------------------------
INT_JSON="$CORE_DIR/interact.json"
if [[ -f "$INT_JSON" ]]; then
  n=$(jq -r '.interact.variables | length' "$INT_JSON")
  [[ "$n" -le 16 ]] || fail "interact.json has $n variables; APF allows 16"

  dupe=$(jq -r '.interact.variables[].id' "$INT_JSON" | sort | uniq -d)
  [[ -z "$dupe" ]] || fail "duplicate interact id: $dupe"

  dupe=$(jq -r '.interact.variables[].address' "$INT_JSON" | sort | uniq -d)
  [[ -z "$dupe" ]] || fail "two interact variables share an address: $dupe"

  # Every address the menu writes has to be decoded, or the setting silently
  # does nothing.
  for a in $(jq -r '.interact.variables[].address' "$INT_JSON"); do
    grep -qi "32'h${a#0x}" target/pocket/core_top.v \
      || fail "interact.json address $a is not decoded in target/pocket/core_top.v"
  done
fi

# ---- video -----------------------------------------------------------------
VID_JSON="$CORE_DIR/video.json"
if [[ -f "$VID_JSON" ]]; then
  n=$(jq -r '.video.scaler_modes | length' "$VID_JSON")
  [[ "$n" -ge 1 ]] || fail "video.json declares no scaler modes"
  # This core drives no APF slot-select word, so a second mode could never be
  # reached. See target/pocket/core_top.v, the video section.
  [[ "$n" -le 1 ]] || fail "video.json declares $n scaler modes but core_top.v selects none"
fi

# ---- every file core.json names, other than the built bitstream -------------
for f in $(jq -r '.core.cores[].filename' "$CORE_JSON"); do
  [[ "$f" == "$bit" ]] && continue
  [[ -f "$CORE_DIR/$f" ]] || fail "core.json names $f, which is not in the package"
done

[[ $rc -eq 0 ]] && echo "manifests ok: $CORE_NAME, bitstream $bit"
exit $rc
