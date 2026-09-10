# Handoff

State as of 2026-09-10. Read `PLAN.md` first, then `BASELINE.md`.

## Where it stands

**P0 compiles, fits and meets timing. It has never run on hardware.**

The first fit, `99f84f4` at seed 3 on sisko2, came back at **5,876 ALMs, 31.8
per cent of the device**, 84 of 308 memory blocks, setup +1.773 ns and hold
+0.075 ns, in 251 seconds. `docs/BASELINE.md` has the numbers and reads them
against what was predicted before the build. The short version: the port fits
with two thirds of the device to spare, and every feature tied off in
`gg_core.sv` was removed by the fitter. The by-entity table shows six entities
left inside `system` and no FM chip, no MC8123, no System E decoder, no second
VDP and neither BIOS RAM. The VDP is 63 per cent of what remains.

**A `.gg` boots on hardware, and the picture is right.** P0's exit criterion
in `docs/PLAN.md` is met on both halves: two seeds in `BASELINE.md` and a game
running on a Pocket, 2026-09-10. Two screenshots taken a second apart
(`Memories/Screenshots/20260910_150121.png`, `...150124.png`) show a top-down
RPG in a walled corridor: correct colours, clean sprites, no tearing or
corruption. That is the VDP's BGR444-to-RGB conversion, the video output
stage's one-cycle hs/vs pulses and the 5.369318 MHz pixel clock all working as
reasoned in `gg_core.sv`, not just simulated.

Not yet confirmed: audio, controls beyond whatever moved the character between
those two frames, and whether the menu's "ROM load errors" readout reads
zero.

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
| `pkg/Cores/kroy.GG/` | the manifests. One data slot, one video mode, three menu items |
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
   enough, which the menu reads back as "ROM load errors". A non-zero value
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

1. **A second seed.** Done: seed 1 came back at 5,865 ALMs against seed 3's
   5,876, and the SDRAM and video-crossing paths both close. `BASELINE.md` has
   the comparison.
2. **A package.** Done: `b1f08e0` produced `kroy.GG_0.9999.zip`, 460,148
   bytes. Packaging now re-executes itself inside the Quartus image rather
   than trusting whatever the host has, after the first fit died on a runner
   with no `jq`.
3. **Hardware: a `.gg` from the card boots.** The whole video path, the
   controls and the i2s audio have been reasoned about and never observed.
   Watch the menu's "ROM load errors" readout on the first boot: a non-zero
   value means the ROM queue overran and the image has holes in it.
4. Then P1.

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

