# Game Gear, Master System and SG-1000 for Analogue Pocket, with cheats

A Pocket core for the Sega Game Gear, Master System and SG-1000, ported by
hand from
[MiSTer-devel/SMS_MiSTer](https://github.com/MiSTer-devel/SMS_MiSTer), with a
cheat engine, SD-ROM loading and battery saves. One bitstream ships as three
packages, `kroy.GG`, `kroy.SMS` and `kroy.SG1000`, one per platform. The
Game Gear package plays cartridges through Analogue's Game Gear adapter.

**Based on SMS_MiSTer by Sorgelig**, which is a port of Ben's Sega Master
System for the Papilio, with the T80, jt89, VM2413 and the VDP by their
respective authors, all credited in the file headers under `rtl/upstream/`.
Everything that will run here is theirs apart from the Pocket glue and the
cheat engine.

## Status

Release `v0.9999.20260915` packages tested build `440ccc6`: it boots the EEPROM titles that hang on `edc23d4`, adds save
states, sleep, FM sound and cartridge play, and runs Master System titles at
their own resolutions. Game Gear and Master System ROMs, video, audio,
controls, both kinds of save, save states, sleep, FM sound, both cheat
mechanisms, the named overlay and Game Gear cartridges are confirmed on
hardware. SG-1000 boots Flicky, The Castle and Zaxxon. The build uses
11,642 ALMs (63.0 %) and passes every timing category.

| Feature | Status |
|---|---|
| Upstream vendored at `1fc3c121` | Verified by `make test` |
| SD ROMs, video, audio and controls | Tested on Pocket, Game Gear and Master System |
| Battery saves | Eternal Legend, Phantasy Star and Ys saved and loaded after a power cycle |
| 93C46 EEPROM saves | World Series Baseball '95 saved and loaded after a power cycle |
| Game Genie ROM patches and Pro Action Replay RAM writes | Tested on Pocket, Game Gear and Master System (OutRun's timer) |
| `.cht`, `.chtbin` and named overlay | Tested, including switching cheat files; overlay confirmed in the 256-wide Master System frame |
| Save states and sleep | Menu save and load, sleep and wake, tested on Pocket; MiSTer's engine behind APF |
| Master System at 192, 224 and 240 lines | 192 tested (Phantasy Star, Ys); 224 and 240 untested |
| SG-1000 | Flicky, The Castle and Zaxxon boot; The Castle's 32 KB cart RAM is written back, reload untested |
| FM sound (YM2413) | OutRun switches between FM and PSG on the Pocket; output averaged over a 1024-cycle window |
| Game Gear cartridges through Analogue's adapter | Sonic 2, Arch Rivals and World Series Baseball (an EEPROM cart) play from the cartridge, cheats included; saves not kept yet |

Merge a release package's `Assets`, `Cores` and `Platforms` into the SD
root; the three packages are independent, so install only the platforms you
want. Put `.gg` ROMs in `Assets/gg/common/`, `.sms` in `Assets/sms/common/`
and `.sg` in `Assets/sg1000/common/`. No BIOS is needed. Put `Game.gg.cht`
beside `Game.gg`, select the cheats in the file and turn on **Cheats** in the
core menu. The cheat and overlay switches start off and are not persisted.
`.chtbin` also works, without names. The shared table holds 32 codes.
**Play Cartridge** in the Game Gear entry, with Analogue's Game Gear
adapter fitted, reads the cartridge through the adapter and then runs it as
if it had come from the card: the cartridge's own mapper is used only to get
the bytes out, up to the 512 KB the mapper can address, about a second.
Saves made while playing a cartridge are not kept yet: nothing is written
back to the cartridge, and the Pocket writes no save file for a core started
without a ROM slot. `CG:`, `CS:` and `CR:` in the menu are the adapter report, the read
state and the CRC32 of what was read, for when nothing appears.
**FM sound** in the core menu is the YM2413 and starts on. A game asks for
the chip through port $F2 when it boots, so the switch takes effect at the
next **Reset core**, and some export titles ask only with **Region** set to
Japan.

See [docs/PROVENANCE.md](docs/PROVENANCE.md) for source attribution,
including the platform image and the core icon.

The Game Gear runs at 160 x 144, which the Pocket's 1600 x 1440 display shows
at exactly ten times. The Master System and SG-1000 packages declare 256 x 192,
256 x 224 and 256 x 240 at 4:3 and the core picks the slot each frame from the
VDP mode. The three packages share one bitstream because the Pocket delivers
a ROM slot before start only when it is required, and a package can carry
only one required ROM slot, so each platform needs its own package.

## Documents

| | |
|---|---|
| [docs/PLAN.md](docs/PLAN.md) | engineering history (private) |
| [docs/PROVENANCE.md](docs/PROVENANCE.md) | where `rtl/upstream/` comes from and the rule that it is never edited |
| [docs/HANDOFF.md](docs/HANDOFF.md) | where the work stands (private) |
| [docs/BASELINE.md](docs/BASELINE.md) | current tested build measurements |

## Build

    make gg        build -> build/gg/
    make test      provenance, Quartus project paths, APF manifests
    make dist      package a flashable core -> build/gg/dist/
    make report    re-read an existing build's utilisation and slack
    make icon      render assets/icon-*.svg into the core icons
    make platform  render assets/platform-*.svg into the platform images

Releases are built from the tagged commit on a controlled builder with Quartus
Prime Lite 25.1std. No Quartus runs on GitHub; the release workflow only checks
the published package. To rebuild a release yourself, see
[tools/podman/README.md](tools/podman/README.md#reproducing-a-release).

## Licence

GNU GPL. The upstream's headers say version 2 or later; see `LICENSE`.

## Versions

Versions use `0.9999.YYYYMMDD`, where the date is UTC. Release tags add `v`,
for example `v0.9999.20260913`. Each project releases independently.
The source commit and bitstream checksums are recorded in build provenance.
A published date is not reused for a different build.
