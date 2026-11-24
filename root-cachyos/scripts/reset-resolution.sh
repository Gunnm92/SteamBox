#!/bin/bash
# Contrepartie "undo" de set-resolution.sh — revient à une résolution par
# défaut raisonnable à la déconnexion du client Moonlight, plutôt que de
# laisser la sortie bloquée sur la résolution du dernier client connecté.
set -uo pipefail

# Même choix de mode que set-resolution.sh (dongle HDMI en DRM, KWin), avec
# 1920x1080@60 comme résolution du « client ».
SUNSHINE_CLIENT_WIDTH=1920 SUNSHINE_CLIENT_HEIGHT=1080 SUNSHINE_CLIENT_FPS=60 \
    exec /usr/local/bin/scripts/set-resolution.sh
