#!/bin/bash
# Raccourci de bureau/menu "Steam (Steam Link)" — indépendant de l'entrée
# Sunshine "Steam Big Picture" (apps.json), volontairement laissée telle
# quelle : elle fonctionne déjà bien pour jouer via Moonlight. Ce script
# répond à un besoin différent (demande utilisateur, 07/09) : pouvoir
# utiliser Steam Link EN PLUS de Moonlight (meilleur support manette dans
# certains cas), donc lancer Steam sur le compositeur headless (wayland-1)
# d'une manière compatible avec le flux vidéo propre à Steam Link.
#
# ÉTAT CONNU (07/09) : la connexion Steam Link, l'audio et le protocole de
# stream fonctionnent (bitrate adaptatif, pas de perte de frames anormale —
# confirmé en direct dans les logs Steam), mais le JEU s'affiche en écran
# noir côté client Steam Link (l'overlay Steam, lui, s'affiche
# correctement). Deux approches essayées, même résultat final :
#   - Cette version (portail XDG + PipeWire, voir ci-dessous) : ScreenCast
#     s'enregistre bien après les deux correctifs listés plus bas, mais le
#     buffer GPU (dmabuf) du contenu 3D du jeu ne s'importe pas — limitation
#     documentée de xdg-desktop-portal-wlr avec le pilote propriétaire
#     NVIDIA (projet peu maintenu, surtout testé contre Mesa/AMD/Intel).
#   - Alternative essayée : lancer Steam DANS gamescope (comme "Mode
#     SteamOS", qui a sa propre capture native pour Remote Play/Steam Link,
#     sans passer par le portail) — MÊME résultat, écran noir, confirmé en
#     direct par l'utilisateur. Sunshine/Moonlight, qui capture wayland-1
#     directement via wlr-screencopy (jamais via un chemin PipeWire tiers),
#     fonctionne bien lui, y compris avec gamescope ("Mode SteamOS" marche
#     normalement via Moonlight, confirmé). Le point commun des deux échecs
#     pointe vers quelque chose de plus profond que le portail seul : le
#     backend headless de labwc + NVIDIA semble incapable de fournir des
#     pixels exploitables à quiconque capture autrement que Sunshine
#     lui-même. Piste non explorée faute de temps : forcer un vrai backend
#     DRM plutôt que headless pour gamescope, ou inspecter les logs
#     Vulkan/EGL au moment précis de la capture PipeWire.
#
# Décision utilisateur (07/09) : laissé de côté pour l'instant (Moonlight
# répond au besoin de jeu ; Steam Link reste ouvert pour naviguer la
# bibliothèque/discuter, juste pas pour streamer un jeu). Ce script garde
# la version la plus stable des deux essais (celle-ci ne plante jamais,
# contrairement à la variante gamescope qui a produit une erreur Vulkan
# "vkCreateComputePipelines failed"/NVVM lors des tests en CLI — non
# reproduite via une vraie connexion Sunshine, cause non élucidée).
#
# Steam Link est un flux SÉPARÉ de Sunshine/Moonlight, propre à Steam : il
# passe par xdg-desktop-portal + PipeWire (ScreenCast), jamais par
# wlr-screencopy (ce que Sunshine utilise directement). Deux correctifs
# nécessaires ensemble pour que ScreenCast s'enregistre correctement
# (testés en direct, confirmés par introspection D-Bus ET logs Steam sans
# erreur de portail) :
#   1. Isoler Steam sur son propre bus D-Bus (WAYLAND_DISPLAY=wayland-1),
#      sinon xdg-desktop-portal reste lié à wayland-0 (lancé en premier par
#      wayland-session.sh sur le bus partagé) — Steam parle alors à un
#      portail lié au mauvais bureau, ou pire, xdg-desktop-portal-wlr
#      plante à l'activation D-Bus faute de WAYLAND_DISPLAY dans
#      l'environnement d'activation du bus partagé.
#   2. XDG_CURRENT_DESKTOP=XFCE exporté explicitement avant
#      dbus-run-session — quand xdg-desktop-portal est activé par D-Bus
#      (Steam appelle une méthode, ne le lance jamais lui-même), il hérite
#      de l'environnement du démon D-Bus tout juste forké, pas forcément de
#      celui de Steam. Sans cette variable, xdg-desktop-portal ne trouve
#      aucun fichier de config portail
#      (/etc/xdg-desktop-portal/xfce-portals.conf, voir Dockerfile.cachyos)
#      et n'enregistre jamais l'interface ScreenCast du tout.
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
