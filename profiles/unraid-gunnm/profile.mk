# Profil unraid-gunnm — build/push depuis le conteneur de dev, dont le démon
# Docker est joint via docker-socket-proxy (pas de socket local).
REGISTRY ?= registry.elfenn.eu
DOCKER   ?= DOCKER_HOST=tcp://docker-socket-proxy:2375 DOCKER_TLS_VERIFY= docker
