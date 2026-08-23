#!/bin/bash
# Préparation système one-shot, avant la boucle superviseur.
set -e

if [ ! -f /etc/locale.gen.done ]; then
    printf 'fr_FR.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n' > /etc/locale.gen
    locale-gen
    touch /etc/locale.gen.done
fi

mkdir -p /config/.config/sunshine /config/.local/share/Steam
chown -R "${PUID:-1000}:${PGID:-1000}" /config
