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

# Thème sombre système — sans ça, seuls waybar/le dock (leur propre CSS
# Catppuccin) sont stylés : toute VRAIE application (Dolphin, PCSX2, Steam,
# nwg-drawer...) reste en thème clair par défaut (GTK Adwaita / Qt Fusion),
# ce qui donne l'impression qu'aucun thème n'est appliqué puisque c'est là
# que se passe l'essentiel du temps à l'écran. adwaita-qt6 fournit un style
# Qt "adwaita-dark" tout fait (pas besoin de palette qt6ct écrite à la main) ;
# GTK a un mode sombre intégré (gtk-application-prefer-dark-theme), testé en
# direct sur Dolphin et nwg-drawer, tous les deux rendus sombres correctement.
export QT_STYLE_OVERRIDE=adwaita-dark
mkdir -p "${HOME}/.config/gtk-3.0" "${HOME}/.config/gtk-4.0"
cat > "${HOME}/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
EOF
cp "${HOME}/.config/gtk-3.0/settings.ini" "${HOME}/.config/gtk-4.0/settings.ini"

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
    "height": 38,
    "spacing": 4,
    "margin-top": 6,
    "margin-left": 10,
    "margin-right": 10,
    "modules-left": ["hyprland/workspaces", "hyprland/window"],
    "modules-center": ["clock"],
    "modules-right": ["cpu", "memory", "pulseaudio", "network"],
    "hyprland/window": {
        "format": "{title}",
        "max-length": 40,
        "separate-outputs": true
    },
    "clock": { "format": "{:%H:%M   %d/%m/%Y}" },
    "cpu": { "format": "CPU {usage}%", "interval": 3 },
    "memory": { "format": "RAM {percentage}%", "interval": 3 },
    "network": {
        "format-ethernet": "{ipaddr}",
        "format-wifi": "{essid} ({signalStrength}%)",
        "format-disconnected": "hors ligne"
    },
    "pulseaudio": { "format": "VOL {volume}%", "format-muted": "muet" }
}
EOF

cat > "${HOME}/.config/waybar/style.css" <<'EOF'
@import url("file:///usr/share/catppuccin/mocha.css");

* {
    font-family: "JetBrainsMono Nerd Font", "sans-serif";
    font-size: 14px;
    min-height: 0;
}
window#waybar {
    background: transparent;
    color: @text;
}
#workspaces, #window, #clock, #cpu, #memory, #pulseaudio, #network {
    background: alpha(@base, 0.75);
    border: 1px solid alpha(@mauve, 0.35);
    border-radius: 14px;
    margin: 0 3px;
    padding: 0 12px;
}
#workspaces {
    padding: 0 6px;
}
#workspaces button {
    padding: 2px 10px;
    margin: 4px 2px;
    color: @subtext0;
    border-radius: 10px;
    background: transparent;
    transition: background 0.15s ease-in-out;
}
#workspaces button.active {
    background: @mauve;
    color: @base;
}
#workspaces button:hover {
    background: alpha(@mauve, 0.35);
    color: @text;
}
#window {
    color: @subtext1;
    font-style: italic;
}
#clock {
    font-weight: 600;
    color: @pink;
}
#cpu, #memory {
    color: @sky;
}
#pulseaudio {
    color: @green;
}
#pulseaudio.muted {
    color: @overlay1;
}
#network {
    color: @yellow;
}
#network.disconnected {
    color: @red;
}
EOF

mkdir -p "${HOME}/.config/nwg-dock-hyprland"
cat > "${HOME}/.config/nwg-dock-hyprland/style.css" <<'EOF'
@import url("file:///usr/share/catppuccin/mocha.css");

window {
    background: alpha(@base, 0.8);
    border: 1px solid alpha(@mauve, 0.35);
    border-radius: 20px;
}
button {
    border-radius: 14px;
    padding: 6px;
    transition: background 0.15s ease-in-out;
}
button:hover {
    background: alpha(@mauve, 0.3);
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

# exec (pas de &+wait) : ce script EST le run d'un service longrun s6
# (svc-hyprland) — s6 supervise directement le process remplacé ici, plutôt
# que ce script lui-même. svc-sunshine/svc-wayvnc détectent eux-mêmes le
# socket Wayland réel une fois up (son nom n'est pas garanti "wayland-0",
# observé : parfois wayland-1 alors que wayland-0 était libre).
exec dbus-run-session -- start-hyprland
