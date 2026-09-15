## Game Gear, Master System and SG-1000

One core now ships as three independent packages: **kroy.GG**, **kroy.SMS**
and **kroy.SG1000**. Install the platforms you want. Game Gear and Master
System ROMs run with Game Genie ROM patches, Pro Action Replay RAM writes,
and named cheat overlays, confirmed on the Pocket. Master System testing
includes OutRun's timer cheats and its overlay at the full 256-pixel width.

This update also brings save states, sleep and wake, YM2413 FM sound, and
correct EEPROM-game detection. World Series Baseball '95 now boots from SD
and keeps its save across a power cycle. Game Gear and Master System SD
battery saves are tested. FM output is averaged over each Pocket audio frame;
OutRun's FM/PSG switch is confirmed. **FM sound** defaults on and takes effect
at the next **Reset core**; some export games require **Region: Japan**.

SG-1000 boots Flicky, The Castle and Zaxxon. **SG-1000 cheats are untested.**
The Castle's 32 KB RAM is written back, but save reload is not verified.
Master System's 192-line display is tested; 224 and 240 lines remain untested.

## Limited Game Gear cartridge support

With Analogue's Game Gear adapter, select **Play Cartridge** in the Game Gear
core. Sonic 2, Arch Rivals and World Series Baseball (an EEPROM cartridge)
play with cheats. The core reads the ROM through the physical mapper, up to
512 KB, then runs the copy from memory. This is a small tested cartridge set,
not a claim that every cartridge or mapper works.

**Cartridge saves do not work in this release.** Nothing is written back to
the physical cartridge, and the Pocket keeps no SD save file in Play
Cartridge mode. Use an SD ROM when save persistence is needed. The working
SD-ROM save support above does not extend to Play Cartridge.

## Install and use

Download the ZIP for each desired platform and merge its `Assets`, `Cores`
and `Platforms` into the SD root, preserving existing files. No BIOS is needed.

| Package | ROM path | Cheat file beside the ROM |
|---|---|---|
| `kroy.GG_<version>.zip` | `Assets/gg/common/Game.gg` | `Game.gg.cht` |
| `kroy.SMS_<version>.zip` | `Assets/sms/common/Game.sms` | `Game.sms.cht` |
| `kroy.SG1000_<version>.zip` | `Assets/sg1000/common/Game.sg` | `Game.sg.cht` |

Select the desired cheats in the file, load it through **Cheats** where
needed, and turn on the global **Cheats** switch. Cheats and the overlay start
off and are not persisted. `.chtbin` also works, without names. The table holds
32 codes shared by both mechanisms. Pocket Tools prepares named cheat files
and installs each available platform package independently.

## Credits

Ported from [SMS_MiSTer](https://github.com/MiSTer-devel/SMS_MiSTer) by Sorgelig,
from Ben's Sega Master System for the Papilio, with T80, jt89, VM2413 and the
VDP credited in preserved upstream headers. See
[provenance](https://github.com/kroy-the-rabbit/openfpga-GG-cheats/blob/main/docs/PROVENANCE.md).

<!-- Release preparation: append the passing build's source commit, bitstream
SHA-256, utilization and timing results after hardware verification. Do not
publish this draft while fitting is pending. -->
