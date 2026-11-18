#!/bin/bash
# Réglages XFCE par défaut (thème, icônes, police, fond d'écran), appliqués
# SEULEMENT s'ils ne sont pas déjà réglés (26/09) — avant, le bureau visible
# et le bureau Moonlight les réécrivaient à chaque démarrage : un changement
# de police ou de fond fait par l'utilisateur était perdu au redémarrage
# suivant (vu en direct : dossier du fond d'écran en défilement, police).
#
# Usage : xfce-defaults.sh <sortie> [-- <commande...>]
#   <sortie>    : nom du moniteur pour le fond (HDMI-A-1 bureau visible,
#                 HEADLESS-1 bureau Moonlight)
#   <commande>  : exécutée à la place de ce script ensuite (ex. xfsettingsd)
#
# Réglages dans xfconf, pas seulement gtk-3.0/settings.ini : une fois
# xfsettingsd démarré, c'est LUI l'autorité (protocole XSETTINGS), il écrase
# settings.ini. xfconfd est activé par D-Bus : xfconf-query suffit, sans
# attendre xfsettingsd.
set -uo pipefail

output="${1:?usage: xfce-defaults.sh <sortie> [-- commande...]}"
shift
[[ "${1:-}" == "--" ]] && shift

# xfconfd joignable ? (bus de session tout juste démarré au boot)
for _ in $(seq 1 20); do
    xfconf-query -c xsettings -l >/dev/null 2>&1 && break
    sleep 0.5
done

# set_default <canal> <propriété> <type> <valeur> : n'écrit que si absente.
set_default() {
    xfconf-query -c "$1" -p "$2" >/dev/null 2>&1 && return 0
    xfconf-query -c "$1" -p "$2" -n -t "$3" -s "$4" 2>/dev/null || true
}

set_default xsettings /Net/ThemeName string "WhiteSur-Dark"
set_default xsettings /Net/IconThemeName string "WhiteSur-dark"
set_default xsettings /Gtk/CursorThemeName string "WhiteSur-cursors"
# Taille du curseur (18/11) : xfsettingsd lit /Gtk/CursorThemeSize (pas
# /Gtk/CursorSize, réglé ici jusqu'au 18/11 et ignoré) et la recopie dans
# dconf (org.gnome.desktop.interface cursor-size). Restée vide (type
# "empty") : cursor-size=0, et la GTK3 embarquée par les AppImage
# Tauri/WebKitGTK (fefw-launcher) n'arrivait plus à charger le thème
# ("Failed to load cursor theme"), puis plantait sous Wayland au survol de
# la fenêtre (assertion cursor_theme_name). Vide ou 0 : reprend l'ancienne
# clé, sinon 24 ; une taille choisie par l'utilisateur est gardée.
size=$(xfconf-query -c xsettings -p /Gtk/CursorThemeSize 2>/dev/null || true)
if ! [[ "${size}" =~ ^[1-9][0-9]*$ ]]; then
    size=$(xfconf-query -c xsettings -p /Gtk/CursorSize 2>/dev/null || true)
    [[ "${size}" =~ ^[1-9][0-9]*$ ]] || size=24
    xfconf-query -c xsettings -p /Gtk/CursorThemeSize -r 2>/dev/null || true
    xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s "${size}" 2>/dev/null || true
fi
xfconf-query -c xsettings -p /Gtk/CursorSize -r 2>/dev/null || true
set_default xsettings /Gtk/FontName string "Cantarell 10"
set_default xsettings /Gtk/MonospaceFontName string "JetBrains Mono 10"
# Police Nerd retirée de l'image (29/09, ttf-jetbrains-mono-nerd → 232 Mo) :
# un réglage déjà enregistré sur l'ancienne police est basculé sur la
# nouvelle, sans toucher à un autre choix de l'utilisateur.
case "$(xfconf-query -c xsettings -p /Gtk/MonospaceFontName 2>/dev/null)" in
    "JetBrainsMono Nerd Font"*)
        xfconf-query -c xsettings -p /Gtk/MonospaceFontName -s "JetBrains Mono 10" 2>/dev/null || true ;;
esac

# Fond : clé du moniteur réel, celle que lit xfdesktop (le dialogue
# "Réglages du bureau" a parfois écrit sous monitorUnknown, vu le 30/08).
backdrop="/backdrop/screen0/monitor${output}/workspace0"
if ! xfconf-query -c xfce4-desktop -p "${backdrop}/last-image" >/dev/null 2>&1; then
    set_default xfce4-desktop "${backdrop}/last-image" string "/usr/share/backgrounds/xfce/xfce-cp-dark.svg"
    set_default xfce4-desktop "${backdrop}/image-style" int 5
fi

# Greffon son du panneau (18/11) : xfce4-pulseaudio-plugin est dans l'image,
# mais le panneau par défaut de XFCE ne l'a pas — pas d'icône de volume,
# même en stream Moonlight. Inséré UNE fois, juste après la zone de
# notification (systray) ; le marqueur évite de le remettre si
# l'utilisateur l'a retiré. Pas encore de panneau (premier démarrage, créé
# par xfce4-panel lui-même) : réessayé au démarrage suivant.
pa_marker="${HOME}/.config/xfce4/.steambox-pulseaudio-plugin"
if [ ! -e "${pa_marker}" ]; then
    plugins=$(xfconf-query -c xfce4-panel -l -v 2>/dev/null | awk '$1 ~ /^\/plugins\/plugin-[0-9]+$/ { sub(/.*-/, "", $1); print $1, $2 }')
    systray=$(awk '$2 == "systray" { print $1; exit }' <<<"${plugins}")
    if awk '$2 == "pulseaudio" { f = 1 } END { exit !f }' <<<"${plugins}"; then
        touch "${pa_marker}"
    elif [ -n "${systray}" ]; then
        new=$(( $(awk '$1 > m { m = $1 } END { print m + 0 }' <<<"${plugins}") + 1 ))
        for panel in $(xfconf-query -c xfce4-panel -p /panels 2>/dev/null | grep -E '^[0-9]+$'); do
            ids=$(xfconf-query -c xfce4-panel -p "/panels/panel-${panel}/plugin-ids" 2>/dev/null | grep -E '^[0-9]+$')
            grep -qx "${systray}" <<<"${ids}" || continue
            args=()
            for id in ${ids}; do
                args+=(-t int -s "${id}")
                [ "${id}" = "${systray}" ] && args+=(-t int -s "${new}")
            done
            xfconf-query -c xfce4-panel -p "/plugins/plugin-${new}" -n -t string -s pulseaudio \
                && xfconf-query -c xfce4-panel -p "/panels/panel-${panel}/plugin-ids" --force-array "${args[@]}" \
                && touch "${pa_marker}"
            break
        done
    fi
fi
# Volume plafonné à 100 % (18/11) : le greffon monte jusqu'à 150 % par
# défaut (molette sur l'icône, touches multimédia qu'il intercepte) et
# WirePlumber mémorise le volume par sortie — la sortie 5.1 de Sunshine
# restait à 150 % (+10,6 dB) : son saturé, « basse résolution », dans
# Moonlight. Seulement si absent : un autre plafond choisi est gardé.
for pa in $(xfconf-query -c xfce4-panel -l -v 2>/dev/null | awk '$1 ~ /^\/plugins\/plugin-[0-9]+$/ && $2 == "pulseaudio" { print $1 }'); do
    set_default xfce4-panel "${pa}/volume-max" int 100
done

if [[ $# -gt 0 ]]; then
    exec "$@"
fi
