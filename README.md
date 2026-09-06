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

**Framework only. Nothing builds yet.** The repository holds the vendored
upstream, the build harness, and the plan. The first phase that produces a
bitstream is P0 in [docs/PLAN.md](docs/PLAN.md).

| | |
|---|---|
| Upstream vendored at `1fc3c121`, verified by `make test` | done |
| Build harness, sisko/kira through the orchestrator | done, untested until P0 |
| Quartus project, `core_top.sv`, manifests | **not started** |
| ROM from the card | **not started** |
| Saves | **not started** |
| Cheats | **not started** |
| Cartridge adapter | **not started** |

## Documents

| | |
|---|---|
| [docs/PLAN.md](docs/PLAN.md) | what is being built, from what, in what order, and the lessons the sibling cores paid for |
| [docs/PROVENANCE.md](docs/PROVENANCE.md) | where `rtl/upstream/` comes from and the rule that it is never edited |
| [docs/HANDOFF.md](docs/HANDOFF.md) | where the work stands |

## Build

    make gg        build -> build/gg/          (no project yet; P0)
    make test      rtl/upstream matches docs/upstream.sha256
    make report    re-read an existing build's utilisation and slack

Quartus runs only on the controlled builders through the orchestrator's
`runner-build`, against a private Quartus Lite image. Quartus Lite needs no
licence, but that grants no right to redistribute its installed files, so the
image is never published; each repo documents building it from Intel's own
installers. Releases publish the built package and its checksums, and CI
verifies that package against the tag rather than building anything.

## Licence

GNU GPL. The upstream's headers say version 2 or later; see `LICENSE`.
