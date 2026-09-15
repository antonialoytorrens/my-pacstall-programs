#!/usr/bin/make -f

# Integrate built .deb packages into a reprepro repository (after testing
# GitHub prereleases). Architecture comes from each .deb (Architecture: field);
# pass one file per arch — no separate arch flag on includedeb:
#
#   reprepro -b /path/to/repo includedeb <codename> ./gatus_5.36.0~debian13_amd64.deb
#   reprepro -b /path/to/repo includedeb <codename> ./wger_2.7~ubuntu26.04_amd64.deb
#   reprepro -b /path/to/repo export
#
# Packages are discovered by convention:
#   packages/<name>/<name>.pacscript
# Distros come from docker/Dockerfile* (rendered from docker/Dockerfile.in).
# Version comes from pkgver="..." in the pacscript (no VERSION file).
#
# Pacstall cannot target a foreign architecture by itself; builds must run
# under the real arch (native runner or QEMU via Docker --platform).

SHELL := /bin/bash

include settings.cfg

DISCOVER := ./scripts/discover.sh
MAKE_TARGETS := $(shell $(DISCOVER) make-targets)

.PHONY: all help clean packagelist srclist dockerfiles docker-build docker-shell docker-down \
	$(MAKE_TARGETS) $(addprefix docker-,$(MAKE_TARGETS))

all: help

help:
	@echo "Usage: make <package>-<arch>"
	@echo "       make <package>-<distribution>-<release>-<arch>"
	@echo "       make docker-<target>   # same via docker compose"
	@echo ""
	@echo "Examples:"
	@echo "  make gatus-amd64"
	@echo "  make glitchtip-amd64"
	@echo "  make weblate-arm64"
	@echo "  make docker-wger-armhf"
	@echo "  make wger-ubuntu-26.04-amd64"
	@echo ""
	@echo "Packages (from packages/; distros from docker/Dockerfile*):"
	@$(DISCOVER) list | while read -r p; do \
	  arches="$$($(DISCOVER) arches "$$p" | tr '\n' ' ')"; \
	  echo "  $$p: $$arches"; \
	done
	@echo "Distros:"
	@$(DISCOVER) dockerfiles | while IFS='|' read -r df distro release; do \
	  echo "  $$distro $$release ($$df)"; \
	done
	@echo ""
	@echo "Other targets:"
	@echo "  packagelist / srclist - Regenerate from pacscripts"
	@echo "  dockerfiles    - Render docker/Dockerfile* from Dockerfile.in"
	@echo "  clean          - Remove built .deb / .sha256 artifacts"
	@echo "  docker-build   - Build (or rebuild) the compose builder image"
	@echo "  docker-shell   - Interactive shell in the builder container"
	@echo "  docker-down    - Remove compose containers"
	@echo ""
	@echo " Foreign-arch builds need QEMU binfmt once, e.g.:"
	@echo "   docker run --privileged --rm tonistiigi/binfmt --install all"

clean:
	rm -f ./*.deb ./*.sha256

packagelist:
	$(DISCOVER) packagelist > packagelist

srclist:
	$(DISCOVER) srclist > srclist

dockerfiles:
	./scripts/render-dockerfiles.sh

docker-build:
	$(COMPOSE) build

docker-shell:
	$(COMPOSE) run --rm $(SERVICE) bash

docker-down:
	$(COMPOSE) down

# Generic package builds (discovered targets)
$(MAKE_TARGETS): packagelist srclist
	$(DISCOVER) build "$@"

# Docker-wrapped: make docker-<target>
$(addprefix docker-,$(MAKE_TARGETS)):
	@target="$(@:docker-%=%)"; \
	case "$$target" in \
	  *-amd64) platform=linux/amd64 ;; \
	  *-arm64) platform=linux/arm64 ;; \
	  *-armhf) platform=linux/arm/v7 ;; \
	  *) echo "ERROR: unknown docker target '$$target'"; exit 1 ;; \
	esac; \
	DOCKER_PLATFORM=$$platform $(COMPOSE) run --rm $(SERVICE) make $$target
