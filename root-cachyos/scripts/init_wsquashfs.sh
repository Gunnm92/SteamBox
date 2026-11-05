#!/bin/bash
# SteamBox — Installe le lanceur wsquashfs-launcher (et son pont DualSense)
# dans le home de arcade, /config/.local/bin, comme le fait son install.sh
# hors root. Installation initiale seulement : si le lanceur est déjà là, on
# ne touche à rien. Lancé par init-system ; il ne fait rien une fois installé.
# Le lanceur doit vivre dans un dossier inscriptible par arcade : son updater
# ne fonctionne pas s'il est dans /usr/bin ou /usr/local/bin.
set -u

REPO="https://raw.githubusercontent.com/Gunnm92/wsquashfs-launcher"
REF="${WSQUASHFS_REF:-main}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# /home/arcade est un lien vers /config (init-system) : on écrit dans /config.
BIN_DIR="/config/.local/bin"
STATE_DIR="/config/.local/share/wsquashfs"
LAUNCHER="${BIN_DIR}/wsquashfs-launcher"
BRIDGE="${BIN_DIR}/dualsense-usb-bridge"

# fetch <url> <dest> : écrit dans un fichier temporaire, ne remplace dest que
# si le contenu est un script (#!) non vide.
fetch() {
    local url="$1" dest="$2" tmp
    tmp="$(mktemp "${dest}.XXXXXX")" || return 1
    if curl -fsSL --retry 2 --max-time 60 "${url}" -o "${tmp}" \
        && [ -s "${tmp}" ] && [ "$(head -c 2 "${tmp}")" = "#!" ]; then
        chmod 755 "${tmp}" && mv -f "${tmp}" "${dest}" && return 0
    fi
    rm -f "${tmp}"
    return 1
}

mkdir -p "${BIN_DIR}" "${STATE_DIR}"
chown "${PUID}:${PGID}" "${BIN_DIR}" "${STATE_DIR}" 2>/dev/null || true

# Installation seulement si le lanceur est absent. Une fois présent, il se met
# à jour lui-même (son updater écrit dans ~/.local/bin, pas dans /usr/bin) :
# on ne l'écrase jamais ici.
if [ -x "${LAUNCHER}" ]; then
    echo "[wsquashfs] lanceur déjà installé (${LAUNCHER}) — mises à jour par son updater"
    exit 0
fi

echo "[wsquashfs] installation initiale du lanceur (${REF}) dans ${BIN_DIR}..."
if fetch "${REPO}/${REF}/wsquashfs-launcher" "${LAUNCHER}"; then
    fetch "${REPO}/${REF}/tools/dualsense-usb-bridge/dualsense-usb-bridge" "${BRIDGE}" \
        || echo "[wsquashfs] pont DualSense non téléchargé (optionnel)"
    chown "${PUID}:${PGID}" "${LAUNCHER}" "${BRIDGE}" 2>/dev/null || true
    echo "[wsquashfs] installé"
else
    echo "[wsquashfs] téléchargement échoué (GitHub injoignable ?) — relancer le démarrage plus tard"
fi
exit 0
