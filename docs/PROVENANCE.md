# Provenance

## Upstream

`MiSTer-devel/SMS_MiSTer`, commit `1fc3c121c16c91d83ed714dfef71df078205ded4`,
2026-08-31, "Adjust aspect ratio for 248x192 resolution." Sorgelig's MiSTer
port of Ben's Sega Master System for the Papilio. Licence in the file headers:
GNU GPL version 2 or later. The remote is `upstream`, fetch only, push URL
`DISABLED`.

## What is vendored, and where

`rtl/upstream/` is the upstream `rtl/` directory byte for byte, plus `SMS.sv`
and `files.qip` from the repository root, kept as the reference for the
MiSTer-side wiring. Nothing else from upstream is here: not `sys/` (the
DE10-nano framework, which the Pocket does not use), not `mist/`, not
`releases/`, not `SMSBootLoader/` (its output, `mboot.mif`, is in `rtl/`).

`mboot.mif` is Bock's SMS Boot Loader (SMS Power, 2001), a free boot ROM the
upstream ships. It runs in Master System mode only.

## Rules

1. **`rtl/upstream/` is never edited.** A file that needs a Pocket change is
   copied to `rtl/gg/` and the copy is edited, with its header intact and a
   line saying what changed and why. The project file lists the copy, not
   the original. `tools/check/provenance.sh` verifies every file under
   `rtl/upstream/` against `docs/upstream.sha256` and fails `make test` on
   any drift, added file or missing file.
2. **Attribution stays.** Upstream headers, copyright lines and licence
   notices are kept verbatim in every copied file. Nothing here removes an
   author.
3. **Syncing upstream** is `git fetch upstream`, then a diff of
   `upstream/master:rtl` against `rtl/upstream/`, applied by copying the files
   in and regenerating the manifest:

        tools/check/provenance.sh --regen

   Record the new commit and date at the top of this file in the same commit.
4. **The bitstream is not upstream's.** Everything under `target/`, `pkg/`
   and `rtl/gg/` is this project's, under the licence in `LICENSE`.

## From the sibling cores, not from upstream

`rtl/upstream/` is MiSTer's. These came from the sibling Pocket cores
instead, and the licence line in each is theirs, GPL-3.0-or-later, not this
repository's GPLv2. Upstream's "or later" permits that; it also means the
combined work is GPL-3.

| file | from | changed |
|---|---|---|
| `rtl/gg/cheat_font.sv` | `pocket-pcengine`, byte-identical in every sibling | nothing. `tools/cheats/genfont.py --check` regenerates it and confirms the copy |
| `rtl/gg/cheat_titles.sv` | `pocket-pcengine`, byte-identical in every sibling | nothing |
| `rtl/gg/cheat_poker.sv` | `pocket-pcengine` | comments, and the work RAM it writes into. Logic unchanged |
| `rtl/gg/cheat_osd.sv` | `pocket-gbc`, not `pocket-pcengine` | comments; the pipeline collapsed from three delay stages to two, matching `cheat_titles`' true one-cycle read latency instead of the two the sibling comment assumed |
| `tools/cheats/genfont.py` | `pocket-gbc` | the output path, `src/gb/` to `rtl/gg/` |
| `tools/podman/Containerfile` | `pocket-gbc` | the header's project name |
| `tools/podman/fetch-installers.sh` | `pocket-gbc` | nothing |
| `tools/podman/compare.sh` | `pocket-pcengine` | the default revision, `gg_pocket` |
| `tools/icon/genicon.py` | `pocket-gbc`, `tools/cheats/genicon.py` | the venv path in the usage note |

`rtl/gg/cheat_binloader.sv` is this project's, but its shape is
`pocket-gba`'s: the magic interlock, the byte counter, the shift register and
the two-state sequencer.

`rtl/gg/cheat_loader.sv` is the same kind of thing. The keyword lexer and the
two-bank deferred-push buffer are `pocket-gba`'s, which took the lexer in turn
from the GB/GBC fork; the title streaming is `pocket-pcengine`'s, whose
`desc_*` ports already matched `cheat_titles`. The tokeniser is new, because no
sibling has this machine's two code formats or a Game Genie address that is a
permutation of its digits.

The picker keeps byte-identical copies of each core's host-side decoder and
`make sync-check` there compares them, so this repository's are named to sit
beside the existing ones without collision: `tools/cheats/ggcht.py` beside
`gbacht.py`, `tools/cheats/gg2bin.py` beside `cht2bin.py`.

## Artwork

`assets/icon-gg.svg`, `icon-sms.svg` and `icon-sg1000.svg` are this
project's. `make icon` renders them through ImageMagick and
`tools/icon/genicon.py` into `pkg/Cores/kroy.*/icon.bin`:
36x36, one little-endian 16-bit word per pixel, intensity in the low byte,
column major. The order was confirmed against shipped third-party icons on
2026-09-14; a row-major file shows transposed on the Pocket.

`assets/platform-gg.svg`, `platform-sms.svg` and `platform-sg1000.svg` are
this project's too. `make platform` renders them into `pkg/Platforms/_images/`: 521x165, one little-endian 16-bit word per
pixel, the low byte is 255 minus the grey level, stored column major with the
columns reversed. That format was read back from a community image sitting
beside its PNG source on the card. No third-party image is shipped.
