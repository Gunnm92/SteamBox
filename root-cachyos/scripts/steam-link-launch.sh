#!/bin/bash
# Raccourci de bureau/menu "Steam (Steam Link)" — indépendant de l'entrée
# Sunshine "Steam Big Picture" (apps.json), volontairement laissée telle
# quelle : elle fonctionne déjà bien pour jouer via Moonlight. Ce script
# répond à un besoin différent (demande utilisateur, 07/09) : pouvoir
# utiliser Steam Link EN PLUS de Moonlight (meilleur support manette dans
# certains cas), donc lancer Steam sur le compositeur headless (wayland-1)
# d'une manière compatible avec le flux vidéo propre à Steam Link.
#
# Steam Link est un flux SÉPARÉ de Sunshine/Moonlight, propre à Steam : il
# passe par xdg-desktop-portal + PipeWire (ScreenCast), jamais par
# wlr-screencopy (ce que Sunshine utilise). Symptôme confirmé en direct :
# la connexion Steam Link elle-même passait, mais lancer un JEU affichait
# l'erreur Steam demandant l'option -pipewire — déjà appliquée en réalité
# (wrapper /usr/local/bin/steam) ; le vrai souci est que le xdg-desktop-
# portal déjà vivant sur le bus D-Bus de session PARTAGÉ (avec wayland-0,
# le bureau visible) a démarré avec WAYLAND_DISPLAY=wayland-0 (lancé par
# wayland-session.sh, premier arrivé) — Steam sur wayland-1 se retrouvait à
# parler à un portail lié au MAUVAIS bureau. Pire : xdg-desktop-portal-wlr
# (seul backend à implémenter vraiment ScreenCast sous labwc/wlroots —
# org.freedesktop.impl.portal.desktop.wlr, voir /usr/share/xdg-desktop-
# portal/portals/wlr.portal) plantait même à l'activation D-Bus (exit 1
# immédiat) faute de WAYLAND_DISPLAY dans l'environnement d'activation du
# bus partagé — seul xdg-desktop-portal-gtk tournait, qui ne fait pas de
# vraie capture (d'où l'échec au lancement du jeu malgré une connexion
# Steam Link apparemment fonctionnelle).
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

PIDFILE="${XDG_RUNTIME_DIR}/steam-link-launch.pid"

# Idempotent : un double-clic sur le raccourci (ou un second lancement
# pendant que Steam tourne déjà) ne doit pas empiler un nouveau
# dbus-run-session (et donc un xdg-desktop-portal/-wlr redondant) — Steam
# lui-même refuse une deuxième instance et se contente de refocus.
if [ -f "${PIDFILE}" ] && kill -0 "$(cat "${PIDFILE}" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo "$$" > "${PIDFILE}"

exec dbus-run-session -- steam -gamepadui
