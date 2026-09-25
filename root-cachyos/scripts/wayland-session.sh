#!/bin/bash
# Bureau Wayland réel via labwc (compositeur wlroots) — second pivot Waybox
# (29/08). Remplace la session KWin : ni wayvnc ni evdev-bridge (input
# souris/clavier Sunshine) ne fonctionnent contre KWin, qui n'implémente pas
# les protocoles wlroots dont ces deux outils dépendent — voir point 6 de
# l'historique en tête de Dockerfile.cachyos.
#
# Lancé par svc-labwc (root) : prépare le runtime puis passe la main, en
# arcade, à labwc-session.sh, qui écrit la configuration de labwc et se
# REMPLACE par labwc. Les composants XFCE (xfsettingsd, xfdesktop,
# xfce4-panel, nm-applet, agent polkit) sont des services s6 séparés depuis
# le 26/09 (voir desktop-env.sh) — ils étaient lancés en arrière-plan ici,
# dans un "bash -c '…'" géant : non supervisés, et une seule apostrophe dans
# un commentaire cassait toute la session (vécu le 31/08).
#
# labwc gère nativement son accès DRM/input via seatd — tourne de bout en
# bout en arcade, pas de dance root/runuser type Xorg.wrap.

set -e
# shellcheck source=steambox-env.sh
. /usr/local/bin/scripts/steambox-env.sh

ARCADE_UID="$(id -u arcade)"
ARCADE_RUNTIME_DIR="/run/user/${ARCADE_UID}"
mkdir -p "${ARCADE_RUNTIME_DIR}"
chown arcade:arcade "${ARCADE_RUNTIME_DIR}"
chmod 700 "${ARCADE_RUNTIME_DIR}"

# exec (audit 22/09) : s6 doit signaler directement la chaîne runuser →
# labwc ; sans exec, un s6-svc -r ne tuait que ce script et laissait un
# labwc orphelin garder wayland-0.
#
# WLR_DRM_DEVICES = premier /dev/dri/card* présent : /sys/class/drm liste les
# GPU de l'hôte multi-GPU, mais /dev/dri/ ne contient que celui passé au
# conteneur — sans ce forçage, wlroots essaie card1/card2 et échoue
# ("Could not canonicalize path /dev/dri/cardN", 30/08).
# WLR_LIBINPUT_NO_DEVICES=1 : aucun périphérique libinput au démarrage du
# conteneur ; evdev-bridge et les manettes (SDL) n'en dépendent pas.
# Renderer par défaut (GLES2) : WLR_RENDERER=vulkan casse la capture
# Sunshine (écran noir sous Moonlight, 30/08).
exec runuser -u arcade -- env \
    HOME=/home/arcade XDG_RUNTIME_DIR="${ARCADE_RUNTIME_DIR}" \
    QT_QPA_PLATFORM=wayland XDG_CURRENT_DESKTOP=XFCE XDG_SESSION_TYPE=wayland \
    SDL_VIDEODRIVER=wayland,x11 SDL_JOYSTICK_DISABLE_UDEV=1 \
    LIBSEAT_BACKEND=seatd SEATD_VTBOUND=0 \
    KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT}" KEYBOARD_VARIANT="${KEYBOARD_VARIANT}" \
    WLR_DRM_DEVICES="$(first_drm_card)" WLR_LIBINPUT_NO_DEVICES=1 \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games" \
    /usr/local/bin/scripts/labwc-session.sh
