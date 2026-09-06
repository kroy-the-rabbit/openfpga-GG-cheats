# Build and measurement harness for the Pocket Game Gear core. Nothing builds
# yet: there is no Quartus project until P0 (docs/PLAN.md).
#
# Quartus, containerised (see tools/podman/README.md):
#
#   make gg                    build -> build/gg/{report.txt,build.log,work/}
#   make gg BUILD_NAME=foo     build into build/foo/ instead (compare two trees)
#   make gg NO_SIGNALTAP=1     build without the qsf's SignalTap instrumentation
#   make gg SEED=2             re-run the fitter with a different placement seed
#   make gg SKIP_COMPILE=1     re-report existing outputs (no Quartus run)
#   make dist                   package a flashable core -> build/gg/dist/
#   make dist BUILD_NAME=foo    package build/foo instead
#                               also writes a release zip you can unpack onto
#                               the SD card root
#   make report                 regenerate build/gg/report.txt from existing outputs
#   make shell                  interactive shell in the Quartus container
#   make compare A=gg B=baseline   resource and timing delta between two builds
#   make clean                  remove build/
#
# Builds run on sisko or kira through the orchestrator's runner-build. CI
# never builds: .github/workflows/release.yml verifies the published package.
#
#   tools/check/provenance.sh        rtl/upstream is byte for byte MiSTer's

PODMAN  ?= podman
# Repeatable timing closure. AUTO FIT, which the qsf asks for, lowers effort as
# soon as it believes timing is achievable, and on this design the worst hold
# path has about a tenth of a nanosecond of margin. At the same seed, AUTO FIT
# landed it at -0.025 ns and STANDARD FIT at +0.109 ns. Override with an empty
# value to build the way upstream does. See docs/BASELINE.md.
FITTER_EFFORT ?= STANDARD FIT
IMAGE   ?= localhost/pocket-quartus:25.1std
REV     ?= gg_pocket
HARNESS := tools/podman

.PHONY: gg dist report compare shell clean test

gg:
	PODMAN=$(PODMAN) IMAGE=$(IMAGE) REV=$(REV) SEED=$(SEED) BUILD_NAME=$(BUILD_NAME) \
	SKIP_COMPILE=$(SKIP_COMPILE) NO_SIGNALTAP=$(NO_SIGNALTAP) \
	FITTER_EFFORT="$(FITTER_EFFORT)" NPROC="$(NPROC)" \
	STRICT_TIMING=$(STRICT_TIMING) $(HARNESS)/build.sh

dist:
	REV=$(REV) BUILD_NAME=$(BUILD_NAME) $(HARNESS)/dist.sh

test:
	tools/check/provenance.sh

report:
	REV=$(REV) BUILD_NAME=$(BUILD_NAME) $(HARNESS)/report.sh

shell:
	$(PODMAN) run --rm -it --userns=keep-id --security-opt label=disable \
		-v "$(CURDIR)/build/$(or $(BUILD_NAME),gg)/work:/work" -w /work/projects -e HOME=/tmp $(IMAGE) bash

clean:
	rm -rf build

compare:
	REV=$(REV) $(HARNESS)/compare.sh $(A) $(B)
