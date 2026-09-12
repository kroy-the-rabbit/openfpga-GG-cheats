# Plan: a Game Gear core for the Pocket, ported from MiSTer, with cheats and the cartridge adapter

Scope: Game Gear ROMs from the SD card, cheats on them, and Game Gear
cartridges through Analogue's adapter. Master System and SG-1000 come out of
the same RTL and are a scope decision, not a technical one (§9).

This is the fourth core in the pocket-dev tree and the first ported from MiSTer
by hand rather than forked from an existing Pocket port. The three sibling
forks and the cartridge dumper each paid for a lesson this plan is built on;
§8 lists them with where they are written down. Read those before touching the
part of the work they cover.

---

## 0. Base decision: port `MiSTer-devel/SMS_MiSTer` ourselves

| Candidate | What it is | Verdict |
|---|---|---|
| `spiritualized1997/openFPGA-GG` | the Pocket Game Gear core most people run | **no source.** The repo is a README; releases are bitstreams; no licence. Nothing to fork. |
| `drizzt/openfpga-SMS` | GPL-3.0 Pocket port of SMS_MiSTer, SMS + GG + SG-1000 in one bitstream, created 2026-06, v1.6.1 on 2026-09-05 | forkable, and the layout is the agg23 shape we know. Self-described "LLM assisted port", three months old, 7 stars. Kroy's call: **do not build on it.** Useful as a second opinion on the Pocket-side decisions, and as prior art for the manifest layout, the way Mazamars312's core was for the PC Engine CD work. |
| **`MiSTer-devel/SMS_MiSTer`** | the core both of the above descend from; Sorgelig's port of Ben's Papilio SMS, GPL-2.0-or-later | **chosen.** Vendored verbatim under `rtl/upstream/` at `1fc3c121` (2026-08-31). `docs/PROVENANCE.md` has the rules. |

What the upstream carries, from its README and `SMS.sv`:

* Master System, Game Gear, SG-1000, SC-3000, System E. NTSC and PAL.
* T80 Z80, VDP, jt89 PSG, VM2413 FM, mapper autodetect with manual override,
  Game Gear EEPROM (`cart_eeprom.vhd`, `eeprom_93c46.vhd`), 32 KB cart RAM.
* **Cheats already exist**: `rtl/cheatcodes.sv` is Kitrinx's `CODES`, the same
  module the GB/GBC and PC Engine forks carry, instantiated as `GG_CODE` on the
  CPU bus with `ADDR_WIDTH 16`. MiSTer's ARM side decodes Game Genie codes into
  its 128-bit words and streams them in over `ioctl`. The Pocket has no ARM.
* Savestates (`savestates.sv`, 1684 lines), Gear-to-Gear link over USERIO,
  BIOS loading, Bock's free SMS boot loader as `mboot.mif`.
* `rtl/sdram.sv`, 188 lines, the ROM store. MiSTer's SDRAM is the same kind
  of part as the Pocket's (16-bit, 512 Mbit); agg23 retimed this exact module
  for the PC Engine port and it is `pocket-pcengine/rtl/pce/sdram.sv`.

---

## 1. What the Pocket replaces

`SMS.sv` is the MiSTer top and it is not portable: it is written against
`sys/` (hps_io, video_mixer, audio_out, the DE10 PLLs). Everything it does has
a Pocket equivalent already built in a sibling repo. This table is the port.

| MiSTer piece in `SMS.sv` | Does | Pocket replacement | Take it from |
|---|---|---|---|
| `hps_io` `ioctl_*` download | ROM, BIOS and cheat bytes arrive from the ARM | APF data slots through `data_loader.sv`, one instance per slot | `pocket-pcengine/target/pocket/` |
| `ioctl_file_ext` | picks GG / SMS / SG mode from the extension | slot id, or the extension APF reports through `dataslot_path.sv` | `pocket-pcengine` |
| `status[...]` bits from `CONF_STR` | every menu setting | `interact.json` writes to bridge addresses, synced into `clk_sys` | every sibling |
| `sd_*`, `bk_*`, `img_*` | backup RAM load and save through the ARM | APF save slot: `data_loader` in, `data_unloader` out on exit | `pocket-pcengine` (`data_unloader.sv`) and `pocket-gba` (`save_state_controller.sv`) |
| `gg_code` from `ioctl` index | 128-bit cheat words decoded on the ARM | a cheats slot carrying `.chtbin`, decoded on the host by the picker | `pocket-gba` (`cheat_binloader.sv`, `docs/CHEATBIN.md`) |
| `pll` + `pll_cfg` reconfig | 53.693175 MHz NTSC, 53.203424 MHz PAL | `mf_pllbase` from 74.25 MHz. GG is NTSC only; PAL reconfig only if SMS is in scope | `pocket-pcengine/target/pocket/mf_pllbase` |
| `sdram ram` | ROM in SDRAM | the same controller retimed for the Pocket's `dram_*` pins | `pocket-pcengine/rtl/pce/sdram.sv` or `pocket-gba/src/fpga/core/sdram_pocket.sv`, whichever diff is smaller against `rtl/upstream/sdram.sv` |
| `video_mixer`, `VGA_*` | scandoubler, aspect, scaler | RGB out with the APF video mode word; `video.json` declares the modes | `pocket-pcengine` (`linebuffer.v`), `pocket-gba` (`video_adapter.sv`) |
| `audio_out` | DAC / HDMI audio | `sound_i2s.sv` at 48 kHz | `pocket-pcengine/target/pocket/sound_i2s.sv` |
| `USER_IO` link cable | Gear-to-Gear | **out of scope** for now. The Pocket link port exists; nothing here uses it yet |
| `savestates.sv`, `savestate_ui.sv` | MiSTer savestates, OSD | **decide at P0** (§9). The Pocket has its own sleep and savestate mechanism through APF, which `pocket-gba` implements |
| OSD | | none. The Pocket menu cannot name a cheat, so the overlay is `cheat_osd.sv` drawn into the picture, as GB/GBC and PC Engine do |
| `keyboard.sv`, `lightgun.sv`, `MC8123.v`, `SEGASYS1_PRGDEC.v` | SC-3000 keyboard, light gun, System E decryption | **strip at P0.** None of it is a Game Gear |

`system.vhd` (2010 lines), `io.vhd`, the VDP, T80, jt89, VM2413 and the mapper
logic are the machine and port as they are. The work is `core_top.sv` and the
glue, the same shape as `main.sv` in the PC Engine fork.

---

## 2. Resource budget: unknown until P0, and P0 is the measurement

Nothing about the SMS core's size on a 5CEBA4F23C8 (18,480 ALMs, 308 M10K) is
known here. MiSTer builds it for a part six times larger and never reports.
drizzt's port fits, which says it is possible, not what it costs.

The GBA fork's lesson applies with force: **identical RTL moves 81 ALMs across
fitter seeds**, so a single build cannot size a module (`pocket-gba/docs/
HANDOFF.md`). P0 builds the stripped core at `STANDARD FIT` on two seeds and
records both in `docs/BASELINE.md` before anything is added. Every later phase
adds to the table.

What the Pocket-side pieces cost is known from the siblings and is the
floor for planning:

| | measured in | cost |
|---|---|---|
| cheat engine, poker, loader, overlay, font, titles | `pocket-gbc` | +1,655 ALMs |
| `.chtbin` loader in place of the ASCII parser | `pocket-gba` | 61 ALMs against 441, and no timing cost |
| CD block, for scale of a large addition | `pocket-pcengine` | 5,441 ALMs freed by SuperGrafx paid for it |

---

## 3. Memory

The Pocket exposes SDRAM (512 Mbit, 16-bit), two PSRAM chips, and a 128 K x 16
SRAM. Block RAM is 308 M10K, about 385 KB in total, and the VDP needs 16 KB of
it plus CRAM and the 8 KB work RAM.

ROM goes in SDRAM, as it does on MiSTer and in every sibling that loads a ROM.
The largest Game Gear and Master System ROMs are under 1 MB, so the address
width the mapper needs is small, and the controller's only job is to answer a
Z80-speed bus with margin. Cart RAM (32 KB) and EEPROM (93C46, 128 bytes) stay
in block RAM and are what the save slot writes out.

---

## 4. Cheats: both mechanisms this time

The GB/GBC fork is built around ROM patching (Game Genie) with RAM pokes as
the addition. The PC Engine fork found its entire corpus was RAM pokes and cut
the read override. **Game Gear needs both**, and the libretro database says so.

Census, 2026-09-05, from `libretro/libretro-database`: **818** files under
`Sega - Game Gear`, **724** under `Sega - Master System - Mark III`. A sample of
the first 25 Game Gear files:

| `cheatN_code` shape | count | what it is |
|---|---:|---|
| `XXX-XXX-XXX` | 94 | **Game Genie.** A ROM address, a replacement byte, and an optional compare, encoded. A ROM read override |
| `XXXX-XXXX`, e.g. `00C4-2200` | 63 | **Pro Action Replay.** `C422 <- 00`, a write into the 8 KB work RAM at `C000-DFFF`. A RAM poke |
| either, joined with `+` | 7 | multi-part codes, expanded to several entries |

So:

1. **Game Genie through `CODES`**, which the upstream already instantiates on
   the CPU bus. What is missing is the decoder, and on MiSTer that runs on the
   ARM.

   **This section is half stale, and the correction is 2026-09-10's.** It was
   written on the belief that compiling on the host was simply better. The tree
   has since gone the other way: `pocket-gba` removed savestates, dropped from
   97% to 78% ALMs, put `cheat_loader.sv` back in the fit, and its Cheats slot
   now takes both `cht` and `chtbin`. The reason is the overlay, which draws
   each cheat's name from `cheatN_desc` cut at 26 characters, and a `.chtbin`
   carries no names, so its rows read `CHEAT nn`. `pocket-dev/docs/HANDOFF.md`
   records it under "GBA cheats changed shape". This core is at 36.7% ALMs, the
   roomiest of the set, so the fitting argument against an on-FPGA parser is
   weaker here than anywhere. That parser is now written, §9.8; both readers
   ship and the slot takes either extension.

   Here the decode runs on the host: the picker's converter decodes Game Genie to
   the 128-bit `CODES` word and writes `.chtbin`, and `cheat_binloader.sv`
   shifts it in unchanged. The decode algorithm is verified against a
   reference implementation, not written from memory (§9). **Done, 2026-09-11.**
   Genesis Plus GX's `decode_cheat` (`gx/gui/cheats.c`) was the only complete
   implementation reachable, and SMS Power!'s page 403s, so there is no second
   document. `tools/cheats/ggcht.py` is the corroboration instead: a
   Game Genie compare byte is the original byte at the address it patches, so
   a correct decode predicts the ROM. 230 of 242 codes agree across a 33-game
   set, 29 games perfectly, and the three plausible alternative encodings of
   the compare byte score 5%, 0% and 0%. The algorithm is in that file's
   docstring.
2. **Pro Action Replay through `cheat_poker.sv`**, the PC Engine mechanism:
   writes into work RAM once per frame at vblank through a second port, with
   the lookup keyed on registered addresses (§5).

The full census of both corpora, code shapes and rows that cannot become
either kind of entry, is P3 and is done with the picker's tooling, the way
`pocket-tools/docs/PCE-TG16-PLAN.md` was done for the PC Engine, **before**
the RTL side of P2 is called finished.

The behaviour contract is the one every sibling holds (`fork-alignment-contract`
in pocket-dev memory): cheats **off at startup and never persisted**; loading a
file **does not reset the game**; which cheats are on comes from
`cheatN_enable` in the file, **not** from menu entries; the menu is a master
switch and the overlay toggle, reachable without scrolling.

---

## 5. Timing, known in advance

* GB/GBC's first parser build missed setup by 3.4 ns because the 32-way
  comparator sat on late-arriving read data. **Search on the registered
  address; let data feed one 8-bit compare.** The upstream `CODES` compares
  `addr_in` combinationally in a 32-deep loop, exactly the shape that failed;
  expect to restructure it when P2 measures.
* The GBA fork could not fit an ASCII `.cht` parser at all. **Do not parse
  text on the FPGA.** `.chtbin` exists for this.
* `Quartus exits 0 on a design that misses timing.` `tools/podman/report.sh`
  exits 3 on negative slack and is the gate. Nothing is flashed from a build
  that failed it.
* `STANDARD FIT` for every comparison, or the delta is noise.

---

## 6. Video and audio

The Game Gear draws 160 x 144 out of the VDP's 256 x 192 field. The Pocket's
display is 1600 x 1440, an exact 10x, so the native mode is the one that
matters and it is fixed, which makes the overlay the GB/GBC case rather than the
PC Engine one: `cheat_osd.sv` is parameterised for 160 x 144 already. The
upstream's "extended Game Gear resolution" option is a second mode in
`video.json`. Master System modes (256 x 192, 224, 240) are added only with
that scope.

Audio is jt89 PSG, stereo on the Game Gear, through `sound_i2s.sv` at 48 kHz.
FM is a Master System Japan feature and comes with that scope.

---

## 7. The cartridge adapter

Analogue's Game Gear adapter puts a Game Gear cartridge on the Pocket's slot.
Two facts are unpublished: which of the Pocket's 30 slot lines (`bank0[7:4]`,
`bank1`, `bank2`, `bank3`, `pin30`, `pin31`) carry which cartridge signals, and
the 8-bit adapter ID `core.json`'s `cartridge_adapter` field can be told to
check. The Analogue docs define the field's bits and no ID table.

The method exists and is the cartridge dumper's. In order:

1. **Declare the adapter with power on and the ID check off**, the way the GBA
   branch did (`"cartridge_adapter"` with bit 24 set and neither check bit), so
   the Pocket powers the slot and offers Play Cartridge.
2. **Find the pin map with a probe screen, not a datasheet.** The Pocket has
   no console; the menu readout is the diagnostic surface. `pocket-gba`'s
   `CG:`/`CS:` and the dumper's diagnostics page are the pattern: drive one
   line, read the others, show the result as a number the menu can display.
3. **Wait two seconds after slot power before the first read.** Measured on
   GB cartridges, unexplained, and it decides whether the first probe after
   launch works (`pocket-cartridge/docs/HANDOFF.md`, "asleep for about two
   seconds").
4. **Never write to a cartridge** until there is a cartridge nobody minds
   losing and an explicit toggle. Reads only through the whole bring-up.
5. **Dump first, boot second.** Reading a whole cartridge to the card and
   matching it against No-Intro proves the bus before any game runs on it.
   That work belongs in `pocket-cartridge`, which has the writer, the
   checksum path and the corpus discipline; this core then boots from the
   cart using the map the dumper found.
6. **The probe must not run while the controller is in reset.** Today's GBA
   lesson: the Pocket sends "data slot access all complete" before "Reset
   Exit", so a probe that starts on `allcomplete` while the bus controller
   resets on `reset_n` times out every boot and reports it as a missing
   cartridge. Gate the probe on both.

Cheats on a cartridge game work through the same two mechanisms; the GB/GBC
fork proved it and its README carries the save warning to copy.

---

## 8. Lessons carried in, with their sources

| Lesson | Where it was paid for |
|---|---|
| Quartus exits 0 on a timing miss; `report.sh` is the gate | `pocket-pcengine/docs/BASELINE.md` |
| `STANDARD FIT` only; AUTO FIT throws placements | `pocket-gba/docs/HANDOFF.md` finding 1 |
| One seed sizes nothing; 81 ALMs of variance on identical RTL | `pocket-gba/docs/HANDOFF.md` |
| Measure before moving the toolchain; then move on the measurement | `pocket-gba/README.md`, `docs/BASELINE.md` |
| No ASCII parsing on the FPGA; `.chtbin` | `pocket-gba/docs/CHEATBIN.md` |
| Per-code lookup off registered addresses, not data | `pocket-gbc`, via `pocket-pcengine/docs/PLAN.md` §5 |
| Poker for RAM codes, read override for ROM codes, know which the corpus needs | `pocket-pcengine/docs/PLAN.md` §4 |
| Enables from the file, not menu checkboxes; "Cheat 1" is useless | `fork-alignment-contract` |
| Cheats off at startup, never persisted; loading a file never resets | `fork-alignment-contract` |
| APF read window is pipelined; the value kept is the previous transaction's | `pocket-cartridge/docs/HANDOFF.md`, "APF's file interface, measured" |
| Byte order differs by bridge direction; byte 0 of a file is bits [31:24] of a word | same, and `pocket-pcengine/docs/CD-HANDOFF.md` |
| `0x0188` flush is never answered; every command needs a deadline | `pocket-cartridge/docs/HANDOFF.md` |
| A cartridge is asleep for ~2 s after slot power | same, "The cartridge is asleep" |
| Drop `req` the cycle after raising it | same, "Driving the bus" |
| Read a new bus master against the most bruised master on the bus, not the tidiest | `pocket-dev/docs/HANDOFF.md`, GBA save snapshot |
| A sticky error is not a rate; a single overlay frame is worth nothing | `pocket-pcengine/docs/CD-HANDOFF.md` |
| `allcomplete` arrives before Reset Exit; do not probe a controller in reset | `pocket-gba/docs/CARTRIDGE.md`, first hardware run |
| The menu readout is the only console; design the diagnostic word first | `pocket-gba/docs/CARTRIDGE.md`, `CS:` |
| Every `.sv` a testbench compiles must also be in the qsf | `pocket-cartridge/docs/HANDOFF.md`, `check_qsf_sources.py` |
| Builds run on the runners through `runner-build`, never locally; the image is private; CI verifies the published package | `pocket-dev/docs/HANDOFF.md`, "Release build boundary" |
| Merge onto the card, never delete; find it by mount point; unmount after writing a core | `pocket-card-handling` |

---

## 9. Open questions

1. **Name.** Directory `pocket-gg` is provisional. GitHub repo name and core
   directory (`kroy.GG`) are Kroy's call and are cheap to change now.
2. **Licence text.** Upstream headers are GPL-2.0-or-later. `LICENSE` here is
   the GPLv2 text copied from `pocket-pcengine`. GPL-3.0-or-later is
   permitted by "or later" and is what `pocket-gba` uses. Pick before the
   first push.
3. **Scope.** Game Gear only, or SMS and SG-1000 too? The RTL is the same;
   the cost is a package, a picker system and a `video.json` per platform,
   plus PAL reconfig for SMS. Kroy's direction as of 2026-09-11: SMS is
   planned, ROM-loaded from the card like Game Gear, with no physical cart
   adapter for SMS (unlike P4's Game Gear cartridge). Still not started;
   this is what will make P1's EEPROM path testable on real hardware, since
   every EEPROM-detected title is an SMS exclusive.
4. **Savestates.** Carry MiSTer's `savestates.sv` or drop it for APF sleep and
   savestates as `pocket-gba` does? Decide on the P0 measurement: it is
   1684 lines and MiSTer-shaped.
5. **Game Genie decoding.** ~~Which reference implementation the host converter
   is checked against.~~ **Answered 2026-09-11.** Genesis Plus GX's
   `decode_cheat`, and then checked against a ROM set rather than against a
   second document, because there is no reachable second document. See S4 and
   `tools/cheats/ggcht.py`.
6. **Adapter ID.** Whether the Pocket exposes the adapter's ID to the core at
   all, or only enforces it in firmware. Decides whether the soft check bit
   is ever worth setting.
7. **ROM size ceiling** to size the mapper address width and the save slot.
8. **Where the cheat names come from.** ~~Undecided~~ **Answered 2026-09-11:
   the ASCII parser, for exact alignment with `pocket-gba`.** `rtl/gg/cheat_loader.sv`
   reads a `.cht` and `core_top.v` sniffs the first four bytes for "GGCH" to
   choose between it and `cheat_binloader.sv`. The cost accepted with it is a
   second implementation of the Game Genie decode, in RTL, which has to stay in
   step with `tools/cheats/ggcht.py`. `tools/sim/run.py` is what keeps it in
   step: it diffs the two over all 818 corpus files, entry for entry and title
   for title. The alternative, a name field in this core's `.chtbin` alone,
   would have kept one decode and diverged the format from every sibling.

---

## 10. Phasing

| Phase | Deliverable | Done when |
|---|---|---|
| **F** | **Framework.** This repo, the harness, the vendored upstream with provenance, the plan, registration in pocket-dev. | **Done 2026-09-05.** Nothing builds yet. |
| **P0** | **The port boots.** Quartus project for 5CEBA4F23C8; `core_top.sv` with the APF bridge; PLL; SDRAM controller; a ROM slot into SDRAM; `system.vhd` in Game Gear mode; 160 x 144 out; PSG through i2s; `pkg/Cores/kroy.GG` manifests; §1 strip list applied. | A `.gg` from the card boots on a Pocket. `docs/BASELINE.md` has two seeds at `STANDARD FIT`. |
| **P1** | **Saves.** Cart RAM and 93C46 EEPROM out through the save slot on exit; sleep. | **Saves done 2026-09-11**, `Eternal Legend - Eien no Densetsu (Japan)` saved, survived a power cycle and loaded back. **Sleep is not started**, `core.json` still says `sleep_supported: false`, and it waits on §9.4. No Game Gear cartridge exercises the EEPROM path: `mapper_eeprom`'s CRC list is Master System exclusives only (World Series Baseball, The Majors Pro Baseball). That path stays code-reviewed, not hardware-tested, until P5 adds Master System. |
| **P2** | **Cheats.** Cheats slot, `cheat_binloader`, `CODES` restructured per §5, `cheat_poker` into work RAM, `interact.json` master switch and overlay toggle, `cheat_osd` at 160 x 144. | One Game Genie code and one Pro Action Replay code each take effect on hardware, off at startup, enable from the file. |
| **P3** | **The picker.** `pocket-tools` learns system `gg`: `Assets/gg/common`, the two libretro code shapes decoded to `.chtbin`, the full 818-file census recorded. | Every file in the corpus converts or is refused for a stated reason. |
| **P4** | **The cartridge.** Adapter bring-up per §7, in `pocket-cartridge` first, then ROM from the cart here with cheats on it. | A Game Gear cartridge dumps and matches No-Intro; then boots here. |
| **P5** | Master System and SG-1000 packages, PAL reconfig, FM. | Only if §9.3 says so. |
| **R** | Release `v0.9999.<sha>`: verify-only CI, package built on a runner, signed tag, published by hand. | Same boundary as the other three cores. |

Every phase is a commit with a hardware test and a `report.txt` in
`docs/BASELINE.md`. A fit is 17 to 35 minutes depending on the runner, and
two seeds run side by side, so RTL changes are batched, not iterated a line
at a time.
