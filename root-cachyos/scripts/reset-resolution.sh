#!/bin/bash
# Contrepartie "undo" de set-resolution.sh — revient à une résolution par
# défaut raisonnable à la déconnexion du client Moonlight, plutôt que de
# laisser le headless bloqué sur la résolution du dernier client connecté.
set -uo pipefail

export WAYLAND_DISPLAY=wayland-1
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

wlr-randr --output HEADLESS-1 --custom-mode "1920x1080@60Hz" \
    >/tmp/reset-resolution.log 2>&1
