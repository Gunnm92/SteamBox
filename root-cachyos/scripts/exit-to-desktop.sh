#!/bin/bash
# "Retour au bureau" — ferme gamescope (et Steam avec, puisqu'il tourne comme
# son enfant direct) pour retrouver le bureau XFCE/labwc en dessous. Steam a
# bien sa propre option Quitter qui fait pareil (gamescope se ferme tout
# seul quand son enfant termine), mais ce raccourci donne un moyen explicite
# et fiable d'y revenir sans dépendre du menu Steam.
# -x (nom exact du process) plutôt que -f (ligne de commande complète) —
# plus fiable si gamescope se relance/change ses arguments. On tue aussi
# steam explicitement au cas où gamescope ne l'entraîne pas proprement avec
# lui (gamescope peut parfois survivre brièvement à son enfant).
pkill -x gamescope 2>/dev/null
pkill -x steam 2>/dev/null
exit 0
