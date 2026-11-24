#!/bin/bash
# Session du compositeur KWin de streaming (24/11, phase 1 KWin) : lancée en
# arcade par kwin_wayland (--exit-with-session) quand KWin a fini de démarrer
# (wayland-1 et Xwayland prêts). Elle publie ce dont les autres services ont
# besoin — l'environnement de la session (steambox-stream-session.env, lu par
# stream_session_env), le DISPLAY du Xwayland (steambox-stream-display, lu par
# stream_display, comme note-display.sh stream pour labwc) — puis pré-autorise
# le bureau à distance du portail, pour que Moonlight/Remote Play n'ouvre pas
# de fenêtre de confirmation dans ce conteneur sans écran.
#
# Le fichier d'environnement est écrit dans un .tmp puis renommé : un lecteur
# ne voit jamais un fichier à moitié écrit. La ligne steambox-stream-display
# est écrite en dernier : c'est le signal de disponibilité lu par Sunshine.

R="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR absent}"

{
    for v in DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XDG_CURRENT_DESKTOP; do
        printf '%s=%s\n' "${v}" "${!v:-}"
    done
} > "${R}/steambox-stream-session.env.tmp" \
    && mv -f "${R}/steambox-stream-session.env.tmp" "${R}/steambox-stream-session.env"

# Activation D-Bus : les services lancés par le bus (portails, applis
# démarrées depuis Sunshine) héritent du WAYLAND_DISPLAY et du DISPLAY de KWin.
dbus-update-activation-environment --all

# Autorisation du bureau à distance (portail RemoteDesktop) pour l'appli
# « kde-authorized » : sans ça, le portail demande une confirmation qui ne
# viendra jamais. Un échec n'arrête pas la session (le streaming reste utilisable
# sans la prise de contrôle distante) : on le signale seulement.
gdbus call --session --dest org.freedesktop.impl.portal.PermissionStore \
    --object-path /org/freedesktop/impl/portal/PermissionStore \
    --method org.freedesktop.impl.portal.PermissionStore.SetPermission \
    kde-authorized true remote-desktop "" "['yes']" >/dev/null \
    || echo "[kwin-stream] pré-autorisation du portail RemoteDesktop échouée"

# DISPLAY du Xwayland de KWin, noté comme labwc le fait via note-display.sh.
/usr/local/bin/scripts/note-display.sh stream

exec sleep infinity
