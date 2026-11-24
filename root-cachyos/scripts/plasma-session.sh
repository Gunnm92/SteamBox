#!/bin/bash
# Session Plasma du bureau navigateur (24/11), en arcade — lancée par
# svc-plasma. Prépare la configuration puis se REMPLACE par
# startplasma-wayland, imbriqué dans le compositeur de Selkies (wayland-0) :
# son KWin (kwin_wayland_wrapper, Xwayland à la demande) prend le premier
# socket libre, wayland-1. Sans systemd, startplasma retombe tout seul sur
# le démarrage classique (ksmserver) ; validé à la main le 24/11.
# Remplace labwc-session.sh (labwc + XFCE, retirés le 24/11).
set -euo pipefail

mkdir -p "${HOME}/.config" "${HOME}/.local/share"
# CWD = HOME (audit 01/09) : hérité sinon du dossier de service s6, puis de
# tout ce que le bureau lance.
cd "${HOME}"

# Bus D-Bus de session : service s6 à part (svc-dbus-session) — on attend
# juste son socket. Plasma s'y installe : le streaming a son propre bus
# (bus-stream).
for _ in $(seq 1 60); do
    [ -S "${XDG_RUNTIME_DIR}/bus" ] && break
    sleep 0.5
done
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# Disposition clavier (KEYBOARD_LAYOUT/VARIANT) écrite à chaque démarrage
# dans kxkbrc (write_kxkbrc, steambox-env.sh).
# shellcheck source=steambox-env.sh
. /usr/local/bin/scripts/steambox-env.sh
write_kxkbrc

# Verrouillage d'écran coupé (24/11, relecture) : kscreenlocker verrouille
# après 5 min par défaut, et arcade n'a pas de mot de passe — le bureau
# navigateur resterait verrouillé sans issue. L'accès se protège par
# DESKTOP_PASSWORD (Selkies), pas par l'écran de verrouillage.
kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false

# Fallbacks GTK3/4 (thème, icônes et curseur WhiteSur) pour les applis GTK,
# écrits SEULEMENT s'ils manquent : sous Plasma, les Paramètres
# (Apparence > Style des applications) les réécrivent, un choix de
# l'utilisateur ne doit pas être écrasé à chaque démarrage.
mkdir -p "${HOME}/.config/gtk-3.0" "${HOME}/.config/gtk-4.0"
if [ ! -e "${HOME}/.config/gtk-3.0/settings.ini" ]; then
    cat > "${HOME}/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=WhiteSur-Dark
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=WhiteSur-dark
gtk-cursor-theme-name=WhiteSur-cursors
gtk-cursor-theme-size=24
gtk-font-name=Cantarell 10
EOF
fi
if [ ! -e "${HOME}/.config/gtk-4.0/settings.ini" ]; then
    cp "${HOME}/.config/gtk-3.0/settings.ini" "${HOME}/.config/gtk-4.0/settings.ini"
fi

# libadwaita (applis GNOME récentes) : n'utilise pas le thème GTK choisi,
# seulement ~/.config/gtk-4.0/gtk.css. Relié au CSS WhiteSur-Dark de l'image
# (images en chemins relatifs : assets/ relié aussi) SEULEMENT s'il n'y en a
# pas déjà un — un CSS personnel ou d'un autre thème n'est jamais remplacé.
adw=/usr/share/themes/WhiteSur-Dark/libadwaita
if [ -f "${adw}/gtk-Dark.css" ] && [ ! -e "${HOME}/.config/gtk-4.0/gtk.css" ]; then
    ln -sfn "${adw}/gtk-Dark.css" "${HOME}/.config/gtk-4.0/gtk.css"
    ln -sfn "${adw}/gtk-Dark.css" "${HOME}/.config/gtk-4.0/gtk-dark.css"
    for a in assets windows-assets; do
        if [ -e "${adw}/${a}" ] && [ ! -e "${HOME}/.config/gtk-4.0/${a}" ]; then
            ln -sfn "${adw}/${a}" "${HOME}/.config/gtk-4.0/${a}"
        fi
    done
fi

# Cache de polices de l'utilisateur à jour AVANT tout composant graphique
# (26/09) : pour les polices ajoutées dans ~/.local/share/fonts. Sinon le
# chargeur SVG de glycin reconstruit son cache dans son bac à sable, et
# seccomp le tue (voir fc-cache -s en fin de Dockerfile). Instantané quand
# rien n'a changé.
fc-cache 2>/dev/null || true

xdg-mime default wine.desktop application/x-ms-dos-executable application/x-msi \
    application/x-ms-shortcut application/x-bat 2>/dev/null || true

# Verrou Chrome périmé (31/08) : SingletonLock encode le hostname du dernier
# lancement ; après un renommage de conteneur, Chrome refusait de démarrer.
rm -f "${HOME}/.config/google-chrome/Singleton"{Lock,Cookie,Socket} 2>/dev/null || true

# Environnement publié par desktop-session.sh (autostart) : l'ancien est
# retiré pour qu'aucun script ne lise celui d'une session morte.
rm -f "${XDG_RUNTIME_DIR}/steambox-desktop-session.env" \
      "${XDG_RUNTIME_DIR}/steambox-desktop-display"

# KWin imbriqué : WAYLAND_DISPLAY désigne son hôte (Selkies) ; DISPLAY est
# celui que KWin créera pour son Xwayland, jamais un hérité.
unset DISPLAY
export WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland \
    XDG_SESSION_DESKTOP=plasma DESKTOP_SESSION=plasma \
    KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
exec startplasma-wayland
