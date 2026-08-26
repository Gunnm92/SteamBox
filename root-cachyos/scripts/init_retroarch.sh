#!/bin/bash
# ArcadeBox — Corrige des réglages RetroArch par défaut incompatibles avec
# ce conteneur (confirmés en direct sur la prod).
set -e

CFG="/config/.config/retroarch/retroarch.cfg"
mkdir -p "$(dirname "${CFG}")"
[ -f "${CFG}" ] || touch "${CFG}"

set_cfg() {
    local key="$1" value="$2"
    if grep -q "^${key} = " "${CFG}"; then
        sed -i "s#^${key} = .*#${key} = \"${value}\"#" "${CFG}"
    else
        echo "${key} = \"${value}\"" >> "${CFG}"
    fi
}

# video_vsync : le swap GLX se bloque indéfiniment en attendant un signal
# vblank sur ce GPU/affichage virtuel — confirmé en direct : un jeu se
# lance, charge son BIOS, puis reste figé sur la première image (0% CPU,
# 0% GPU, aucune erreur). Désactiver le vsync règle le problème
# entièrement (confirmé : jeu Dreamcast plein écran et réactif ensuite).
set_cfg "video_vsync" "false"

# pause_nonactive : RetroArch se met en pause dès que sa fenêtre perd le
# focus. Pegasus (et les frontends en général) ne garantissent pas
# toujours le transfert de focus vers le jeu qu'ils viennent de lancer —
# confirmé en direct : la partie se fige immédiatement dans ce cas.
set_cfg "pause_nonactive" "false"

# system_directory : les BIOS de l'utilisateur vivent dans le dossier
# partagé au format Batocera (/userdata/bios), pas dans le dossier par
# défaut de RetroArch (~/.config/retroarch/system, toujours vide ici).
set_cfg "system_directory" "/userdata/bios"

chown -R arcade:arcade "$(dirname "${CFG}")" 2>/dev/null || true
