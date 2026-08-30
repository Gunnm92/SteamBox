REGISTRY     ?= registry.elfenn.eu
IMAGE        ?= steambox
TAG          ?= latest
GITHUB_TOKEN ?=
FULL_IMAGE   = $(REGISTRY)/$(IMAGE):$(TAG)
DOCKER       = DOCKER_HOST=tcp://docker-socket-proxy:2375 DOCKER_TLS_VERIFY= docker
BUILDX       = $(DOCKER) buildx build \
                 --builder default \
                 --platform linux/amd64 \
                 --provenance=false --sbom=false

BUILD_ARGS   = --build-arg BUILD_DATE="$(shell date -u +%Y-%m-%dT%H:%M:%SZ)"
ifdef GITHUB_TOKEN
BUILD_ARGS  += --build-arg GITHUB_TOKEN="$(GITHUB_TOKEN)"
endif

.PHONY: build push run stop logs clean help

# Seul Dockerfile restant depuis le pivot Waybox -> SteamBox (Dockerfile et
# Dockerfile.ubuntu supprimés — plus de variante webstation/Debian ni
# Ubuntu, uniquement CachyOS/Arch + KDE Plasma Wayland).
# Contexte "." (pas ".." comme avant le renommage ArcadeBox -> Waybox) :
# les COPY du Dockerfile sont désormais relatifs à la racine de ce dépôt
# lui-même, plus besoin d'un dossier parent nommé "ArcadeBox".
build:
	$(BUILDX) $(BUILD_ARGS) \
		--file Dockerfile.cachyos \
		--tag $(FULL_IMAGE) \
		--load \
		.

push:
	$(BUILDX) $(BUILD_ARGS) \
		--file Dockerfile.cachyos \
		--tag $(FULL_IMAGE) \
		--push \
		.

run:
	$(DOCKER) compose --file docker-compose.cachyos.yml up -d

stop:
	$(DOCKER) compose --file docker-compose.cachyos.yml down

logs:
	$(DOCKER) compose --file docker-compose.cachyos.yml logs -f

clean:
	$(DOCKER) compose --file docker-compose.cachyos.yml down --rmi local --volumes

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
