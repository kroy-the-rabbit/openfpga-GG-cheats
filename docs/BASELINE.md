# Build measurements

Tested source `d7dfbb8`, seed 1, Quartus Lite 25.1std build 1129, with the
three-package manifests that followed it.
The build uses 10,064 / 18,480 ALMs (54.5 %) and 168 RAM blocks, of which
the savestate engine and its 64 KB buffer are most of the growth from the
first release's 7,291 and 80.
Setup is +1.883 ns, hold +0.095 ns; all timing categories pass.
Game Gear and Master System ROMs, battery saves, the 93C46 EEPROM, save
states, sleep, both cheat mechanisms and the named overlay were tested on
Pocket. The bitstream SHA-256 is
`354dcae3ec70ba04aa661ab0ac5c72eb79eee00d247c95e026fc12d6f1f69fdc`.

[Build and hardware history](https://github.com/kroy-the-rabbit/pocket-engineering/blob/main/game-gear/docs/BASELINE.md) (private).
