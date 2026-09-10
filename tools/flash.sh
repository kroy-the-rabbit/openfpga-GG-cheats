#!/usr/bin/env bash
# Merge a packaged core onto a mounted Pocket SD card, verify the bitstream
# landed intact, and unmount so the card is safe to pull.
#
#   tools/flash.sh                       find the card, flash build/gg/dist
#   tools/flash.sh /run/media/me/pocket  say where the card is
#   BUILD_NAME=foo tools/flash.sh        flash build/foo/dist instead
#
# Three rules, and all three are here because a Pocket card is somebody's whole
# collection:
#
#   * Merge, never delete. rsync runs without --delete, so nothing already on
#     the card is touched: not other cores, not saves, not ROMs.
#   * Find the card by its mount point, never by guessing a device node.
#   * Unmount when done. exFAT write-back means a card pulled without a flush
#     can hold a truncated bitstream that the Pocket then refuses.
#
# It also refuses to flash a build that missed timing, which report.sh records
# by leaving a TIMING_FAILED marker next to the report.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="${BUILD_NAME:-gg}"
SRC="$REPO/build/$NAME/dist"

SD="${1:-$(findmnt -rn -o TARGET | grep -E "^/run/media/$USER/" | head -1 || true)}"

[[ -n "$SD" && -d "$SD" ]] || { echo "no SD card mounted; pass the mount point" >&2; exit 1; }
[[ -d "$SD/Cores" && -d "$SD/Platforms" ]] || {
  echo "$SD has no Cores/ and Platforms/, so it is not a Pocket card" >&2; exit 1; }
[[ -d "$SRC" ]] || { echo "no package at $SRC; run 'make dist BUILD_NAME=$NAME' first" >&2; exit 1; }

if [[ -f "$REPO/build/$NAME/TIMING_FAILED" && -z "${FLASH_ANYWAY:-}" ]]; then
  echo "build/$NAME missed timing and is not fit to flash." >&2
  echo "FLASH_ANYWAY=1 overrides, and then it is on you." >&2
  exit 1
fi

CORE="$(ls "$SRC/Cores")"
RBF="$(cd "$SRC/Cores/$CORE" && ls -- *.rbf_r *.rev 2>/dev/null | head -1)"
[[ -n "$RBF" ]] || { echo "no bitstream in $SRC/Cores/$CORE" >&2; exit 1; }

echo "== flashing $CORE ($RBF) onto $SD"
rsync -rt --no-perms --no-owner --no-group --exclude .gitkeep --itemize-changes \
      "$SRC/" "$SD/" | grep -E '^[>c]' || true
sync

a="$(sha256sum "$SRC/Cores/$CORE/$RBF" | cut -c1-16)"
b="$(sha256sum "$SD/Cores/$CORE/$RBF"  | cut -c1-16)"
[[ "$a" == "$b" ]] || { echo "CHECKSUM MISMATCH: $a on disk, $b on the card" >&2; exit 1; }
echo "== verified $RBF ($a)"

if [[ -n "${NO_UNMOUNT:-}" ]]; then
  echo "== left mounted, NO_UNMOUNT is set. Eject before pulling the card."
else
  dev="$(findmnt -rn -o SOURCE "$SD")"
  udisksctl unmount -b "$dev" >/dev/null && echo "== unmounted $dev, safe to remove"
fi
