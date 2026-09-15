# Build measurements

Tested source `596823a`, seed 3, Quartus Lite 25.1std build 1129.
The build uses 9,641 / 18,480 ALMs (52.2 %) and 168 RAM blocks, of which
the savestate engine and its 64 KB buffer are most of the growth from the
first release's 7,291 and 80.
Setup is +2.382 ns, hold +0.107 ns; all timing categories pass.
ROMs, battery saves, the 93C46 EEPROM, save states, sleep, both cheat
mechanisms and the named overlay were tested on Pocket. The bitstream
SHA-256 is
`dfaad8ec2d8b8b20ff148d2bd9acce0ee1171c9ba9c7c23a8481d93beb5d8d04`.

[Build and hardware history](https://github.com/kroy-the-rabbit/pocket-engineering/blob/main/game-gear/docs/BASELINE.md) (private).
