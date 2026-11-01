#!/bin/bash
# Échec de lancement affiché par EmulationStation (01/11), à sourcer.
#
# Convention Batocera (es-app/src/FileData.cpp, getMessageFromExitCode) :
# quand la commande d'un jeu sort avec le code 250, ES lit
# /tmp/launch_error.log, le supprime et affiche son texte dans une boîte
# « UNE ERREUR S'EST PRODUITE ». C'est l'interface d'ES elle-même : le
# message s'affiche aussi dans le flux Moonlight (wayland-1), alors qu'une
# notification irait sur le bus de session du bureau visible (wayland-0).
# Mécanisme vérifié dans le binaire /opt/batocera-es/emulationstation le
# 01/11.
#
# launch_error <message> : message sur stderr (journal du lancement), dans
# le fichier lu par ES et en notification (xfce4-notifyd : utile hors ES,
# et trace visible sur le bureau), puis sortie en 250. Le code remonte jusqu'à ES
# parce que game-launch.sh lance la commande du jeu par exec et que les
# lanceurs propagent le code de l'émulateur.
LAUNCH_ERROR_FILE="/tmp/launch_error.log"
LAUNCH_ERROR_CODE=250

launch_error() {
    local msg="$*"
    echo "${msg}" >&2
    printf '%s\n' "${msg}" > "${LAUNCH_ERROR_FILE}" 2>/dev/null || true
    # timeout : sans démon joignable, notify-send peut attendre D-Bus
    # longtemps. || true : un échec de notification ne doit pas changer le
    # code de sortie (set -e dans certains lanceurs).
    timeout 5 notify-send -a SteamBox "Lancement impossible" "${msg}" >/dev/null 2>&1 || true
    exit "${LAUNCH_ERROR_CODE}"
}
