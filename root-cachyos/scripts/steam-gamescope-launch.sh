#!/bin/bash
# Lance Steam (gamepadui) niché dans gamescope — l'interface principale de
# la session est Steam (Big Picture/gamepadui) pour les jeux PC — décision
# utilisateur du 29/08. Les jeux rétro/arcade passent par Batocera
# EmulationStation (entrée Moonlight dédiée, depuis le 24/09 ; remplace
# Pegasus).
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

# Applis Qt (Lichii, Eden, PCSX2, RPCS3, DuckStation…) en X11 dans gamescope
# (15/11) : l'image exporte QT_QPA_PLATFORM=wayland, mais gamescope ne donne
# pas de WAYLAND_DISPLAY à ses clients. Qt retombait alors sur wayland-0 (le
# bureau labwc), hors de gamescope : la surface Vulkan échouait (Lichii :
# « Failed to initialize Wayland surface », VK_ERROR_INITIALIZATION_FAILED)
# et le jeu se fermait aussitôt. En xcb, elles s'affichent dans le Xwayland
# de gamescope (DISPLAY fourni par gamescope). Sans effet sur gamescope
# lui-même (SDL) ni sur Steam.
export QT_QPA_PLATFORM=xcb

# XDG_RUNTIME_DIR distinct pour la session gamescope (21/11), comme une
# session de jeu Bazzite/SteamOS où aucun bureau ne tourne derrière gamescope.
# Ici labwc (wayland-0, administration noVNC) et labwc-stream (wayland-1,
# streamé par Sunshine) restent actifs : tout client Wayland lancé dans
# gamescope sans WAYLAND_DISPLAY retombait sur wayland-0 et s'affichait sur le
# bureau. Wine 11 (winewayland) y créait sa fenêtre, la couche Vulkan de
# gamescope refusait la surface (« Failed to get Wayland objects ») et le jeu
# plantait à la création de la swapchain (Tetris Effect Connected, .wsquashfs).
# Le dossier de session ne reprend que bus, D-Bus, PipeWire, Pulse, dconf,
# at-spi et doc (liens), jamais wayland-* : les clients basculent en X11,
# dans le Xwayland de gamescope. gamescope lui-même atteint son compositeur
# par un chemin absolu (accepté par libwayland) ; ses sockets gamescope-0 et
# limiteurs sont créés dans le dossier de session.
RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
SESSION_RUNTIME="${RUNTIME}/gamescope-session"
mkdir -p "${SESSION_RUNTIME}"
chmod 0700 "${SESSION_RUNTIME}"
for entry in bus dbus-1 pipewire-0 pipewire-0-manager pulse dconf at-spi doc; do
    ln -sfn "${RUNTIME}/${entry}" "${SESSION_RUNTIME}/${entry}"
done
case "${WAYLAND_DISPLAY:-wayland-0}" in
    /*) ;;
    *) export WAYLAND_DISPLAY="${RUNTIME}/${WAYLAND_DISPLAY:-wayland-0}" ;;
esac
# Forcés (24/11) : lancé depuis Sunshine sous KWin, le script hériterait du bus
# bus-stream et de XDG_CURRENT_DESKTOP=KDE, ceux d'un KWin arrêté pendant la
# session gamescope. Valeurs d'avant la branche : bus du bureau, XFCE.
export DBUS_SESSION_BUS_ADDRESS="unix:path=${RUNTIME}/bus"
export XDG_CURRENT_DESKTOP=XFCE

# --stream (entrée Sunshine, 22/11) avec le dongle HDMI branché
# (steambox-stream-output, voir svc-labwc-stream) : gamescope pilote seul
# la sortie en DRM, HDR actif — steam-gamescope-session.sh start a arrêté le
# labwc de Sunshine pour la libérer. Mode du dongle choisi par -W/-H/-r
# (résolution du client). --disable-layers --force-composition : tout est
# composé sur le plan principal, le seul que lit la capture KMS de Sunshine
# (sinon écran noir, vu en direct). Écrans dont l'EDID n'annonce pas le HDR
# (dongle sans colorimétrie BT.2020) : profil Lua dans
# ~/.config/gamescope/scripts (voir README). Sans dongle ou hors Sunshine
# (raccourci du bureau) : gamescope niché comme avant.
CONNECTOR=$(cat "${RUNTIME}/steambox-stream-output" 2>/dev/null)
if [ "${1:-}" = --stream ] && [ -n "${CONNECTOR}" ]; then
    # gamescope déjà lancé par steam-gamescope-session.sh start (23/11), qui
    # attend qu'il affiche une image avant que Sunshine ne capture : la
    # commande « detached » de l'appli n'a plus rien à faire.
    if pgrep -x gamescope-wl >/dev/null; then
        exit 0
    fi
    # Définition parmi les modes du dongle (fit_resolution) : le pilote
    # NVIDIA refuse en DRM tout mode absent de son EDID.
    # shellcheck source=steambox-env.sh
    . /usr/local/bin/scripts/steambox-env.sh
    read -r _ _ CONN_SYS <<<"$(stream_drm_card)"
    RES=$(sort -u "${CONN_SYS}/modes" 2>/dev/null | fit_resolution "${WIDTH}" "${HEIGHT}")
    if [ -n "${RES}" ]; then
        WIDTH="${RES%x*}" HEIGHT="${RES#*x}"
    fi
    unset WAYLAND_DISPLAY DISPLAY
    export LIBSEAT_BACKEND=seatd XDG_RUNTIME_DIR="${SESSION_RUNTIME}"
    exec gamescope --backend drm --prefer-output "${CONNECTOR}" \
        -W "${WIDTH}" -H "${HEIGHT}" -r "${FPS}" \
        --hdr-enabled --disable-layers --force-composition -e \
        -- /usr/local/bin/steam -gamepadui
fi
export XDG_RUNTIME_DIR="${SESSION_RUNTIME}"

exec gamescope --force-grab-cursor --backend sdl -W "${WIDTH}" -H "${HEIGHT}" -r "${FPS}" -f -e -C 0 --immediate-flips -- /usr/local/bin/steam -gamepadui
