# Baseline

Every number here comes from a build on one of the runners, at `STANDARD FIT`,
on a named commit. Quartus exits 0 on a design that misses timing, so the gate
is `report.txt` and not the exit code, and one seed sizes nothing: identical
RTL on the GBA fork spans 81 ALMs and 497 ps across seeds, so a comparison is
two seeds or it is noise.

Device: **5CEBA4F23C8**, 18,480 ALMs, 308 M10K blocks, 3,153,920 block memory
bits, 224 pins.

## P0, the stripped port

| commit | seed | ALMs | % | M10K | mem bits | registers | setup | hold | runner | elapsed |
|---|---|---|---|---|---|---|---|---|---|---|
| `99f84f4` | 3 | **5,876** | 31.8 | 84 / 308 | 665,792 (21%) | 8,190 | **+1.773** | **+0.075** | sisko2 | 251 s |
| `b1f08e0` | 3 | 5,876 | 31.8 | 84 / 308 | 665,792 (21%) | 8,190 | +1.773 | +0.075 | sisko2 | 251 s |
| | 1 | | | | | | | | | |

`b1f08e0` changed only the harness, and at the same seed on the same runner it
came back identical to the digit, including which corner won. That matches the
GBA fork's finding that run-to-run variance at one seed on one host is zero and
the seed is the only knob that moves the number. It is not a second seed.

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

Only one seed has run. The second is what makes any later comparison mean
anything, and it has not been done.

### The predictions, and what the fit said

Written before the first build so the reading is a check rather than a story
fitted to the number.

| predicted | outcome |
|---|---|
| the 256 KB external BIOS RAM should not be there | **confirmed.** `spram:ext_bios_inst` was synthesized away, all 2 Mbit of it |
| the Game Gear BIOS RAM should go the same way | **confirmed.** `spram:ext_gg_bios_inst` was synthesized away |
| the System E second VDP should not be there | **confirmed.** `vdp:vdp2_inst`'s memory was synthesized away |
| the SMS boot ROM may well survive, because `bootloader_n` is a register | **it did.** Accounting for the 665,792 bits leaves the 16 KB `mboot.mif` in place, and that is the intended reading |
| the YM2413 should not be there | **not proven either way.** Nothing in the fit report names it, and 5,876 ALMs is small enough to suggest it went, but that is inference. `report.sh` now lifts the by-entity table out of the fitter report so the next build answers it outright |

The block memory adds up as: 16 KB of VDP VRAM, 16 KB of work RAM, 32 KB of
backup RAM and 16 KB of boot ROM, which is 655,360 bits, and about 10 K of
small FIFOs on top.

### Knobs not yet turned

Each is a measurement, not a guess, and each wants two seeds:

* **`MAX_SPPL`.** `system` is instantiated at 63, upstream's setting, which is
  what gives the "extra sprites" option a buffer. A Game Gear draws eight
  sprites per line and 7 would be accurate and smaller.
* **The SMS boot ROM.** 16 KB of block memory for a ROM a Game Gear never
  runs. It stays because `bootloader_n` is a register the fitter cannot fold,
  not because anything needs it.
* **`OPTIMIZATION_MODE`.** Left at Quartus's `BALANCED` so the baseline has as
  few knobs in it as possible.

None of them are worth spending a build on while a third of the device is in
use. They are written down so that the day something does not fit, the list
already exists.

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
