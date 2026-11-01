# Profil unraid-gunnm — build/push depuis le conteneur de dev, dont le démon
# Docker est joint via docker-socket-proxy (pas de socket local).
REGISTRY ?= registry.elfenn.eu
# Push direct sur le registre en LAN (01/11) : registry.elfenn.eu résout vers
# l'IP publique du site, et le NAT loopback du RT-AC88U plafonnait l'envoi à
# ~1,7 Mo/s (mesuré : ~25 min pour les 4,4 Go de couches, plus que le build).
# Même registre (conteneur DockerRegistry3, port 5003), en HTTP : débit
# disque. Les déploiements tirent toujours registry.elfenn.eu/steambox.
PUSH_REGISTRY ?= 10.1.1.1:5003
PUSH_INSECURE ?= 1
DOCKER   ?= DOCKER_HOST=tcp://docker-socket-proxy:2375 DOCKER_TLS_VERIFY= docker
