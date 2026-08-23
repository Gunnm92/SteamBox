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
# X11 n'a pas de notion native de mise à l'échelle par sortie, contrairement
# à Wayland — sans ça, les apps Xwayland (Steam, Pegasus forcé en xcb faute
# de plugin Wayland dans son build...) restent minuscules ou juste
# upscalées en flou par Hyprland (xwayland:force_zero_scaling ci-dessous
# évite justement ce flou, mais seulement combiné à ces variables : testé
# en direct, Pegasus rendait net et à la bonne taille avec les deux).
# Doit rester aligné sur le "scale" de la ligne monitor= ci-dessous — au 4K
# c'était 2, en 1440p (densité de pixels plus faible) c'est 1 : sinon les
# apps Xwayland sortent 2x plus grandes que le reste du bureau natif.
export GDK_SCALE=1
export QT_SCALE_FACTOR=1

mkdir -p "${HOME}/.config/hypr" "${HOME}/.config/waybar"

cat > "${HOME}/.config/hypr/hyprpaper.conf" <<'EOF'
wallpaper {
    monitor = HDMI-A-1
    path = /usr/share/backgrounds/arcadebox.png
    fit_mode = cover
}
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
@import url("file:///usr/share/catppuccin/mocha.css");

* {
    font-family: "sans-serif";
    font-size: 14px;
    min-height: 0;
}
window#waybar {
    background: alpha(@base, 0.85);
    color: @text;
    border-bottom: 2px solid alpha(@mauve, 0.4);
}
#workspaces {
    margin: 4px 6px;
}
#workspaces button {
    padding: 2px 12px;
    margin: 2px;
    color: @text;
    border-radius: 10px;
    background: transparent;
}
#workspaces button.active {
    background: @mauve;
    color: @base;
}
#workspaces button:hover {
    background: alpha(@mauve, 0.3);
}
#clock {
    font-weight: 600;
    color: @pink;
    padding: 0 14px;
}
#pulseaudio, #network {
    padding: 0 12px;
    color: @green;
}
EOF

mkdir -p "${HOME}/.config/nwg-dock-hyprland"
cat > "${HOME}/.config/nwg-dock-hyprland/style.css" <<'EOF'
@import url("file:///usr/share/catppuccin/mocha.css");

window {
    background: alpha(@base, 0.85);
    border: 2px solid alpha(@mauve, 0.4);
    border-radius: 18px;
}
button {
    border-radius: 12px;
    padding: 4px;
}
button:hover {
    background: alpha(@mauve, 0.25);
}
EOF

cat > "${HOME}/.config/hypr/hyprland.conf" <<'EOF'
# 2560x1440@120 plutôt que le 4K natif de l'écran : la 3090 de l'utilisateur
# ne tient pas le 4K confortablement en jeu, 1440p est son plafond réaliste.
# scale=1 (et non plus 2 comme au 4K) : à cette densité de pixels, l'UI du
# bureau est déjà lisible nativement — confirmé en direct via capture grim,
# waybar/nwg-drawer nets et à la bonne taille sans mise à l'échelle.
monitor=,2560x1440@120,auto,1

# Pas d'auto-lancement de Steam ici — lancé à la demande via l'app
# "Steam Big Picture" de Sunshine/Moonlight (apps.json).
exec-once = hyprpaper
exec-once = waybar
exec-once = mako
# -l top (au lieu du défaut "overlay") : Hyprland masque la couche "top"
# quand une fenêtre passe en plein écran (Steam Big Picture) — "overlay"
# reste affichée par-dessus, quel que soit le premier plan. Pas de -d
# (auto-hide) : en VNC/Moonlight, viser précisément le pixel du bord bas
# pour le faire réapparaître est peu pratique — le dock reste visible en
# permanence hors plein écran, masqué seulement pendant Big Picture.
exec-once = nwg-dock-hyprland -p bottom -a center -i 96 -l top

input {
    kb_layout = fr
}

general {
    gaps_in = 6
    gaps_out = 12
    border_size = 2
    col.active_border = rgba(cba6f7ff) rgba(f5c2e7ff) 45deg
    col.inactive_border = rgba(45475aaa)
}

decoration {
    rounding = 12
    shadow {
        enabled = true
        range = 20
        render_power = 3
        color = rgba(00000066)
    }
    blur {
        enabled = true
        size = 6
        passes = 3
        new_optimizations = true
        ignore_opacity = true
    }
}

animations {
    enabled = true
    bezier = smoothOut, 0.36, 0, 0.66, -0.56
    bezier = smoothIn, 0.25, 1, 0.5, 1
    animation = windows, 1, 4, smoothIn
    animation = windowsOut, 1, 4, smoothOut
    animation = fade, 1, 4, smoothIn
    animation = workspaces, 1, 4, smoothIn
}

misc {
    disable_splash_rendering = true
    disable_hyprland_logo = true
    background_color = 0x161028
}

# Aucune barre/lanceur par défaut — sans ce bind, rien n'est joignable au
# clavier sur un bureau vide (Steam n'est plus lancé automatiquement).
bind = SUPER, Return, exec, foot

# Sans ça, Hyprland upscale le buffer Xwayland pour matcher l'échelle du
# moniteur — flou, contrairement au rendu natif net obtenu en combinant ce
# réglage avec GDK_SCALE/QT_SCALE_FACTOR (ci-dessus, avant le lancement de
# Hyprland) qui font rendre les apps X11 nativement à la bonne taille.
xwayland {
    force_zero_scaling = true
}
EOF

pipewire &
sleep 1
wireplumber &
pipewire-pulse &
sleep 1

dbus-run-session -- start-hyprland &
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
