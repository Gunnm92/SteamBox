#!/bin/bash
# Lance KWin (backend DRM, sortie virtuelle car pas de moniteur physique) puis
# Steam en plein écran dedans.
#
# INCERTITUDE CONNUE : contrairement à wlroots (backend headless natif bien
# supporté), le support de KWin pour un rendu GPU accéléré sans connecteur
# DRM réel est moins mature — c'est le point le plus à risque de cette
# architecture, à valider empiriquement. Si "--drm" ne produit pas de sortie
# virtuelle exploitable, il faudra soit un dummy plug HDMI physique sur le
# GPU (contournement classique), soit reconsidérer KWin pour ce rôle.

set -e

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY=wayland-0
export QT_QPA_PLATFORM=wayland
export SDL_VIDEODRIVER=wayland
export SDL_JOYSTICK_DISABLE_UDEV=1

kwin_wayland --drm --no-lockscreen --no-global-shortcuts &
KWIN_PID=$!

TIMEOUT=20
while [ ! -S "${XDG_RUNTIME_DIR}/wayland-0" ] && [ "${TIMEOUT}" -gt 0 ]; do
    sleep 0.5
    TIMEOUT=$((TIMEOUT - 1))
done

if [ ! -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
    echo "[kde-session] ERREUR : KWin n'a pas créé de socket Wayland."
    wait "${KWIN_PID}"
    exit 1
fi

# PipeWire côté session utilisateur (capture audio Sunshine + portails KDE)
pipewire &
sleep 1
wireplumber &
pipewire-pulse &

sleep 2
steam -gamepadui -pipewire &
STEAM_PID=$!

wait "${KWIN_PID}"
kill "${STEAM_PID}" 2>/dev/null || true
