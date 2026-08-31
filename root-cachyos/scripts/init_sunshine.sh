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
    #
    # gamepad volontairement PAS forcé sur "ds4" (essayé puis annulé le
    # 29/08) : casse l'émulation Xbox quand une manette Xbox ET une
    # DualShock/DualSense sont utilisées en alternance sur le même client
    # (cas réel ici, Android TV) — tout se retrouve émulé en DS4 y compris
    # la manette Xbox. "auto" (défaut Sunshine) est censé détecter le bon
    # profil par manette selon ce que Moonlight négocie ; si le pavé tactile
    # DS4 ne remonte quand même pas, creuser côté client Moonlight Android
    # TV (négociation des capacités manette), pas côté ce fichier.
    cat > "${CONF_DIR}/sunshine.conf" <<'EOF'
locale = fr
csrf_allowed_origins = https://10.1.1.1:47990
system_tray = 0
dd_hdr_option = disabled
encoder = nvenc
min_log_level = info
EOF
fi
# NOTE : ce bloc n'écrit sunshine.conf que s'il est absent. Depuis l'audit
# M2 (31/08), la section "Migration des configs persistées" en fin de script
# rattrape les installs existantes : clés manquantes ajoutées (jamais
# écrasées si personnalisées), prep-cmd injectés dans apps.json — versionné
# via ${CONF_DIR}/.config-version. Toute évolution future de ces fichiers
# doit passer par une nouvelle étape de migration là-bas, pas seulement ici.

if [ ! -f "${CONF_DIR}/apps.json" ]; then
    # -gamepadui (pas "steam steam://open/bigpicture") : confirmé en direct
    # très tôt dans ce projet — l'ancien Big Picture (CEF) capturait en écran
    # noir via Steam Link/Remote Play, l'interface gamepadui (façon Steam
    # Deck) fonctionne. Régression retrouvée sur la nouvelle image Ubuntu
    # (apps.json généré avant cette correction pointait encore vers
    # steam://open/bigpicture).
    #
    # "Mode SteamOS (Gamescope)" ajouté (29/08) : gamepadui nu plein écran
    # X11 classique VS ici gamepadui hébergé dans une fenêtre gamescope
    # imbriquée (scaling FSR, limitation de frame rate) — gamescope tourne
    # comme client normal de la session existante (pas de remplacement du
    # serveur d'affichage). --backend sdl requis explicitement : le mode
    # "auto" de gamescope se trompe dans ce conteneur et bascule sur le
    # backend "headless" (aucun affichage) au lieu de nester correctement
    # (testé en direct 29/08, SOUS X11 à l'époque — SDL_VIDEODRIVER valait
    # x11). Pivot Wayland (voir Dockerfile.cachyos, point 5 de l'historique) :
    # SDL_VIDEODRIVER vaut désormais "wayland,x11", donc --backend sdl
    # devrait nester nativement en Wayland, mais ça n'a jamais été revérifié
    # en direct dans ce nouveau contexte — à confirmer avant de faire
    # confiance à cette entrée. Résolution/refresh alignés sur le bureau
    # (2560x1440@120, voir Sunshine "Streaming bitrate"/xrandr).
    # prep-cmd set-resolution.sh/reset-resolution.sh (30/08) : ajuste la
    # sortie du labwc headless (wayland-1, cible de Sunshine depuis le pivot
    # post-audit HDR/gamescope) à la résolution réelle du client Moonlight
    # à la connexion, et la remet à 1920x1080 à la déconnexion — sans ça
    # le headless reste bloqué sur son mode par défaut (1280x720) quel que
    # soit le client. Voir scripts/set-resolution.sh.
    cat > "${CONF_DIR}/apps.json" <<'EOF'
{
  "env": {},
  "apps": [
    { "name": "Desktop", "image-path": "desktop.png",
      "prep-cmd": [ { "do": "/usr/local/bin/scripts/set-resolution.sh", "undo": "/usr/local/bin/scripts/reset-resolution.sh" } ] },
    { "name": "Steam Big Picture", "detached": ["steam -gamepadui"], "image-path": "steam.png",
      "prep-cmd": [ { "do": "/usr/local/bin/scripts/set-resolution.sh", "undo": "/usr/local/bin/scripts/reset-resolution.sh" } ] },
    { "name": "Mode SteamOS (Gamescope)", "detached": ["gamescope --backend sdl -W 2560 -H 1440 -r 120 -f -e -C 0 -- steam -gamepadui"], "image-path": "steam.png",
      "prep-cmd": [ { "do": "/usr/local/bin/scripts/set-resolution.sh", "undo": "/usr/local/bin/scripts/reset-resolution.sh" } ] }
  ]
}
EOF
fi

# ── Migration des configs persistées (audit M2, 31/08) ─────────────────────
# Les blocs ci-dessus n'écrivent sunshine.conf/apps.json que s'ils sont
# ABSENTS : un /config déjà provisionné ne recevait jamais les évolutions du
# dépôt. Deux incidents réels : prep-cmd de résolution absents du apps.json
# live (flux Moonlight figé en 1280x720, vécu le 31/08), et clés
# sunshine.conf jamais rétro-appliquées (voir NOTE historique plus haut).
# Mécanisme : un marqueur de version dans CONF_DIR, et des migrations
# idempotentes appliquées par étape — chacune ne touche QUE ce qui manque,
# jamais ce que l'utilisateur a personnalisé.
VERSION_FILE="${CONF_DIR}/.config-version"
CURRENT_VERSION=2
INSTALLED_VERSION=$(cat "${VERSION_FILE}" 2>/dev/null || echo 1)

if [ "${INSTALLED_VERSION}" -lt 2 ]; then
    # v1 -> v2 : prep-cmd set-resolution/reset-resolution sur chaque app de
    # apps.json qui n'en a pas (résolution dynamique pilotée par le client
    # Moonlight, voir scripts/set-resolution.sh). jq préserve tout le reste
    # de chaque entrée (commandes detached personnalisées incluses).
    if [ -f "${CONF_DIR}/apps.json" ] && command -v jq >/dev/null 2>&1; then
        if jq -e '.apps[] | select(has("prep-cmd") | not)' "${CONF_DIR}/apps.json" >/dev/null 2>&1; then
            cp "${CONF_DIR}/apps.json" "${CONF_DIR}/apps.json.bak-migration-v2"
            jq '{env, apps: [.apps[] | if has("prep-cmd") then . else . + {"prep-cmd": [{"do": "/usr/local/bin/scripts/set-resolution.sh", "undo": "/usr/local/bin/scripts/reset-resolution.sh"}]} end]}' \
                "${CONF_DIR}/apps.json" > "${CONF_DIR}/apps.json.new" \
                && mv "${CONF_DIR}/apps.json.new" "${CONF_DIR}/apps.json" \
                && echo "[init_sunshine] migration v2 : prep-cmd ajoutés à apps.json (sauvegarde .bak-migration-v2)"
        fi
    fi
    # v1 -> v2 : clés sunshine.conf ajoutées depuis, appliquées seulement si
    # absentes (une valeur personnalisée existante n'est jamais écrasée).
    if [ -f "${CONF_DIR}/sunshine.conf" ]; then
        while IFS='=' read -r key value; do
            grep -q "^${key} =" "${CONF_DIR}/sunshine.conf" || {
                echo "${key} =${value}" >> "${CONF_DIR}/sunshine.conf"
                echo "[init_sunshine] migration v2 : ${key} ajouté à sunshine.conf"
            }
        done <<'MIGRATE_EOF'
dd_hdr_option= disabled
encoder= nvenc
min_log_level= info
system_tray= 0
MIGRATE_EOF
    fi
fi

echo "${CURRENT_VERSION}" > "${VERSION_FILE}"

chown -R "${PUID:-1000}:${PGID:-1000}" "${CONF_DIR}"
