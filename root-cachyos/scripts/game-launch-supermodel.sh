#!/bin/bash
# Lanceur pour Supermodel (Sega Model 3, 22/09). Supermodel ne
# reconnaît un romset que via Config/Games.xml, et cherche ce dossier Config/
# d'abord dans le RÉPERTOIRE COURANT, sinon dans ~/.config/supermodel
# (Src/OSD/Unix/FileSystemPath.cpp, vérifié le 22/09). Games.xml n'est livré
# que dans /opt/supermodel/Config, en lecture seule pour arcade, et
# NVRAM/Saves y sont écrits relativement au répertoire courant.
# On prépare donc un dossier de travail persistant et écrivable sur /config,
# avec les fichiers de référence de l'image (Games.xml/Music.xml, rafraîchis
# à chaque lancement pour suivre les mises à jour de Supermodel) et les
# réglages utilisateur (Supermodel.ini, jamais écrasé s'il existe).
set -euo pipefail

WORK="${HOME}/.local/share/supermodel"
mkdir -p "${WORK}/Config" "${WORK}/NVRAM" "${WORK}/Saves"
cp -f /opt/supermodel/Config/Games.xml /opt/supermodel/Config/Music.xml "${WORK}/Config/"
if [[ ! -f "${WORK}/Config/Supermodel.ini" && -f /opt/supermodel/Config/Supermodel.ini ]]; then
    cp /opt/supermodel/Config/Supermodel.ini "${WORK}/Config/"
fi
ln -sfn /opt/supermodel/Assets "${WORK}/Assets"

cd "${WORK}"
exec /usr/local/bin/supermodel "$1" -fullscreen
