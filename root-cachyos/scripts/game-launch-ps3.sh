#!/bin/bash
# Lanceur pour la PS3 (22/09), via RPCS3. Reprend le fonctionnement
# de Batocera (batocera_launch_rpcs3/emulator.py) :
#   - .squashfs = disque complet (PS3_GAME/USRDIR/EBOOT.BIN, vérifié sur la
#     ludothèque réelle) ou jeu PSN (dev_hdd0/game/<ID>/USRDIR/EBOOT.BIN) :
#     monté, puis EBOOT.BIN passé à RPCS3 ;
#   - .psn = fichier texte contenant l'identifiant d'un jeu PSN déjà
#     installé dans RPCS3 (dev_hdd0/game/<ID>) ;
#   - firmware absent : installé d'abord depuis bios/PS3UPDAT.PUP
#     (--installfw), comme Batocera. L'installation n'a lieu qu'une fois.
# Options vérifiées dans rpcs3/rpcs3.cpp le 22/09 : --no-gui, --fullscreen
# ("only useful with no-gui"), --installfw.
set -uo pipefail
# shellcheck source=game-lib.sh
. /usr/local/bin/scripts/game-lib.sh

RPCS3_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/rpcs3"
rom="$1"

if [[ ! -e "${RPCS3_DIR}/dev_flash/vsh/module/vsh.self" ]]; then
    if [[ ! -f "${BIOS_DIR}/PS3UPDAT.PUP" ]]; then
        echo "game-launch-ps3 : firmware PS3 absent (ni installé, ni ${BIOS_DIR}/PS3UPDAT.PUP)" >&2
        exit 1
    fi
    /usr/local/bin/rpcs3 --installfw "${BIOS_DIR}/PS3UPDAT.PUP"
fi

eboot=""
case "${rom,,}" in
    *.psn)
        game_id=$(tr -d '[:space:]' < "${rom}" | tr '[:lower:]' '[:upper:]')
        eboot="${RPCS3_DIR}/dev_hdd0/game/${game_id}/USRDIR/EBOOT.BIN"
        ;;
    *.squashfs)
        mount_squashfs_rom "${rom}" || exit 1
        if [[ -f "${MOUNTED_DIR}/PS3_GAME/USRDIR/EBOOT.BIN" ]]; then
            eboot="${MOUNTED_DIR}/PS3_GAME/USRDIR/EBOOT.BIN"
        else
            eboot=$(find "${MOUNTED_DIR}/dev_hdd0/game" -maxdepth 3 -path '*/USRDIR/EBOOT.BIN' -print -quit 2>/dev/null)
        fi
        ;;
esac

if [[ -z "${eboot}" || ! -f "${eboot}" ]]; then
    echo "game-launch-ps3 : EBOOT.BIN introuvable pour ${rom} (jeu PSN non installé dans RPCS3 ?)" >&2
    exit 1
fi
/usr/local/bin/rpcs3 "${eboot}" --no-gui --fullscreen
