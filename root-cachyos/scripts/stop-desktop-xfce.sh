#!/bin/bash
# Contrepartie "undo" de l'entrée apps.json "Desktop" (29/09) : même motif
# que stop-steam-bigpicture.sh. reset-resolution.sh seul laissait tourner la
# session XFCE lancée par sunshine-desktop-xfce.sh ("detached", jamais
# arrêtée par Sunshine) sur le compositeur headless (wayland-1) — quitter
# « Desktop » dans Moonlight puis lancer « Steam Big Picture » affichait le
# bureau, toujours là (constaté par l'utilisateur).
#
# Arrête l'arbre de processus de cette session (dbus-run-session et ses
# descendants : xfsettingsd, xfdesktop, xfce4-panel, nm-applet et ce qui a
# été lancé depuis le panneau), retrouvé par le fichier PID du script de
# lancement — jamais par nom : le bureau de la TV (wayland-0) fait tourner
# les mêmes programmes et ne doit pas être touché.
set -uo pipefail

/usr/local/bin/scripts/reset-resolution.sh

XDG_RUNTIME_DIR="/run/user/$(id -u)"
PIDFILE="${XDG_RUNTIME_DIR}/sunshine-desktop-xfce.pid"
[ -f "${PIDFILE}" ] || exit 0
ROOT_PID=$(cat "${PIDFILE}" 2>/dev/null)

# Descendants d'un PID (récursif), du plus profond au plus proche.
descendants() {
    local child
    for child in $(pgrep -P "$1" 2>/dev/null); do
        descendants "${child}"
        echo "${child}"
    done
}

if [ -n "${ROOT_PID}" ] && kill -0 "${ROOT_PID}" 2>/dev/null; then
    PIDS="$(descendants "${ROOT_PID}") ${ROOT_PID}"
    # shellcheck disable=SC2086  # liste de PID, découpage voulu
    kill -TERM ${PIDS} 2>/dev/null
    for _ in 1 2 3 4 5; do
        kill -0 "${ROOT_PID}" 2>/dev/null || break
        sleep 1
    done
    # shellcheck disable=SC2086
    kill -KILL ${PIDS} 2>/dev/null
fi
rm -f "${PIDFILE}"
exit 0
