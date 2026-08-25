REGISTRY     ?= registry.elfenn.eu
IMAGE        ?= arcadebox
TAG          ?= latest
GITHUB_TOKEN ?=
FULL_IMAGE   = $(REGISTRY)/$(IMAGE):$(TAG)
DOCKER       = DOCKER_HOST=tcp://docker-socket-proxy:2375 DOCKER_TLS_VERIFY= docker
BUILDX       = $(DOCKER) buildx build \
                 --builder default \
                 --platform linux/amd64

BUILD_ARGS   = --build-arg BUILD_DATE="$(shell date -u +%Y-%m-%dT%H:%M:%SZ)"
ifdef GITHUB_TOKEN
BUILD_ARGS  += --build-arg GITHUB_TOKEN="$(GITHUB_TOKEN)"
endif

.PHONY: build push run stop logs clean help build-cachyos push-cachyos run-cachyos stop-cachyos logs-cachyos build-ubuntu push-ubuntu run-ubuntu stop-ubuntu logs-ubuntu

build:
	$(BUILDX) $(BUILD_ARGS) \
		--file Dockerfile \
		--tag $(FULL_IMAGE) \
		--load \
		..

push:
	$(BUILDX) $(BUILD_ARGS) \
		--file Dockerfile \
		--tag $(FULL_IMAGE) \
		--push \
		..

run:
	$(DOCKER) compose --file ArcadeBox/docker-compose.yml up -d

stop:
	$(DOCKER) compose --file ArcadeBox/docker-compose.yml down

logs:
	$(DOCKER) compose --file ArcadeBox/docker-compose.yml logs -f

clean:
	$(DOCKER) compose --file ArcadeBox/docker-compose.yml down --rmi local --volumes

# ── Variante CachyOS + Hyprland (branche cachyos-kde, expérimentale) ─────────
build-cachyos:
	$(BUILDX) $(BUILD_ARGS) \
		--file Dockerfile.cachyos \
		--tag $(REGISTRY)/$(IMAGE)-cachyos:$(TAG) \
		--load \
		..

push-cachyos:
	$(BUILDX) $(BUILD_ARGS) \
		--file Dockerfile.cachyos \
		--tag $(REGISTRY)/$(IMAGE)-cachyos:$(TAG) \
		--push \
		..

run-cachyos:
	$(DOCKER) compose --file ArcadeBox/docker-compose.cachyos.yml up -d

stop-cachyos:
	$(DOCKER) compose --file ArcadeBox/docker-compose.cachyos.yml down

logs-cachyos:
	$(DOCKER) compose --file ArcadeBox/docker-compose.cachyos.yml logs -f

# ── Variante Ubuntu + KDE (structure root-cachyos/, paquets apt) ────────────
build-ubuntu:
	$(BUILDX) $(BUILD_ARGS) \
		--file Dockerfile.ubuntu \
		--tag $(REGISTRY)/$(IMAGE)-ubuntu:$(TAG) \
		--load \
		..

push-ubuntu:
	$(BUILDX) $(BUILD_ARGS) \
		--file Dockerfile.ubuntu \
		--tag $(REGISTRY)/$(IMAGE)-ubuntu:$(TAG) \
		--push \
		..

run-ubuntu:
	$(DOCKER) compose --file ArcadeBox/docker-compose.ubuntu.yml up -d

stop-ubuntu:
	$(DOCKER) compose --file ArcadeBox/docker-compose.ubuntu.yml down

logs-ubuntu:
	$(DOCKER) compose --file ArcadeBox/docker-compose.ubuntu.yml logs -f

help:
	@echo "Targets:"
	@echo "  build    Build l'image localement (--load)"
	@echo "  push     Build + push vers $(REGISTRY)"
	@echo "  run      docker compose up -d"
	@echo "  stop     docker compose down"
	@echo "  logs     Suivre les logs du conteneur"
	@echo "  clean    Arret + suppression image locale + volumes"
	@echo ""
	@echo "Variables (override avec make VAR=val):"
	@echo "  REGISTRY       $(REGISTRY)"
	@echo "  IMAGE          $(IMAGE)"
	@echo "  TAG            $(TAG)"
	@echo "  GITHUB_TOKEN   (non defini si vide)"
