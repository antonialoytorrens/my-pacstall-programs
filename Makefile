#!/usr/bin/make -f

# Integrate built .deb packages into a reprepro repository (after testing
# GitHub prereleases). Architecture comes from each .deb (Architecture: field);
# pass one file per arch — no separate arch flag on includedeb:
#
#   reprepro -b /path/to/repo includedeb <codename> ./gatus_5.36.0_amd64.deb
#   reprepro -b /path/to/repo includedeb <codename> ./gatus_5.36.0_arm64.deb
#   reprepro -b /path/to/repo includedeb <codename> ./gatus_5.36.0_armhf.deb
#   reprepro -b /path/to/repo includedeb <codename> ./gatus-pgsql_5.36.0_all.deb
#   reprepro -b /path/to/repo includedeb <codename> ./gatus-sqlite_5.36.0_all.deb
#   reprepro -b /path/to/repo export
#
# (Or use `reprepro include <codename> foo.changes` when you have a .changes
# that lists several architectures at once.)
#
# Pacstall cannot target a foreign architecture by itself; builds must run
# under the real arch (native runner or QEMU via Docker --platform).

SHELL := /bin/bash

include settings.cfg

# Arch → Docker platform
platform-amd64 := linux/amd64
platform-arm64 := linux/arm64
platform-armhf := linux/arm/v7

GATUS_TARGETS := $(addprefix gatus-,$(GATUS_ARCHES))
GLITCHTIP_TARGETS := $(addprefix glitchtip-,$(GLITCHTIP_ARCHES))
WEBLATE_TARGETS := $(addprefix weblate-,$(WEBLATE_ARCHES))
WGER_TARGETS := $(addprefix wger-,$(WGER_ARCHES))
BUILD_TARGETS := $(GATUS_TARGETS) $(GLITCHTIP_TARGETS) $(WEBLATE_TARGETS) $(WGER_TARGETS)
DOCKER_TARGETS := $(addprefix docker-,$(BUILD_TARGETS) clean)

.PHONY: all help clean docker-build docker-shell docker-down $(BUILD_TARGETS) $(DOCKER_TARGETS)

all: help

help:
	@echo "Usage: make <package>-<arch>"
	@echo "       make docker-<package>-<arch>   # same via docker compose"
	@echo ""
	@echo "Examples:"
	@echo "  make gatus-amd64"
	@echo "  make glitchtip-amd64"
	@echo "  make weblate-arm64"
	@echo "  make docker-wger-armhf WGER_DOMAIN=ci.example.test"
	@echo ""
	@echo "Packages and arches:"
	@echo "  gatus:     $(GATUS_ARCHES)"
	@echo "  glitchtip: $(GLITCHTIP_ARCHES)"
	@echo "  weblate:   $(WEBLATE_ARCHES)"
	@echo "  wger:      $(WGER_ARCHES)"
	@echo ""
	@echo "Other targets:"
	@echo "  clean         - Remove built .deb / .sha256 artifacts"
	@echo "  docker-build  - Build (or rebuild) the compose builder image"
	@echo "  docker-shell  - Interactive shell in the builder container"
	@echo "  docker-down   - Remove compose containers"
	@echo ""
	@echo " Foreign-arch builds (armhf on amd64 hosts, etc.) need QEMU"
	@echo " binfmt_misc registered once, e.g.:"
	@echo "   docker run --privileged --rm tonistiigi/binfmt --install all"
	@echo ""
	@echo " After testing GitHub prereleases, add each .deb to reprepro"
	@echo " (arch is read from the package; one includedeb per file):"
	@echo "   reprepro -b /path/to/repo includedeb <codename> ./pkg_ver_amd64.deb"
	@echo "   reprepro -b /path/to/repo includedeb <codename> ./pkg_ver_arm64.deb"
	@echo "   reprepro -b /path/to/repo export"

clean:
	rm -f ./*.deb ./*.sha256

docker-build:
	$(COMPOSE) build

docker-shell:
	$(COMPOSE) run --rm $(SERVICE) bash

docker-down:
	$(COMPOSE) down

# --- gatus ---
define gatus_rule
gatus-$(1):
	docker buildx build --platform $$(platform-$(1)) \
	  -f docker/gatus/Dockerfile --target artifact --output . .
endef
$(foreach a,$(GATUS_ARCHES),$(eval $(call gatus_rule,$(a))))

# --- glitchtip (amd64 only) ---
define glitchtip_rule
glitchtip-$(1):
	docker buildx build --platform $$(platform-$(1)) \
	  --build-arg GLITCHTIP_DOMAIN=$$(GLITCHTIP_DOMAIN) \
	  -f docker/glitchtip/Dockerfile --target artifact --output . .
endef
$(foreach a,$(GLITCHTIP_ARCHES),$(eval $(call glitchtip_rule,$(a))))

# --- weblate ---
define weblate_rule
weblate-$(1):
	docker buildx build --platform $$(platform-$(1)) \
	  -f docker/weblate/Dockerfile --target artifact --output . .
endef
$(foreach a,$(WEBLATE_ARCHES),$(eval $(call weblate_rule,$(a))))

# --- wger ---
define wger_rule
wger-$(1):
	docker buildx build --platform $$(platform-$(1)) \
	  --build-arg WGER_DOMAIN=$$(WGER_DOMAIN) \
	  -f docker/wger/Dockerfile --target artifact --output . .
endef
$(foreach a,$(WGER_ARCHES),$(eval $(call wger_rule,$(a))))

# Docker-wrapped equivalents: make docker-<target>
# Runs the same make target inside compose (kiwi-style). Target arch is still
# handled by docker buildx --platform inside the nested make recipe.
$(DOCKER_TARGETS):
	@target="$(@:docker-%=%)"; \
	case "$$target" in \
	  *-amd64|clean) platform=linux/amd64 ;; \
	  *-arm64) platform=linux/arm64 ;; \
	  *-armhf) platform=linux/arm/v7 ;; \
	  *) echo "ERROR: unknown docker target '$$target'"; exit 1 ;; \
	esac; \
	DOCKER_PLATFORM=$$platform $(COMPOSE) run --rm $(SERVICE) make $$target \
	  $(if $(WGER_DOMAIN),WGER_DOMAIN=$(WGER_DOMAIN)) \
	  $(if $(GLITCHTIP_DOMAIN),GLITCHTIP_DOMAIN=$(GLITCHTIP_DOMAIN))
