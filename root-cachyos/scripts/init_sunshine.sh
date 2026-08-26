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
    #
    # encoder = nvenc : sans le forcer, Sunshine peut retomber sur un
    # encodeur logiciel si sa détection GPU échoue silencieusement — sur ce
    # matériel (NVIDIA direct, pas de passthrough) nvenc doit toujours être
    # disponible.
    # min_log_level = info (audit 2026-08-26) : par défaut Sunshine ne dit
    # jamais explicitement quelle méthode de capture d'écran il a retenue
    # (NvFBC vs. repli logiciel X11). Sans le patch keylase/nvidia-patch
    # (verrou NvFBC réservé aux Quadro, à appliquer côté HOST Unraid — les
    # libs NVIDIA sont injectées en lecture seule par le runtime, un patch
    # dans ce conteneur ne survivrait de toute façon pas), Sunshine capture
    # en logiciel (XGetImage, un des postes de CPU les plus coûteux
    # identifiés dans l'audit) sans jamais le signaler. Ce niveau de log
    # permet de vérifier dans `docker logs` quelle méthode est réellement
    # utilisée avant d'aller plus loin sur ce point.
    cat > "${CONF_DIR}/sunshine.conf" <<'EOF'
locale = fr
csrf_allowed_origins = https://10.1.1.1:47990
system_tray = 0
dd_hdr_option = disabled
encoder = nvenc
min_log_level = info
EOF
fi
# NOTE : ce bloc n'écrit sunshine.conf que s'il est absent — sur un /config
# déjà provisionné (prod existante), les clés ci-dessus ne sont PAS ajoutées
# rétroactivement. Pour les appliquer à une install existante : ajouter les
# deux lignes à la main dans /config/.config/sunshine/sunshine.conf, ou
# supprimer ce fichier pour le laisser être régénéré (perd la config
# personnalisée éventuelle : PIN, résolutions, apps.json custom...).

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
