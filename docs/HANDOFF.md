# Handoff

State as of 2026-09-11. Read `PLAN.md` first, then `BASELINE.md`.

## Where it stands

**P0 is done.** It compiles, fits within margin on two seeds, meets timing, and
every hardware check has come back clean: video, audio, controls and the ROM
load diagnostic.

The fit: two seeds in `docs/BASELINE.md`, **5,865 to 5,876 ALMs, about 32 per
cent of the device**, 84 of 308 memory blocks. The by-entity table shows six
entities left inside `system` and no FM chip, no MC8123, no System E decoder,
no second VDP and neither BIOS RAM: every feature tied off in `gg_core.sv` was
removed by the fitter, as the plan meant it to be. The VDP is 63 per cent of
what remains.

The hardware, 2026-09-10, a game running from `Assets/gg/common`: the picture
is right (`Memories/Screenshots/20260910_150121.png`, `...150124.png` on the
card, correct colour, clean sprites, no tearing), audio works, controls work,
and `RQ:` reads `0x00000000` — the ROM queue never overran loading this ROM.
That readout only worked after a fix: its first label, "ROM load errors", was
long enough to wrap the hex value off screen. `docs/BASELINE.md` has the
detail.

What is here:

| | |
|---|---|
| `projects/gg_pocket.{qpf,qsf,qip,sdc}` | revision `gg_pocket`, top level `apf_top`, `STANDARD FIT`, SignalTap off |
| `platform/pocket/` | Analogue's APF framework, copied verbatim from the PC Engine fork |
| `target/pocket/core_top.v` | the Pocket side: bridge decode, ROM slot, controls, video out, i2s |
| `target/pocket/core_constraints.sdc` | clock groups and the SDRAM interface timing |
| `target/pocket/mf_pllbase` | 74.25 MHz in, 53.693181 MHz and 5.369318 MHz x2 out |
| `rtl/gg/gg_core.sv` | the machine, in place of MiSTer's `SMS.sv` |
| `rtl/gg.qip` | what of `rtl/upstream/` the project compiles, and what it leaves out |
| `pkg/Cores/kroy.GG/` | the manifests. Two data slots (cartridge, save), one video mode, three menu items |
| `tools/check/project.sh` | every path the project names resolves |
| `tools/check/manifests.sh` | the APF rules the siblings paid to learn |

What P0 deliberately does not have: a save slot, cheats, the extended Game
Gear resolution, savestates, the link port, and any Master System or SG-1000
package.

## How the port was done

`rtl/upstream/` is not edited and nothing is copied out of it. `gg_core.sv`
instantiates `system`, `video`, `sdram`, `spram` and `dpram` straight from
there and ties every feature a Game Gear does not have to a constant, on the
expectation that the fitter removes what the constants make unreachable. That
keeps a future upstream sync a diff rather than a merge. Whether it also keeps
the design small is the first thing `BASELINE.md` asks of the fit.

Three things in it are worth knowing before changing anything:

1. **The ROM path has a queue in it.** MiSTer throttles its loader with
   `ioctl_wait`; APF's `data_loader` has no backpressure at all, so bytes
   arrive in bursts of four faster than the SDRAM controller can take them.
   `gg_core.sv` buffers 64 of them and sets a sticky flag if that is ever not
   enough, which the menu reads back at `RQ:`. A non-zero value
   there means the loaded ROM has holes in it.
2. **The SDRAM reference clock changes during a load.** Upstream drives the
   controller's `clkref` from the CPU clock enable, which is one transaction
   every 279 ns. While the ROM is being written the Z80 is held in reset and
   nothing reads, so `clkref` comes from a free-running divide-by-eight
   instead and the load is about four times quicker. The mux only ever moves
   while the machine is in reset.
3. **`projects/rtl` is a symlink to `../rtl/upstream`.** `system.vhd`
   initialises the SMS boot ROM from the literal string `"rtl/mboot.mif"`,
   which Quartus resolves against the project directory, and the entity's
   `BASE_DIR` generic can only prefix that string. The symlink is how the
   vendored tree answers to the name upstream uses without editing upstream or
   keeping a second copy of the file.

## Decisions still open, cheap now

From `PLAN.md` §9, in the order they bite:

1. The name. `pocket-gg` here, `kroy.GG` for the core directory, and
   `core.json` points at a GitHub repository that does not exist yet.
2. Licence text: the GPLv2 file copied from the PC Engine fork, or
   GPL-3.0-or-later as the GBA fork uses. Upstream is "version 2 or later".
3. Scope beyond Game Gear.
4. **Which face button is Game Gear button 1.** It is A here, matching MiSTer
   and putting the jump button under the Pocket's primary face button. On the
   console 1 is the left of the pair and 2 the right, which argues for B.
   `input.json` names both so the Pocket's remapping screen can settle it, but
   the default is a choice.
5. **The platform image is a placeholder.** `pkg/Platforms/_images/gg.bin` is
   the right size and a flat colour. It needs a real one before release.
6. **There is no core icon.** `pkg/Cores/kroy.GG/icon.bin` does not exist, so
   the Pocket shows its default.

## Next, in order

P0 is closed: two seeds, a package, and every hardware check clean. P1 is
saves, per `docs/PLAN.md`, and the RTL and manifests are written but not yet
built or run:

1. **Done.** Cart RAM out through the save slot: `core_top.v` has a
   `save_data_loader`/`save_data_unloader` pair on `gg_core.sv`'s second
   `nvram_inst` port, muxed by `save_download_s` so the loader owns the bus
   while the slot streams in and the unloader owns it otherwise.
2. **Done, and for free.** The 93C46 EEPROM shares `nvram_inst` with cart RAM
   inside `system.vhd` already (`nvram_a` muxes between them), so the one
   save slot above covers both without `core_top.v` ever reading
   `mapper_eeprom_out`.
3. **Done.** `data.json` declares a `"Save"` slot, id 2, `nonvolatile: true`,
   `0x8000` (the whole `nvram_inst`, cart RAM and EEPROM both), and
   `core_top.v`'s datatable write reports that size once `pll_core_locked`.
4. **Fits, and is flashed.** Two seeds, 6,057 to 6,067 ALMs, 32.8%, timing
   met on both; `docs/BASELINE.md` has the numbers. Hold margin is the
   tightest this project has produced, 0.068 to 0.072 ns, and worth a glance
   if a later change tightens it further. The seed-3 build is on the Pocket's
   card, verified by checksum against the zip; the first attempt flashed P0
   again, see `BASELINE.md`, "Things the harness got wrong". The exit
   criterion, a save surviving closing the core and a power cycle, is still
   open and needs one RAM game: `Defenders of Oasis`,
   `Sylvan Tale`, `Crystal Warriors`, and `Phantasy Star Gaiden` are all
   confirmed battery-save Game Gear titles (MAME's `gamegear.xml` software
   list) and all four are in Kroy's ROM set. There is no EEPROM game to test
   against; see `PLAN.md` §9.3.

## Rules that hold here as in every sibling

* Builds on the runners only, through `runner-build`, see below. The
  Quartus image is private. CI verifies a published package and builds
  nothing.
* `report.sh` is the timing gate. Quartus exits 0 on a miss.
* `STANDARD FIT`, and never one seed for a comparison.
* `rtl/upstream/` is never edited; copies go to `rtl/gg/` with headers kept.
* Attribution is never removed from anything.
* Releases are `v0.9999.<short sha>` of the exact built commit, from `main`.

## Runners

Four, all driven from the orchestrator checkout beside this one. The
`pocket-gg:gg` profile exists in `runner-build` already; it runs `make gg`
with `STANDARD FIT` and `NPROC=16` on the exact local commit it is given.

| runner | use it for |
|---|---|
| `sisko` | the fit being waited on |
| `sisko2` | the second seed of the same commit, at the same time; same speed as sisko |
| `kira` | a third seed, about a third slower |
| `odo` | a fourth seed, slowest |

sisko and sisko2 are two containers on one node, each pinned to its own
CPU socket, so they do not slow each other. Addresses and container ids are
in `pocket-dev/docs/HANDOFF.md`, "Builds", and stay out of this repository.

    R=../tools/runner-build
    $R status                                  # lock and Quartus state, all four
    SEED=1 $R start sisko  pocket-gg gg p0-s1 HEAD
    SEED=3 $R start sisko2 pocket-gg gg p0-s3 HEAD
    $R job   sisko  pocket-gg gg p0-s1 HEAD    # state, log tail, slack, ALMs
    $R fetch sisko  pocket-gg gg p0-s1 HEAD    # results into build/gg/

`start` bundles the commit, not the working tree: commit first. One fit per
runner; a busy runner is a refusal, pick another. `fetch` finds the checkout
by commit and refuses when a runner holds two of the same commit, so give a
seed retry of one commit a different runner rather than the same one.
`report.txt` is the gate, not the exit code.

