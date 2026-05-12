#!/bin/bash
# Lance Steam en Gaming Mode SteamOS (gamescope + gamepadui)
# Tue Steam s'il tourne déjà, puis démarre le Gaming Mode.
# À la sortie du Gaming Mode, relance Steam en mode silencieux.

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/config/.XDG}"
if [ -S "${XDG_RUNTIME_DIR}/wayland-1" ]; then
    export WAYLAND_DISPLAY=wayland-1
elif [ -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
    export WAYLAND_DISPLAY=wayland-0
fi

# Arrêter Steam proprement
if pgrep -x "steam" > /dev/null 2>&1 || pgrep -f "steam.sh" > /dev/null 2>&1; then
    steam -shutdown 2>/dev/null || true
    sleep 3
    pkill -f "steam" 2>/dev/null || true
    sleep 1
fi

# Lancer le Gaming Mode
gamescope --steam -e \
    -W "${GAMESCOPE_WIDTH:-1920}" \
    -H "${GAMESCOPE_HEIGHT:-1080}" \
    -r "${GAMESCOPE_RATE:-60}" \
    --force-grab-cursor \
    -- steam -gamepadui -steamos3 -steamdeck -pipewire

# Retour au bureau : relancer Steam silencieux
/usr/games/steam -silent -pipewire &
