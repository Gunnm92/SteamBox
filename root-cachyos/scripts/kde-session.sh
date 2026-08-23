#!/bin/bash
# Lance une vraie session Plasma (startplasma-wayland : kwin_wayland + Xwayland
# + plasmashell + démons de session) plutôt qu'un kwin_wayland nu — sans
# plasmashell, KWin compose un bureau vide (fond d'écran/panneau absents),
# donc un flux Sunshine techniquement valide mais visuellement noir.
#
# systemdBoot=false (startkderc) : Plasma 6 lance ses composants comme
# unités systemd --user par défaut, dépendance absente d'un conteneur sans
# systemd (PID 1 = bash ici). Ce réglage repasse sur l'ancien modèle —
# composants enfants directs de plasma_session — sans rien demander de plus.
# Trouvé via github.com/ianepreston/nixos/issues/456 (même problème,
# documenté en détail), après avoir tenté sans succès de faire tourner un
# vrai systemd --user (ksplash/kcminit/kded6 se bloquaient en cascade).

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

mkdir -p "${HOME}/.config"
cat > "${HOME}/.config/startkderc" <<'EOF'
[General]
systemdBoot=false
EOF

# Désactive l'écran de démarrage (ksplashqml, app Qt Quick/OpenGL) — bloque
# indéfiniment sur ce rendu headless sans jamais planter proprement.
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

dbus-run-session -- startplasma-wayland &
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
