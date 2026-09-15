# Build and measurement harness for the Pocket Game Gear core.
# Routine synthesis runs through the shared runner-build interface.
#
# Quartus, containerised (see tools/podman/README.md):
#
#   ACCEPT_ALTERA_EULA=1 make installers   Quartus Lite installers -> tools/podman/dl/
#   make image                  install them into the local Quartus image
#   make gg                    build -> build/gg/{report.txt,build.log,work/}
#   make gg BUILD_NAME=foo     build into build/foo/ instead (compare two trees)
#   make gg NO_SIGNALTAP=1     strip SignalTap assignments added for a hardware probe
#   make gg SEED=2             re-run the fitter with a different placement seed
#   make gg SKIP_COMPILE=1     re-report existing outputs (no Quartus run)
#   make dist                   package a flashable core -> build/gg/dist/
#   make dist BUILD_NAME=foo    package build/foo instead
#                               also writes a release zip you can unpack onto
#                               the SD card root
#   make report                 regenerate build/gg/report.txt from existing outputs
#   make shell                  interactive shell in the Quartus container
#   make compare A=gg B=baseline   resource and timing delta between two builds
#   make flash                  merge build/gg/dist onto the mounted Pocket card
#   make icon                   render assets/icon.svg -> pkg/Cores/kroy.GG/icon.bin
#   make platform               render assets/platform-*.svg -> pkg/Platforms/_images/*.bin
#   make clean                  remove build/
#
# Release builds run on controlled builders. CI builds nothing:
# .github/workflows/release.yml verifies the published package.
#
#   make test                   provenance, project file paths, APF manifests

PODMAN  ?= podman
# Repeatable timing closure. AUTO FIT lowers effort as soon as it believes
# timing is achievable, which on the sibling cores moved the answer by 0.4 ns
# and spread 0.5 ns across seeds for no reason the design could explain, while
# STANDARD FIT agreed to a picosecond. The qsf asks for STANDARD FIT too, so
# this only matters if it is overridden.
FITTER_EFFORT ?= STANDARD FIT
IMAGE   ?= localhost/pocket-quartus:25.1std
REV     ?= gg_pocket
HARNESS := tools/podman
DL      := $(HARNESS)/dl

.PHONY: installers image gg dist report compare shell clean test flash icon platform

installers:
	$(HARNESS)/fetch-installers.sh

image: installers
	$(PODMAN) build --security-opt label=disable \
		-v "$(CURDIR)/$(DL):/dl:ro" \
		-t $(IMAGE) -f $(HARNESS)/Containerfile $(HARNESS)

gg:
	PODMAN=$(PODMAN) IMAGE=$(IMAGE) REV=$(REV) SEED=$(SEED) BUILD_NAME=$(BUILD_NAME) \
	SKIP_COMPILE=$(SKIP_COMPILE) NO_SIGNALTAP=$(NO_SIGNALTAP) \
	FITTER_EFFORT="$(FITTER_EFFORT)" NPROC="$(NPROC)" \
	STRICT_TIMING=$(STRICT_TIMING) $(HARNESS)/build.sh

dist:
	PODMAN=$(PODMAN) IMAGE=$(IMAGE) REV=$(REV) BUILD_NAME=$(BUILD_NAME) $(HARNESS)/dist.sh

test:
	tools/check/provenance.sh
	tools/check/project.sh
	tools/check/manifests.sh
	tools/check/cheats.sh

report:
	REV=$(REV) BUILD_NAME=$(BUILD_NAME) $(HARNESS)/report.sh

flash:
	BUILD_NAME=$(BUILD_NAME) tools/flash.sh $(SD)

# ImageMagick renders the SVG; the encoder needs Pillow, so it runs from a venv
# under build/ (see tools/icon/genicon.py).
VENV ?= build/gg/venv
icon:
	[ -x $(VENV)/bin/python3 ] || (python3 -m venv $(VENV) && $(VENV)/bin/pip -q install pillow)
	magick -background none -density 576 assets/icon.svg -resize 288x288 build/gg/icon.png
	$(VENV)/bin/python3 tools/icon/genicon.py build/gg/icon.png pkg/Cores/kroy.GG/icon.bin

platform:
	[ -x $(VENV)/bin/python3 ] || (python3 -m venv $(VENV) && $(VENV)/bin/pip -q install pillow)
	for p in gg sms sg1000; do \
	  magick +antialias -background white assets/platform-$$p.svg -colorspace Gray -depth 8 build/gg/platform-$$p.png && \
	  $(VENV)/bin/python3 tools/icon/genplatform.py build/gg/platform-$$p.png pkg/Platforms/_images/$$p.bin || exit 1; \
	done

shell:
	$(PODMAN) run --rm -it --userns=keep-id --security-opt label=disable \
		-v "$(CURDIR)/build/$(or $(BUILD_NAME),gg)/work:/work" -w /work/projects -e HOME=/tmp $(IMAGE) bash

clean:
	rm -rf build

compare:
	REV=$(REV) $(HARNESS)/compare.sh $(A) $(B)
