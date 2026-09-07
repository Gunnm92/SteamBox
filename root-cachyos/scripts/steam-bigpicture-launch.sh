#!/bin/bash
# "detached" de l'entrée Sunshine "Steam Big Picture" (apps.json) —
# jusque-là un simple "steam -gamepadui" inline, qui héritait du bus D-Bus
# de session PARTAGÉ ($XDG_RUNTIME_DIR/bus) entre wayland-0 (bureau visible)
# et wayland-1 (headless, où Steam tourne réellement).
#
# Symptôme (retour utilisateur, 07/09) : Steam Link se connecte mais montre
# un écran noir — le stream Sunshine/Moonlight lui-même fonctionne (il
# capture wayland-1 en direct via wlr-screencopy, jamais via ce mécanisme),
# mais Steam Link est un flux SÉPARÉ, propre à Steam, qui passe par
# xdg-desktop-portal + PipeWire (ScreenCast), pas par Sunshine.
#
# Cause confirmée en direct : le xdg-desktop-portal déjà en vie sur le bus
# partagé a démarré avec WAYLAND_DISPLAY=wayland-0 (lancé depuis
# wayland-session.sh, premier arrivé sur ce bus) — Steam, sur wayland-1,
# se retrouve donc à parler à un portail lié au MAUVAIS bureau. Pire :
# xdg-desktop-portal-wlr (le seul backend qui implémente vraiment
# ScreenCast sous labwc/wlroots — org.freedesktop.impl.portal.desktop.wlr,
# voir /usr/share/xdg-desktop-portal/portals/wlr.portal) plantait même à
# l'activation D-Bus (exit 1, immédiat) faute de WAYLAND_DISPLAY dans
# l'environnement d'activation du bus partagé — seul xdg-desktop-portal-gtk
# tournait, qui ne fait pas de vraie capture d'écran (écran noir).
#
# Isoler Steam sur son propre bus D-Bus privé (même mécanisme que
# sunshine-desktop-xfce.sh pour XFCE) avec WAYLAND_DISPLAY=wayland-1
# explicite règle les deux : xdg-desktop-portal ET -wlr démarrent frais sur
# CE bus, liés au bon compositeur — testé en direct, org.freedesktop.impl.
# portal.desktop.wlr s'active et reste vivant sans erreur dans ce contexte.
set -uo pipefail

export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:1
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

PIDFILE="${XDG_RUNTIME_DIR}/sunshine-steam-bigpicture.pid"

# Idempotent : Sunshine relance ce "detached" à chaque connexion à l'app
# "Steam Big Picture" — Steam lui-même refuse une deuxième instance (juste
# refocus), mais sans cette garde on empilerait un nouveau dbus-run-session
# (et donc un nouveau xdg-desktop-portal/-wlr redondant) à chaque fois.
if [ -f "${PIDFILE}" ] && kill -0 "$(cat "${PIDFILE}" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo "$$" > "${PIDFILE}"

exec dbus-run-session -- steam -gamepadui
