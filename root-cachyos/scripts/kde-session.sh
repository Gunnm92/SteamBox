#!/bin/bash
# Lance KWin comme compositeur racine (backend DRM direct, --drm) avec
# plasmashell comme shell — pas le lanceur officiel startplasma-wayland
# (dépend de ksmserver/kcminit, eux-mêmes attendus par un vrai systemd
# --user — absent ici, c'est ce qui avait fait abandonner KDE la première
# fois). À la place, même schéma que linuxserver/docker-webtop (branche
# arch-kde) : kwin_wayland + plasmashell lancés à la main dans un
# dbus-run-session, sans passer par la chaîne de démarrage systemd.
#
# KWIN_WAYLAND_NO_PERMISSION_CHECKS=1 : sans ça, le backend de capture
# natif de Sunshine (kwingrab, via zkde_screencast_unstable_v1) refuse la
# capture ("zkde_screencast_unstable_v1 not found in registry... set
# KWIN_WAYLAND_NO_PERMISSION_CHECKS=1") — confirmé en direct, capture
# NVENC/DMA-BUF fonctionnelle une fois ce flag posé.

set -e

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export QT_QPA_PLATFORM=wayland
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_TYPE=wayland
export KDE_SESSION_VERSION=6
export DISPLAY=:0
export SDL_VIDEODRIVER=wayland
export SDL_JOYSTICK_DISABLE_UDEV=1
export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
export HYPRLAND_NO_SD_NOTIFY=1

mkdir -p "${HOME}/.config" "${HOME}/.local/share"

# GTK ne suit pas automatiquement le thème Plasma comme le font les
# applications Qt (intégration native via plasma-integration) — breeze-gtk
# fournit le thème mais il faut le sélectionner explicitement.
mkdir -p "${HOME}/.config/gtk-3.0" "${HOME}/.config/gtk-4.0"
cat > "${HOME}/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Breeze-Dark
gtk-icon-theme-name=Papirus-Dark
EOF
cp "${HOME}/.config/gtk-3.0/settings.ini" "${HOME}/.config/gtk-4.0/settings.ini"

# Pas d'écran de verrouillage : aucun mécanisme de login ici, un verrouillage
# serait une impasse définitive plutôt qu'une protection utile.
kwriteconfig6 --file "${HOME}/.config/kscreenlockerrc" --group Daemon --key Autolock false 2>/dev/null || true

touch "${HOME}/.local/share/user-places.xbel"

# Thème sombre par défaut pour les applications Qt/Plasma (GTK est réglé
# séparément ci-dessus) — sans ça Arch installe Breeze en clair par défaut.
kwriteconfig6 --file "${HOME}/.config/kdeglobals" --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop 2>/dev/null || true
kwriteconfig6 --file "${HOME}/.config/kdeglobals" --group General --key ColorScheme BreezeDark 2>/dev/null || true
kwriteconfig6 --file "${HOME}/.config/kwinrc" --group org.kde.kdecoration2 --key theme Breeze 2>/dev/null || true

# Sans thème de curseur explicite, confirmé en direct : curseur invisible
# sous KWin (contrairement à Hyprland, qui s'en sortait avec un défaut
# raisonnable tout seul).
kwriteconfig6 --file "${HOME}/.config/kcminputrc" --group Mouse --key cursorTheme breeze_cursors 2>/dev/null || true
kwriteconfig6 --file "${HOME}/.config/kcminputrc" --group Mouse --key cursorSize 24 2>/dev/null || true

# Reconstruit la base d'applications (kickoff/menu) — nécessaire pour que nos
# .desktop personnalisés (Steam, Sunshine, Chrome, émulateurs...) apparaissent.
[ -f /etc/xdg/menus/applications.menu ] || \
    cp /etc/xdg/menus/plasma-applications.menu /etc/xdg/menus/applications.menu 2>/dev/null || true
kbuildsycoca6 2>/dev/null || true

# PipeWire — requis par le backend de capture natif de Sunshine sous KWin
# (kwingrab passe par zkde_screencast_unstable_v1 -> PipeWire, pas par
# wlr-screencopy comme sous Hyprland). Sans ça : "[kwingrab] stream_output
# failed: Impossible de se connecter à un contexte « PipeWire »" et Sunshine
# échoue à trouver un encodeur — confirmé en direct après un redémarrage du
# conteneur (oubli à la première version de ce script, jamais nécessaire
# sous Hyprland qui capture sans PipeWire).
pipewire &
sleep 1
wireplumber &
pipewire-pulse &
sleep 1

# exec (pas de &+wait) : ce script EST le run d'un service longrun s6
# (svc-kde) — s6 supervise directement le process remplacé ici.
exec dbus-run-session bash -c '
    kwin_wayland --xwayland --drm --no-lockscreen &
    KWIN_PID=$!
    sleep 3
    if [ -x /usr/lib/polkit-kde-authentication-agent-1 ]; then
        /usr/lib/polkit-kde-authentication-agent-1 &
    fi
    plasmashell
    kill "${KWIN_PID}"
'
