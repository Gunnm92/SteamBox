#!/bin/bash
# Crée une config Sunshine minimale si absente (persistée sur /config).
set -e

CONF_DIR="/config/.config/sunshine"
mkdir -p "${CONF_DIR}"

if [ ! -f "${CONF_DIR}/sunshine.conf" ]; then
    # csrf_allowed_origins : la Web UI de Sunshine bloque par défaut toute
    # origine hors localhost — nécessaire pour y accéder via l'IP LAN.
    cat > "${CONF_DIR}/sunshine.conf" <<'EOF'
locale = fr
csrf_allowed_origins = https://10.1.1.1:47990
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
