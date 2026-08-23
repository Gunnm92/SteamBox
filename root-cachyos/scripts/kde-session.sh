#!/bin/bash
# Lance une vraie session Plasma (startplasma-wayland : kwin_wayland + Xwayland
# + plasmashell + démons de session) plutôt qu'un kwin_wayland nu — sans
# plasmashell, KWin compose un bureau vide (fond d'écran/panneau absents),
# donc un flux Sunshine techniquement valide mais visuellement noir.
#
# startplasma-wayland exige un bus D-Bus de session (dbus-run-session) et
# lance Steam via l'autostart XDG standard (~/.config/autostart), pas en
# argument de ligne de commande.

set -e

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY=wayland-0
export QT_QPA_PLATFORM=wayland
export SDL_VIDEODRIVER=wayland
export SDL_JOYSTICK_DISABLE_UDEV=1
# KWin bloque zkde_screencast_unstable_v1 (utilisé par Sunshine) derrière un
# système de permission pensé pour un utilisateur qui clique "autoriser" —
# inapplicable en headless.
export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1

# Désactive l'écran de démarrage (ksplashqml, app Qt Quick/OpenGL) — bloque
# indéfiniment sur ce rendu headless sans jamais planter proprement, ce qui
# gèle toute la suite du bootstrap Plasma (plasmashell, autostart, etc.).
mkdir -p "${HOME}/.config"
cat > "${HOME}/.config/ksplashrc" <<'EOF'
[KSplash]
Theme=None
Engine=none
EOF

mkdir -p "${HOME}/.config/autostart"
if [ ! -f "${HOME}/.config/autostart/steam.desktop" ]; then
    cat > "${HOME}/.config/autostart/steam.desktop" <<'EOF'
[Desktop Entry]
Name=Steam
Exec=steam -gamepadui -pipewire
Icon=steam
Terminal=false
Type=Application
Categories=Network;FileTransfer;Game;
X-GNOME-Autostart-enabled=true
EOF
fi

pipewire &
sleep 1
wireplumber &
pipewire-pulse &
sleep 1

# Bus D-Bus de session PERSISTANT (pas dbus-run-session, qui en crée un
# scopé à sa seule commande) — systemd --user et startplasma-wayland doivent
# partager le MÊME bus, pas deux bus séparés et incompatibles.
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS

# Plasma 6 lance plasmashell et d'autres composants de session comme unités
# systemd --user (changement d'architecture récent) — sans instance systemd
# utilisateur, plasma_session reste bloqué indéfiniment à essayer de la
# joindre, sans jamais planter ni logger d'erreur claire.
/usr/lib/systemd/systemd --user &
TIMEOUT=10
while ! systemctl --user is-system-running --quiet 2>/dev/null && [ "${TIMEOUT}" -gt 0 ]; do
    sleep 0.5
    TIMEOUT=$((TIMEOUT - 1))
done

startplasma-wayland &
PLASMA_PID=$!

TIMEOUT=30
while [ ! -S "${XDG_RUNTIME_DIR}/wayland-0" ] && [ "${TIMEOUT}" -gt 0 ]; do
    sleep 0.5
    TIMEOUT=$((TIMEOUT - 1))
done

if [ ! -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
    echo "[kde-session] ERREUR : pas de socket Wayland après démarrage de Plasma."
fi

wait "${PLASMA_PID}"
