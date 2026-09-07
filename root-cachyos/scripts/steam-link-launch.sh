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
# explicite règle ça — MAIS pas suffisant à lui seul (confirmé en direct,
# deuxième round de debug 07/09) : quand xdg-desktop-portal est activé
# automatiquement par D-Bus (Steam se contente d'appeler une méthode sur
# org.freedesktop.portal.Desktop, jamais de le lancer lui-même), il hérite
# de l'environnement du DÉMON D-Bus (celui que dbus-run-session vient de
# forker), pas de celui de Steam — XDG_CURRENT_DESKTOP doit donc être
# exporté ICI, avant dbus-run-session, sinon xdg-desktop-portal ne trouve
# aucun fichier de config portail (/etc/xdg-desktop-portal/xfce-portals.conf,
# voir Dockerfile.cachyos) et n'enregistre jamais l'interface ScreenCast du
# tout — confirmé par les logs Steam ("L'interface org.freedesktop.portal.
# ScreenCast n'existe pas") et par une introspection D-Bus directe. Testé en
# lançant xdg-desktop-portal à la main avec ces mêmes variables : "XDP:
# Using wlr.portal for org.freedesktop.impl.portal.ScreenCast (default
# config)" — la combinaison WAYLAND_DISPLAY + XDG_CURRENT_DESKTOP + le
# fichier de config est bien les trois pièces nécessaires ensemble.
set -uo pipefail

export WAYLAND_DISPLAY=wayland-1
export DISPLAY=:1
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_CURRENT_DESKTOP=XFCE

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
