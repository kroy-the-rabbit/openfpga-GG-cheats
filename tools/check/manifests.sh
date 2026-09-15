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

# ---- one package per platform, one bitstream between them ------------------
# The Pocket only delivers a ROM slot before the core starts when the slot is
# required, and a package can hold only one required ROM slot (a second one
# spawns a file browser at every launch). Three ROM slots in one package put
# every platform on a white screen on 2026-09-15. So each platform gets its
# own Cores/ directory around the same bitstream, and these rules keep the
# three packages interchangeable copies of one core.
CORE_DIRS=(pkg/Cores/*/)
[[ ${#CORE_DIRS[@]} -ge 1 ]] || fail "no core under pkg/Cores"
bits=$(for d in "${CORE_DIRS[@]}"; do jq -r '.core.cores[0].filename' "$d/core.json"; done | sort -u)
[[ $(wc -l <<<"$bits") -eq 1 ]] || fail "the packages name different bitstreams: $(paste -sd' ' <<<"$bits")"
for shared in audio.json input.json interact.json variants.json; do
  n=$(for d in "${CORE_DIRS[@]}"; do sha256sum "$d/$shared" | cut -c1-16; done | sort -u | wc -l)
  [[ "$n" -eq 1 ]] || fail "$shared differs between packages; it describes the one bitstream"
done

check_core() {
  local CORE_DIR="${1%/}"
  local CORE_NAME; CORE_NAME="$(basename "$CORE_DIR")"

  # ---- every manifest is valid JSON ----------------------------------------
  for f in "$CORE_DIR"/*.json; do
    jq -e . "$f" >/dev/null 2>&1 || fail "$f is not valid JSON"
  done

  local CORE_JSON="$CORE_DIR/core.json"

  # ---- the core directory must be <author>.<shortname> ----------------------
  # A mismatch produces a core the Pocket lists and then refuses to start, with
  # "error in core setup" and nothing else to go on.
  local author short
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

  # ---- the bitstream must be named ------------------------------------------
  # dist.sh writes the reversed bitstream to whatever this says.
  local bit
  bit=$(jq -r '.core.cores[0].filename' "$CORE_JSON")
  [[ -n "$bit" && "$bit" != "null" ]] || fail "$CORE_NAME/core.json names no bitstream"

  # ---- no chip32 program ----------------------------------------------------
  # A chip32 program IS the loader: declaring one makes APF load only the slots
  # the program asks for, so any slot it does not name is never delivered.
  jq -e '.core.framework | has("chip32_vm")' "$CORE_JSON" >/dev/null 2>&1 \
    && fail "$CORE_NAME/core.json declares framework.chip32_vm; this core ships no chip32 program"

  # ---- version, held at 0.9999 ---------------------------------------------
  local ver
  ver=$(jq -r '.core.metadata.version' "$CORE_JSON")
  [[ "$ver" == "0.9999" ]] || fail "$CORE_NAME/core.json version is '$ver', every project in this tree sits at 0.9999"

  # ---- exactly one platform, with its Platforms/ entry ------------------------
  local np
  np=$(jq -r '.core.metadata.platform_ids | length' "$CORE_JSON")
  [[ "$np" -eq 1 ]] || fail "$CORE_NAME/core.json lists $np platforms; one package per platform"
  local pid
  for pid in $(jq -r '.core.metadata.platform_ids[]' "$CORE_JSON"); do
    [[ -f "pkg/Platforms/$pid.json" ]] || fail "$CORE_NAME claims platform '$pid' with no pkg/Platforms/$pid.json"
    [[ -f "pkg/Platforms/_images/$pid.bin" ]] || fail "no platform image pkg/Platforms/_images/$pid.bin"
    # 521x165, one 16-bit word per pixel. A single distinct word is a flat fill,
    # which is what shipped as the placeholder until 2026-09-14.
    [[ $(stat -c %s "pkg/Platforms/_images/$pid.bin") -eq 171930 ]] || fail "pkg/Platforms/_images/$pid.bin is not 171930 bytes"
    [[ $(od -An -tx2 -v "pkg/Platforms/_images/$pid.bin" | tr -s ' ' '\n' | sort -u | grep -c .) -gt 1 ]] || fail "pkg/Platforms/_images/$pid.bin is a flat fill"
    [[ -d "pkg/Assets/$pid/common" ]] || fail "no pkg/Assets/$pid/common for ROMs to live in"
  done

  # ---- core icon ------------------------------------------------------------
  # 36x36, one 16-bit word per pixel, 2592 bytes. tools/icon/genicon.py writes it.
  [[ -f "$CORE_DIR/icon.bin" ]] || fail "no $CORE_DIR/icon.bin"
  [[ $(stat -c %s "$CORE_DIR/icon.bin") -eq 2592 ]] || fail "$CORE_DIR/icon.bin is not 2592 bytes"

  # ---- data slots -----------------------------------------------------------
  local DATA_JSON="$CORE_DIR/data.json"
  if [[ -f "$DATA_JSON" ]]; then
    local dupe
    dupe=$(jq -r '.data.data_slots[].id' "$DATA_JSON" | sort | uniq -d)
    [[ -z "$dupe" ]] || fail "$CORE_NAME: duplicate data slot id: $dupe"

    # Two slots sharing an address prefix means two data_loader instances would
    # answer the same bridge writes.
    dupe=$(jq -r '.data.data_slots[] | select(.address != null) | .address[0:4]' "$DATA_JSON" | sort | uniq -d)
    [[ -z "$dupe" ]] || fail "$CORE_NAME: two data slots share an address prefix: $dupe"

    # The ROM is slot index 0 and the only required slot: APF delivers a slot
    # before start only when it is required, the Save slot's parameters clone
    # the filename of slot 0, and core_top.v writes the datatable size at
    # index 1, which has to be the Save slot.
    jq -e '.data.data_slots[0].required == true' "$DATA_JSON" >/dev/null \
      || fail "$CORE_NAME: data slot 0 (the ROM) is not required, so APF starts the core without it"
    local nreq
    nreq=$(jq -r '[.data.data_slots[] | select(.required == true)] | length' "$DATA_JSON")
    [[ "$nreq" -eq 1 ]] || fail "$CORE_NAME: $nreq required slots; a second one spawns a file browser at every launch"

    # A nonvolatile slot is written back to the card when the core exits. If
    # nothing in the core drives the datatable size for it, APF writes back
    # whatever the bridge happens to return, over a real save file.
    local nv
    nv=$(jq -r '[.data.data_slots[] | select(.nonvolatile == true)] | length' "$DATA_JSON")
    if [[ "$nv" != "0" ]]; then
      grep -q 'datatable_wren <= 1' target/pocket/core_top.v \
        || fail "$CORE_NAME/data.json declares $nv nonvolatile slot(s) but core_top.v never writes the datatable size"
      jq -e '.data.data_slots[1].nonvolatile == true' "$DATA_JSON" >/dev/null \
        || fail "$CORE_NAME: the nonvolatile slot is not data slot index 1, where core_top.v writes its size"
    fi
  fi

  # ---- interact variables ---------------------------------------------------
  local INT_JSON="$CORE_DIR/interact.json"
  if [[ -f "$INT_JSON" ]]; then
    local n
    n=$(jq -r '.interact.variables | length' "$INT_JSON")
    [[ "$n" -le 16 ]] || fail "$CORE_NAME/interact.json has $n variables; APF allows 16"

    dupe=$(jq -r '.interact.variables[].id' "$INT_JSON" | sort | uniq -d)
    [[ -z "$dupe" ]] || fail "$CORE_NAME: duplicate interact id: $dupe"

    dupe=$(jq -r '.interact.variables[].address' "$INT_JSON" | sort | uniq -d)
    [[ -z "$dupe" ]] || fail "$CORE_NAME: two interact variables share an address: $dupe"

    # Every address the menu writes has to be decoded, or the setting silently
    # does nothing.
    local a
    for a in $(jq -r '.interact.variables[].address' "$INT_JSON"); do
      grep -qi "32'h${a#0x}" target/pocket/core_top.v \
        || fail "interact.json address $a is not decoded in target/pocket/core_top.v"
    done
  fi

  # ---- video ----------------------------------------------------------------
  local VID_JSON="$CORE_DIR/video.json"
  if [[ -f "$VID_JSON" ]]; then
    n=$(jq -r '.video.scaler_modes | length' "$VID_JSON")
    [[ "$n" -ge 1 ]] || fail "$CORE_NAME/video.json declares no scaler modes"
    # More than one mode is only reachable if core_top.v sends APF's end-of-line
    # slot word; gg_core's video_mode is what it sends.
    if [[ "$n" -gt 1 ]]; then
      grep -q 'vmode_v, 13' target/pocket/core_top.v \
        || fail "$CORE_NAME/video.json declares $n scaler modes but core_top.v sends no slot word"
      [[ "$n" -le 8 ]] || fail "$CORE_NAME/video.json declares $n scaler modes; APF has slots 0 to 7"
    fi
  fi

  # ---- every file core.json names, other than the built bitstream -----------
  local f
  for f in $(jq -r '.core.cores[].filename' "$CORE_JSON"); do
    [[ "$f" == "$bit" ]] && continue
    [[ -f "$CORE_DIR/$f" ]] || fail "$CORE_NAME/core.json names $f, which is not in the package"
  done
}

for f in pkg/Platforms/*.json; do
  jq -e . "$f" >/dev/null 2>&1 || fail "$f is not valid JSON"
done
for d in "${CORE_DIRS[@]}"; do check_core "$d"; done

[[ $rc -eq 0 ]] && echo "manifests ok: $(for d in "${CORE_DIRS[@]}"; do basename "$d"; done | paste -sd' '), bitstream $bits"
exit $rc
