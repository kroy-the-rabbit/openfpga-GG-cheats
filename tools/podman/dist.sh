#!/usr/bin/env bash
# Assemble a flashable Pocket core from a finished build.
#
# Quartus emits gg_pocket.rbf with the bit order the Cyclone V configuration
# engine wants. The Pocket's loader wants each byte bit-reversed. That reversal
# is the whole of what this does, plus copying the pkg/ tree around it.
#
# The output name is not ours to pick: core.json names the bitstream, and this
# name is whatever core.json says it is, not a constant in this script.
# Read it rather than hardcoding it, so a rename cannot quietly produce a
# package the Pocket refuses to load.
#
# This runs inside the Quartus image, not on the host, and re-executes itself
# there if it was started outside. The work is only byte transforms and file
# copying, so the container is not for Quartus: it is so that packaging is the
# same on a workstation, on any of the four runners and in a shell, rather than
# depending on what happens to be installed. The first P0 fit compiled cleanly
# for four minutes and then exited 127 here because a runner had no jq.
#
# DIST_NATIVE=1 stays on the host. QUARTUS_ROOTDIR does the same, so a machine
# with a native toolchain and no podman behaves as it does for build.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/tools/podman/version.sh"
VERSION=$(pocket_version "${RELEASE_NAME:-}")

PODMAN=${PODMAN:-podman}
IMAGE=${IMAGE:-localhost/pocket-quartus:25.1std}

if [[ -z "${DIST_IN_IMAGE:-}" && -z "${DIST_NATIVE:-}" && -z "${QUARTUS_ROOTDIR:-}" ]]; then
  # keep-id maps the calling user into the container so the package is owned by
  # whoever asked for it. It only exists in rootless podman, and a build runner
  # is root, which does not need the mapping. Key the flag on the uid, not on
  # the machine.
  USERNS=(--userns=keep-id)
  if [[ $(id -u) -eq 0 ]]; then USERNS=(); fi

  echo "== dist in $IMAGE"
  exec $PODMAN run --rm "${USERNS[@]}" --security-opt label=disable \
    -v "$ROOT:/work" -w /work -e HOME=/tmp \
    -e DIST_IN_IMAGE=1 \
    -e BUILD_NAME="${BUILD_NAME:-}" \
    -e REV="${REV:-}" \
    -e RELEASE_NAME="$VERSION" \
    "$IMAGE" bash /work/tools/podman/dist.sh
fi

NAME="${BUILD_NAME:-gg}"
REV="${REV:-gg_pocket}"

RBF="$ROOT/build/$NAME/work/projects/output_files/$REV.rbf"
OUT="$ROOT/build/$NAME/dist"

[ -f "$RBF" ] || { echo "no bitstream at $RBF; run 'make gg BUILD_NAME=$NAME' first" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
cp -r "$ROOT/pkg/." "$OUT/"
# .gitkeep only exists to keep the empty Assets directory in git; it has no
# business on an SD card or in a release archive.
find "$OUT" -name .gitkeep -delete

# One bitstream, one package per platform. The Pocket only delivers a ROM
# slot before the core starts when the slot is required, and a package can
# carry only one required ROM slot, so each platform gets its own Cores/
# directory around the same bitstream, as drizzt's openfpga-SMS does. The
# bit-reversed image is made once and copied.
#
# unpack 'b*' reads each byte LSB-first, pack 'B*' writes it MSB-first, so the
# round trip is exactly a per-byte bit reversal. Byte order is unchanged.
REVERSED="$(mktemp)"
perl -e 'binmode STDIN; binmode STDOUT; local $/; my $d = <STDIN>; print pack("B*", unpack("b*", $d));' \
     < "$RBF" > "$REVERSED"

echo "== dist $OUT"
for CORE_PATH in "$OUT"/Cores/*/; do
  CORE_DIR="$(basename "$CORE_PATH")"
  CORE_JSON="$CORE_PATH/core.json"

  # perl, not jq: the image has no jq, and perl is already a hard dependency
  # above for the bit reversal. Reading fields with a regex is only safe
  # because this JSON is ours; tools/check/manifests.sh is what actually
  # validates it, and that runs where jq exists.
  BITNAME="$(perl -0777 -ne '
    exit unless /"cores"\s*:\s*\[(.*?)\]/s;
    my $cores = $1;
    print $1 if $cores =~ /"filename"\s*:\s*"([^"]*)"/;
  ' "$CORE_JSON")"
  [ -n "$BITNAME" ] || { echo "$CORE_DIR/core.json does not name a bitstream" >&2; exit 1; }
  PID="$(perl -0777 -ne 'print $1 if /"platform_ids"\s*:\s*\[\s*"([^"]*)"/' "$CORE_JSON")"
  [ -n "$PID" ] || { echo "$CORE_DIR/core.json names no platform" >&2; exit 1; }

  cp "$REVERSED" "$CORE_PATH/$BITNAME"

  # Stamp the package; the checked-in manifest remains a template.
  tmp="$(mktemp)"
  V="$VERSION" D="$(pocket_version_date "$VERSION")" perl -0777 -pe '
    s/("version"\s*:\s*)"[^"]*"/$1"$ENV{V}"/;
    s/("date_release"\s*:\s*)"[^"]*"/$1"$ENV{D}"/;
  ' "$CORE_JSON" > "$tmp"
  mv "$tmp" "$CORE_JSON"

  # Release archive, laid out so it unzips straight onto the SD card root:
  # this core, its platform entry and image, and the Assets directory the
  # ROMs live in. Named after the core and its version.
  ZIP="$ROOT/build/$NAME/${CORE_DIR// /_}_${VERSION}.zip"
  rm -f "$ZIP"
  (cd "$OUT" && zip -qr "$ZIP" "Cores/$CORE_DIR" "Platforms/$PID.json" "Platforms/_images/$PID.bin" "Assets/$PID")

  echo "   core      $CORE_DIR ($PID)"
  echo "   bitstream $BITNAME, $(stat -c%s "$CORE_PATH/$BITNAME") bytes (from $REV.rbf, $(stat -c%s "$RBF") bytes)"
  echo "   release   $ZIP ($(stat -c%s "$ZIP") bytes)"
done
rm -f "$REVERSED"
echo "   stamped   version=$VERSION"
echo
echo "   Copy the contents of $OUT onto the Pocket's SD card root."
