#!/bin/bash
# Session labwc du bureau visible (wayland-0), en arcade — lancée par
# wayland-session.sh (svc-labwc). Écrit la configuration de labwc et des
# fallbacks GTK, puis se REMPLACE par labwc : s6 supervise le compositeur
# lui-même. Les composants XFCE sont des services s6 à part (desktop-env.sh).
set -euo pipefail

mkdir -p "${HOME}/.config" "${HOME}/.local/share"
# CWD = HOME (audit 01/09) : hérité sinon du dossier de service s6.
cd "${HOME}"

# Bus D-Bus de session : service s6 à part (svc-dbus-session, dépendance de
# svc-labwc) — on attend juste son socket.
for _ in $(seq 1 60); do
    [ -S "${XDG_RUNTIME_DIR}/bus" ] && break
    sleep 0.5
done
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# Clavier : labwc ne lit PAS XKB_DEFAULT_LAYOUT dans son environnement, mais
# dans ~/.config/labwc/environment (doc labwc, confirmé le 30/08).
# Disposition : KEYBOARD_LAYOUT/VARIANT (steambox-env.sh).
# Curseur : celui réglé dans XFCE (xfconf), sinon WhiteSur — labwc le
# transmet à Xwayland et aux applis qu'il lance ; sans lui, le curseur par
# défaut s'affichait sur le fond et les bordures de fenêtres.
cursor_theme=$(xfconf-query -c xsettings -p /Gtk/CursorThemeName 2>/dev/null || true)
cursor_size=$(xfconf-query -c xsettings -p /Gtk/CursorSize 2>/dev/null || true)
mkdir -p "${HOME}/.config/labwc"
cat > "${HOME}/.config/labwc/environment" <<EOF
XKB_DEFAULT_LAYOUT=${KEYBOARD_LAYOUT:-us}
XKB_DEFAULT_VARIANT=${KEYBOARD_VARIANT:-}
XCURSOR_THEME=${cursor_theme:-WhiteSur-cursors}
XCURSOR_SIZE=${cursor_size:-24}
EOF

# Thème des bordures de fenêtres : celui du thème GTK choisi (xfconf) s'il
# fournit un thème labwc — c'est le cas de WhiteSur (26/09) —, sinon le
# thème par défaut de labwc. Lu au démarrage de la session.
gtk_theme=$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null || true)
labwc_theme=""
for d in "${HOME}/.themes" "${HOME}/.local/share/themes" /usr/share/themes; do
    if [ -n "${gtk_theme}" ] && [ -d "${d}/${gtk_theme}/labwc" ]; then
        labwc_theme="  <theme><name>${gtk_theme}</name></theme>"
        break
    fi
done

# rc.xml, partagé avec le labwc headless de Sunshine (wayland-1, même HOME) :
# - followMouse sans mouvement requis (31/08) : le clavier virtuel
#   Sunshine/evdev-bridge perdait le focus après un changement de fenêtre
#   côté Moonlight ; le curseur virtuel étant piloté en continu, le focus
#   suit la fenêtre sous le curseur. raiseOnFocus retiré (17/09) : une
#   fenêtre passait au premier plan au moindre survol.
# - xwaylandPersistence (31/08) : sinon Xwayland meurt ~10 s après le
#   dernier client X11, et les applis X11 du menu échouaient ("Missing X
#   server or DISPLAY") sur un bureau resté sans appli X11.
cat > "${HOME}/.config/labwc/rc.xml" <<EOF
<?xml version="1.0"?>
<labwc_config>
${labwc_theme}
  <core>
    <xwaylandPersistence>yes</xwaylandPersistence>
  </core>
  <focus>
    <followMouse>yes</followMouse>
    <followMouseRequiresMovement>no</followMouseRequiresMovement>
  </focus>
</labwc_config>
EOF

# Fallbacks GTK3/4 (thème, icônes et curseur WhiteSur) pour les applis lancées avant
# xfsettingsd — ensuite c'est xfconf/XSETTINGS qui fait foi
# (xfce-defaults.sh).
mkdir -p "${HOME}/.config/gtk-3.0" "${HOME}/.config/gtk-4.0"
cat > "${HOME}/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=WhiteSur-Dark
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=WhiteSur-dark
gtk-cursor-theme-name=WhiteSur-cursors
gtk-font-name=Cantarell 10
EOF
cp "${HOME}/.config/gtk-3.0/settings.ini" "${HOME}/.config/gtk-4.0/settings.ini"

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

# WAYLAND_DISPLAY/DISPLAY hérités (ENV du Dockerfile) : labwc tenterait de
# s'y CONNECTER comme client imbriqué au lieu de créer son propre backend
# ("Could not connect to remote display", confirmé en direct). Xwayland
# démarre à la demande du premier client X11.
unset WAYLAND_DISPLAY DISPLAY
exec labwc
