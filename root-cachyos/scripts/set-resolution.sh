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
