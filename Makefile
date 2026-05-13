REGISTRY     ?= registry.elfenn.eu
IMAGE        ?= arcadebox
TAG          ?= latest
GITHUB_TOKEN ?=
CONFIG_DIR   ?= /mnt/user/appdata/arcadebox

FULL_IMAGE   = $(REGISTRY)/$(IMAGE):$(TAG)
DOCKER       = DOCKER_HOST=tcp://docker-socket-proxy:2375 DOCKER_TLS_VERIFY= docker
BUILDX       = $(DOCKER) buildx build \
                 --builder default \
                 --platform linux/amd64

BUILD_ARGS   = --build-arg BUILD_DATE="$(shell date -u +%Y-%m-%dT%H:%M:%SZ)"
ifdef GITHUB_TOKEN
BUILD_ARGS  += --build-arg GITHUB_TOKEN="$(GITHUB_TOKEN)"
endif

.PHONY: build push deploy run stop logs clean help

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

deploy:
	@echo "-> Deploiement des scripts custom-cont-init.d vers $(CONFIG_DIR)"
	mkdir -p $(CONFIG_DIR)/custom-cont-init.d
	cp -v ArcadeBox/custom-cont-init.d/*.sh $(CONFIG_DIR)/custom-cont-init.d/
	chmod +x $(CONFIG_DIR)/custom-cont-init.d/*.sh

run:
	$(DOCKER) compose --file ArcadeBox/docker-compose.yml up -d

stop:
	$(DOCKER) compose --file ArcadeBox/docker-compose.yml down

logs:
	$(DOCKER) compose --file ArcadeBox/docker-compose.yml logs -f

clean:
	$(DOCKER) compose --file ArcadeBox/docker-compose.yml down --rmi local --volumes

help:
	@echo "Targets:"
	@echo "  build    Build l'image localement (--load)"
	@echo "  push     Build + push vers $(REGISTRY)"
	@echo "  deploy   Copie custom-cont-init.d vers CONFIG_DIR"
	@echo "  run      docker compose up -d"
	@echo "  stop     docker compose down"
	@echo "  logs     Suivre les logs du conteneur"
	@echo "  clean    Arret + suppression image locale + volumes"
	@echo ""
	@echo "Variables (override avec make VAR=val):"
	@echo "  REGISTRY       $(REGISTRY)"
	@echo "  IMAGE          $(IMAGE)"
	@echo "  TAG            $(TAG)"
	@echo "  CONFIG_DIR     $(CONFIG_DIR)"
	@echo "  GITHUB_TOKEN   (non defini si vide)"
