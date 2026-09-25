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
mkdir -p "${HOME}/.config/labwc"
cat > "${HOME}/.config/labwc/environment" <<EOF
XKB_DEFAULT_LAYOUT=${KEYBOARD_LAYOUT:-us}
XKB_DEFAULT_VARIANT=${KEYBOARD_VARIANT:-}
EOF

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
  <core>
    <xwaylandPersistence>yes</xwaylandPersistence>
  </core>
  <focus>
    <followMouse>yes</followMouse>
    <followMouseRequiresMovement>no</followMouseRequiresMovement>
  </focus>
</labwc_config>
EOF

# Fallbacks GTK3/4 (thème sombre Mc-OS-CTLina + Papirus) pour les applis
# lancées avant xfsettingsd — ensuite c'est xfconf/XSETTINGS qui fait foi
# (xfce-defaults.sh).
mkdir -p "${HOME}/.config/gtk-3.0" "${HOME}/.config/gtk-4.0"
cat > "${HOME}/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=Mc-OS-CTLina-XFCE-Dark
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Cantarell 10
EOF
cp "${HOME}/.config/gtk-3.0/settings.ini" "${HOME}/.config/gtk-4.0/settings.ini"

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
