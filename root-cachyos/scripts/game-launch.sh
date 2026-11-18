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
# shellcheck source=launch-error.sh
. /usr/local/bin/scripts/launch-error.sh

LOG="${XDG_RUNTIME_DIR:-/tmp}/game-launch.log"
rom="${1:-}"

# Échec tracé dans le journal des lancements, puis affiché par
# EmulationStation (launch_error, code 250 : voir launch-error.sh).
fail() {
    echo "[$(date '+%F %T')] ÉCHEC ${rom} : $*" >> "${LOG}"
    launch_error "$*"
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

# Options avancées d'EmulationStation (18/11, es_features.cfg de l'image) :
# ES les enregistre dans batocera.conf, comme Batocera — jeu
# (<système>["<fichier>"].<option>, '=' et '#' retirés du nom comme le fait
# ES), puis système, puis global ; vide ou "auto" = non réglé.
ES_CONF="${ES_HOME:-/home/arcade/.emulationstation}/batocera.conf"
es_conf_get() {
    [[ -f "${ES_CONF}" ]] || return 0
    awk -v k="$1=" 'index($0, k) == 1 { v = substr($0, length(k) + 1) } END { if (v != "") print v }' "${ES_CONF}"
}
es_option() {
    local k v game="${name//[=#]/}"
    for k in "${system}[\"${game}\"].$1" "${system}.$1" "global.$1"; do
        v=$(es_conf_get "${k}")
        if [[ -n "${v}" && "${v}" != "auto" ]]; then
            echo "${v}"
            return
        fi
    done
}

# Génération d'images MAKO (option « mako ») : la commande passe par
# mako-launch, qui active la couche Vulkan pour ce seul jeu (rien ailleurs :
# il isole les couches implicites) puis fait exec — même
# PID, la sortie par la manette (svc-pad-hotkeys) reste valable. Réglages
# dans le profil de mako-ui qui vise l'émulateur ; « mako_profile » en
# impose un par son nom (MAKO_PROFILE). Sans profil applicable, MAKO reste
# inactif.
wrapper=""
if [[ "$(es_option mako)" == "1" ]]; then
    if command -v mako-launch >/dev/null 2>&1; then
        wrapper="mako-launch "
        mako_profile=$(es_option mako_profile)
        [[ -n "${mako_profile}" ]] && export MAKO_PROFILE="${mako_profile}"
    else
        echo "[$(date '+%F %T')] MAKO demandé mais mako-launch absent, lancement sans" >> "${LOG}"
    fi
fi

echo "[$(date '+%F %T')] ${system} : ${MAKO_PROFILE:+MAKO_PROFILE=${MAKO_PROFILE} }${wrapper}${cmd}" >> "${LOG}"
# GAME_LAUNCH_DRYRUN=1 : affiche la commande sans la lancer (tests).
if [[ -n "${GAME_LAUNCH_DRYRUN:-}" ]]; then
    echo "${MAKO_PROFILE:+MAKO_PROFILE=${MAKO_PROFILE} }${wrapper}${cmd}"
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
# géré par le service s6 svc-pad-hotkeys (pad-exit-watcher.py, 27/09), qui
# lit ici le jeu en cours. pid = NOTRE pid, que le jeu reprend via exec
# ci-dessous. Jeu Wine : signaler le lanceur ne suffit pas à fermer Wine —
# le service arrête le wineserver du prefix du jeu (même chemin que
# wsquashfs-launcher : $HOME/.cache/wsquashfs/wine/<jeu>), puis le lanceur
# démonte normalement. Fichier périmé (jeu terminé) ignoré par le service.
state="${XDG_RUNTIME_DIR:-/tmp}/steambox-game"
if [[ "${cmd}" != retroarch* ]]; then
    wine_prefix=""
    # game-launch-arcade.sh passe les .wsquashfs à wsquashfs-launcher (même
    # prefix) ; arcade-launcher (.squashfs/.windowsloader) s'arrête lui-même
    # proprement sur SIGTERM (Wine compris, comme sous RGS) : pas de prefix.
    if [[ "${cmd}" == *wsquashfs-launcher* \
          || ( "${cmd}" == *game-launch-arcade.sh* && "${rom_real,,}" == *.wsquashfs ) ]]; then
        wine_prefix="${WSQUASHFS_CACHE:-${HOME}/.cache/wsquashfs}/wine/$(basename "${rom_real}" .wsquashfs)"
    fi
    printf 'pid=%s\nprefix=%s\nrom=%s\n' "$$" "${wine_prefix}" "${rom_real}" > "${state}.tmp" \
        && mv -f "${state}.tmp" "${state}"
else
    rm -f "${state}"
fi
eval "exec ${wrapper}${cmd}"
