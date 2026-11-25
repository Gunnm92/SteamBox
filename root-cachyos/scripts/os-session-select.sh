#!/bin/bash
# os-session-select — point d'extension appelé par steamos-session-select
# (voir ce fichier), convention officielle ChimeraOS/gamescope-session-steam
# pour la logique spécifique à CETTE distribution/ce conteneur, quand on
# choisit « Basculer vers le bureau » dans Steam. L'argument ($1,
# "plasma"/"gamescope"...) est ignoré.
#
# Session Moonlight « Mode SteamOS (Gamescope) » (25/11) : gamescope y pilote
# seul la sortie du dongle, KWin de streaming arrêté par le prep-cmd. Tuer
# Steam seul (ancien comportement) laissait la sortie sans maître DRM, KWin
# jamais relancé ; Sunshine tombait à la réinitialisation de sa capture et
# bouclait ensuite sur « wayland-stream absent ». On joue donc la fin de
# session normale (steam-gamescope-session.sh stop : Steam fermé proprement,
# gamescope arrêté, KWin relancé), détachée : ce script est un enfant de
# Steam, que stop attend.
RUNTIME="/run/user/$(id -u)"
if [ -s "${RUNTIME}/steambox-stream-output" ] &&
   [ "$(/command/s6-svstat -o up /run/service/svc-kwin-stream 2>/dev/null)" = false ]; then
    setsid -f /usr/local/bin/scripts/steam-gamescope-session.sh stop \
        >"${RUNTIME}/steam-gamescope-stop.log" 2>&1 </dev/null
    exit 0
fi

# Ailleurs (gamescope imbriqué dans un bureau) : fermer Steam suffit,
# gamescope s'arrête avec son enfant principal.
pkill -x steam 2>/dev/null
exit 0
