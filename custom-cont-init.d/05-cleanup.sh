#!/bin/bash
# ArcadeBox — Nettoyage au démarrage
# /dev/shm et /tmp persistent lors d'un docker restart (pas de rm+run)
# → supprimer audio.lock pour que svc-selkies recrée les sinks PulseAudio
# → supprimer les locks X11 périmés pour que labwc obtienne toujours :0
#   (sans ça, labwc prend :1/:2/... et DISPLAY=:0 configuré par startwm_wayland.sh
#    pointe vers un Xwayland mort → connexion refusée pour toutes les apps X11)

rm -f /dev/shm/audio.lock
echo "[cleanup] audio.lock supprimé"

rm -f /tmp/.X*-lock
rm -f /tmp/.X11-unix/X*
echo "[cleanup] locks X11 périmés supprimés"

# Injecter WAYLAND_DISPLAY + XDG_RUNTIME_DIR dans l'env s6
# wayland-0 = socket labwc (affiché par selkies-desktop)
# wayland-1 = socket Selkies (créé avant svc-de, labwc s'y connecte en tant que client)
# Sans XDG_RUNTIME_DIR=/config/.XDG, les apps ne trouvent pas /config/.XDG/wayland-0
# même si WAYLAND_DISPLAY=wayland-0 est correct.
mkdir -p /run/s6/container_environment
printf 'wayland-0' > /run/s6/container_environment/WAYLAND_DISPLAY
printf '/config/.XDG' > /run/s6/container_environment/XDG_RUNTIME_DIR
echo "[cleanup] WAYLAND_DISPLAY=wayland-0 + XDG_RUNTIME_DIR=/config/.XDG injectés dans l'env s6"
