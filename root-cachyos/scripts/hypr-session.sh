#!/bin/bash
# Lance Hyprland comme compositeur racine (backend DRM auto-détecté, pas de
# WAYLAND_DISPLAY/DISPLAY parent — même position que KWin --drm dans la
# tentative KDE précédente, qui capturait correctement en DMA-BUF via
# Sunshine). Contrairement à KWin, Hyprland est wlroots : pas de dépendance
# systemd --user, pas de chaîne kcminit/ksplash/kded à contourner, et
# zwlr_virtual_pointer_manager_v1/zwp_virtual_keyboard_manager_v1 sont
# implémentés nativement (wayvnc a l'input, pas seulement la capture vidéo).

set -e

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY=wayland-0
export QT_QPA_PLATFORM=wayland
export SDL_VIDEODRIVER=wayland
export SDL_JOYSTICK_DISABLE_UDEV=1
# Hyprland tente un sd_notify au démarrage par défaut ; sans systemd
# (PID 1 = bash ici) c'est un no-op silencieux, mais on le désactive
# explicitement pour ne pas dépendre de ce comportement.
export HYPRLAND_NO_SD_NOTIFY=1

mkdir -p "${HOME}/.config/hypr" "${HOME}/.config/waybar"

cat > "${HOME}/.config/hypr/hyprpaper.conf" <<'EOF'
preload = /usr/share/backgrounds/arcadebox.png
wallpaper = ,/usr/share/backgrounds/arcadebox.png
EOF

cat > "${HOME}/.config/waybar/config.jsonc" <<'EOF'
{
    "layer": "top",
    "position": "top",
    "height": 32,
    "spacing": 6,
    "modules-left": ["hyprland/workspaces"],
    "modules-center": ["clock"],
    "modules-right": ["pulseaudio", "network"],
    "clock": { "format": "{:%H:%M — %A %d %B}" },
    "network": {
        "format-ethernet": "{ipaddr}",
        "format-disconnected": "hors ligne"
    },
    "pulseaudio": { "format": "{volume}% {icon}", "format-icons": ["","",""] }
}
EOF

cat > "${HOME}/.config/waybar/style.css" <<'EOF'
* { font-family: sans-serif; font-size: 13px; }
window#waybar {
    background: rgba(20, 20, 30, 0.75);
    color: #f0f0f0;
}
#workspaces button { padding: 0 8px; color: #f0f0f0; }
#workspaces button.active { background: rgba(255,255,255,0.15); border-radius: 6px; }
#clock, #pulseaudio, #network { padding: 0 10px; }
EOF

cat > "${HOME}/.config/hypr/hyprland.conf" <<'EOF'
monitor=,preferred,auto,1

# Pas d'auto-lancement de Steam ici — lancé à la demande via l'app
# "Steam Big Picture" de Sunshine/Moonlight (apps.json).
exec-once = hyprpaper
exec-once = waybar
exec-once = nwg-dock-hyprland -p bottom -a center

input {
    kb_layout = fr
}

general {
    gaps_in = 0
    gaps_out = 0
    border_size = 0
}

decoration {
    rounding = 0
    shadow {
        enabled = false
    }
}

animations {
    enabled = false
}

misc {
    disable_splash_rendering = true
    disable_hyprland_logo = true
}

# Aucune barre/lanceur par défaut — sans ce bind, rien n'est joignable au
# clavier sur un bureau vide (Steam n'est plus lancé automatiquement).
bind = SUPER, Return, exec, foot
EOF

pipewire &
sleep 1
wireplumber &
pipewire-pulse &
sleep 1

dbus-run-session -- Hyprland &
HYPR_PID=$!

# Hyprland ne respecte pas forcément WAYLAND_DISPLAY=wayland-0 pour le nom du
# socket qu'il crée (observé : wayland-1 alors que wayland-0 était libre) —
# on détecte le socket réellement créé plutôt que de supposer son nom.
SOCK=""
TIMEOUT=30
while [ -z "${SOCK}" ] && [ "${TIMEOUT}" -gt 0 ]; do
    SOCK=$(find "${XDG_RUNTIME_DIR}" -maxdepth 1 -name 'wayland-[0-9]*' ! -name '*.lock' 2>/dev/null | head -n1)
    [ -z "${SOCK}" ] && sleep 0.5
    TIMEOUT=$((TIMEOUT - 1))
done

if [ -z "${SOCK}" ]; then
    echo "[hypr-session] ERREUR : pas de socket Wayland après démarrage de Hyprland."
else
    basename "${SOCK}" > "${XDG_RUNTIME_DIR}/.wayland-socket-name"
fi

wait "${HYPR_PID}"
