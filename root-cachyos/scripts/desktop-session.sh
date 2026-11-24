#!/bin/bash
# Autostart de la session Plasma du bureau navigateur (24/11,
# /etc/xdg/autostart/steambox-desktop-session.desktop) : publie ce dont les
# scripts lancés hors du bureau ont besoin pour y ouvrir une fenêtre —
# l'environnement de la session (steambox-desktop-session.env, lu par
# desktop_session_env) et le DISPLAY de son Xwayland (steambox-desktop-display,
# lu par desktop_display). Pendant de kwin-stream-session.sh pour le
# streaming. Le WAYLAND_DISPLAY de KWin (wayland-1 en pratique) n'est ainsi
# écrit en dur nulle part.
#
# Écrit dans un .tmp puis renommé : un lecteur ne voit jamais un fichier à
# moitié écrit.
R="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR absent}"

{
    for v in DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XDG_CURRENT_DESKTOP XAUTHORITY; do
        printf '%s=%s\n' "${v}" "${!v:-}"
    done
} > "${R}/steambox-desktop-session.env.tmp" \
    && mv -f "${R}/steambox-desktop-session.env.tmp" "${R}/steambox-desktop-session.env"

/usr/local/bin/scripts/note-display.sh desktop
