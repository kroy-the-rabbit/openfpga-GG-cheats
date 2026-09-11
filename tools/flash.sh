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
# Builds run on the runners, and `runner-build fetch` brings back the release
# zip rather than the dist tree that made it. The zip is laid out to unpack
# straight onto the card, so unpack it here and flash that: one entry point
# whether the package was built on this machine or fetched from a runner.
#
# A zip newer than the dist tree replaces it. The first P1 flash did not do
# this: a dist tree left over from P0 sat beside the freshly fetched P1 zip,
# the zip was never opened, and the card got P0 again while every doc said P1.
zips=("$REPO/build/$NAME"/*.zip)
if [[ -f "${zips[0]}" && ( ! -d "$SRC" || "${zips[0]}" -nt "$SRC" ) ]]; then
  [[ ${#zips[@]} -eq 1 ]] || {
    echo "more than one zip in build/$NAME; unpack the one you want to $SRC" >&2
    printf '  %s\n' "${zips[@]}" >&2
    exit 1
  }
  echo "== unpacking $(basename "${zips[0]}") over $SRC"
  rm -rf "$SRC"
  mkdir -p "$SRC"
  unzip -q -o "${zips[0]}" -d "$SRC"
fi

[[ -d "$SRC" ]] || {
  echo "no package at $SRC and no zip in build/$NAME." >&2
  echo "Build on a runner and fetch it, or run 'make dist BUILD_NAME=$NAME'." >&2
  exit 1; }

if [[ -f "$REPO/build/$NAME/TIMING_FAILED" && -z "${FLASH_ANYWAY:-}" ]]; then
  echo "build/$NAME missed timing and is not fit to flash." >&2
  echo "FLASH_ANYWAY=1 overrides, and then it is on you." >&2
  exit 1
fi

CORE="$(ls "$SRC/Cores")"

# nullglob so a pattern with no match vanishes instead of ls treating it as a
# literal filename and failing: this core ships .rbf_r, a sibling ships .rev,
# and under `set -e -o pipefail` a failing ls took the whole script down even
# though the bitstream it needed was right there.
shopt -s nullglob
cands=("$SRC/Cores/$CORE"/*.rbf_r "$SRC/Cores/$CORE"/*.rev)
shopt -u nullglob
[[ ${#cands[@]} -gt 0 ]] || { echo "no bitstream in $SRC/Cores/$CORE" >&2; exit 1; }
RBF="$(basename -- "${cands[0]}")"

echo "== flashing $CORE ($RBF) onto $SD"

# Platforms/_images/ is shared: every core that declares a platform id points
# at the same file, so overwriting one here changes what every other core on
# the card shows. --ignore-existing on that directory alone means a real image
# already on the card is never replaced by a placeholder shipped here; a
# platform this repo is first to add still gets its image copied in.
# FLASH_PLATFORM_IMAGES=1 overrides, for the day pkg/Platforms/_images holds a
# real one and it is meant to replace what is there.
PLATIMG=()
[[ -n "${FLASH_PLATFORM_IMAGES:-}" ]] || PLATIMG=(--ignore-existing)

rsync -rt --no-perms --no-owner --no-group --exclude .gitkeep \
      --exclude Platforms/_images/ --itemize-changes \
      "$SRC/" "$SD/" | grep -E '^[>c]' || true
rsync -rt --no-perms --no-owner --no-group "${PLATIMG[@]}" --itemize-changes \
      "$SRC/Platforms/_images/" "$SD/Platforms/_images/" \
      | grep -E '^[>c]' | sed 's|^\([><c][a-zA-Z.+]*\) |\1 Platforms/_images/|' || true
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
