# Containerised Quartus for the Pocket Game Gear core

The Pocket's FPGA is a Cyclone V `5CEBA4F23C8`, and this project is an
OpenGateware-style tree: the Quartus project lives in `projects/`, sources come
in through `projects/gg_pocket.qip` and `rtl/gg.qip`, and the board pinout,
the pre/post-flow scripts and `target/pocket/core.qip` are pulled in by
`platform/pocket/pocket.tcl`.

Nothing here is installed on the host. Quartus runs in a container image,
`localhost/pocket-quartus:25.1std` by default. Release builds run on controlled
builders; no Quartus runs on GitHub.

## Reproducing a release

You download Quartus Lite from Altera and accept Altera's terms yourself;
installers are fetched only with `ACCEPT_ALTERA_EULA=1` set.

```sh
git checkout v0.9999.YYYYMMDD
ACCEPT_ALTERA_EULA=1 make installers   # 3.4 GB into tools/podman/dl/, once
make image                             # Quartus installed into a local image, once
make gg STRICT_TIMING=1
RELEASE_NAME=v0.9999.YYYYMMDD make dist
```

Compare `build/gg/report.txt` with the release's `report.txt`, and the
release's `BUILD.json` for the source commit it was built from. The bitstream
hash can differ from the release even on the same source: build-ID timestamps
and placement on another machine change it.

## Commands

    make gg                 build and report
    make gg NO_SIGNALTAP=1  strip SignalTap assignments added for a hardware probe
    make gg SEED=2          another fitter placement seed
    make gg SKIP_COMPILE=1  re-report existing outputs
    make report              regenerate build/gg/report.txt
    make shell               shell in the container, project at /work/projects
    make clean               remove build/

## Where things go

The checked-in tree is never written to. `build.sh` rsyncs the repo to
`build/gg/work/` and Quartus compiles there, which is also what makes it safe
to change fitter settings for an experiment: `projects/gg_pocket.qsf` in the
repo stays as checked in, and the patched copy is the one that gets compiled. Quartus scratch (`db/`, `incremental_db/`, `output_files/`)
survives an rsync so incremental compiles work; `make clean` wipes all of it.

Outputs:

    build/gg/report.txt   utilisation and slack summary (see below)
    build/gg/build.log    the full Quartus transcript
    build/gg/elapsed      wall-clock seconds of the compile
    build/gg/work/projects/output_files/   Quartus's own reports and bitstream

## The report

`report.sh` leads with ALM occupancy, because on a part this size that is what
decides whether anything can be added to the core. Quartus rounds its own
percentage to a whole number, so the harness recomputes it from the raw counts
and also prints how many ALMs are free.

Timing is reported but not enforced. This harness exists to measure the stock
core, and a baseline that misses timing is a result rather than a build
failure; `STRICT_TIMING=1` makes negative slack exit non-zero for builds that
are actually meant to be flashed. Either way a `build/gg/TIMING_FAILED` marker
is left behind when slack goes negative.

## Project settings that affect the numbers

* `NUM_PARALLEL_PROCESSORS 6` is pinned in the qsf. The build copy gets `ALL`,
  or `NPROC=<n>` when two experiments are sharing the machine. This changes
  compile time only.
* SignalTap is off and no `.stp` is checked in. `NO_SIGNALTAP=1` strips the
  assignments again if one is added temporarily to probe hardware.
