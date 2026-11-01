#!/bin/bash
# SteamBox — Lanceur commun des AppImage installées par AppManager.
#
# Les émulateurs ne sont plus dans l'image : ils vivent dans ~/Applications,
# rangés par AppManager (donc dans /config, persistant). Ce script est lancé
# par des liens du même nom dans /usr/local/bin (ppsspp, pcsx2, rpcs3…) : il
# lit son propre nom ($0), cherche l'AppImage correspondante et la lance avec
# les arguments reçus. Les scripts de jeux et apps.json n'ont donc pas à
# connaître le nom exact du fichier, qui peut changer à chaque mise à jour.
#
# Noms acceptés : AppManager nomme le fichier d'après l'AppImage, avec la
# casse et le suffixe de l'éditeur (« shadPS4 », « Xenia Canary », vus le
# 01/11) — comparaison sans tenir compte de la casse, avec ou sans
# .AppImage, et plusieurs noms possibles par émulateur.
#
# Si l'AppImage n'est pas installée, le message dit quoi installer et sort en
# erreur. Lancé depuis EmulationStation, game-launch.sh envoie la sortie dans
# un journal : le message passe donc par launch_error (code 250), qu'ES
# affiche dans une boîte d'erreur (voir launch-error.sh).
set -u
# shellcheck source=launch-error.sh
. /usr/local/bin/scripts/launch-error.sh

app="$(basename "$0")"
case "${app}" in
    ppsspp)                          names=("PPSSPP") ;;
    flycast)                         names=("Flycast") ;;
    cemu)                            names=("Cemu") ;;
    pcsx2)                           names=("PCSX2") ;;
    pcsx2x6)                         names=("PCSX2x6") ;;
    rpcs3)                           names=("RPCS3") ;;
    melonDS)                         names=("melonDS") ;;
    eden)                            names=("Eden Nightly" "Eden") ;;
    lindbergh)                       names=("Lindbergh Loader") ;;
    duckstation|duckstation-qt)      names=("DuckStation") ;;
    xemu)                            names=("Xemu") ;;
    vita3k)                          names=("Vita3K") ;;
    xenia)                           names=("Xenia Canary" "Xenia") ;;
    shadps4)                         names=("shadPS4") ;;
    steam-rom-manager)               names=("Steam ROM Manager") ;;
    retroarch)                       names=("RetroArch") ;;
    dolphin-emu)                     names=("Dolphin Emulator" "Dolphin") ;;
    scummvm)                         names=("ScummVM") ;;
    supermodel)                      names=("Supermodel") ;;
    heroic)                          names=("Heroic Games Launcher" "Heroic") ;;
    *) echo "appimage-launch : lanceur inconnu « ${app} »" >&2; exit 2 ;;
esac

apps_dir="${HOME}/Applications"
for name in "${names[@]}"; do
    want="${name,,}"
    for candidate in "${apps_dir}"/*; do
        [ -f "${candidate}" ] || continue
        file="${candidate##*/}"
        file="${file,,}"
        if [ "${file}" = "${want}" ] || [ "${file}" = "${want}.appimage" ]; then
            exec "${candidate}" "$@"
        fi
    done
done

launch_error "${names[0]} n'est pas installée dans ${apps_dir}. Installe-la avec AppManager (fichier AppImage → Installer)."
