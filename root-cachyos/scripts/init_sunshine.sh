#!/bin/bash
# Crée une config Sunshine minimale si absente (persistée sur /config).
set -e

CONF_DIR="/config/.config/sunshine"
mkdir -p "${CONF_DIR}"

if [ ! -f "${CONF_DIR}/sunshine.conf" ]; then
    cat > "${CONF_DIR}/sunshine.conf" <<'EOF'
locale = fr
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
