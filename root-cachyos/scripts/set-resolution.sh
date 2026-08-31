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

# Trace des valeurs recues (audit B6, 31/08) : le repli silencieux sur
# 1920x1080 quand Sunshine ne fournit pas SUNSHINE_CLIENT_* a deja coute
# une session de debug ("fige sur 1920" alors que le prep-cmd ne tournait
# simplement pas) — une ligne de log leve l'ambiguite immediatement.
{
    echo "[$(date '+%F %T')] client=${SUNSHINE_CLIENT_WIDTH:-ABSENT}x${SUNSHINE_CLIENT_HEIGHT:-ABSENT}@${SUNSHINE_CLIENT_FPS:-ABSENT} -> applique ${WIDTH}x${HEIGHT}@${FPS}Hz"
    wlr-randr --output HEADLESS-1 --custom-mode "${WIDTH}x${HEIGHT}@${FPS}Hz" 2>&1
} >>/tmp/set-resolution.log
