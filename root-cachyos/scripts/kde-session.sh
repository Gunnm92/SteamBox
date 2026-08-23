#!/bin/bash
# Lance KWin (backend DRM, sortie virtuelle car pas de moniteur physique) avec
# Xwayland, PipeWire, puis Steam en plein écran — Steam est passé en argument
# à kwin_wayland lui-même (pas lancé en process séparé) pour que KWin attende
# que Xwayland soit prêt et lui fournisse un DISPLAY correct automatiquement.

set -e

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY=wayland-0
export QT_QPA_PLATFORM=wayland
export SDL_VIDEODRIVER=wayland
export SDL_JOYSTICK_DISABLE_UDEV=1
# KWin bloque le protocole zkde_screencast_unstable_v1 derrière un système de
# permission par app (pensé pour un utilisateur qui clique "autoriser") —
# inapplicable en headless sans utilisateur pour répondre. Sunshine a un
# fichier de permission système (dev.lizardbyte.app.Sunshine.kwin.desktop)
# mais ça ne suffit pas seul ; ce flag désactive complètement le contrôle.
export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1

pipewire &
sleep 1
wireplumber &
pipewire-pulse &
sleep 1

kwin_wayland --drm --xwayland --no-lockscreen --no-global-shortcuts \
  -- bash -c 'exec steam -gamepadui -pipewire' &
KWIN_PID=$!

TIMEOUT=20
while [ ! -S "${XDG_RUNTIME_DIR}/wayland-0" ] && [ "${TIMEOUT}" -gt 0 ]; do
    sleep 0.5
    TIMEOUT=$((TIMEOUT - 1))
done

if [ ! -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
    echo "[kde-session] ERREUR : KWin n'a pas créé de socket Wayland."
fi

wait "${KWIN_PID}"
