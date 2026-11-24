#!/bin/bash
# prep-cmd Sunshine de « Mode SteamOS (Gamescope) » (22/11) :
#   start (do)   : avant la session ;
#   stop  (undo) : à la fermeture de l'appli.
#
# Dongle HDMI (steambox-stream-output, voir svc-kwin-stream ; obligatoire
# depuis le 24/11) : gamescope pilote seul la sortie en DRM, avec le HDR
# (steam-gamescope-launch.sh --stream). start arrête le KWin de streaming
# pour libérer la sortie — un seul maître DRM à la fois — et stop ferme
# Steam et gamescope puis relance KWin pour les autres applis (Desktop,
# EmulationStation, Big Picture). Sunshine capture la sortie en KMS dans les
# deux cas, sans changer de méthode.
# start lance aussi gamescope et attend qu'il affiche une image sur la sortie
# (23/11) : Sunshine démarre la capture KMS dès la fin du prep-cmd, ~1 s
# après avoir lancé l'appli ; gamescope n'avait pas encore allumé la sortie
# → « Couldn't find monitor [0] », la première connexion échouait à chaque
# fois (la suivante marchait, gamescope tournant déjà). La commande
# « detached » de l'appli (steam-gamescope-launch.sh --stream) ne fait alors
# plus rien, gamescope étant déjà là.
# Sans dongle il n'y a pas de Sunshine, donc pas de prep-cmd : sortie 0.
set -uo pipefail

RUNTIME="/run/user/$(id -u)"
# Sous KWin (24/11), Sunshine passe à ses prep-cmd le bus bus-stream et
# XDG_CURRENT_DESKTOP=KDE : or start arrête ce KWin, et Steam (portail vers un
# wayland-stream mort) ne doit rien en hériter. Bus du bureau (Plasma, 24/11 ;
# XFCE avant). Tout ce que lance cette session le reprend.
export DBUS_SESSION_BUS_ADDRESS="unix:path=${RUNTIME}/bus"
export XDG_CURRENT_DESKTOP=KDE
SVC=/run/service/svc-kwin-stream
CONNECTOR=$(cat "${RUNTIME}/steambox-stream-output" 2>/dev/null)

case "${1:-}" in
start)
    [ -n "${CONNECTOR}" ] || exit 0
    /command/s6-svc -d "${SVC}"
    # Sortie libérée seulement une fois KWin réellement arrêté.
    /command/s6-svwait -D -t 15000 "${SVC}"
    # shellcheck source=steambox-env.sh
    . /usr/local/bin/scripts/steambox-env.sh
    read -r CARD _ CONN_SYS <<<"$(stream_drm_card)"
    FB_CHECK=(python3 /usr/local/bin/scripts/drm-output-fb.py "${CARD}" "${CONN_SYS}")
    # Image restée sur la sortie après KWin (console fbdev) : gamescope est
    # prêt quand une autre image s'affiche.
    BEFORE=$("${FB_CHECK[@]}" 2>/dev/null || echo 0)
    if ! pgrep -x gamescope-wl >/dev/null; then
        # setsid : hors du groupe de processus du prep-cmd ; journal à part
        # (la sortie du prep-cmd est fermée par Sunshine à sa fin).
        setsid -f /usr/local/bin/scripts/steam-gamescope-launch.sh --stream \
            >"${RUNTIME}/steam-gamescope.log" 2>&1 </dev/null
    fi
    SECONDS=0
    while [ "${SECONDS}" -lt 20 ]; do
        FB=$("${FB_CHECK[@]}" 2>/dev/null || echo 0)
        if [ "${FB}" != 0 ] && [ "${FB}" != "${BEFORE}" ]; then
            exit 0
        fi
        sleep 0.2
    done
    echo "[steam-gamescope-session] ${CONN_SYS##*/} toujours sans image de gamescope après 20 s (voir ${RUNTIME}/steam-gamescope.log)" >&2
    ;;
stop)
    [ -n "${CONNECTOR}" ] || exit 0
    # Steam d'abord (sauvegarde de son état), puis gamescope : il ignore
    # SIGTERM une fois Steam fermé (vu en direct), d'où le SIGKILL.
    if pgrep -x steam >/dev/null; then
        XDG_RUNTIME_DIR="${RUNTIME}/gamescope-session" timeout 20 steam -shutdown >/dev/null 2>&1
        for _ in $(seq 1 25); do
            pgrep -x steam >/dev/null || break
            sleep 1
        done
    fi
    pkill -TERM -x gamescope-wl 2>/dev/null
    for _ in $(seq 1 5); do
        pgrep -x gamescope-wl >/dev/null || break
        sleep 1
    done
    pkill -KILL -x gamescope-wl 2>/dev/null
    /command/s6-svc -u "${SVC}"
    ;;
*)
    echo "usage : $0 start|stop" >&2
    exit 2
    ;;
esac
