#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render a frame of rtl/gg/cheat_osd.sv and read the text back off it.

tb_cheat_osd.sv parses a .cht, draws one 160x144 frame and prints it as
characters. This decodes the picture through the same font the RTL drew it with
and asserts on the words, which is the only way to catch a column shift or an
off-by-one row: both still produce a plausible looking panel.

    tools/sim/run_osd.py            # the built-in cases
    tools/sim/run_osd.py x.cht      # render one file and print what it says
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "cheats"))
import genfont  # noqa: E402

BUILD = os.path.join(ROOT, "build", "sim")
SOURCES = ["tools/sim/tb_cheat_osd.sv", "rtl/gg/cheat_osd.sv",
           "rtl/gg/cheat_loader.sv", "rtl/gg/cheat_titles.sv",
           "rtl/gg/cheat_font.sv"]

CELL, COLS, ROWS = 6, 26, 18
ROW = re.compile(r"^ROW (\d+) \|(.*)\|$")
COUNTS = re.compile(r"^COUNTS cheats=(\d+) codes=(\d+)$")

# The glyph a rendered cell holds, keyed by its seven 5-bit rows.
GLYPHS = {tuple(g[:7]): chr(32 + i) for i, g in enumerate(genfont.glyphs())}


def build() -> str:
    for t in ("iverilog", "vvp"):
        if shutil.which(t) is None:
            sys.exit(f"{t} is not on PATH; this check needs Icarus Verilog")
    os.makedirs(BUILD, exist_ok=True)
    out = os.path.join(BUILD, "tb_cheat_osd")
    subprocess.run(["iverilog", "-g2012", "-o", out]
                   + [os.path.join(ROOT, s) for s in SOURCES], check=True)
    return out


def render(exe: str, path: str) -> tuple[list[str], tuple[int, int]]:
    r = subprocess.run(["vvp", exe, f"+f={path}"], capture_output=True,
                       text=True, check=True)
    pic: dict[int, str] = {}
    counts = (0, 0)
    for line in r.stdout.splitlines():
        if m := ROW.match(line):
            pic[int(m.group(1))] = m.group(2)
        elif m := COUNTS.match(line):
            counts = (int(m.group(1)), int(m.group(2)))
    if "X" in "".join(pic.values()):
        bad = [y for y, l in pic.items() if "X" in l]
        sys.exit(f"the picture has undriven pixels on rows {bad[:8]}")
    return [pic[y] for y in sorted(pic)], counts


def text_rows(pic: list[str]) -> list[str]:
    """The picture as one string per text row, decoded through the font."""
    out = []
    for tr in range(ROWS):
        line = ""
        for col in range(COLS):
            bits = []
            for gr in range(7):
                px = pic[tr * 8 + gr][col * CELL:col * CELL + CELL]
                v = 0
                for x in range(5):
                    if px[x] == "#":
                        v |= 0x80 >> x
                bits.append(v)
            line += GLYPHS.get(tuple(bits), "?")
        out.append(line.rstrip())
    return out


def run(exe: str, name: str, body: str, want: list[str]) -> list[str]:
    with tempfile.NamedTemporaryFile("w", suffix=".cht", delete=False) as fh:
        fh.write(body)
        tmp = fh.name
    try:
        rows = text_rows(render(exe, tmp)[0])
    finally:
        os.unlink(tmp)
    bad = []
    for i, w in enumerate(want):
        if rows[i] != w:
            bad.append(f"{name}: row {i} is {rows[i]!r}, want {w!r}")
    return bad


CHEAT = ('cheats = 3\n\n'
         'cheat0_desc = "Infinite Rings"\ncheat0_code = "187-456-4CA"\n'
         'cheat0_enable = true\n\n'
         'cheat1_desc = "Keep Shield"\ncheat1_code = "00C8-0418+00C8-0600"\n'
         'cheat1_enable = true\n\n'
         'cheat2_desc = "All Emeralds"\ncheat2_code = "775-FB5-190+3A6-C46-C41"\n'
         'cheat2_enable = true\n')

# 26 characters exactly, and one longer, to pin the truncation.
LONG = ('cheats = 1\n\ncheat0_desc = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123"\n'
        'cheat0_code = "187-456-4CA"\ncheat0_enable = true\n')

OFF = ('cheats = 1\n\ncheat0_desc = "Not Wanted"\ncheat0_code = "187-456-4CA"\n'
       'cheat0_enable = false\n')


def main() -> int:
    exe = build()
    if len(sys.argv) > 1:
        for row in text_rows(render(exe, sys.argv[1])[0]):
            print(f"  |{row}|")
        return 0

    bad = []
    # A single-digit count still reserves its tens column, blank rather than
    # dropped, so a real row here carries a leading space and a doubled one
    # before the second count. digit() in cheat_osd.sv is what decides that.
    bad += run(exe, "three cheats", CHEAT,
               [" 3 CHEATS  5 CODES", "INFINITE RINGS", "KEEP SHIELD",
                "ALL EMERALDS", ""])
    bad += run(exe, "truncation", LONG,
               [" 1 CHEATS  1 CODES", "ABCDEFGHIJKLMNOPQRSTUVWXYZ", ""])
    bad += run(exe, "nothing enabled", OFF, ["NO CHEATS LOADED", ""])

    for b in bad:
        print(f"MISMATCH {b}")
    print(f"cheat_osd: {3 if not bad else 3} cases, {len(bad)} mismatches")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
