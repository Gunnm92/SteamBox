# Profil d'installation (25/09) : profiles/<PROFILE>/ porte tout ce qui est
# propre à un déploiement — registre et commande docker (profile.mk),
# override compose (GPU, volumes) et variables du conteneur (env). Choix du
# profil : make <cible> PROFILE=<nom>, ou une fois pour toutes dans local.mk
# (non versionné) : PROFILE = <nom>.
-include local.mk
PROFILE      ?= example
-include profiles/$(PROFILE)/profile.mk

REGISTRY     ?=
IMAGE        ?= steambox
TAG          ?= latest
GITHUB_TOKEN ?=
FULL_IMAGE   = $(if $(REGISTRY),$(REGISTRY)/)$(IMAGE):$(TAG)
DOCKER       ?= docker
COMPOSE      = STEAMBOX_IMAGE=$(FULL_IMAGE) $(DOCKER) compose \
                 --file docker-compose.yml \
                 --file profiles/$(PROFILE)/compose.override.yml
BUILDX       = $(DOCKER) buildx build \
                 --builder default \
                 --platform linux/amd64 \
                 --provenance=false --sbom=false

BUILD_ARGS   += --build-arg BUILD_DATE="$(shell date -u +%Y-%m-%dT%H:%M:%SZ)"
# GITHUB_TOKEN passé en secret BuildKit (audit C1, 05/09), plus en
# --build-arg : un build-arg consommé par un RUN reste lisible en clair
# dans l'historique de l'image pour toujours (confirmé en direct, token
# révoqué suite à cet incident) — un secret n'est monté que le temps du
# RUN qui le demande explicitement (--mount=type=secret,id=github_token
# côté Dockerfile) et n'apparaît jamais dans aucune couche. env=GITHUB_TOKEN
# lit la valeur depuis la variable d'environnement du process make, jamais
# depuis un fichier sur disque.
ifdef GITHUB_TOKEN
BUILD_ARGS  += --secret id=github_token,env=GITHUB_TOKEN
endif

.PHONY: build push run stop logs clean lint help

# Fichiers shell du dépôt : scripts de session/init, outils de build, et
# les "run" s6 (shebang with-contenv, non reconnu par shellcheck d'où -s bash).
SHELL_FILES  = root-cachyos/scripts root-cachyos/build root-cachyos/usr/local/bin \
               root-cachyos/etc/s6-overlay/s6-rc.d

# Seul Dockerfile restant depuis le pivot Waybox -> SteamBox (Dockerfile et
# Dockerfile.ubuntu supprimés — plus de variante webstation/Debian ni
# Ubuntu, uniquement CachyOS/Arch + labwc/XFCE Wayland).
# Contexte "." : les COPY du Dockerfile sont relatifs à la racine de ce
# dépôt. Le contexte est filtré par Dockerfile.cachyos.dockerignore
# (nommage par-Dockerfile requis par BuildKit — audit 31/08).
build:
	$(BUILDX) $(BUILD_ARGS) \
		--file Dockerfile.cachyos \
		--tag $(FULL_IMAGE) \
		--load \
		.

push:
	@test -n "$(REGISTRY)" || { echo "REGISTRY vide : à définir dans profiles/$(PROFILE)/profile.mk ou make push REGISTRY=..."; exit 1; }
	$(BUILDX) $(BUILD_ARGS) \
		--file Dockerfile.cachyos \
		--tag $(FULL_IMAGE) \
		--push \
		.

run:
	$(COMPOSE) up -d

stop:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

clean:
	$(COMPOSE) down --rmi local --volumes

# Lint (audit 22/09) — shellcheck + hadolint via leurs images officielles,
# rien à installer localement. Les fichiers passent par stdin (tar), pas par
# un bind mount : le démon Docker est joint via docker-socket-proxy, un
# chemin local n'existerait pas de son côté. Sévérité "warning" pour
# shellcheck (bugs probables, pas le style). Règles hadolint écartées, en
# connaissance de cause :
#   DL3059  RUN consécutifs — un RUN par composant est voulu (cache, lisibilité)
#   DL4006  pipefail — chaque "curl | grep" vérifie explicitement un résultat
#           vide ; un pipefail global ferait échouer au hasard les
#           "grep | head -1" (SIGPIPE sur grep)
#   DL3003  cd dans un RUN — uniquement dans des dossiers /tmp jetables
#   DL3010  ADD pour les archives — le thème est patché juste après extraction
#   DL3013  versions pip épinglées — contraire à la politique "tout à jour à
#           chaque rebuild" du projet
lint:
	tar -c $(SHELL_FILES) | $(DOCKER) run --rm -i --entrypoint sh koalaman/shellcheck-alpine:stable -c \
		'mkdir /w && cd /w && tar -x && find . -type f \( -name "*.sh" -o -name run -o -path "*/build/*" -o -path "*/usr/local/bin/*" \) \
		| sort | xargs shellcheck -s bash -S warning'
	$(DOCKER) run --rm -i hadolint/hadolint hadolint --no-color --failure-threshold warning \
		--ignore DL3059 --ignore DL4006 --ignore DL3003 --ignore DL3010 --ignore DL3013 \
		- < Dockerfile.cachyos

help:
	@echo "Targets:"
	@echo "  lint     shellcheck + hadolint (via Docker)"
	@echo "  build    Build l'image localement (--load)"
	@echo "  push     Build + push vers $(REGISTRY)"
	@echo "  run      docker compose up -d"
	@echo "  stop     docker compose down"
	@echo "  logs     Suivre les logs du conteneur"
	@echo "  clean    Arret + suppression image locale + volumes"
	@echo ""
	@echo "Variables (override avec make VAR=val):"
	@echo "  PROFILE        $(PROFILE)  (profiles/$(PROFILE)/)"
	@echo "  REGISTRY       $(REGISTRY)"
	@echo "  IMAGE          $(IMAGE)"
	@echo "  TAG            $(TAG)"
	@echo "  GITHUB_TOKEN   (non defini si vide)"
