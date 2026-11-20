#!/bin/bash
# Autostart XDG de l'utilisateur (~/.config/autostart) — lancé par labwc -s
# dans labwc-session.sh, une fois le bureau (wayland-0) prêt.
#
# Attente de la zone de notification (18/11) : xfce4-panel est un service s6
# démarré en parallèle de labwc, et dex passait ~1 s AVANT lui. Les icônes
# (wsquashfs-launcher --tray…) vérifient au lancement qu'un
# org.kde.StatusNotifierWatcher existe et quittent sinon : le tray ne se
# lançait jamais. On attend donc ce nom sur le bus (60 s au plus — au-delà
# on lance quand même, pour les applis sans icône).
gdbus wait --session --timeout 60 org.kde.StatusNotifierWatcher 2>/dev/null || \
    echo "xdg-autostart : pas de zone de notification après 60 s, autostart lancé quand même" >&2

# -e XFCE : respecte OnlyShowIn/NotShowIn. --search-paths : SEULEMENT le
# dossier de l'utilisateur — /etc/xdg/autostart relancerait en double
# xfsettingsd (déjà service s6) et xfce4-notifyd.
exec dex -a -e XFCE --search-paths "${XDG_CONFIG_HOME:-${HOME}/.config}/autostart"
