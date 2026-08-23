#!/bin/bash
# Crée une config Sunshine minimale si absente (persistée sur /config).
set -e

CONF_DIR="/config/.config/sunshine"
mkdir -p "${CONF_DIR}"

if [ ! -f "${CONF_DIR}/sunshine.conf" ]; then
    # csrf_allowed_origins : la Web UI de Sunshine bloque par défaut toute
    # origine hors localhost — nécessaire pour y accéder via l'IP LAN.
    # system_tray = 0 : le setcap cap_sys_nice+p sur le binaire sunshine
    # déclenche AT_SECURE côté noyau, qui casse l'auto-launch D-Bus pour
    # l'icône de zone de notification ("Cannot spawn a message bus when
    # AT_SECURE is set") — mène à un crash GTK différé (widget invalide).
    # Le tray n'a de toute façon aucun sens en headless.
    cat > "${CONF_DIR}/sunshine.conf" <<'EOF'
locale = fr
csrf_allowed_origins = https://10.1.1.1:47990
system_tray = 0
EOF
fi

if [ ! -f "${CONF_DIR}/apps.json" ]; then
    cat > "${CONF_DIR}/apps.json" <<'EOF'
{
  "env": {},
  "apps": [
    { "name": "Desktop", "image-path": "desktop.png" },
    { "name": "Steam Big Picture", "detached": ["steam steam://open/bigpicture"], "image-path": "steam.png" }
  ]
}
EOF
fi

chown -R "${PUID:-1000}:${PGID:-1000}" "${CONF_DIR}"
