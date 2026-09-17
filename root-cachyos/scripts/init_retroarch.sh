#!/bin/bash
# SteamBox — Corrige des réglages RetroArch par défaut incompatibles avec
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
# partagé au format Batocera, pas dans le dossier par défaut de RetroArch
# (~/.config/retroarch/system, toujours vide ici). Plus sous /userdata
# (15/09, reliquat d'un ancien montage séparé — /mnt/user/Game/Batocera
# était monté deux fois, une fois seul sur /userdata, une fois via le
# parent /mnt/user/Game sur /config/games ; /home/arcade est un symlink
# vers /config, donc /home/arcade/games/Batocera/bios pointe déjà sur les
# mêmes données réelles sans ce second montage).
set_cfg "system_directory" "/home/arcade/games/Batocera/bios"

# Cœurs : hybride entre les ~30 cœurs installés par pacman (groupe
# "libretro", voir Dockerfile — /usr/lib/libretro, propriété root, non
# inscriptible par l'utilisateur arcade) et le Core Downloader intégré de
# RetroArch, désactivé par défaut sur ce paquet Arch/CachyOS
# (menu_show_core_updater=false — confirmé en direct, aucun réglage de ce
# script ne le touchait). Pointer libretro_directory directement sur
# /usr/lib/libretro empêcherait tout téléchargement (permission refusée) ;
# on le fait pointer vers un dossier utilisateur repeuplé à chaque
# démarrage par des liens symboliques vers les cœurs pacman (idempotent,
# ln -sf) — un cœur téléchargé depuis RetroArch lui-même reste un fichier
# réel dans ce même dossier, jamais touché par ce repeuplage sauf mise à
# jour volontaire du même nom de fichier depuis le Core Downloader.
CORES_DIR="/config/.config/retroarch/cores"
mkdir -p "${CORES_DIR}"
for so in /usr/lib/libretro/*.so; do
    [ -e "${so}" ] || continue
    ln -sf "${so}" "${CORES_DIR}/$(basename "${so}")"
done
set_cfg "libretro_directory" "${CORES_DIR}"
set_cfg "menu_show_core_updater" "true"

# Base de données ("Scan Directory"/Manual Scan ne créait aucune liste,
# 18/09) : content_database_path par défaut (~/.config/retroarch/database/
# rdb) reste vide tant que personne n'a lancé "Online Updater > Update
# Databases" à la main — confirmé en direct. Pointée à la place vers le
# dossier système peuplé au build (voir Dockerfile), données statiques de
# référence, pas de raison d'en avoir une copie par-utilisateur.
set_cfg "content_database_path" "/usr/share/retroarch/database/rdb"

# Garde de propriétaire (audit F4, 05/09, même motif qu'init_system.sh) :
# ce chown -R tournait inconditionnellement à CHAQUE boot sur un dossier
# qui contient thumbnails et shaders RetroArch, potentiellement volumineux
# et sur FUSE (/config) — coûteux pour rien une fois déjà correct.
CFG_DIR="$(dirname "${CFG}")"
TARGET_OWNER="${PUID:-1000}:${PGID:-1000}"
CURRENT_OWNER=$(stat -c '%u:%g' "${CFG_DIR}" 2>/dev/null || echo "")
[ "${CURRENT_OWNER}" = "${TARGET_OWNER}" ] || chown -R "${TARGET_OWNER}" "${CFG_DIR}" 2>/dev/null || true
