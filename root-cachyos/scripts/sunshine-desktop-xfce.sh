#!/bin/bash
# "detached" de l'entrée Sunshine "Desktop" (apps.json) — sans lui,
# svc-labwc-headless (wayland-1, cible de capture Sunshine) tourne nu :
# aucun panneau/bureau n'y est jamais lancé (contrairement à wayland-0, voir
# wayland-session.sh), donc "Desktop" sous Moonlight affichait un écran
# vide.
#
# dbus-run-session obligatoire (confirmé en direct 06/09) : xfsettingsd/
# xfdesktop/xfce4-panel/nm-applet lancés en héritant simplement du bus de
# session existant ($XDG_RUNTIME_DIR/bus, svc-dbus-session) s'exécutaient
# bien mais se terminaient tout seuls en ~1s (exit 0, aucune erreur) —
# wayland-0 (bureau visible) ET wayland-1 (ce script) partagent le MÊME
# XDG_RUNTIME_DIR (même utilisateur arcade), donc le même bus de session :
# xfsettingsd y voit le nom D-Bus org.xfce.Xfconf déjà possédé par
# l'instance de wayland-0 et se considère redondant. Testé en isolant
# xfsettingsd sur un bus privé (dbus-run-session) : reste vivant sans
# problème — Wayland/X11 (WAYLAND_DISPLAY, DISPLAY) restent partagés sans
# souci, seul le bus D-Bus de SESSION doit être distinct par bureau XFCE.
set -uo pipefail

# Exports explicites plutôt que confiance dans l'héritage de l'environnement
# de Sunshine (même motif que set-resolution.sh) — Sunshine les positionne
# bien pour ses commandes "detached"/prep-cmd, mais ce projet a déjà été
# pris en défaut plusieurs fois par une variable supposée héritée qui ne
# l'était pas (voir historique wayland-session.sh).
export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:1
XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR

PIDFILE="${XDG_RUNTIME_DIR}/sunshine-desktop-xfce.pid"

# Idempotent : Sunshine relance ce "detached" à chaque connexion à l'app
# "Desktop", pas seulement au premier lancement. $$ est stable à travers le
# exec plus bas (remplace l'image du process sans changer son PID) : ce
# PID reste celui de dbus-run-session tant que la session XFCE tourne.
if [ -f "${PIDFILE}" ] && kill -0 "$(cat "${PIDFILE}" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo "$$" > "${PIDFILE}"

mkdir -p "${HOME}/.config" "${HOME}/.local/share"
cd "${HOME}" || exit 1

exec dbus-run-session -- bash -c '
xfsettingsd &
# Réglages par défaut seulement si absents (26/09, xfce-defaults.sh) : les
# forcer ici écrasait à chaque session Moonlight les choix de lutilisateur
# (police, fond) faits sur lun ou lautre bureau (même xfconf, même HOME).
/usr/local/bin/scripts/xfce-defaults.sh HEADLESS-1
xfdesktop &
xfce4-panel &
nm-applet &
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

wait
'
