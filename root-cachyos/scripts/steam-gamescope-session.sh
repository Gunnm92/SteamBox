#!/bin/bash
# prep-cmd Sunshine de « Mode SteamOS (Gamescope) » (22/11) :
#   start (do)   : avant la session ;
#   stop  (undo) : à la fermeture de l'appli.
#
# Dongle HDMI branché (steambox-stream-output non vide, voir
# svc-labwc-stream) : gamescope pilote seul la sortie en DRM, avec le HDR
# (steam-gamescope-launch.sh --stream). start arrête le labwc de Sunshine
# pour libérer la sortie — un seul maître DRM à la fois — et stop ferme
# Steam et gamescope puis relance labwc pour les autres applis (Desktop,
# EmulationStation, Big Picture). Sunshine capture la sortie en KMS dans les
# deux cas, sans changer de méthode.
# Sans dongle (headless) : comportement d'avant, gamescope niché dans le
# labwc headless, résolution réglée par set-resolution.sh / reset.
set -uo pipefail

RUNTIME="/run/user/$(id -u)"
SVC=/run/service/svc-labwc-stream
CONNECTOR=$(cat "${RUNTIME}/steambox-stream-output" 2>/dev/null)

case "${1:-}" in
start)
    [ -n "${CONNECTOR}" ] || exec /usr/local/bin/scripts/set-resolution.sh
    /command/s6-svc -d "${SVC}"
    # Sortie libérée seulement une fois labwc réellement arrêté.
    /command/s6-svwait -D -t 15000 "${SVC}"
    ;;
stop)
    [ -n "${CONNECTOR}" ] || exec /usr/local/bin/scripts/reset-resolution.sh
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
