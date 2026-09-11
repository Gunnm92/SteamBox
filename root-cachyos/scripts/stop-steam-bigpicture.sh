#!/bin/bash
# Contrepartie "undo" dédiée à l'entrée apps.json "Steam Big Picture"
# (10/09) : reset-resolution.sh seul ne fait que remettre le headless en
# 1920x1080, mais Steam (-gamepadui) reste "detached" — Sunshine ne le tue
# jamais lui-même à la fin du stream, par design pour les apps "detached".
# Résultat confirmé en direct : Steam continue d'afficher/animer son UI
# gamepadui sur le compositeur headless (wayland-1) bien après la
# déconnexion Moonlight, ce qui maintient le GPU à ~30% d'utilisation et le
# CPU du labwc headless chargé indéfiniment jusqu'au prochain redémarrage
# du conteneur.
#
# pkill -x (nom exact du process), pas -f (ligne de commande complète) :
# même piège que documenté dans exit-to-desktop.sh -- un -f ici matcherait
# aussi la commande de CE script/l'appel prep-cmd de Sunshine lui-même s'il
# contient "steam" quelque part dans sa ligne de commande complète.
set -uo pipefail

/usr/local/bin/scripts/reset-resolution.sh

pkill -x steam 2>/dev/null
exit 0
