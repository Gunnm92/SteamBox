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
# PUSH_REGISTRY (01/11) : adresse par laquelle make push ENVOIE l'image, si
# elle diffère de REGISTRY (celle que tirent les déploiements) — typiquement
# le même registre joint en direct sur le LAN plutôt que par son nom public.
# PUSH_INSECURE=1 : ce registre parle HTTP (registry.insecure de BuildKit).
PUSH_REGISTRY ?= $(REGISTRY)
PUSH_INSECURE ?=
PUSH_IMAGE   = $(PUSH_REGISTRY)/$(IMAGE):$(TAG)
comma        := ,
DOCKER       ?= docker
COMPOSE      = STEAMBOX_IMAGE=$(FULL_IMAGE) $(DOCKER) compose \
                 --file docker-compose.yml \
                 --file profiles/$(PROFILE)/compose.override.yml
# --pull (15/11) : base cachyos-v3:latest revérifiée à chaque build (sinon
# le démon réutilise la copie locale, aussi vieille soit-elle).
BUILDX       = $(DOCKER) buildx build \
                 --builder default --pull \
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

# Composants précompilés (15/11) — evdev-bridge, Sunshine DualSense USB,
# Batocera ES, xfce-panel-launcher, freeimage : construits par
# Dockerfile.prebuilt (make prebuilt, à la demande), publiés en release
# GitHub de PREBUILT_REPO (make prebuilt-publish), téléchargés par make
# build/push au lieu d'être recompilés. PREBUILT_TAG vide = dernière release ;
# make push PREBUILT_TAG=prebuilt-AAAAMMJJ-HHMM pour revenir en arrière.
# make prebuilt-check dit s'il faut relancer make prebuilt (nouvelle version
# amont, ou evdev-bridge/ modifié).
PREBUILT_REPO ?= Gunnm92/SteamBox
PREBUILT_TAG  ?=
BUILD_ARGS   += --build-arg PREBUILT_REPO=$(PREBUILT_REPO)
# Sunshine vient de la release de Gunnm92/sunshine-ds (vide = dernière).
SUNSHINE_DS_TAG ?=
ifneq ($(SUNSHINE_DS_TAG),)
BUILD_ARGS   += --build-arg SUNSHINE_DS_TAG=$(SUNSHINE_DS_TAG)
endif
ifneq ($(PREBUILT_TAG),)
BUILD_ARGS   += --build-arg PREBUILT_TAG=$(PREBUILT_TAG)
endif
# Surcharges du build précompilé : ES_REF (branche/tag d'ES),
# XFCE_LAUNCHER_REF (commit du lanceur, vide = main). Sunshine : voir
# SUNSHINE_DS_TAG (release de Gunnm92/sunshine-ds).
PREBUILT_ARGS = --build-arg BUILD_DATE="$(shell date -u +%Y-%m-%dT%H:%M:%SZ)" \
                --build-arg EVDEV_REF=$(shell git log -1 --format=%h -- evdev-bridge) \
                $(if $(ES_REF),--build-arg ES_REF=$(ES_REF)) \
                $(if $(XFCE_LAUNCHER_REF),--build-arg XFCE_LAUNCHER_REF=$(XFCE_LAUNCHER_REF))

.PHONY: build push run stop logs clean lint help prebuilt prebuilt-publish prebuilt-check

# Fichiers shell du dépôt : scripts de session/init, outils de build, et
# les "run" s6 (shebang with-contenv, non reconnu par shellcheck d'où -s bash).
SHELL_FILES  = root-cachyos/scripts root-cachyos/build root-cachyos/usr/local/bin \
               root-cachyos/etc/s6-overlay/s6-rc.d prebuilt/check.sh

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
		--output type=image,name=$(PUSH_IMAGE),push=true$(if $(PUSH_INSECURE),$(comma)registry.insecure=true) \
		.

# Export local (type=local) : BuildKit renvoie les fichiers au client, ça
# marche aussi avec un démon distant (docker-socket-proxy), sans registre.
# Dossier vidé avant : l'export n'efface pas les fichiers d'un ancien build.
prebuilt:
	rm -rf prebuilt/out
	$(BUILDX) $(PREBUILT_ARGS) \
		--file Dockerfile.prebuilt \
		--output type=local,dest=prebuilt/out \
		.
	@cat prebuilt/out/versions.txt

prebuilt-publish:
	@test -f prebuilt/out/versions.txt || { echo "prebuilt/out/ vide : lancer make prebuilt d'abord"; exit 1; }
	tag=prebuilt-$$(date -u +%Y%m%d-%H%M) && \
	gh release create "$$tag" --repo $(PREBUILT_REPO) --latest \
		--title "Composants précompilés $$tag" --notes-file prebuilt/out/versions.txt \
		prebuilt/out/*.tar.zst prebuilt/out/*.version prebuilt/out/versions.txt && \
	echo "Publié : $$tag (pris par le prochain make push)"

prebuilt-check:
	@prebuilt/check.sh $(PREBUILT_REPO)

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
	$(DOCKER) run --rm -i hadolint/hadolint hadolint --no-color --failure-threshold warning \
		--ignore DL3059 --ignore DL4006 --ignore DL3003 --ignore DL3010 --ignore DL3013 \
		- < Dockerfile.prebuilt

help:
	@echo "Targets:"
	@echo "  lint     shellcheck + hadolint (via Docker)"
	@echo "  build    Build l'image localement (--load)"
	@echo "  push     Build + push vers $(PUSH_REGISTRY)$(if $(filter-out $(REGISTRY),$(PUSH_REGISTRY)), (tiree ensuite via $(REGISTRY)))"
	@echo "  prebuilt          Compile les composants precompiles (Dockerfile.prebuilt) dans prebuilt/out/"
	@echo "  prebuilt-publish  Publie prebuilt/out/ en release GitHub de $(PREBUILT_REPO) (gh)"
	@echo "  prebuilt-check    Compare la derniere release a l'amont (faut-il relancer make prebuilt ?)"
	@echo "  run      docker compose up -d"
	@echo "  stop     docker compose down"
	@echo "  logs     Suivre les logs du conteneur"
	@echo "  clean    Arret + suppression image locale + volumes"
	@echo ""
	@echo "Variables (override avec make VAR=val):"
	@echo "  PROFILE        $(PROFILE)  (profiles/$(PROFILE)/)"
	@echo "  REGISTRY       $(REGISTRY)"
	@echo "  PUSH_REGISTRY  $(PUSH_REGISTRY)$(if $(PUSH_INSECURE),  (HTTP))"
	@echo "  IMAGE          $(IMAGE)"
	@echo "  TAG            $(TAG)"
	@echo "  GITHUB_TOKEN   (non defini si vide)"
	@echo "  PREBUILT_REPO  $(PREBUILT_REPO)  (releases des composants precompiles)"
	@echo "  PREBUILT_TAG   $(if $(PREBUILT_TAG),$(PREBUILT_TAG),(derniere release))"
	@echo "  ES_REF / XFCE_LAUNCHER_REF  surcharges de make prebuilt ; SUNSHINE_DS_TAG : release sunshine-ds"
