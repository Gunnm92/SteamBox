# Réglages de build/push du profil (inclus par le Makefile).
# Registre où publier l'image (make push). Vide = image locale seulement.
# REGISTRY ?= ghcr.io/<compte>
# Commande docker (ex. démon distant) :
# DOCKER ?= DOCKER_HOST=tcp://mon-hote:2375 docker
# Locales compilées dans l'image, en plus d'en_US :
# BUILD_ARGS += --build-arg EXTRA_LOCALES="fr_FR de_DE"
