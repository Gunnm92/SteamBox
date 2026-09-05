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
# tourne réellement, pas juste lancé). -e : intégration Steam-gamescope
# (statistiques de perf, contrôle de la résolution depuis Steam).
#
# Résolution/fréquence pilotées par le client (audit M7, 05/09) : ce script
# sert deux appelants — le raccourci "Steam" du bureau XFCE local (aucune
# variable SUNSHINE_CLIENT_* définie, replis 2560x1440@120 ci-dessous
# inchangés) ET l'entrée apps.json "Mode SteamOS (Gamescope)" lancée par
# Sunshine (qui exporte SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS dans l'environnement
# de la commande "detached", même mécanisme que prep-cmd — voir
# set-resolution.sh). Avant ce correctif, gamescope rendait TOUJOURS en
# 2560x1440@120 même pour un client négociant du 1080p60, chargeant GPU et
# NVENC pour des pixels ensuite jetés au rescale.
#
# IMPORTANT — pourquoi un script et pas la commande inline dans apps.json :
# Sunshine exécute "detached" via boost::process::child(cmd, ...), qui
# tokenise la chaîne lui-même (découpage simple par espaces/guillemets) —
# CE N'EST PAS un /bin/sh -c (confirmé dans platf::run_command,
# src/platform/linux/misc.cpp). Une syntaxe ${VAR:-defaut} placée
# directement dans la commande JSON n'est donc JAMAIS développée, elle
# arriverait littéralement en argument à gamescope. Seul un vrai script
# shell, invoqué comme exécutable, bénéficie de l'expansion bash.
#
# --force-grab-cursor --immediate-flips (05/09) : ajoutés ici après avoir
# été trouvés dans l'entrée live du 31/08 (modifiés depuis l'UI web
# Sunshine, jamais reportés dans ce dépôt jusqu'ici) — capture le curseur
# dans la fenêtre gamescope (évite qu'un mouvement de souris streamé sorte
# de la zone de jeu) et réduit la latence de présentation.
WIDTH="${SUNSHINE_CLIENT_WIDTH:-2560}"
HEIGHT="${SUNSHINE_CLIENT_HEIGHT:-1440}"
FPS="${SUNSHINE_CLIENT_FPS:-120}"

exec gamescope --force-grab-cursor --backend sdl -W "${WIDTH}" -H "${HEIGHT}" -r "${FPS}" -f -e -C 0 --immediate-flips -- /usr/local/bin/steam -gamepadui
