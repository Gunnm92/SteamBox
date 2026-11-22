#!/bin/bash
# Autostart XDG de l'utilisateur (~/.config/autostart) — lancé par labwc -s
# dans labwc-session.sh, une fois le bureau (wayland-0) prêt.
#
# DISPLAY du Xwayland du bureau noté (22/11, desktop_display dans
# steambox-env.sh) : fourni par labwc dès son démarrage.
/usr/local/bin/scripts/note-display.sh desktop

# Résolution du bureau ensuite (22/11) : headless, il démarre en 1280x720 ;
# DESKTOP_RESOLUTION (steambox-env.sh, 1920x1080 par défaut) est appliquée
# avant que le panneau et les applis ne se placent.
mode="${DESKTOP_RESOLUTION:-1920x1080}"
case "${mode}" in *@*) ;; *) mode="${mode}@60Hz" ;; esac
case "${mode}" in *Hz) ;; *) mode="${mode}Hz" ;; esac
wlr-randr --output HEADLESS-1 --custom-mode "${mode}" 2>&1 || \
    echo "xdg-autostart : résolution ${mode} refusée, 1280x720 conservé" >&2
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
