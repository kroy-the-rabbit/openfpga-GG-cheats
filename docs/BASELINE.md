# Baseline

Every number here comes from a build on one of the runners, at `STANDARD FIT`,
on a named commit. Quartus exits 0 on a design that misses timing, so the gate
is `report.txt` and not the exit code, and one seed sizes nothing: identical
RTL on the GBA fork spans 81 ALMs and 497 ps across seeds, so a comparison is
two seeds or it is noise.

Device: **5CEBA4F23C8**, 18,480 ALMs, 308 M10K blocks, 3,153,920 block memory
bits, 224 pins.

## P0, the stripped port

Not yet measured. The rows below are what the first two fits fill in.

| commit | seed | ALMs | % | M10K | mem bits | setup | hold | runner | elapsed |
|---|---|---|---|---|---|---|---|---|---|
| | 1 | | | | | | | | |
| | 3 | | | | | | | | |

### What the fit is expected to say, and what would be a surprise

Recorded before the first build so the reading afterwards is a check and not a
story fitted to the number.

* **The System E and SG-1000 hardware should not be there.** `gg_core.sv` ties
  `systeme`, `encrypt`, `sc3000_en`, `sk1100_en`, `has_paddle` and `has_pedal`
  to constants rather than cutting anything out of `system.vhd`, on the theory
  that Quartus propagates the constants and removes the second VDP, the second
  PSG, `MC8123_rom_decrypt` and `SEGASYS1_DECT2`. If the fit is much larger
  than the Master System has any right to be, that theory is where to look
  first, and the answer is a `rtl/gg/` copy of `system.vhd` rather than a
  toolchain setting.
* **The YM2413 should not be there.** `fm_ena` is tied low, which makes
  `FM_gated` a constant and leaves the VM2413 instance with no readers. A real
  Game Gear has no FM chip, so its presence in the fit would be pure waste.
* **The 256 KB external BIOS RAM should not be there.** `system.vhd`
  instantiates a `spram` of `widthad_a => 18` unconditionally, which is 2 Mbit,
  two thirds of the whole device's block memory. `ext_bios_loaded` is tied low
  so nothing ever selects its output. If block memory comes back near the
  ceiling, this is the first thing to check in the fitter's RAM summary.
* **The SMS boot ROM may well still be there.** `bootloader_n` is a register,
  not a constant, so Quartus may not be able to prove that `mboot.mif` is never
  read. That is 16 KB and worth leaving alone if so.
* **Sprites per line.** `system` is instantiated with `MAX_SPPL = 63`, which is
  upstream's setting and gives the "extra sprites" option a buffer to use. A
  real Game Gear draws eight per line and `MAX_SPPL = 7` would be accurate and
  smaller. Left at 63 for parity; the difference is a measurement worth making
  once there is a baseline to compare against.
* **The SDRAM interface is constrained for the first time here.**
  `target/pocket/core_constraints.sdc` declares `sdram_clk`, the output and
  input delays and the read multicycle. The sibling PC Engine core ships with
  none of that, so these paths have never been analysed in this tree. They run
  at 53.7 MHz against a part rated far above it, so they should pass with
  room; if they do not, the numbers in that file are the first suspect, not the
  design.

## Method

    R=../tools/runner-build
    SEED=1 $R start sisko  pocket-gg gg p0-s1 HEAD
    SEED=3 $R start sisko2 pocket-gg gg p0-s3 HEAD
    $R job   sisko2 pocket-gg gg p0-s3 HEAD
    $R fetch sisko2 pocket-gg gg p0-s3 HEAD

`start` bundles the commit, not the working tree, so commit first. `fetch`
resolves by commit and refuses when one runner holds two checkouts of the same
commit, so a seed retry goes to a different runner.
