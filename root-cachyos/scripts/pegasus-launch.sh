#!/bin/bash
# Lanceur générique Pegasus (22/09) : UNE seule commande pour toute la
# ludothèque — launch: /usr/local/bin/scripts/pegasus-launch.sh "{file.path}"
# — posée par init_pegasus.sh dans chaque metadata.pegasus.txt.
#
# Pourquoi générique : les metadata.pegasus.txt viennent de RomM, qui
# regroupe plusieurs plateformes sous une même collection (20 dossiers
# arcade — mame, naomi, segaalls, type-x... — tous "collection: Arcade", que
# Pegasus fusionne) et les réécrit à chaque synchronisation. Une commande par
# plateforme obligeait à éclater ces fichiers jeu par jeu ; ici la plateforme
# est déduite du DOSSIER du jeu (roms/<plateforme>/...), la même ligne sert
# partout, et la structure RomM reste intacte.
#
# Émulateur, extensions acceptées et commande de chaque plateforme :
# pegasus-systems.sh. Journal : ${XDG_RUNTIME_DIR}/pegasus-launch.log.
set -uo pipefail
# shellcheck source=pegasus-systems.sh
. /usr/local/bin/scripts/pegasus-systems.sh

ROMS_DIR="${PEGASUS_ROMS_DIR:-/home/arcade/games/Batocera/roms}"
LOG="${XDG_RUNTIME_DIR:-/tmp}/pegasus-launch.log"
rom="${1:-}"

fail() {
    echo "[$(date '+%F %T')] ÉCHEC ${rom} : $*" | tee -a "${LOG}" >&2
    command -v notify-send >/dev/null 2>&1 && notify-send -a Pegasus "Lancement impossible" "$*" 2>/dev/null
    exit 1
}

[[ -e "${rom}" ]] || fail "fichier introuvable"

# Plateforme = premier dossier sous roms/, chemins résolus (/home/arcade est
# un lien vers /config : Pegasus peut transmettre l'une ou l'autre forme).
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
# PEGASUS_LAUNCH_DRYRUN=1 : affiche la commande sans la lancer (tests).
if [[ -n "${PEGASUS_LAUNCH_DRYRUN:-}" ]]; then
    echo "${cmd}"
    exit 0
fi
eval "exec ${cmd}"
