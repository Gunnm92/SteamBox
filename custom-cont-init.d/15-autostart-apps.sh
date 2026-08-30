#!/bin/bash
# ArcadeBox — Complète l'autostart XDG (~/.config/autostart) lancé par dex au
# démarrage du bureau (voir /defaults/autostart_wayland).
#
# Sunshine n'a aucune entrée d'autostart dans l'image de base : il fallait le
# lancer manuellement à chaque démarrage. On en crée une, en appelant le
# binaire directement (l'entrée fournie par le paquet Sunshine passe par
# "systemctl start --user", inutilisable ici : pas de session systemd).
#
# NB : le flag "-silent" de Steam (fenêtre cachée) est fixé dans STEAM_EXEC de
# root/etc/s6-overlay/s6-rc.d/init-arcadebox/run, qui régénère steam.desktop à
# CHAQUE démarrage — un correctif ici serait écrasé aussitôt. Le retrait du
# flag se fait donc directement dans ce script source (rebuild d'image requis).

AUTOSTART_DIR="${HOME}/.config/autostart"
mkdir -p "${AUTOSTART_DIR}"

if [ ! -f "${AUTOSTART_DIR}/sunshine.desktop" ]; then
    cat > "${AUTOSTART_DIR}/sunshine.desktop" <<'EOF'
[Desktop Entry]
Name=Sunshine
Exec=/usr/bin/sunshine
Icon=dev.lizardbyte.app.Sunshine
Terminal=false
Type=Application
Categories=Network;Game;
X-GNOME-Autostart-enabled=true
EOF
    echo "[arcadebox] sunshine.desktop créé dans ${AUTOSTART_DIR}"
fi
