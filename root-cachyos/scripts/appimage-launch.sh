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
# Si l'AppImage n'est pas installée, le message dit quoi installer et sort en
# erreur, au lieu d'un échec silencieux.
set -u

app="$(basename "$0")"
case "${app}" in
    ppsspp)                          name="PPSSPP" ;;
    flycast)                         name="Flycast" ;;
    cemu)                            name="Cemu" ;;
    pcsx2)                           name="PCSX2" ;;
    pcsx2x6)                         name="PCSX2x6" ;;
    rpcs3)                           name="RPCS3" ;;
    melonDS)                         name="melonDS" ;;
    eden)                            name="Eden Nightly" ;;
    lindbergh)                       name="Lindbergh Loader" ;;
    duckstation|duckstation-qt)      name="DuckStation" ;;
    xemu)                            name="Xemu" ;;
    vita3k)                          name="Vita3K" ;;
    xenia)                           name="Xenia" ;;
    shadps4)                         name="ShadPS4" ;;
    steam-rom-manager)               name="Steam ROM Manager" ;;
    retroarch)                       name="RetroArch" ;;
    dolphin-emu)                     name="Dolphin Emulator" ;;
    scummvm)                         name="ScummVM" ;;
    supermodel)                      name="Supermodel" ;;
    heroic)                          name="Heroic Games Launcher" ;;
    *) echo "appimage-launch : lanceur inconnu « ${app} »" >&2; exit 2 ;;
esac

apps_dir="${HOME}/Applications"
for candidate in "${apps_dir}/${name}" "${apps_dir}/${name}.AppImage"; do
    if [ -f "${candidate}" ]; then
        exec "${candidate}" "$@"
    fi
done

echo "${name} n'est pas installée dans ${apps_dir}." >&2
echo "Installe-la avec AppManager (fichier AppImage → Installer)." >&2
exit 1
