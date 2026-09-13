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

P0 is closed. P1's saves are closed too, on hardware; P1's other half, sleep,
is not started and waits on the savestates decision in `PLAN.md` §9.4. What
saves took:

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
4. **Done, and confirmed on hardware.** Two seeds, 6,057 to 6,067 ALMs,
   32.8%, timing met on both; `docs/BASELINE.md` has the numbers. Hold margin
   is the tightest this project has produced, 0.068 to 0.072 ns, and worth a
   glance if a later change tightens it further. The seed-3 build is on the
   Pocket's card, verified by checksum against the zip; the first attempt
   flashed P0 again, see `BASELINE.md`, "Things the harness got wrong". The
   exit criterion is met: `Eternal Legend - Eien no Densetsu (Japan)` saved,
   survived a power cycle and loaded back, 2026-09-11. Other confirmed
   battery-save Game Gear titles, if another is wanted: `Defenders of Oasis`,
   `Sylvan Tale`, `Crystal Warriors`, `Phantasy Star Gaiden` (MAME's
   `gamegear.xml` software list). There is no EEPROM game to test against,
   see `PLAN.md` §9.3.
5. **Not started: sleep.** `core.json` declares `sleep_supported: false`.
   `PLAN.md` §9.4 decides whether that is APF sleep, MiSTer savestates, or
   neither.

P2 is cheats, all three stages done. Stage 2's `.cht` reader is committed and
fitted (`25572cb`, 38.2%/38.1%, timing met on both seeds, numbers in
`BASELINE.md`); the overlay that reads the title store it feeds is written and
passing its own render-and-decode check, not yet fitted. See "P2 stage 2,
finished: the overlay" below.

1. **Done, fitted, not yet on hardware.** Both mechanisms are wired. Work RAM
   became a `dpram` so `cheat_poker` can write Pro Action Replay pokes on port
   B once a frame, beside the cold-reset clear that already owned that port;
   the Game Genie half needed no new engine, because `system.vhd`'s `CODES`
   instance has been idle since P0 and only wanted a code word. One slot feeds
   both: `cheat_binloader.sv` splits the file on bit 127 of each entry. Two
   seeds, 6,779 to 6,792 ALMs, 36.7%, and timing improved rather than
   degraded; `BASELINE.md` has the numbers and explains why the block memory
   went *down* by 8 KB.
2. **Done.** `rtl/gg/cheat_loader.sv` parses a plain libretro `.cht` into both
   mechanisms, and `core_top.v` sniffs the first four bytes for "GGCH" to
   choose between it and `cheat_binloader.sv`. Both readers see every byte and
   only their outputs are muxed, which is safe because the verdict lands at
   byte four and neither can emit before then.

   What shaped the module: `cheatN_enable` comes *after* `cheatN_code`, and
   `CODES` cannot withdraw a code once clocked in, so a cheat's entries are
   buffered and pushed only once its enable state is known. That is
   `pocket-gba`'s two-bank buffer, not `pocket-pcengine`'s commit-and-roll-back,
   which only works on a table that is an array and a count.

   `tools/sim/run.py` is the gate on it: Icarus runs the RTL over every corpus
   file and diffs the pushed entries and the parsed titles against
   `tools/cheats/gg2bin.py`. **818 files, two passes each, 0 mismatches.** Both
   end-of-file paths are covered, the download's falling edge and the idle
   timer. It needs Icarus and a corpus, so it is not in `make test`:

       CHT_DB="$HOME/.config/retroarch/cheats/Sega - Game Gear" tools/sim/run.py
       tools/sim/run.py --idle

   The overlay that draws these titles is its own subsection below.
3. **Done, on the host side.** `tools/cheats/gg2bin.py` writes the `.chtbin`
   that `cheat_binloader.sv` reads, both code kinds. All 818 libretro Game Gear
   files convert with no crash and 7,133 entries. The Game Genie decode is in
   `tools/cheats/ggcht.py`, which doubles as the check against a ROM set;
   `PLAN.md` S4 records the evidence. `tools/check/cheats.sh` asserts the field
   positions against the RTL's documented layout and is in `make test`.
   Untested on hardware, which needs the overlay above to be worth using.

## P2 stage 2, finished: the overlay

`rtl/gg/cheat_osd.sv` draws the cheat list over the game picture, ported from
`pocket-gbc`'s copy rather than `pocket-pcengine`'s: a Game Gear draws 160x144,
the same raster the Game Boy does, so the geometry needs no inset and the
`COL0`/`ROW0` parameters `PLAN.md` expected to need do not exist here. That note
was wrong; corrected in the module's own header.

Wired on `clk_vid`: `de` alone paces it, since this core has no `ce_pix` to hand
over (one pixel is one `clk_vid` edge already). `cheat_titles`' read port moved
from the temporary `CT:` probe to the overlay; `core_top.v` composites
`osd_active`/`osd_ink` over `vid_rgb` before the video output stage, ink white
on a black panel. The "Cheat overlay" switch is back at `0xF000010C`, first in
`interact.json`'s array beside "Cheats". `CT:` at `0xF0000218` now reads the two
counts the header draws from instead of a raw title character, so a count that
never crossed into `clk_74a` reads back as zero rather than looking identical
to a genuinely empty file.

**Two independent bugs, both found and fixed by a render-and-decode check**
(`tools/sim/tb_cheat_osd.sv` + `tools/sim/run_osd.py`, parallel to
`tools/sim/run.py` for the parser): parse a `.cht`, draw one frame, decode the
pixels back through the font, and assert on the words. Neither bug would have
been visible from eyeballing the ASCII-art picture alone; both needed decoding
it back to text.

1. **The pipeline compared title data one stage later than it arrives.**
   `cheat_titles` registers its RAM read once, so `title_char`/`title_len` for
   a column are valid one cycle after `title_col` asks for it. The module
   compared them against a three-stage-delayed copy of the column counter
   instead of a two-stage one, so the write for column N used column N+1's
   title data - genuinely unwritten one column early - and leaked
   uninitialised RAM into the last visible character of every title. Found by
   tracing `title_char` against the pipeline's delay registers cycle by cycle
   in simulation and comparing to the expected string; not visible from the
   picture, which still looked like a plausible, readable panel. Fixed by
   collapsing the pipeline to two stages (address, then write) and comparing
   at the stage where the data actually lands.
2. **The render testbench itself had two bugs**, both in
   `tools/sim/tb_cheat_osd.sv`, not the RTL: its row buffer was declared one
   character wider than it filled, leaving an uninitialised leading glyph on
   every decoded row, and it sampled each pixel one clock edge later than the
   pixel it meant to read, because `de` is raised before the first clock edge
   of a row while the pixel counters are still mid-transition. Both were
   invisible until the picture was decoded back to text; the raw ASCII-art
   picture looked fine either way.

`tools/sim/run_osd.py` now passes all three of its cases (three titles, 26
character truncation, "no cheats loaded") with 0 mismatches, and
`tools/sim/run.py` still passes all 818 corpus files afterward, confirming the
parser was never in question.

## Rules that hold here as in every sibling## Rules that hold here as in every sibling

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

