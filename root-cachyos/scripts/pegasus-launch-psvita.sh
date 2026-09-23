#!/bin/bash
# Lanceur Pegasus pour la PS Vita (22/09). Un jeu Batocera ".psvita" est un
# simple fichier texte contenant l'identifiant du titre (ex: PCSE00349,
# vérifié sur la ludothèque réelle) — le jeu lui-même doit déjà être
# installé dans Vita3K (menu Fichier > Installer .pkg/.zip). Vita3K le lance
# par cet identifiant : --installed-path/-r, plein écran --fullscreen/-F
# (options vérifiées dans vita3k/config/src/config.cpp le 22/09).
set -euo pipefail

title_id=$(tr -d '[:space:]' < "$1")
if [[ ! "${title_id}" =~ ^[A-Z]{4}[0-9]{5}$ ]]; then
    echo "pegasus-launch-psvita : identifiant de titre invalide dans $1 : '${title_id}'" >&2
    exit 1
fi
exec /usr/local/bin/vita3k -F -r "${title_id}"
