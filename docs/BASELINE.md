# Build measurements

Tested source `21b980f`, seed 2, Quartus Lite 25.1std build 1129.
The build uses 11,285 / 18,480 ALMs (61.1 %), 171 RAM blocks and 6 DSP
blocks; the savestate engine and its 64 KB buffer, then the YM2413, are most
of the growth from the first release's 7,291 ALMs and 80 RAM blocks.
Setup is +2.332 ns, hold +0.076 ns; all timing categories pass. Seed 1 of
the same source passed with hold at +0.005 ns and was set aside for margin.
Game Gear and Master System ROMs, battery saves, the 93C46 EEPROM, save
states, sleep, FM sound, both cheat mechanisms and the named overlay were
tested on Pocket; SG-1000 boots Flicky, The Castle and Zaxxon. The bitstream
SHA-256 is
`766032053e212a76d8f39c8f64ef2ab3f10cc7041be29ebb36b2b7d2d1b69403`.

[Build and hardware history](https://github.com/kroy-the-rabbit/pocket-engineering/blob/main/game-gear/docs/BASELINE.md) (private).
