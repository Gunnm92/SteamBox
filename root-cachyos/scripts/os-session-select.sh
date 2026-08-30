#!/bin/bash
# os-session-select — point d'extension appelé par steamos-session-select
# (voir ce fichier), convention officielle ChimeraOS/gamescope-session-steam
# pour la logique spécifique à CETTE distribution/ce conteneur. L'argument
# ($1, "plasma"/"plasma-persistent"/"gamescope"...) est ignoré : dans cette
# architecture (gamescope niché dans labwc/XFCE, pas de vraie bascule de
# session systemd/display-manager façon SteamOS réelle — pas de SDDM ici),
# la seule action possible est toujours la même : fermer gamescope/Steam
# pour révéler le bureau XFCE/labwc en dessous.
pkill -x gamescope 2>/dev/null
pkill -x steam 2>/dev/null
exit 0
