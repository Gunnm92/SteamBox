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
    # dd_hdr_option = disabled : sans ça, Sunshine tente de négocier du HEVC
    # 10-bit (mode "display device" HDR automatique) même en contenu SDR —
    # confirmé en direct, le client Moonlight refuse purement et simplement
    # ("GPU ne prend pas en charge le décodage HEVC/AV1 10 bits pour le
    # streaming HDR") si son GPU ne décode pas le 10-bit. "disabled" laisse
    # l'affichage tel quel plutôt que de laisser Sunshine changer son état.
    cat > "${CONF_DIR}/sunshine.conf" <<'EOF'
locale = fr
csrf_allowed_origins = https://10.1.1.1:47990
system_tray = 0
dd_hdr_option = disabled
EOF
fi

if [ ! -f "${CONF_DIR}/apps.json" ]; then
    # -gamepadui (pas "steam steam://open/bigpicture") : confirmé en direct
    # très tôt dans ce projet — l'ancien Big Picture (CEF) capturait en écran
    # noir via Steam Link/Remote Play, l'interface gamepadui (façon Steam
    # Deck) fonctionne. Régression retrouvée sur la nouvelle image Ubuntu
    # (apps.json généré avant cette correction pointait encore vers
    # steam://open/bigpicture).
    cat > "${CONF_DIR}/apps.json" <<'EOF'
{
  "env": {},
  "apps": [
    { "name": "Desktop", "image-path": "desktop.png" },
    { "name": "Steam Big Picture", "detached": ["steam -gamepadui"], "image-path": "steam.png" }
  ]
}
EOF
fi

chown -R "${PUID:-1000}:${PGID:-1000}" "${CONF_DIR}"
