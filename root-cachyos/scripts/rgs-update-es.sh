#!/bin/bash
# Entrée « Mise à jour RGS » d'EmulationStation (14/11) : lance rgs-update
# dans un terminal plein écran, comme le rgs_upgrade.sh du système « rgs »
# sous Batocera (xterm maximisé). Les scripts Batocera de roms/rgs
# (rgs_upgrade.sh, yuzu_config.sh...) ne tournent pas ici (/userdata, xterm sur
# :0.0) : ES ne liste que les fichiers .steambox de ce dossier, que Batocera
# ignore. Le contenu du fichier, s'il y en a un, donne les arguments de
# rgs-update (« theme », « loader --force »...), par défaut « all ».
set -euo pipefail

entry="${1:-}"
args="all"
if [[ -s "${entry}" ]]; then
    args=$(grep -vE '^\s*(#|$)' "${entry}" | head -n1 || true)
    # Seuls les mots que rgs-update connaît (le fichier est dans la ludothèque).
    [[ "${args}" =~ ^[a-z\ -]*$ ]] || args="all"
    [[ -n "${args}" ]] || args="all"
fi

# --disable-server : le terminal ne rend la main qu'une fois fermé, ES attend
# la fin de la mise à jour (et le reprend ensuite, thèmes rechargés).
exec xfce4-terminal --disable-server --fullscreen --hide-menubar --hide-toolbar \
    --title "Mise à jour RGS" \
    -x bash -c "rgs-update ${args}; echo; read -r -t 60 -p 'Terminé. Fermeture dans 60 s (Entrée pour fermer).' || true"
