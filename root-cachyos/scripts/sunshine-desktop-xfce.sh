#!/bin/bash
# "detached" de l'entrée Sunshine "Desktop" (apps.json) — sans lui,
# svc-labwc-headless (wayland-1, cible de capture Sunshine) tourne nu :
# aucun panneau/bureau n'y est jamais lancé (contrairement à wayland-0, voir
# wayland-session.sh), donc "Desktop" sous Moonlight affichait un écran
# vide. Reprend le même panneau/bureau XFCE que la session visible pour une
# expérience identique en distant, mais lancé directement (pas de second
# labwc : svc-labwc-headless fournit déjà le compositeur).
set -uo pipefail

export WAYLAND_DISPLAY=wayland-1
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

PIDFILE="${XDG_RUNTIME_DIR}/sunshine-desktop-xfce.pid"

# Idempotent : Sunshine relance ce "detached" à chaque connexion à l'app
# "Desktop", pas seulement au premier lancement — sans cette garde, quitter
# puis rouvrir "Desktop" empile un second xfdesktop/xfce4-panel (même piège
# que documenté dans wayland-session.sh, audit M2).
if [ -f "${PIDFILE}" ] && kill -0 "$(cat "${PIDFILE}" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi

mkdir -p "${HOME}/.config" "${HOME}/.local/share"
cd "${HOME}"

xfsettingsd &
echo "$!" > "${PIDFILE}"

for i in $(seq 1 20); do
    xfconf-query -c xsettings -p /Net/ThemeName >/dev/null 2>&1 && break
    sleep 0.5
done
xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "Mc-OS-CTLina-XFCE-Dark" 2>/dev/null || true
xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s "Papirus-Dark" 2>/dev/null || true
xfconf-query -c xsettings -p /Gtk/FontName -n -t string -s "Cantarell 10" 2>/dev/null || true

# monitorHEADLESS-1 : nom réel de la sortie du labwc headless (confirmé via
# wlr-randr --output HEADLESS-1 dans set-resolution.sh), pas HDMI-A-1
# (connecteur réel utilisé côté wayland-0/bureau visible).
xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitorHEADLESS-1/workspace0/last-image" \
    -n -t string -s "/usr/share/backgrounds/xfce/xfce-cp-dark.svg" 2>/dev/null || true
xfconf-query -c xfce4-desktop -p "/backdrop/screen0/monitorHEADLESS-1/workspace0/image-style" \
    -n -t int -s 5 2>/dev/null || true
xfdesktop &
xfce4-panel &
nm-applet &
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

# Pas de `wait` ici : ces daemons sont autonomes (labwc headless, déjà
# supervisé par svc-labwc-headless, est leur vrai parent fonctionnel) —
# contrairement à wayland-session.sh qui attend labwc lui-même, ce script
# n'a qu'à les lancer une fois puis rendre la main à Sunshine.
disown -a
