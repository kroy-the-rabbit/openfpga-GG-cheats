# Build measurements

Tested source `440ccc6`, seed 2, Quartus Lite 25.1std build 1129
(`554a9c6` trims comments on the same RTL).
The build uses 11,642 / 18,480 ALMs (63.0 %) and 171 RAM blocks; the
savestate engine and its buffer, the YM2413 and the cartridge path are the
growth from the first release's 7,291 ALMs and 80 RAM blocks.
Setup is +1.258 ns, hold +0.100 ns; all timing categories pass.
Game Gear and Master System ROMs, battery saves, the 93C46 EEPROM, save
states, sleep, FM sound, both cheat mechanisms and the named overlay were
tested on Pocket; SG-1000 boots Flicky, The Castle and Zaxxon; Sonic 2,
Arch Rivals and World Series Baseball play from the cartridge. The
bitstream SHA-256 is
`fb4ef384b3c027cb49c0d0bee74e498ab617b78618823770c4243c2cf4447a69`.

[Build and hardware history](https://github.com/kroy-the-rabbit/pocket-engineering/blob/main/game-gear/docs/BASELINE.md) (private).
