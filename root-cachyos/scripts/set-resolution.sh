#!/bin/bash
# Résolution dynamique (30/08) — appelé par Sunshine comme prep-cmd "do" à la
# connexion d'un client Moonlight : règle la sortie du KWin de streaming
# (wayland-stream, svc-kwin-stream, dongle HDMI en DRM) sur la résolution et
# la fréquence demandées par CE client (SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS,
# positionnés par Sunshine pour les prep-cmd). Historique : wlr-randr sur le
# labwc headless jusqu'au 24/11 ; KWin seul depuis (labwc retiré).
set -uo pipefail

WIDTH="${SUNSHINE_CLIENT_WIDTH:-1920}"
HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1080}"
FPS="${SUNSHINE_CLIENT_FPS:-60}"

XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR
export WAYLAND_DISPLAY="${XDG_RUNTIME_DIR}/stream/wayland-stream"

# Trace des valeurs recues (audit B6, 31/08) : le repli silencieux sur
# 1920x1080 quand Sunshine ne fournit pas SUNSHINE_CLIENT_* a deja coute
# une session de debug ("fige sur 1920" alors que le prep-cmd ne tournait
# simplement pas) — une ligne de log leve l'ambiguite immediatement.
# Le pilote NVIDIA refuse en DRM tout mode absent de l'EDID du dongle (modes
# sur mesure essayés le 22/11 : refusés) : définition choisie parmi les
# siennes par fit_resolution (la plus grande qui tient dans celle du
# client), puis la fréquence la plus proche.
# shellcheck source=steambox-env.sh
. /usr/local/bin/scripts/steambox-env.sh

# kwin_set_resolution (24/11, phase 1 KWin) : la sortie se règle
# par kscreen-doctor, qui parle au KWin par D-Bus : il faut donc la session
# (stream_session_env : bus-stream, DISPLAY, WAYLAND_DISPLAY). kscreen-doctor
# veut l'id du mode (« output.<sortie>.mode.<id> ») : le nom « LxH@F.00 » est
# refusé (essai du 24/11). Définition
# retenue par fit_resolution, puis fréquence la plus proche de FPS. Échec
# (pas de session, pas de sortie, mode absent) : journalisé et sortie 0, le
# stream reste à la résolution courante — un code d'erreur empêcherait le
# lancement de l'appli (prep-cmd Sunshine).
kwin_set_resolution() {
    local info output modes res best mode modeid out
    if ! stream_session_env; then
        echo "[$(date '+%F %T')] KWin : pas de session de streaming (steambox-stream-session.env absent), résolution inchangée" >>/tmp/set-resolution.log
        return 0
    fi
    info=$(timeout 10 kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    # 3e champ de la ligne « Output: <n> <nom> <uuid> »
    output=$(awk '/^Output:/ {print $3; exit}' <<<"${info}")
    if [[ -z "${output}" ]]; then
        echo "[$(date '+%F %T')] KWin : aucune sortie listée par kscreen-doctor, résolution inchangée" >>/tmp/set-resolution.log
        return 0
    fi
    # Ligne « Modes: » : éléments « id:LxH@F » (* = actuel, ! = préféré, à
    # retirer). Sortie « LxH@F id », une par mode.
    modes=$(awk '/Modes:/ { for (i = 2; i <= NF; i++) { gsub(/[*!]/, "", $i); split($i, m, ":"); print m[2], m[1] } }' <<<"${info}")
    res=$(cut -d' ' -f1 <<<"${modes}" | cut -d@ -f1 | sort -u | fit_resolution "${WIDTH}" "${HEIGHT}")
    best=$(awk -v res="${res}" -v fps="${FPS}" '
        { split($1, m, "@") }
        m[1] == res { d = m[2] - fps; if (d < 0) d = -d; if (pick == "" || d < bd) { pick = $0; bd = d } }
        END { print pick }' <<<"${modes}")
    read -r mode modeid <<<"${best}"
    if [[ -z "${modeid}" ]]; then
        echo "[$(date '+%F %T')] client=${WIDTH}x${HEIGHT}@${FPS} : aucun mode utilisable sur ${output} (kscreen-doctor), résolution inchangée" >>/tmp/set-resolution.log
        return 0
    fi
    # Sortie de kscreen-doctor journalisée : une erreur D-Bus ou un refus du
    # KWin y est visible sans rejouer le script.
    out=$(timeout 10 kscreen-doctor "output.${output}.mode.${modeid}" "output.${output}.scale.1" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    {
        echo "[$(date '+%F %T')] client=${WIDTH}x${HEIGHT}@${FPS} -> ${mode} sur ${output} (kscreen-doctor)"
        echo "${out}"
    } >>/tmp/set-resolution.log
    return 0
}

# Sans dongle (stream_compositor vide), il n'y a ni KWin ni Sunshine : la
# fonction le journalise (pas de session) et sort 0.
kwin_set_resolution
