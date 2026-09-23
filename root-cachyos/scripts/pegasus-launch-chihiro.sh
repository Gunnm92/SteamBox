#!/bin/bash
# Lanceur Pegasus pour Sega Chihiro (22/09), via xemu. Reprend le
# fonctionnement de Batocera (batocera_launch/emulators/xemu.py, même xemu
# officiel v0.8.x que cette image) : le jeu .iso est monté comme DVD, avec le
# flashrom Cerbios, la bootrom MCPX, 128 Mo de RAM (valeur Chihiro) et le
# rendu OpenGL (Batocera : "defaulting to OpenGL due to a Xemu bug").
# Config xemu dédiée (xemu -config_path), séparée d'une éventuelle config
# Xbox : aucun réglage Xbox n'est modifié. Clés vérifiées dans
# config_spec.yml de xemu le 22/09. Disque dur virtuel : copie de l'image
# vierge livrée dans l'image (/usr/share/xemu/xbox_hdd.qcow2), faite une
# seule fois pour garder les sauvegardes.
set -euo pipefail

BIOS_DIR="/home/arcade/games/Batocera/bios"
DATA="${XDG_DATA_HOME:-${HOME}/.local/share}/xemu-chihiro"
rom="$1"

for f in cerbios.bin mcpx_1.0.bin; do
    [[ -f "${BIOS_DIR}/${f}" ]] || { echo "pegasus-launch-chihiro : ${BIOS_DIR}/${f} absent" >&2; exit 1; }
done
mkdir -p "${DATA}"
[[ -f "${DATA}/xbox_hdd.qcow2" ]] || cp /usr/share/xemu/xbox_hdd.qcow2 "${DATA}/xbox_hdd.qcow2"

# Chaînes TOML entre apostrophes (littérales, sans échappement) : un nom de
# jeu contenant une apostrophe est refusé plutôt que de produire un TOML
# invalide.
if [[ "${rom}" == *"'"* ]]; then
    echo "pegasus-launch-chihiro : apostrophe non prise en charge dans ${rom}" >&2
    exit 1
fi
cat > "${DATA}/xemu.toml" <<EOF
[general]
show_welcome = false

[display]
renderer = 'OPENGL'

[display.window]
fullscreen_on_startup = true

[sys]
mem_limit = '128'

[sys.files]
flashrom_path = '${BIOS_DIR}/cerbios.bin'
bootrom_path = '${BIOS_DIR}/mcpx_1.0.bin'
hdd_path = '${DATA}/xbox_hdd.qcow2'
eeprom_path = '${DATA}/eeprom.bin'
dvd_path = '${rom}'
EOF

exec /usr/local/bin/xemu -config_path "${DATA}/xemu.toml"
