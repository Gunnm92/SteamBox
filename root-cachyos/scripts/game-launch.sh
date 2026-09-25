#!/bin/bash
# Lanceur générique (22/09, frontend EmulationStation depuis le 24/09) : UNE
# seule commande pour toute la ludothèque — <command> de chaque système dans
# es_systems.cfg (généré par es-systems-gen.sh) : game-launch.sh %ROM%.
#
# Pourquoi générique : la plateforme est déduite du DOSSIER du jeu
# (roms/<plateforme>/...), la même commande sert partout — changer un
# émulateur se fait dans game-systems.sh seulement, jamais dans les fichiers
# de la ludothèque (gamelist.xml RomM intacts).
#
# Émulateur, extensions acceptées et commande de chaque plateforme :
# game-systems.sh. Journal : ${XDG_RUNTIME_DIR}/game-launch.log.
set -uo pipefail
# shellcheck source=game-systems.sh
. /usr/local/bin/scripts/game-systems.sh

LOG="${XDG_RUNTIME_DIR:-/tmp}/game-launch.log"
rom="${1:-}"

fail() {
    echo "[$(date '+%F %T')] ÉCHEC ${rom} : $*" | tee -a "${LOG}" >&2
    command -v notify-send >/dev/null 2>&1 && notify-send -a SteamBox "Lancement impossible" "$*" 2>/dev/null
    exit 1
}

[[ -e "${rom}" ]] || fail "fichier introuvable"

# Plateforme = premier dossier sous roms/, chemins résolus (/home/arcade est
# un lien vers /config : le frontend peut transmettre l'une ou l'autre forme).
roms_real=$(realpath "${ROMS_DIR}")
rom_real=$(realpath "${rom}")
[[ "${rom_real}" == "${roms_real}/"* ]] || fail "hors de ${ROMS_DIR}, plateforme inconnue"
rel="${rom_real#"${roms_real}"/}"
system="${rel%%/*}"

entry="${SYSTEMS[${system}]:-}"
[[ -n "${entry}" ]] || fail "aucun émulateur configuré pour la plateforme '${system}'"
IFS='|' read -r _ extensions template <<< "${entry}"

# Format pris en charge ? ("/" dans la liste = dossier de jeu accepté.)
name="${rom_real##*/}"
ext="${name##*.}"
ext="${ext,,}"
if [[ -d "${rom_real}" ]]; then
    [[ ",${extensions}," == *",/,"* ]] \
        || fail "jeu en dossier non pris en charge pour '${system}' (attendu : ${extensions})"
elif [[ "${name}" != *.* || ",${extensions}," != *",${ext},"* ]]; then
    fail "format .${ext} non pris en charge pour '${system}' (attendu : ${extensions})"
fi

# Émulateur (ou cœur RetroArch) présent ?
read -r -a words <<< "${template}"
bin="${words[0]}"
[[ "${bin}" == "sudo" ]] && bin="${words[2]}"
command -v "${bin}" >/dev/null 2>&1 || fail "émulateur absent : ${bin}"
core=$(grep -oE '/[^ "]*_libretro\.so' <<< "${template}" || true)
[[ -z "${core}" || -e "${core}" ]] \
    || fail "cœur $(basename "${core}") absent (RetroArch > Charger un cœur > Télécharger un cœur)"

# Substitution du chemin, échappé pour le shell : la table ne contient que
# des commandes de ce dépôt, le seul élément variable est le chemin du jeu.
cmd="${template//\"\{file.path\}\"/$(printf '%q' "${rom}")}"
echo "[$(date '+%F %T')] ${system} : ${cmd}" >> "${LOG}"
# GAME_LAUNCH_DRYRUN=1 : affiche la commande sans la lancer (tests).
if [[ -n "${GAME_LAUNCH_DRYRUN:-}" ]]; then
    echo "${cmd}"
    exit 0
fi
# Sortie du jeu dans son propre journal (écrasé à chaque lancement), jamais
# vers le frontend : EmulationStation fait passer stdout par `head -300` —
# au-delà de 300 lignes (Wine/wsquashfs-launcher les dépassent vite), head
# se ferme, l'écriture suivante tue ce script par SIGPIPE, ES croit la partie
# finie et relance sa musique pendant que le jeu tourne encore (confirmé en
# direct : House of the Dead 3 toujours actif, un 2e jeu lancé par-dessus).
exec > "${XDG_RUNTIME_DIR:-/tmp}/game-launch-last.log" 2>&1
# Hotkey (PS / Xbox) + Start = quitter le jeu, comme evmapy sous Batocera,
# pour tout ce qui n'est pas RetroArch (qui a ses propres raccourcis) :
# surveillant lancé sur NOTRE pid, que le jeu reprend via exec ci-dessous.
# Jeu Wine : le lanceur tourne en root (sudo), il ne peut pas être signalé
# par arcade — le surveillant arrête alors le wineserver du prefix du jeu
# (même chemin que wsquashfs-launcher : $HOME/.cache/wsquashfs/wine/<jeu>).
if [[ "${cmd}" != retroarch* ]] && command -v python3 >/dev/null 2>&1; then
    wine_prefix=""
    if [[ "${cmd}" == *wsquashfs-launcher* ]]; then
        wine_prefix="${WSQUASHFS_CACHE:-${HOME}/.cache/wsquashfs}/wine/$(basename "${rom_real}" .wsquashfs)"
    fi
    # setsid + fermeture des descripteurs hérités : ES lance le jeu dans un
    # pipeline shell (fd 3 vers `read xs`, stdout vers `head -300`) — le
    # surveillant ne doit ni en hériter ni partager son groupe de processus.
    setsid /usr/local/bin/scripts/pad-exit-watcher.py "$$" ${wine_prefix:+--wine-prefix "${wine_prefix}"} \
        </dev/null >/dev/null 2>&1 3>&- 4>&- 5>&- &
fi
eval "exec ${cmd}"
