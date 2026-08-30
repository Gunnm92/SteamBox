#!/bin/bash
# Résolution dynamique (30/08) — appelé par Sunshine comme prep-cmd "do" à la
# connexion d'un client Moonlight : ajuste la sortie du labwc HEADLESS
# (wayland-1, voir svc-labwc-headless) à la résolution/fréquence réellement
# demandée par CE client, via SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS que Sunshine
# positionne pour les prep-cmd. Sans ça, le headless reste bloqué sur son
# mode par défaut (1280x720, confirmé en direct) quel que soit le client —
# c'est ce qui donnait une image "bizarre" (upscale/mauvais ratio) côté
# Moonlight. Pattern repris de github.com/daaaaan/sunshine-headless-sway
# (swaymsg là-bas, wlr-randr ici pour labwc — même protocole standard
# wlr-output-management sous-jacent, wlr-randr fonctionne avec n'importe
# quel compositeur wlroots qui l'implémente, pas seulement Sway).
set -uo pipefail

WIDTH="${SUNSHINE_CLIENT_WIDTH:-1920}"
HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1080}"
FPS="${SUNSHINE_CLIENT_FPS:-60}"

export WAYLAND_DISPLAY=wayland-1
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

wlr-randr --output HEADLESS-1 --custom-mode "${WIDTH}x${HEIGHT}@${FPS}Hz" \
    >/tmp/set-resolution.log 2>&1
