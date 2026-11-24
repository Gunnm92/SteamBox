#!/bin/bash
# Entrée Sunshine « Steam Big Picture » (22/11, contournement) : Steam
# gamepadui directement sur le compositeur de streaming (labwc headless à l'époque, wayland-1 / Xwayland :1),
# avec le pilote x11 de Wine imposé aux jeux qu'il lance.
#
# Wine 11 (wine-tkg, jeux .wsquashfs) choisit son pilote Wayland
# (winewayland) dès qu'un compositeur répond : le jeu s'ouvre en fenêtre
# Wayland native sur wayland-1. Steam, client X11, ne voit pas cette fenêtre
# et ne sait pas que le jeu est au premier plan : Big Picture continue de
# naviguer à la manette pendant la partie (sons de navigation en fond), même
# réduit et sans focus — vérifié en direct, aucun réglage côté fenêtres ne
# le corrige. En X11, Steam reconnaît la fenêtre du jeu et coupe sa
# navigation lui-même. Prix : les .wsquashfs perdent l'affichage Wayland
# natif dans cette session seulement (bureau inchangé). Les jeux Proton
# sont déjà en X11 par défaut ; WINEDLLOVERRIDES est complété, jamais
# remplacé (wsquashfs-launcher et Proton y ajoutent leurs propres règles).
#
# Si Steam tourne déjà (bureau), « steam -gamepadui » ne fait que basculer
# l'instance existante en Big Picture : elle garde son environnement, donc
# sans ce réglage. stop-steam-bigpicture.sh (undo Sunshine) ferme Steam à la
# déconnexion.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+${WINEDLLOVERRIDES};}winewayland.drv=d"

# Session streamée avec le DISPLAY réel de son Xwayland (stream-exec.sh).
exec /usr/local/bin/scripts/stream-exec.sh steam -gamepadui
