#!/usr/bin/env bash
# The cheat converter still writes what cheat_binloader.sv reads.
#
# Field positions are asserted against the RTL's documented layout rather than
# against whatever the converter currently emits, so a change to either side
# that is not matched in the other fails here. The corpus is not needed: the
# cases below are written out by hand, including the ones the corpus taught us
# about (the '+' that should be a '-', the O typed for a zero, placeholders).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"

python3 - <<'PY'
import sys
sys.path.insert(0, "tools/cheats")
from gg2bin import convert, MAGIC, MAX_CODES
from ggcht import decode

def cht(*codes):
    out = [f"cheats = {len(codes)}"]
    for i, c in enumerate(codes):
        out += [f'cheat{i}_desc = "c{i}"', f'cheat{i}_code = "{c}"',
                f"cheat{i}_enable = true"]
    return "\n".join(out)

def entries(text, **kw):
    blob, n, warns = convert(text, **kw)
    assert blob[:4] == MAGIC, "magic"
    assert blob[4] == 1, "version"
    assert int.from_bytes(blob[6:8], "little") == n, "header count"
    assert len(blob) == 16 + 16 * n, "length"
    return [int.from_bytes(blob[16 + 16 * i:32 + 16 * i], "little")
            for i in range(n)], warns

def fields(w):
    return dict(replace=w & 0xFF, compare=(w >> 32) & 0xFF,
                addr=(w >> 64) & 0xFFFF, cmpflag=(w >> 96) & 1,
                poke=(w >> 127) & 1)

# The decode itself, against the one code checked by hand out of the ROM:
# Alien Syndrome's 010-75F-E66 replaces the byte at 0x0075, whose original
# value is 0x03. verify_genie.py is the wider check against a whole ROM set.
assert decode("01075FE66") == (0x0075, 0x01, 0x03), decode("01075FE66")

# Game Genie, nine digits, and the '+' separator 924 corpus codes use where a
# '-' belongs: both forms are one code, not three.
for form in ("010-75F-E66", "010+75F+E66"):
    (w,), warns = entries(cht(form))
    f = fields(w)
    assert f == dict(replace=0x01, compare=0x03, addr=0x0075, cmpflag=1, poke=0), (form, f)
    assert not warns, warns

# Six digits is the same minus the compare, so it replaces unconditionally.
(w,), _ = entries(cht("010-75F"))
f = fields(w)
assert f["cmpflag"] == 0 and f["compare"] == 0 and f["addr"] == 0x0075, f

# Pro Action Replay: a constant 00, a Z80 address, a byte. Poke bit set, and
# no compare, because a poke is a write and never a comparison.
(w,), _ = entries(cht("00C0-1509"))
f = fields(w)
assert f == dict(replace=0x09, compare=0, addr=0xC015, cmpflag=0, poke=1), f

# Two codes joined by '+' are two entries, and order is preserved.
ws, _ = entries(cht("00C0-1509+00C0-1609"))
assert [fields(w)["addr"] for w in ws] == [0xC015, 0xC016], ws

# Everything that must be refused rather than guessed at. A misread address
# writes into a running game once a frame, so each of these is a skip.
for bad, why in [("00CA-5DXX", "placeholder X"),
                 ("00CA-5D??", "placeholder ?"),
                 ("O10-75F-E66", "letter O for zero"),
                 ("010-75F-E66-AB", "not a whole number of groups"),
                 ("0000-0000", "poke outside work RAM")]:
    ws, warns = entries(cht(bad))
    assert ws == [] and warns, f"{why} was not refused: {bad}"

# An unedited corpus file has every cheat disabled, and that has to convert to
# an empty table: cheats are off at startup and the file decides, not a menu.
ws, _ = entries('cheats = 1\ncheat0_code = "010-75F-E66"\ncheat0_enable = false')
assert ws == [], ws
ws, _ = entries('cheats = 1\ncheat0_code = "010-75F-E66"\ncheat0_enable = false',
                enable_all=True)
assert len(ws) == 1, ws

# The ceiling is CODES' MAX_CODES and the excess is dropped, not wrapped:
# wrapping would overwrite codes already loaded.
ws, warns = entries(cht(*["00C0-1509"] * (MAX_CODES + 3)))
assert len(ws) == MAX_CODES and any("ceiling" in w for w in warns), (len(ws), warns)

print(f"cheats ok: {MAX_CODES}-entry ceiling, both code kinds, 5 refusals")
PY
