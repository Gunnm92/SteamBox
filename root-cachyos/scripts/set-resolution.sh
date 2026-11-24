#!/bin/bash
# Résolution dynamique (30/08) — appelé par Sunshine comme prep-cmd "do" à la
# connexion d'un client Moonlight : ajuste la sortie du labwc HEADLESS
# (wayland-1, voir svc-labwc-stream) à la résolution/fréquence réellement
# demandée par CE client, via SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS que Sunshine
# positionne pour les prep-cmd. Sans ça, le headless reste bloqué sur son
# mode par défaut (1280x720, confirmé en direct) quel que soit le client —
# c'est ce qui donnait une image "bizarre" (upscale/mauvais ratio) côté
# Moonlight. Pattern repris de github.com/daaaaan/sunshine-headless-sway
# (swaymsg là-bas, wlr-randr ici pour labwc — même protocole standard
# wlr-output-management sous-jacent, wlr-randr fonctionne avec n'importe
# quel compositeur wlroots qui l'implémente, pas seulement Sway).
set -uo pipefail

WIDTH="${SUNSHINE_CLIENT_WIDTH:-1920}"
HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1080}"
FPS="${SUNSHINE_CLIENT_FPS:-60}"

export WAYLAND_DISPLAY=wayland-1
XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR

# Trace des valeurs recues (audit B6, 31/08) : le repli silencieux sur
# 1920x1080 quand Sunshine ne fournit pas SUNSHINE_CLIENT_* a deja coute
# une session de debug ("fige sur 1920" alors que le prep-cmd ne tournait
# simplement pas) — une ligne de log leve l'ambiguite immediatement.
# Sortie détectée (22/11) : HEADLESS-1 en headless, HDMI-A-1 quand labwc
# pilote le dongle HDMI en DRM (capture KMS, HDR). En DRM, le pilote NVIDIA
# refuse tout mode absent de l'EDID du dongle (modes sur mesure essayés le
# 22/11 : refusés) : définition choisie parmi les siennes par fit_resolution
# (la plus grande qui tient dans celle du client), puis la fréquence la plus
# proche.
# shellcheck source=steambox-env.sh
. /usr/local/bin/scripts/steambox-env.sh

# kwin_set_resolution (24/11, phase 1 KWin) : sous le KWin de streaming
# (stream_compositor = kwin), wlr-randr ne sert à rien — la sortie se règle
# par kscreen-doctor, qui parle au KWin par D-Bus : il faut donc la session
# (stream_session_env : bus-stream, DISPLAY, WAYLAND_DISPLAY). kscreen-doctor
# veut l'id du mode (« output.<sortie>.mode.<id> ») : le nom « LxH@F.00 » est
# refusé (essai du 24/11). Mêmes règles que la branche labwc : définition
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
    info=$(kscreen-doctor -o 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
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
    out=$(kscreen-doctor "output.${output}.mode.${modeid}" "output.${output}.scale.1" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
    {
        echo "[$(date '+%F %T')] client=${WIDTH}x${HEIGHT}@${FPS} -> ${mode} sur ${output} (kscreen-doctor)"
        echo "${out}"
    } >>/tmp/set-resolution.log
    return 0
}

if [[ "$(stream_compositor)" == kwin ]]; then
    kwin_set_resolution
    exit 0
fi

OUTPUT=$(wlr-randr 2>/dev/null | awk '/^[^ ]/ {print $1; exit}')
OUTPUT="${OUTPUT:-HEADLESS-1}"

# best_mode : « LxH@fréquence » listé par wlr-randr pour la définition
# retenue ($1), fréquence la plus proche de FPS (vide si aucune).
best_mode() {
    wlr-randr --output "${OUTPUT}" 2>/dev/null | awk -v res="$1" -v fps="${FPS}" '
        $1 == res && $2 == "px," {
            r = $3 + 0; d = r - fps; if (d < 0) d = -d
            if (best == "" || d < bestd) { best = $3; bestd = d }
        }
        END { if (best != "") print res "@" best }'
}

{
    echo "[$(date '+%F %T')] client=${SUNSHINE_CLIENT_WIDTH:-ABSENT}x${SUNSHINE_CLIENT_HEIGHT:-ABSENT}@${SUNSHINE_CLIENT_FPS:-ABSENT} -> applique ${WIDTH}x${HEIGHT}@${FPS}Hz sur ${OUTPUT}"
    case "${OUTPUT}" in
        HEADLESS-*)
            wlr-randr --output "${OUTPUT}" --custom-mode "${WIDTH}x${HEIGHT}@${FPS}Hz" 2>&1 ;;
        *)
            RES=$(wlr-randr --output "${OUTPUT}" 2>/dev/null | awk '$2 == "px," {print $1}' | sort -u | fit_resolution "${WIDTH}" "${HEIGHT}")
            MODE=$(best_mode "${RES}")
            [ "${RES}" = "${WIDTH}x${HEIGHT}" ] || echo "${WIDTH}x${HEIGHT} absent des modes de ${OUTPUT} : ${RES} retenu"
            wlr-randr --output "${OUTPUT}" --mode "${MODE}Hz" 2>&1 ;;
    esac
} >>/tmp/set-resolution.log
