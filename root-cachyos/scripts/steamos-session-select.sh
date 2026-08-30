#!/bin/bash
# steamos-session-select — reprend exactement le script officiel de
# ChimeraOS/gamescope-session-steam (github.com/ChimeraOS/gamescope-session-steam,
# usr/bin/steamos-session-select), le point d'entrée que Steam (gamepadui)
# appelle réellement quand on choisit "Basculer sur le bureau" dans son menu
# Marche/Arrêt. Ce script lui-même ne fait rien de spécifique à un OS : il
# délègue à /usr/lib/os-session-select si présent (le point d'extension
# prévu pour chaque distribution/setup), sinon retombe sur "steam -shutdown"
# (ferme juste Steam, sans bascule de session).
GAMESCOPE_SESSION_SCRIPT="/usr/lib/os-session-select"

if [ -f "${GAMESCOPE_SESSION_SCRIPT}" ]; then
    exec "${GAMESCOPE_SESSION_SCRIPT}" "$@"
else
    exec steam -shutdown
fi
