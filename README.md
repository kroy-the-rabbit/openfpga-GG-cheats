# Game Gear for Analogue Pocket, with cheats

A Pocket core for the Sega Game Gear, ported by hand from
[MiSTer-devel/SMS_MiSTer](https://github.com/MiSTer-devel/SMS_MiSTer), with a
cheat engine, SD-ROM loading and battery saves. Physical cartridge support
is not implemented.

**Based on SMS_MiSTer by Sorgelig**, which is a port of Ben's Sega Master
System for the Papilio, with the T80, jt89, VM2413 and the VDP by their
respective authors, all credited in the file headers under `rtl/upstream/`.
Everything that will run here is theirs apart from the Pocket glue and the
cheat engine.

## Status

Release `v0.9999.20260913` packages tested build `edc23d4`. ROMs, video,
audio, controls, saves,
both cheat mechanisms and the named overlay are confirmed on hardware.
The build uses 7,291 ALMs (39.5 %) and passes every timing category.

| Feature | Status |
|---|---|
| Upstream vendored at `1fc3c121` | Verified by `make test` |
| SD ROMs, video, audio and controls | Tested on Pocket |
| Battery saves | Eternal Legend saved and loaded after a power cycle |
| Game Genie ROM patches and Pro Action Replay RAM writes | Tested on Pocket |
| `.cht`, `.chtbin` and named overlay | Tested, including switching cheat files |
| Physical cartridge adapter, sleep and savestates | Not implemented |

Merge the release package's `Assets`, `Cores` and `Platforms`
into the SD root.
Put `.gg` ROMs in `Assets/gg/common/`. No BIOS is needed. Put `Game.gg.cht`
beside `Game.gg`, select the cheats in the file and turn on **Cheats** in the
core menu. The cheat and overlay switches start off and are not persisted.
`.chtbin` also works, without names. The shared table holds 32 codes.

The current package uses a plain platform image and the Pocket's default core
icon. See [docs/PROVENANCE.md](docs/PROVENANCE.md) for source attribution.

The Game Gear runs at 160 x 144, which the Pocket's 1600 x 1440 display shows
at exactly ten times, so there is one video mode and no scaling to argue with.
Master System and SG-1000 come out of the same RTL and are a scope decision
rather than a technical one; nothing here is built for them yet.

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
