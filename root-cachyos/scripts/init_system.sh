#!/bin/bash
# Préparation système one-shot, avant la boucle superviseur.
set -e

if [ ! -f /etc/locale.gen.done ]; then
    printf 'fr_FR.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n' > /etc/locale.gen
    locale-gen
    touch /etc/locale.gen.done
fi

mkdir -p /config/.config/sunshine /config/.local/share/Steam

# chown -R sur /config est devenu lent (Wine/Steam/RetroArch/Heroic ont fait
# grossir l'arborescence à plusieurs dizaines de milliers de fichiers, sur du
# stockage FUSE shfs en prime) — inutile de tout re-parcourir à chaque boot
# si l'ownership est déjà correcte. On ne teste que la racine : PUID/PGID ne
# changent pas entre deux boots normaux, et le premier boot (où /config est
# fraîchement peuplé depuis le squelette de l'image) reste couvert par le
# chown complet ci-dessous.
CURRENT_OWNER=$(stat -c '%u:%g' /config 2>/dev/null || echo "")
TARGET_OWNER="${PUID:-1000}:${PGID:-1000}"
if [ "${CURRENT_OWNER}" != "${TARGET_OWNER}" ]; then
    chown -R "${TARGET_OWNER}" /config
fi
