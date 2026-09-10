# Game Gear for Analogue Pocket, with cheats

A Pocket core for the Sega Game Gear, ported by hand from
[MiSTer-devel/SMS_MiSTer](https://github.com/MiSTer-devel/SMS_MiSTer), with a
cheat engine and support for Game Gear cartridges through Analogue's adapter.

**Based on SMS_MiSTer by Sorgelig**, which is a port of Ben's Sega Master
System for the Papilio, with the T80, jt89, VM2413 and the VDP by their
respective authors, all credited in the file headers under `rtl/upstream/`.
Everything that will run here is theirs apart from the Pocket glue and the
cheat engine.

## Status

**P0 is done: it fits, meets timing on two seeds, and a `.gg` boots on a
Pocket with video, audio, controls and the ROM load diagnostic all confirmed
clean.** The port takes **5,865 to 5,876 ALMs, a third of the Cyclone V**; see
[docs/BASELINE.md](docs/BASELINE.md). Phases are in
[docs/PLAN.md](docs/PLAN.md).

| | |
|---|---|
| Upstream vendored at `1fc3c121`, verified by `make test` | done |
| Build harness, the four runners through the orchestrator | done |
| Quartus project, `core_top.v`, `gg_core.sv`, manifests | fits at 32%, timing met |
| ROM from the card into SDRAM | boots on hardware |
| Saves | **not started** |
| Cheats | **not started** |
| Cartridge adapter | **not started** |

The Game Gear runs at 160 x 144, which the Pocket's 1600 x 1440 display shows
at exactly ten times, so there is one video mode and no scaling to argue with.
Master System and SG-1000 come out of the same RTL and are a scope decision
rather than a technical one; nothing here is built for them yet.

## Documents

| | |
|---|---|
| [docs/PLAN.md](docs/PLAN.md) | what is being built, from what, in what order, and the lessons the sibling cores paid for |
| [docs/PROVENANCE.md](docs/PROVENANCE.md) | where `rtl/upstream/` comes from and the rule that it is never edited |
| [docs/HANDOFF.md](docs/HANDOFF.md) | where the work stands |
| [docs/BASELINE.md](docs/BASELINE.md) | what every build measured, and what the first one was expected to say |

## Build

    make gg        build -> build/gg/
    make test      provenance, Quartus project paths, APF manifests
    make dist      package a flashable core -> build/gg/dist/
    make report    re-read an existing build's utilisation and slack

Quartus runs only on the controlled builders through the orchestrator's
`runner-build`, against a private Quartus Lite image. Quartus Lite needs no
licence, but that grants no right to redistribute its installed files, so the
image is never published; each repo documents building it from Intel's own
installers. Releases publish the built package and its checksums, and CI
verifies that package against the tag rather than building anything.

## Licence

GNU GPL. The upstream's headers say version 2 or later; see `LICENSE`.
