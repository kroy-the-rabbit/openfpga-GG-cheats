#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Convert a 521x165 PNG into the platform image the Pocket's library shows.

The format is not documented by Analogue. It was read back on 2026-09-14
from a community image on a card that sat beside its own PNG source, and
the mapping below matched every sampled pixel:

    521 x 165 pixels, greyscale
    one 16-bit little endian word per pixel, high byte zero
    the low byte is 255 minus the grey level: 0 is white, 255 is black
    column major with the columns reversed: index = (520 - x) * 165 + y
    171930 bytes, no header

The greys are snapped to a short palette so a rendered SVG comes out as
pixel art rather than a smear of anti-aliasing.

    tools/icon/genplatform.py <source.png> <dest.bin>
    tools/icon/genplatform.py --show <image.bin> <out.png>   # decode for a look

Needs Pillow, so run it from a venv:

    python3 -m venv build/gg/venv && build/gg/venv/bin/pip install pillow
"""
from __future__ import annotations

import struct
import sys

W, H = 521, 165
PALETTE = (0, 0x20, 0x30, 0x4a, 0x9a, 0xc8, 0xff)


def snap(v: int) -> int:
    return min(PALETTE, key=lambda p: abs(p - v))


def encode(png: str) -> bytes:
    from PIL import Image                                  # noqa: PLC0415
    src = Image.open(png).convert("L")
    if src.size != (W, H):
        sys.exit(f"{png}: {src.size[0]}x{src.size[1]}, want {W}x{H}")
    px = src.load()
    out = bytearray()
    for x in range(W - 1, -1, -1):                         # columns reversed
        for y in range(H):
            out += struct.pack("<H", 255 - snap(px[x, y]))
    return bytes(out)


def show(binpath: str, png: str) -> None:
    from PIL import Image                                  # noqa: PLC0415
    data = open(binpath, "rb").read()
    if len(data) != W * H * 2:
        sys.exit(f"{binpath}: {len(data)} bytes, want {W * H * 2}")
    img = Image.new("L", (W, H))
    px = img.load()
    for x in range(W):
        for y in range(H):
            px[x, y] = 255 - (struct.unpack_from("<H", data, ((W - 1 - x) * H + y) * 2)[0] & 0xFF)
    img.save(png)
    print(f"wrote {png}")


def main(argv: list[str]) -> int:
    if len(argv) == 3 and argv[0] == "--show":
        show(argv[1], argv[2])
        return 0
    if len(argv) != 2:
        sys.exit("usage: genplatform.py <source.png> <dest.bin> | --show <image.bin> <out.png>")
    blob = encode(argv[0])
    open(argv[1], "wb").write(blob)
    print(f"wrote {argv[1]}: {len(blob)} bytes from {argv[0]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
