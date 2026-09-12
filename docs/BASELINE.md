# Baseline

Every number here comes from a build on one of the runners, at `STANDARD FIT`,
on a named commit. Quartus exits 0 on a design that misses timing, so the gate
is `report.txt` and not the exit code, and one seed sizes nothing: identical
RTL on the GBA fork spans 81 ALMs and 497 ps across seeds, so a comparison is
two seeds or it is noise.

Device: **5CEBA4F23C8**, 18,480 ALMs, 308 M10K blocks, 3,153,920 block memory
bits, 224 pins.

## P0, the stripped port

All four builds are the same RTL: only docs and the harness moved between
them.

| commit | seed | ALMs | % | M10K | mem bits | registers | worst setup | worst hold | elapsed |
|---|---|---|---|---|---|---|---|---|---|
| `99f84f4` | 3 | 5,876 | 31.8 | 84 / 308 | 665,792 | 8,190 | +1.773 `clk_sys` | +0.075 `clk_sys` | 251 s |
| `b1f08e0` | 3 | 5,876 | 31.8 | 84 / 308 | 665,792 | 8,190 | +1.773 `clk_sys` | +0.075 `clk_sys` | 251 s |
| `6c0a718` | 3 | 5,876 | 31.8 | 84 / 308 | 665,792 | 8,190 | +1.773 `clk_sys` | +0.075 `clk_sys` | 251 s |
| `f8bd256` | 1 | **5,865** | 31.7 | 84 / 308 | 665,792 | 8,188 | **+2.852** `sdram_clk` | **+0.136** `clk_74a` | 232 s |

All on sisko2.

**Seed 3 against seed 1: 11 ALMs and 1.24 ns.** The three seed-3 builds are
identical to the digit, including which corner won, so run-to-run variance at
one seed on one runner is zero here as it is on the GBA fork. The seed is the
only knob that moved anything.

The 1.24 ns is on `clk_sys`, which went +1.773 at seed 3 to +3.012 at seed 1,
and it is larger than the 497 ps the GBA fork saw. That fork lived at 97 per
cent occupancy where the router has no choices left; at 32 per cent it has
plenty, and more freedom is more spread. Neither seed is anywhere near an edge,
so this is a note for later rather than a problem.

Per clock at seed 1, worst corner:

| clock | setup |
|---|---|
| `sdram_clk` | +2.852 |
| `clk_sys` 53.693181 MHz | +3.012 |
| `clk_74a` | +3.287 |
| `clk_vid` 5.369318 MHz | +8.345 |
| `bridge_spiclk` | +11.154 |

Two of those answer questions this file asked before the first build:

* **The SDRAM interface closes.** `sdram_clk` is analysed, not ignored, and it
  is the worst corner at seed 1 with 2.85 ns in hand. The output and input
  delays in `core_constraints.sdc` were guesses from the data sheet class of
  part and they are not tight.
* **The clk_sys to clk_vid crossing is real and passes.** Putting the PLL
  outputs in one clock group rather than three asynchronous ones was so that
  the analyser would look at the once-per-pixel handover into the video output
  stage. It does, and there is 8.3 ns of margin.

Other corners at seed 3, all on `clk_sys`:

| | slack |
|---|---|
| Recovery | +9.647 ns |
| Removal | +0.608 ns |
| Minimum pulse width | +0.776 ns |

DSP blocks 0 / 66. PLLs 1 / 4. Pins 224 / 224, which is every APF core: the
framework drives the whole package.

**The port fits with room.** A third of the device, a fifth of the block
memory, and 1.77 ns of setup margin at 53.693181 MHz. The GBA fork spent its
whole life at 96 to 97 per cent occupancy where "a fit is a lottery ticket";
this is not that design. The cheat engine, its overlay and the cartridge front
end have somewhere to go.

Two seeds have run and agree to 11 ALMs, so a later change that moves the
number by more than that has moved something real.

### The predictions, and what the fit said

Written before the first build so the reading is a check rather than a story
fitted to the number.

| predicted | outcome |
|---|---|
| the 256 KB external BIOS RAM should not be there | **confirmed.** `spram:ext_bios_inst` was synthesized away, all 2 Mbit of it |
| the Game Gear BIOS RAM should go the same way | **confirmed.** `spram:ext_gg_bios_inst` was synthesized away |
| the System E second VDP should not be there | **confirmed.** `vdp:vdp2_inst`'s memory was synthesized away |
| the SMS boot ROM may well survive, because `bootloader_n` is a register | **it did.** Accounting for the 665,792 bits leaves the 16 KB `mboot.mif` in place, and that is the intended reading |
| the YM2413 should not be there | **confirmed**, once `report.sh` learned to lift the by-entity table out of the fitter report. See below |

The block memory adds up as: 16 KB of VDP VRAM, 16 KB of work RAM, 32 KB of
backup RAM and 16 KB of boot ROM, which is 655,360 bits, plus 2,112 bits for
the ROM load queue and 8,192 for the APF datatable.

### What is actually in the fit

From the by-entity table in `report.txt`, at `6c0a718`. The fitter lists only
what survived, so this is the answer to the whole strip-by-constant question:
these six are every direct child of `system` that is left.

| entity | ALMs | share of the design |
|---|---:|---:|
| `vdp:vdp_inst` | 3,723.6 | 63% |
| `T80s:z80_inst` | 1,138.9 | 19% |
| `jt89:psg_inst` | 152.2 | 3% |
| `io:io_inst` | 29.7 | 0.5% |
| `AudioMix:mix` | 5.8 | |
| `sprom:boot_rom_inst` | 0 | 16 KB of block memory |

and outside the machine:

| entity | ALMs |
|---|---:|
| `core_bridge_cmd:icb` | 135.1 |
| `data_loader:rom_loader` | 89.9 |
| `sdram:ram` | 51.4 |
| `dpram:nvram_inst` | 11.3 |
| `spram:ram_inst` | 1.8 |
| `pin_ddio_clk:sdram_clk_out` | 0 |

**Nothing else is there.** `opll:fm`, `MC8123_rom_decrypt`, `SEGASYS1_DECT2`,
`cart_eeprom`, the second `vdp`, `spram:ext_bios_inst` and
`spram:ext_gg_bios_inst` are all absent from the table. The entities are listed
in ASCII order by entity name, and `vdp` is present as the last of them, so
this is absence and not a truncated report: `opll` would sit between `jt89` and
`sprom`, and it does not.

So tying the constants off in `gg_core.sv` did the whole job, and
`rtl/upstream/` never had to be edited.

**The VDP is the design.** `vdp_main` alone is 3,279.7 ALMs and `vdp_cram`
another 331.5. Anything that wants ALMs later should look there first, and the
obvious lever is `MAX_SPPL`.

### Knobs not yet turned

Each is a measurement, not a guess, and each wants two seeds:

* **`MAX_SPPL`.** `system` is instantiated at 63, upstream's setting, which is
  what gives the "extra sprites" option a buffer. A Game Gear draws eight
  sprites per line and 7 would be accurate and smaller. The by-entity table
  says this is where the ALMs are: `vdp_main` is 3,280 of the 5,876, more than
  half the design, and the sprite buffer and its comparators are inside it.
* **The SMS boot ROM.** 16 KB of block memory for a ROM a Game Gear never
  runs. It stays because `bootloader_n` is a register the fitter cannot fold,
  not because anything needs it.
* **`OPTIMIZATION_MODE`.** Left at Quartus's `BALANCED` so the baseline has as
  few knobs in it as possible.

None of them are worth spending a build on while a third of the device is in
use. They are written down so that the day something does not fit, the list
already exists.

## P1, the save slot

Two seeds, both on the same RTL as `f224504`'s docs-only diff from
`0c8d2af`.

| commit | seed | runner | ALMs | % | M10K | mem bits | registers | worst setup | worst hold | elapsed |
|---|---|---|---|---|---|---|---|---|---|---|
| `0c8d2af` | 1 | sisko2 | 6,067 | 32.8 | 84 / 308 | 665,792 | 8,795 | +2.551 `sdram_clk` | +0.068 `divclk` | 278 s |
| `f224504` | 3 | sisko | 6,057 | 32.8 | 84 / 308 | 665,792 | 8,846 | +1.962 `sdram_clk` | +0.072 `divclk` | 277 s |

**Seed 3 against seed 1: 10 ALMs, 0.589 ns setup, 0.004 ns hold.** Same
pattern as P0: the seed is the only knob that moved, and the two agree
closely.

**+180 to +200 ALMs over P0's two seeds, no new block memory.** The by-entity
table accounts for it directly: `data_loader:save_data_loader` is 70.7 ALMs
and `data_unloader:save_data_unloader` is 79.8 at seed 1, the pair the save
slot added to `core_top.v`. Block memory bits are unchanged at 665,792
because the save RAM was already `nvram_inst`, counted into that number
since P0; the slot reads and writes the block that was already there rather
than adding one.

Hold margin, 0.068 to 0.072 ns, is the tightest this project has produced,
and now confirmed at two seeds rather than resting on one: P0's own hold
numbers ranged 0.075 to 0.136 ns across its two seeds, so P1 sits just below
that range, consistently, not as noise. Still positive on both corners
checked; worth a glance if a later change tightens it further.

## P2 stage 1, both cheat mechanisms

Two seeds on one commit, so this is a real pair rather than two builds that
differ in their docs.

| commit | seed | runner | ALMs | % | M10K | mem bits | registers | worst setup | worst hold | elapsed |
|---|---|---|---|---|---|---|---|---|---|---|
| `379ff5c` | 1 | sisko | 6,779 | 36.7 | 77 / 308 | 600,928 | 10,493 | +2.759 `clk_74a` | +0.125 `divclk` | 303 s |
| `379ff5c` | 3 | sisko2 | 6,792 | 36.8 | 77 / 308 | 600,928 | 10,542 | +2.763 `clk_74a` | +0.085 `divclk` | 301 s |

**+712 to +725 ALMs over P1, and timing got better rather than worse.** That
was the thing this build was run to find out: P0 pruned `CODES` entirely, so
this is the first fit with a 32-way comparator back in the Z80 read path
(`system.vhd:525`), and P1's hold margin was already the tightest this project
had produced at 0.068 to 0.072 ns. It is now 0.085 to 0.125, and the worst
setup corner moved off `sdram_clk` to `clk_74a` with 2.76 ns in hand. The
comparator is wide but it is one level deep and the fitter had a third of the
device to spread it into.

Where the ALMs went, from the by-entity table at seed 1:

| entity | ALMs | registers |
|---|---:|---:|
| `CODES:GAMEGENIE` | 408.2 | 1,101 |
| `cheat_binloader:chtbin` | 52.9 | 251 |
| `data_loader:cheat_loader` | 44.4 | 148 |
| `cheat_poker:poker` | 19.2 | 35 |

That is 525 of the 712. The rest is glue: the second work RAM port, the two
settings registers, and the clock domain crossings for four readouts.

### The block memory went down, and that is correct

600,928 bits against P1's 665,792, and 77 M10K against 84. Adding a feature
does not shrink memory, so the drop was chased rather than accepted, and it
resolves exactly:

| | bits | M10K |
|---|---:|---:|
| work RAM, `spram` to `dpram` | -65,536 | -8 |
| `cheat_poker`'s table | +672 | +1 |
| net | **-64,864** | **-7** |

**P0 and P1 shipped 8 KB of work RAM that nothing could reach.** `ram_inst`
was declared `widthad_a(14)`, 16 KB, but a Game Gear has 8 KB at C000-DFFF and
the CPU side only ever drives `ram_a[12:0]`. Under `spram` the fitter could not
prove the top half dead, because one port carried both the CPU's reads and the
cold-clear's full 14-bit walk. Under `dpram` the CPU owns port A and reads only
the low 8 KB, the clear moved to port B, and `q_b` goes nowhere: the top half
is now written and never read, so the fitter removed it. The clear's walk still
counts to 16,383 and simply wraps, clearing the low 8 KB twice, which costs
nothing and is why this was left alone rather than narrowed to match.

### What the corpus made the converter handle

libretro's 818 Game Gear files are not clean, and each of these was found by
converting all of them rather than by reading the format:

| | count | what is done |
|---|---:|---|
| `+` where `-` belongs, so one code looks like three | 924 codes | split on both, regroup by group width |
| `X` or `?` for a value the player was meant to pick | 111 | skipped |
| a character that is neither hex nor a placeholder, mostly `O` for `0` | 14 | skipped, not corrected |
| more than 32 entries once expanded | 40 files | truncated at `CODES`' ceiling |
| a poke outside work RAM, all of them the placeholder `0000-0000` | 4 | skipped |

The refusals are deliberate. `O` for `0` is a tempting correction, but a
an address that is wrong writes into a running game once a frame, and the cost of
skipping is one cheat that does nothing.

## P2 stage 2, the .cht reader

`rtl/gg/cheat_loader.sv`, 607 lines, parses a plain libretro `.cht` into both
mechanisms beside `cheat_binloader.sv`. `core_top.v` reads the first four bytes
of the slot and sends the file to whichever reader claims it. No fit yet.

### It is checked against the converter, not eyeballed

`tools/sim/run.py` runs the RTL in Icarus over the corpus and diffs what it
pushes against `tools/cheats/gg2bin.py`, entry for entry and title for title.
**818 files, two passes each, 0 mismatches**, in 15 seconds on this machine.

Two passes per file because libretro ships every cheat in the corpus with
`enable = false`. The stock pass proves the enable path, where both sides must
produce nothing at all and would otherwise agree trivially; the second rewrites
those keys to true and is where the decode is compared. `--idle` covers the
other end-of-file path, the timer that fires when the download's falling edge
never arrives.

Four rules had to be picked deliberately, because the two sides would otherwise
have differed and a `.cht` would then behave differently from the `.chtbin` made
from it. Two were settled in the Python, on the grounds that the RTL's rule is
the one two siblings already ship:

| | | settled in |
|---|---|---|
| no `cheatN_enable` key at all | on, so a hand-written file of nothing but codes works | Python |
| `cheatN_enable = 1` | on, as well as `true` | Python |
| more than 32 entries | truncate mid-cheat, matching the converter's one entry list. `pocket-gba` drops the whole cheat instead, because a compare entry there suppresses the following slot, and nothing here couples one entry to the next | RTL |
| whitespace in a code field | leading and trailing allowed, interior not, which is what the converter's `.strip()` does | RTL |

None of the four occurs anywhere in the corpus. The cross-check is what surfaced
them, not the 818 files.

### What shaped the module

`cheatN_enable` comes after `cheatN_code`, so a cheat has to be staged before
its fate is known. `pocket-pcengine` stages optimistically and rolls back;
`CODES` cannot, because its index only ever increments. So this is
`pocket-gba`'s two-bank buffer with a deferred push, an `eof` input and an
idle-timer backstop.

The tokeniser is the part no sibling had. Both code formats are groups of hex
digits joined by `-` or `+`, and the corpus does not use the two consistently:
924 codes write one nine-digit Game Genie code as `058+BA8+E66`. So the code
boundary comes from the group *width*, threes taking three groups to a code and
fours taking two, and a field whose groups are not all one width contributes
nothing at all rather than being regrouped on a guess. Digits are kept in an
indexed array rather than shifted into a word, because the Game Genie address is
a permutation: `(d5 ^ 0xF)`, then `d2`, `d3`, `d4`, and the compare takes `d6`
and `d8` and discards `d7`.

### A second cheat file used to be misread

Both readers now reset on the *rising* edge of the download rather than on core
reset. `cheat_binloader.sv` arms its header check only out of reset, so before
this a second `.chtbin` loaded in one session would have been read as entries
from byte zero, with no header and no `code_reset`, appending to the first file's
codes until the 32 slots filled. Reachable by changing the cheat file from the
Pocket's menu without power cycling. Found while wiring the second reader, which
needs the same edge to clear its parser.

### The title store is in the fit, the overlay is not

`cheat_titles.sv` is wired to the parser's `desc_*` ports so the description
path is measured rather than stripped. Its one read port sits on the first
character of the first title and reports it at `CT:`, which is the only view of
the store until `cheat_osd.sv` exists and takes that port over. `CF:` reads back
which reader claimed the file.

## Hardware

2026-09-10, on a Pocket, from `Assets/gg/common`: a top-down RPG boots and
renders correctly. `Memories/Screenshots/20260910_150121.png` and
`...150124.png` on the card show correct colour, clean sprite rendering and no
tearing. Audio and controls confirmed working.

The `RQ:` readout first could not be read at all: its label, "ROM load
errors", was long enough to push the hex value off screen, wrapping to just
"0x". Fixed by shortening it to `RQ:`, matching the short-diagnostic-name
pattern `pocket-gba` already paid for (`CG:`, `CS:`, `SF:`, `EE:`). Re-checked
after the fix: **`RQ:` reads `0x00000000`.** The 64-entry queue in
`gg_core.sv` never overran loading this ROM, so the byte-per-eight-clk_sys
SDRAM writer kept up with the APF loader's bursts as designed.

Every hardware check P0 set out to make now passes: video, audio, controls,
and the diagnostic that would have caught a corrupted load.

**2026-09-11, saves, `f224504`.** `Eternal Legend - Eien no Densetsu (Japan)`
saved in game, exited to the menu, power cycled, reloaded, and the save was
there. Both directions of the slot work: the host read 32,768 bytes out of
`nvram_inst` on exit, the size the datatable reports, and wrote them back in
on the next load. On the card as
`Saves/gg/common/Eternal Legend - Eien no Densetsu (Japan).sav`, one written
region at `0x0310-0x05cf` and `0xFF` everywhere else. P1's exit criterion is
met for cart RAM; the EEPROM half of the slot has no Game Gear title that can
exercise it, see `PLAN.md` §9.3.

## Method

    R=../tools/runner-build
    SEED=1 $R start sisko  pocket-gg gg p0-s1 HEAD
    SEED=3 $R start sisko2 pocket-gg gg p0-s3 HEAD
    $R job   sisko2 pocket-gg gg p0-s3 HEAD
    $R fetch sisko2 pocket-gg gg p0-s3 HEAD

`start` bundles the commit, not the working tree, so commit first. `fetch`
resolves by commit and refuses when one runner holds two checkouts of the same
commit, so a seed retry goes to a different runner.

A fit is about four minutes on sisko2, not the 17 to 35 the sibling cores take:
this design is a fraction of their size.

## Things the harness got wrong, and when

* **2026-09-10, `99f84f4`.** The first fit compiled cleanly and then exited 127
  in `tools/podman/dist.sh`: the build runners have no `jq`. Four minutes of
  Quartus, a bitstream on the runner, and no package.

  The fix is not a different JSON reader. `dist.sh` now re-executes itself
  inside the Quartus image, so packaging runs against one known set of tools
  wherever it is started: a workstation, any of the four runners, or a shell.
  It reads the two fields it needs with `perl`, which the image has and which
  it already required for the bit reversal. `DIST_NATIVE=1` stays on the host.

* **2026-09-11, `f224504`.** The first P1 flash put P0 back on the card.
  `flash.sh` only unpacked the fetched zip when `build/gg/dist` was absent,
  and a dist tree from the P0 flash was still there, so the P1 zip was never
  opened: the card got P0's bitstream and a `data.json` with no save slot,
  and the save test failed for a reason that had nothing to do with the RTL.
  Found by checksum: the card's `gg.rbf_r` matched the stale tree, not the
  zip. `flash.sh` now re-unpacks whenever the zip is newer than the tree.
