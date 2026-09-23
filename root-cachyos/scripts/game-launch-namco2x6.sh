#!/bin/bash
# Lanceur pour Namco System 246/256 (22/09), via PCSX2X6
# (github.com/PS2Homebrew-arcade/pcsx2x6, fork arcade de PCSX2). Reprend le
# fonctionnement de Batocera (batocera_launch/emulators/pcsx2x6.py) :
#   - chaque jeu est un .squashfs contenant un .acgame (description du jeu,
#     dont "platform=246|256"), le .elf, le .chd et la sram — vérifié sur la
#     ludothèque réelle ;
#   - BIOS r27v1602f.7d pour la plateforme 246, r27v1602f.8g sinon (256,
#     super256...), dans bios/namco2x6 ;
#   - lancement : pcsx2x6-qt -nogui <fichier.acgame> ;
#   - dongle (clé de sécurité de la borne, image de carte mémoire PS2 de
#     8 650 752 octets, nom exact donné par "dongle=" dans le .acgame) : UN
#     dossier de cartes mémoire commun à tous les jeux, comme Batocera
#     (Folders/MemoryCards = saves/namco2x6/pcsx2x6). Les images de jeux ne
#     le contiennent pas (vérifié sur les 48 de la ludothèque, 23/09) : il se
#     récupère à part, puis se décompresse/renomme en .ps2 dans ce dossier.
# Seules les clés nécessaires de PCSX2.ini sont écrites (dossiers BIOS et
# cartes mémoire, BIOS de la plateforme, assistant de premier lancement
# désactivé, plein écran) :
# tout autre réglage fait depuis l'interface de PCSX2X6 est conservé.
set -uo pipefail
# shellcheck source=game-lib.sh
. /usr/local/bin/scripts/game-lib.sh

rom="$1"
mount_squashfs_rom "${rom}" || exit 1
acgame=$(find "${MOUNTED_DIR}" -maxdepth 2 -name '*.acgame' -print -quit)
if [[ -z "${acgame}" ]]; then
    echo "game-launch-namco2x6 : aucun .acgame dans ${rom}" >&2
    exit 1
fi

platform=$(sed -n 's/^[[:space:]]*platform[[:space:]]*=[[:space:]]*//p' "${acgame}" | head -1 | tr -d '\r')
dongle=$(sed -n 's/^[[:space:]]*dongle[[:space:]]*=[[:space:]]*//p' "${acgame}" | head -1 | tr -d '\r')

# Dongle vérifié AVANT le lancement : sans lui, PCSX2X6 n'affiche qu'un
# "requested dongle image does not exist" peu parlant (vécu le 23/09).
MEMCARDS_DIR="${SAVES_DIR}/namco2x6/pcsx2x6"
mkdir -p "${MEMCARDS_DIR}"
if [[ -n "${dongle}" && ! -f "${MEMCARDS_DIR}/${dongle}" ]]; then
    msg="Dongle manquant : « ${dongle} » attendu dans ${MEMCARDS_DIR}"
    echo "game-launch-namco2x6 : ${msg}" >&2
    command -v notify-send >/dev/null 2>&1 && notify-send -a SteamBox "Namco 246/256" "${msg}" 2>/dev/null
    exit 1
fi
bios_file="r27v1602f.8g"
[[ "${platform}" == "246" ]] && bios_file="r27v1602f.7d"

ini="${XDG_CONFIG_HOME:-${HOME}/.config}/PCSX2x6/inis/PCSX2.ini"
mkdir -p "$(dirname "${ini}")"
python3 - "${ini}" "${BIOS_DIR}/namco2x6" "${bios_file}" "${MEMCARDS_DIR}" <<'INI_EOF'
import configparser, sys
path, bios_dir, bios_file, memcards_dir = sys.argv[1:5]
cfg = configparser.ConfigParser(interpolation=None, strict=False)
cfg.optionxform = str  # PCSX2 est sensible à la casse des clés
cfg.read(path)
for section, key, value in (
    ("UI", "SetupWizardIncomplete", "false"),
    ("UI", "ConfirmShutdown", "false"),
    ("UI", "StartFullscreen", "true"),
    ("Folders", "Bios", bios_dir),
    ("Folders", "MemoryCards", memcards_dir),
    ("Filenames", "BIOS", bios_file),
):
    if not cfg.has_section(section):
        cfg.add_section(section)
    cfg.set(section, key, value)
with open(path, "w") as f:
    cfg.write(f, space_around_delimiters=True)
INI_EOF

# Sous-dossier du jeu (23/09, "cannot open arcade media image") : sans ligne
# subdir= dans le .acgame, PCSX2X6 cherche le .chd, l'.elf et la sram dans
# <dossier du .acgame>/<gameid>/ (VMManager.cpp : subdir vaut par défaut le
# gameid). Les .squashfs de la ludothèque (anciens paquets Batocera) ont
# tout à la racine et pas de subdir= — log constaté : "Open failed to open
# CHD: 6" (fichier introuvable) sur .../Battle Gear 3/NM00010/*.chd. Sans
# toucher aux images, on reconstitue la structure attendue dans un dossier
# de travail : copie du .acgame + dossier <gameid>/ de liens vers l'image
# montée. La sram.bin (réglages/records de la borne, écrite par le jeu) ne
# peut pas vivre dans l'image montée en lecture seule : copie persistante
# dans saves/namco2x6/<gameid>/, initialisée une fois depuis l'image.
if grep -qE '^[[:space:]]*subdir[[:space:]]*=' "${acgame}"; then
    /usr/local/bin/pcsx2x6 -nogui "${acgame}"
    exit $?
fi
gameid=$(sed -n 's/^[[:space:]]*gameid[[:space:]]*=[[:space:]]*//p' "${acgame}" | head -1 | tr -d '\r')
[[ -n "${gameid}" ]] || { echo "game-launch-namco2x6 : gameid absent de ${acgame}" >&2; exit 1; }
work="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/game-namco2x6"
rm -rf "${work}"
mkdir -p "${work}/${gameid}"
for f in "${MOUNTED_DIR}"/*; do
    case "${f##*/}" in
        *.acgame|sram.bin) ;;
        *) ln -s "${f}" "${work}/${gameid}/${f##*/}" ;;
    esac
done
sram_dir="${SAVES_DIR}/namco2x6/${gameid}"
mkdir -p "${sram_dir}"
if [[ ! -f "${sram_dir}/sram.bin" && -f "${MOUNTED_DIR}/sram.bin" ]]; then
    cp "${MOUNTED_DIR}/sram.bin" "${sram_dir}/sram.bin"
fi
[[ -f "${sram_dir}/sram.bin" ]] && ln -s "${sram_dir}/sram.bin" "${work}/${gameid}/sram.bin"
cp "${acgame}" "${work}/${acgame##*/}"

/usr/local/bin/pcsx2x6 -nogui "${work}/${acgame##*/}"
