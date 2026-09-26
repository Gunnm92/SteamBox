#!/bin/bash
# Lancement d'un programme du bureau visible (labwc wayland-0) comme service
# s6, à sourcer depuis un run (26/09). Chaque composant du bureau XFCE
# (xfsettingsd, xfdesktop, xfce4-panel, nm-applet) est son
# propre service : s6 le relance s'il plante — xfce4-panel mourait sur une
# icône introuvable (GTK3, "Bail out!") et restait absent jusqu'au
# redémarrage — et `s6-svc -r /run/service/<svc>` le relance proprement.
# Avant, wayland-session.sh les lançait tous en arrière-plan derrière labwc,
# sans supervision individuelle.
#
# desktop_exec <commande...> : attend le compositeur et le bus D-Bus de
# session, puis remplace le run par la commande, en arcade, avec
# l'environnement de la session (hérité ensuite par tout ce que le panneau
# lance). Sans wayland-0 après 30 s : échec, s6 retente.

desktop_exec() {
    local runtime timeout=60
    runtime="/run/user/$(id -u arcade)"
    while { [ ! -S "${runtime}/wayland-0" ] || [ ! -S "${runtime}/bus" ]; } && [ "${timeout}" -gt 0 ]; do
        sleep 0.5
        timeout=$((timeout - 1))
    done
    if [ ! -S "${runtime}/wayland-0" ]; then
        echo "[$1] wayland-0 absent après 30 s — s6 va relancer."
        exit 1
    fi
    # CWD = HOME : sinon le dossier de service s6 (chemin éphémère) est
    # hérité par tout ce que le panneau lance (vu dans les raccourcis
    # "Ajouter à Steam" de Heroic, audit 01/09).
    cd /home/arcade || exit 1
    # DISPLAY/WAYLAND_DISPLAY explicites (18/09) : les applis lancées depuis
    # le panneau doivent s'ouvrir sur ce bureau (VNC), pas sur le headless
    # wayland-1 de Moonlight.
    exec runuser -u arcade -- env \
        HOME=/home/arcade XDG_RUNTIME_DIR="${runtime}" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${runtime}/bus" \
        WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 \
        QT_QPA_PLATFORM=wayland XDG_CURRENT_DESKTOP=XFCE XDG_SESSION_TYPE=wayland \
        SDL_VIDEODRIVER=wayland,x11 SDL_JOYSTICK_DISABLE_UDEV=1 \
        PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games" \
        "$@"
}
