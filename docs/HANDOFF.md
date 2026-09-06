# Handoff

State as of 2026-09-05. Read `PLAN.md` first.

## Where it stands

Phase F, the framework, is done. Nothing builds. There is no Quartus project,
no `core_top.sv`, no `pkg/Cores/kroy.GG`. `make test` passes: it checks that
`rtl/upstream/` is byte for byte `MiSTer-devel/SMS_MiSTer` at `1fc3c121`.

## Decisions still open, cheap now

From `PLAN.md` §9, in the order they bite:

1. The name. `pocket-gg` here, `kroy.GG` for the core directory. No GitHub
   repository exists yet.
2. Licence text: the GPLv2 file copied from the PC Engine fork, or
   GPL-3.0-or-later as the GBA fork uses. Upstream is "version 2 or later".
3. Scope beyond Game Gear.

## Next, in order

1. **P0.** Copy the Pocket side from `pocket-pcengine/target/pocket/` and the
   SDRAM controller from whichever sibling diffs smallest against
   `rtl/upstream/sdram.sv`. Write `core_top.sv` against `system.vhd` in Game
   Gear mode. Strip the §1 list. Manifests under `pkg/Cores/kroy.GG`. Build on
   sisko at seed 1 and seed 3, `STANDARD FIT`, and start `docs/BASELINE.md`
   with both.
2. Register a `tools/cheats/check-manifests.sh` equivalent in `make test` as
   soon as `pkg/` exists; the PC Engine one is the model, and use `grep`, not
   `rg`, because the CI runner has no ripgrep.
3. Hardware: a `.gg` boots. Then P1.

## Rules that hold here as in every sibling

* Builds on sisko or kira only, through `runner-build`. The Quartus image is
  private. CI verifies a published package and builds nothing.
* `report.sh` is the timing gate. Quartus exits 0 on a miss.
* `STANDARD FIT`, and never one seed for a comparison.
* `rtl/upstream/` is never edited; copies go to `rtl/gg/` with headers kept.
* Attribution is never removed from anything.
* Releases are `v0.9999.<short sha>` of the exact built commit, from `main`.
