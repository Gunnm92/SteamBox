#!/bin/bash
# Lance Steam (gamepadui) niché dans gamescope — l'interface principale de
# la session est Steam (Big Picture/gamepadui), pas Pegasus. Pegasus se
# lance DEPUIS Steam (ajouté comme "jeu non-Steam" dans la bibliothèque,
# configuration manuelle ponctuelle côté utilisateur, pas automatisable
# proprement dans l'image — dépend du compte Steam connecté) — décision
# utilisateur du 29/08, revenant sur l'autostart direct de Pegasus.
#
# evdev-bridge (ciblant les protocoles wlroots zwlr_virtual_pointer/
# zwp_virtual_keyboard) retiré d'ici (29/08) : confirmé en direct que cette
# version de gamescope utilise libei ("Successfully initialized libei for
# input emulation!" dans ses logs), pas les protocoles wlroots — evdev-bridge
# vise le mauvais mécanisme pour cet input, inutile ici. Reste à vérifier en
# direct si Sunshine utilise nativement libei (auquel cas souris/clavier
# devraient fonctionner sans contournement) ou retombe sur l'ancien chemin
# uinput (auquel cas le bug udev historique, jamais élucidé, s'applique
# probablement encore) — non testé, à valider via une vraie connexion
# Moonlight plutôt qu'en devinant depuis les logs de démarrage.
set -e

# --backend sdl explicite : "auto" bascule sur le backend "headless" (aucun
# affichage) dans ce conteneur, confirmé en direct côté init_sunshine.sh
# ("Mode SteamOS (Gamescope)", audit 29/08) — sous X11 à l'époque ; sous
# Wayland (SDL_VIDEODRIVER=wayland,x11 désormais), --backend sdl passe par
# le driver SDL wayland, confirmé fonctionner en direct le 29/08 (gamescope
# tourne réellement, pas juste lancé). Résolution/refresh alignés sur
# scripts/init_sunshine.sh (2560x1440@120). -e : intégration Steam-gamescope
# (statistiques de perf, contrôle de la résolution depuis Steam).
exec gamescope --backend sdl -W 2560 -H 1440 -r 120 -f -e -C 0 -- /usr/local/bin/steam -gamepadui
