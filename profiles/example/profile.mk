# Réglages de build/push du profil (inclus par le Makefile).
# Registre où publier l'image (make push). Vide = image locale seulement.
# REGISTRY ?= ghcr.io/<compte>
# Adresse pour ENVOYER l'image, si elle diffère (ex. même registre joint en
# direct sur le LAN, plus rapide que par son nom public) ; HTTP : PUSH_INSECURE=1.
# PUSH_REGISTRY ?= 192.168.1.10:5000
# PUSH_INSECURE ?= 1
# Commande docker (ex. démon distant) :
# DOCKER ?= DOCKER_HOST=tcp://mon-hote:2375 docker
# Locales compilées dans l'image, en plus d'en_US :
# BUILD_ARGS += --build-arg EXTRA_LOCALES="fr_FR de_DE"
