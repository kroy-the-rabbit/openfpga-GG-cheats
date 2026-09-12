#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Cross-check rtl/gg/cheat_loader.sv against tools/cheats/gg2bin.py.

Runs the RTL in Icarus Verilog over real libretro .cht files and diffs the
entries it pushes, in push order, against the Python model. The RTL is the
reference and the Python is what writes every .chtbin, so without this there is
no independent check on the converter at all.

    tools/sim/run.py                    # every .cht under $CHT_DB
    tools/sim/run.py -n 50              # a sample
    tools/sim/run.py path/to/one.cht    # named files
    tools/sim/run.py --idle             # the end-of-file backstop only

Every file runs twice. libretro ships the whole corpus with every cheat set to
`enable = false`, so the stock pass proves the enable path (both sides must
produce nothing at all) and would prove nothing about the decode. The second
pass rewrites those keys to true and is where the entries are compared.

This repo carries no corpus. Point CHT_DB at a directory of .cht files:

    CHT_DB="$HOME/.config/retroarch/cheats/Sega - Game Gear" tools/sim/run.py
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools", "cheats"))
import gg2bin  # noqa: E402

DB = os.environ.get("CHT_DB") or os.path.join(ROOT, "external", "cht")
BUILD = os.path.join(ROOT, "build", "sim")
SOURCES = ["tools/sim/tb_cheat_loader.sv", "rtl/gg/cheat_loader.sv"]

# Only the value of an _enable key is touched, so a description containing the
# word "false" is left alone.
ENABLE = re.compile(rb"(_enable\s*=\s*)false", re.I)

PUSH_G = re.compile(r"^PUSH G ([0-9a-f]{4}) ([0-9a-f]{2}) ([0-9a-f]{2}) ([01])$")
PUSH_P = re.compile(r"^PUSH P ([0-9a-f]{4}) ([0-9a-f]{2}) (\d+)$")
DESC = re.compile(r"^DESC (\d+) (\d+) (\d+)$")
DESCEND = re.compile(r"^DESCEND (\d+) (\d+)$")
TOTAL = re.compile(r"^TOTAL bytes=(\d+) cheats=(\d+) genie=(\d+) pokes=(\d+) "
                   r"overrun=(\d+)$")

TITLE_W = 26


def build(idle_bits: int | None = None) -> str:
    for t in ("iverilog", "vvp"):
        if shutil.which(t) is None:
            sys.exit(f"{t} is not on PATH; this check needs Icarus Verilog")
    os.makedirs(BUILD, exist_ok=True)
    out = os.path.join(BUILD, "tb_cheat_loader"
                       + ("" if idle_bits is None else f"_idle{idle_bits}"))
    cmd = ["iverilog", "-g2012", "-o", out]
    if idle_bits is not None:
        cmd += [f"-DIDLE_BITS={idle_bits}"]
    cmd += [os.path.join(ROOT, s) for s in SOURCES]
    subprocess.run(cmd, check=True)
    return out


def fold(text: str) -> str:
    """A name as cheat_titles ends up holding it: uppercased into 64 glyphs."""
    out = []
    for c in text[:TITLE_W]:
        up = ord(c.upper())
        out.append(chr(up if 32 <= up <= 95 else 32))
    return "".join(out)


def rtl(exe: str, path: str, use_eof: bool = True) -> tuple:
    # Through vvp by name rather than the compiled file's shebang, which hard
    # codes wherever iverilog was installed.
    r = subprocess.run(["vvp", exe, f"+f={path}", "+gap=4",
                        f"+eof={int(use_eof)}"],
                       capture_output=True, text=True, check=True)
    entries, totals = [], None
    titles: dict[int, list[str]] = {}
    lengths: dict[int, int] = {}
    for line in r.stdout.splitlines():
        if m := PUSH_G.match(line):
            a, v, c, f = m.groups()
            entries.append(("G", int(a, 16), int(v, 16),
                            int(c, 16) if f == "1" else None))
        elif m := PUSH_P.match(line):
            a, v, _ = m.groups()
            entries.append(("P", int(a, 16), int(v, 16)))
        elif m := DESC.match(line):
            g, col, ch = (int(x) for x in m.groups())
            titles.setdefault(g, [" "] * TITLE_W)[col] = chr(ch + 32)
        elif m := DESCEND.match(line):
            g, n = (int(x) for x in m.groups())
            lengths[g] = n
        elif m := TOTAL.match(line):
            totals = tuple(int(x) for x in m.groups())
    named = {g: "".join(titles.get(g, []))[:lengths.get(g, 0)]
             for g in set(titles) | set(lengths)}
    return entries, named, totals


def model(text: str) -> tuple:
    entries, names, warnings = gg2bin.model(text)
    want = []
    for e in entries:
        want.append(e if e[0] == "G" else ("P", e[1] & 0x1FFF, e[2]))
    truncated = any("is the ceiling" in w for w in warnings)
    return want, [fold(n) for n in names], truncated


def check(exe: str, path: str) -> list[str]:
    bad = []
    raw = open(path, "rb").read()
    name = os.path.basename(path)

    # Pass one: stock. Nothing may come out of either side.
    got, _, totals = rtl(exe, path)
    want, _, _ = model(raw.decode("utf-8", "replace"))
    if got or want:
        bad.append(f"{name}: stock file is not inert, rtl={len(got)} model={len(want)}")
    if totals and totals[4]:
        bad.append(f"{name}: overrun on the stock pass")

    # Pass two: every cheat enabled.
    with tempfile.NamedTemporaryFile(suffix=".cht", delete=False) as fh:
        fh.write(ENABLE.sub(rb"\1true", raw))
        tmp = fh.name
    try:
        got, names, totals = rtl(exe, tmp)
        want, wnames, truncated = model(open(tmp, encoding="utf-8",
                                             errors="replace").read())
        if got != want:
            bad.append(f"{name}: {len(got)} entries vs {len(want)}\n"
                       f"    rtl   {got[:6]}\n    model {want[:6]}")
        if totals and totals[4]:
            bad.append(f"{name}: overrun")
        # At the ceiling the model keeps the name of a cheat whose entries were
        # then truncated away, so the two only have to agree below it.
        if not truncated:
            for i, w in enumerate(wnames):
                if names.get(i, "") != w:
                    bad.append(f"{name}: title {i} {names.get(i, '')!r} != {w!r}")
    finally:
        os.unlink(tmp)
    return bad


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("-n", type=int, help="run a random sample of this many")
    ap.add_argument("-j", type=int, default=os.cpu_count())
    ap.add_argument("--idle", action="store_true",
                    help="only check the idle-timer end of file backstop")
    args = ap.parse_args()

    if args.idle:
        return idle_check()

    files = args.files
    if not files:
        if not os.path.isdir(DB):
            sys.exit(f"no corpus at {DB}; set CHT_DB")
        files = sorted(os.path.join(DB, f) for f in os.listdir(DB)
                       if f.endswith(".cht"))
    if args.n:
        random.seed(0)
        files = random.sample(files, min(args.n, len(files)))

    exe = build()
    bad, done = [], 0
    with cf.ThreadPoolExecutor(max_workers=args.j) as pool:
        for out in pool.map(lambda p: check(exe, p), files):
            bad += out
            done += 1
            if done % 50 == 0:
                print(f"  {done}/{len(files)}", file=sys.stderr)

    for b in bad:
        print(f"MISMATCH {b}")
    print(f"cheat_loader: {len(files)} files, {len(bad)} mismatches")
    return 1 if bad else 0


def idle_check() -> int:
    """The last cheat in a file has nothing after it to resolve its enable key.
    core_top pulses eof on the falling edge of the download; this proves the
    idle timer reaches the same answer when that edge never arrives."""
    exe = build(idle_bits=10)
    body = ('cheats = 1\n\ncheat0_desc = "Last"\ncheat0_code = "187-456-4CA"\n'
            'cheat0_enable = true\n')
    with tempfile.NamedTemporaryFile("w", suffix=".cht", delete=False) as fh:
        fh.write(body)
        tmp = fh.name
    try:
        with_eof, _, _ = rtl(exe, tmp, use_eof=True)
        no_eof, _, _ = rtl(exe, tmp, use_eof=False)
    finally:
        os.unlink(tmp)
    want, _, _ = model(body)
    ok = with_eof == want and no_eof == want
    print(f"idle backstop: eof={with_eof} idle={no_eof} model={want}")
    print("idle backstop ok" if ok else "idle backstop FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
