## Game Gear, Master System and SG-1000

One core now ships as three independent packages: **kroy.GG**, **kroy.SMS**
and **kroy.SG1000**. Install the platforms you want. Game Gear and Master
System ROMs run with Game Genie ROM patches, Pro Action Replay RAM writes,
and named cheat overlays, confirmed on the Pocket. Master System testing
includes OutRun's timer cheats and its overlay at the full 256-pixel width.

This update also brings save states, sleep and wake, YM2413 FM sound, and
correct EEPROM-game detection. World Series Baseball '95 now boots from SD
and keeps its save across a power cycle. Game Gear and Master System SD
battery saves are tested. FM output is averaged over a 1024-cycle window before the Pocket audio output;
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
| `kroy.GG_0.9999.20260915.zip` | `Assets/gg/common/Game.gg` | `Game.gg.cht` |
| `kroy.SMS_0.9999.20260915.zip` | `Assets/sms/common/Game.sms` | `Game.sms.cht` |
| `kroy.SG1000_0.9999.20260915.zip` | `Assets/sg1000/common/Game.sg` | `Game.sg.cht` |

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

## Tested build

Version `0.9999.20260915` preserves the hardware-tested `440ccc6`, seed 2
bitstream. Later source changes trim comments and update documentation.
Quartus Lite 25.1std build 1129: 11,642 ALMs (63.0 %), 171 RAM blocks,
+1.258 ns setup and +0.100 ns hold. Every timing category passes.

Bitstream SHA-256:
`fb4ef384b3c027cb49c0d0bee74e498ab617b78618823770c4243c2cf4447a69`.
The three ZIPs share those exact bytes. `BUILD.json` records the original
build commit separately from the release commit. `report.txt` and
`SHA256SUMS` accompany the downloads.

## Verify the downloads

Artifacts are signed with Kroy's normal key,
`7268DF1E6F75DA7731A46B65888C35858FEACF72`. The release includes its public
key and detached signatures for the ZIPs, provenance and timing report.

```sh
gpg --import RELEASE-KEY.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
sha256sum -c SHA256SUMS
```
