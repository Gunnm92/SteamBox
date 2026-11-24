#!/bin/bash
# Réglages d'écran KDE (24/11, demande utilisateur) : lancé par l'entrée de
# menu XFCE « Réglages de l'écran (KDE) » (steambox-reglages-ecran.desktop,
# Dockerfile). systemsettings et son module kcm_kscreen ne parlent qu'au KWin
# de streaming : sous labwc il n'y a aucune sortie à régler, la fenêtre
# s'ouvrirait vide ou en erreur. D'où la branche de repli : on le dit à
# l'utilisateur par une notification, sans lancer de fenêtre.
#
# La session (bus-stream, DISPLAY, WAYLAND_DISPLAY) vient de
# steambox-stream-session.env, écrit par kwin-stream-session.sh au démarrage
# de KWin. Cette entrée est lancée depuis le bureau XFCE (wayland-0, autre bus
# D-Bus) : sans ces variables, kscreen parlerait au mauvais compositeur.
# shellcheck source=/usr/local/bin/scripts/steambox-env.sh
. /usr/local/bin/scripts/steambox-env.sh

if [[ "$(stream_compositor)" == kwin ]]; then
    if stream_session_env; then
        exec systemsettings kcm_kscreen
    fi
    # KWin arrêté (session « Mode SteamOS » en cours, 24/11) : pas de bon bus.
    timeout 5 notify-send -a SteamBox "Réglages de l'écran" \
        "KWin est arrêté (session Mode SteamOS en cours)" >/dev/null 2>&1 || true
    exit 1
fi

# timeout : sans démon de notification joignable, notify-send peut attendre
# D-Bus longtemps (même précaution que launch-error.sh).
timeout 5 notify-send -a SteamBox "Réglages de l'écran" \
    "Réglages KDE disponibles seulement avec le dongle (KWin)" >/dev/null 2>&1 || true
exit 1
