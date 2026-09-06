# Provenance

## Upstream

`MiSTer-devel/SMS_MiSTer`, commit `1fc3c121c16c91d83ed714dfef71df078205ded4`,
2026-08-31, "Adjust aspect ratio for 248x192 resolution." Sorgelig's MiSTer
port of Ben's Sega Master System for the Papilio. Licence in the file headers:
GNU GPL version 2 or later. The remote is `upstream`, fetch only, push URL
`DISABLED`.

## What is vendored, and where

`rtl/upstream/` is the upstream `rtl/` directory byte for byte, plus `SMS.sv`
and `files.qip` from the repository root, kept as the reference for the
MiSTer-side wiring. Nothing else from upstream is here: not `sys/` (the
DE10-nano framework, which the Pocket does not use), not `mist/`, not
`releases/`, not `SMSBootLoader/` (its output, `mboot.mif`, is in `rtl/`).

`mboot.mif` is Bock's SMS Boot Loader (SMS Power, 2001), a free boot ROM the
upstream ships. It runs in Master System mode only.

## Rules

1. **`rtl/upstream/` is never edited.** A file that needs a Pocket change is
   copied to `rtl/gg/` and the copy is edited, with its header intact and a
   line saying what changed and why. The project file lists the copy, not
   the original. `tools/check/provenance.sh` verifies every file under
   `rtl/upstream/` against `docs/upstream.sha256` and fails `make test` on
   any drift, added file or missing file.
2. **Attribution stays.** Upstream headers, copyright lines and licence
   notices are kept verbatim in every copied file. Nothing here removes an
   author.
3. **Syncing upstream** is `git fetch upstream`, then a diff of
   `upstream/master:rtl` against `rtl/upstream/`, applied by copying the files
   in and regenerating the manifest:

        tools/check/provenance.sh --regen

   Record the new commit and date at the top of this file in the same commit.
4. **The bitstream is not upstream's.** Everything under `target/`, `pkg/`
   and `rtl/gg/` is this project's, under the licence in `LICENSE`.
