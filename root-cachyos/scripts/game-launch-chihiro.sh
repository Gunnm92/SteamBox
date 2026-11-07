#!/bin/bash
# Lanceur pour Sega Chihiro (07/11), via xemu-chihiro : le fork Chihiro de
# xemu (github.com/Tovarichtch/xemu) que Batocera intègre depuis la v44
# (package xemu-chihiro, lanceur python-src/batocera-launch-xemu-chihiro) et
# que RGS reprend en v43. Les jeux sont des images de la carte DIMM en .bin
# (noms MAME : ghostsqu.bin, outr2.bin...), comme chez RGS. Avant (22/09) :
# des .iso montés en DVD sur une Xbox à BIOS Cerbios, avec le xemu officiel,
# qui ne lit pas ces images.
#
# AppImage installée par AppManager sous le nom « xemu » (~/Applications) :
# elle remplace le xemu officiel, le fork lançant aussi les jeux Xbox.
#
# Comme le lanceur Batocera (emulator.py, relu le 07/11) : config dédiée
# (xemu -config_path), relue puis mise à jour clé par clé — les réglages
# faits dans le menu du fork (contrôles...) restent d'une partie à l'autre ;
# BIOS, flash de la carte média et EEPROM dans bios/chihiro
# (chihiro_xbox_bios.bin, ver1305.bin si présent) ; rendu OpenGL, plein écran,
# barre de menus cachée, région « ex » (export). Non repris : précalibrage
# des pistolets et liaison entre bornes. Le fork garde ses sauvegardes dans
# son dossier par défaut (~/.local/share/xemu/xemu) : Batocera le patche vers
# saves/chihiro, ce qu'une AppImage ne permet pas.
set -euo pipefail

# shellcheck source=steambox-env.sh
. /usr/local/bin/scripts/steambox-env.sh
# shellcheck source=launch-error.sh
. /usr/local/bin/scripts/launch-error.sh

rom="$1"
bios="${BIOS_DIR}/chihiro"
config="${XDG_CONFIG_HOME:-${HOME}/.config}/xemu-chihiro/xemu.toml"

[[ -f "${bios}/chihiro_xbox_bios.bin" ]] \
    || launch_error "BIOS Chihiro absent : ${bios}/chihiro_xbox_bios.bin"
mkdir -p "$(dirname "${config}")"

# Mise à jour du TOML : tomllib lit, l'écriture est faite ici (ni toml ni
# tomli_w dans l'image) — tables imbriquées de chaînes, booléens et nombres,
# ce qu'écrit xemu.
python3 - "${config}" "${rom}" "${bios}" <<'PY'
import sys, tomllib
from pathlib import Path

path, rom, bios = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
try:
    config = tomllib.loads(path.read_text()) if path.is_file() else {}
except (tomllib.TOMLDecodeError, OSError):
    config = {}

def section(name):
    node = config
    for key in name.split('.'):
        node = node.setdefault(key, {})
    return node

section('general').update(show_welcome=False)
section('general.updates')['check'] = False
section('sys')['default_machine'] = 'chihiro'
section('sys.files')['dvd_path'] = rom
section('perf').update(cache_shaders=True)
section('display')['renderer'] = section('display').get('renderer', 'OPENGL')
section('display.window').update(fullscreen_on_startup=True)
section('display.ui')['show_menubar'] = False
roms = section('chihiro.roms')
roms['bios_path'] = str(bios / 'chihiro_xbox_bios.bin')
net = bios / 'ver1305.bin'
roms['net_firmware_path'] = str(net) if net.is_file() else ''
settings = section('chihiro.settings')
settings.setdefault('region', 'ex')
settings['dimm_size'] = 'auto'
settings['board_type'] = 'auto'

def value(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, list):
        return '[' + ', '.join(value(x) for x in v) + ']'
    s = str(v).replace('\\', '\\\\').replace('"', '\\"')
    return f'"{s}"'

def dump(node, prefix, out):
    scalars = {k: v for k, v in node.items() if not isinstance(v, dict)}
    tables = {k: v for k, v in node.items() if isinstance(v, dict)}
    if prefix and scalars:
        out.append(f'[{prefix}]')
    out.extend(f'{k} = {value(v)}' for k, v in scalars.items())
    if scalars:
        out.append('')
    for k, v in tables.items():
        dump(v, f'{prefix}.{k}' if prefix else k, out)

out = []
dump(config, '', out)
tmp = path.with_suffix('.tmp')
tmp.write_text('\n'.join(out) + '\n')
tmp.replace(path)
PY

exec /usr/local/bin/xemu -config_path "${config}"
