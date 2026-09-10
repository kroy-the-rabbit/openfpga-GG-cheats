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

## Hardware

2026-09-10, on a Pocket, from `Assets/gg/common`: a top-down RPG boots and
renders correctly. `Memories/Screenshots/20260910_150121.png` and
`...150124.png` on the card show correct colour, clean sprite rendering and no
tearing. Audio and controls confirmed working. The `RQ:` readout could not be
read: the label "ROM load errors" was long enough to push the hex value off
screen, wrapping to just "0x". Fixed by shortening the label to `RQ:`,
matching the short-diagnostic-name pattern `pocket-gba` already paid for
(`CG:`, `CS:`, `SF:`, `EE:`). Not yet re-checked on hardware.

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
