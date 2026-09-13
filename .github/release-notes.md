First public Game Gear release for Analogue Pocket, ported from
MiSTer-devel/SMS_MiSTer. SD-ROM gameplay, audio, controls, battery saves,
Game Genie ROM patches, Pro Action Replay RAM writes and the named cheat
overlay are confirmed on hardware. Switching between cheat files is tested.

Download `kroy.GG_0.9999.edc23d4.zip` and merge `Assets`, `Cores` and
`Platforms` into the SD root. Put `.gg` ROMs in `Assets/gg/common/`.
No BIOS is required. Put `Game.gg.cht` beside `Game.gg` and enable the
desired cheats in that file, then turn on **Cheats** in the core menu.
The cheat and overlay switches start off. `.chtbin` is also supported,
without names. The code table holds 32 entries shared by both mechanisms.

Eternal Legend's battery save survived a power cycle and reloaded.
Physical cartridges, sleep, savestates, Master System and SG-1000 are not
supported by this package. The platform image is plain and the core icon is
the Pocket default.

Built from `edc23d4`, Quartus Lite 25.1std build 1129: 7,291 ALMs (39.5 %),
+2.259 ns setup, +0.111 ns hold; all timing categories pass. The release
includes `report.txt` and `SHA256SUMS`.

Based on SMS_MiSTer by Sorgelig, from Ben's Sega Master System for the Papilio,
with T80, jt89, VM2413 and the VDP credited in the preserved upstream headers.
See [provenance](https://github.com/kroy-the-rabbit/openfpga-GG-cheats/blob/main/docs/PROVENANCE.md).
