#!/bin/bash
# Lanceur pour Sega Lindbergh (14/11), via l'AppImage « Lindbergh Loader »
# (lindbergh-loader 2.x, installée par AppManager dans ~/Applications).
#
# Les jeux suivent la convention Batocera : un dossier par jeu, et dans le
# dossier de l'exécutable un fichier repère <jeu>.game (2spicy/elf/2spicy.game,
# vf5/vf5.game...) que liste EmulationStation. Avant, ES listait les .elf/.sh
# trouvés n'importe où dans ces dossiers et les passait tels quels au loader,
# qui attend un DOSSIER de jeu.
#
# Inodes 32 bits : le loader et les jeux sont des binaires i386 sans prise en
# charge des gros fichiers. Sur le partage Unraid (shfs), les numéros d'inode
# dépassent 2^32 (14636698798288512 pour 2spicy/elf) : stat() et la lecture
# des dossiers y échouent (EOVERFLOW) — « Output directory does not exist »,
# « File does not exist » sur des fichiers bien présents. Le dossier du jeu
# est donc monté par fuse-overlayfs avec l'option ino32_t (non listée dans
# son --help, vérifiée le 14/11) : mêmes fichiers, inodes sur 32 bits. Les
# écritures du jeu (EEPROM, SRAM, lindbergh.ini) vont dans la couche haute,
# ~/.local/share/steambox/lindbergh/<jeu>/upper (disque local, persistant) :
# la ludothèque n'est jamais modifiée.
#
# Comme Batocera : on se place dans le dossier du .game et le loader y
# détecte l'exécutable lui-même. Le loader 2.x lit lindbergh.ini (pas
# l'ancien lindbergh.conf de Batocera) : s'il manque, il est créé en plein
# écran (--create config), puis modifiable dans la couche haute.
set -euo pipefail

# shellcheck source=steambox-env.sh
. /usr/local/bin/scripts/steambox-env.sh
# shellcheck source=launch-error.sh
. /usr/local/bin/scripts/launch-error.sh

rom="$1"
[[ -f "${rom}" ]] || launch_error "Fichier de jeu Lindbergh introuvable : ${rom}"
rom_real=$(realpath "${rom}")
system_dir=$(realpath "${ROMS_DIR}/lindbergh")
[[ "${rom_real}" == "${system_dir}/"* ]] \
    || launch_error "Jeu Lindbergh hors de ${system_dir} : ${rom}"

# Dossier racine du jeu (2spicy) et sous-dossier du .game (elf) : on monte
# la racine, le jeu lit aussi les dossiers voisins (2spicy/fs...).
rel="${rom_real#"${system_dir}"/}"
game="${rel%%/*}"
sub="$(dirname "${rel#"${game}"}")"
sub="${sub#/}"

# Le loader refuse les espaces dans les chemins de config et de bibliothèques.
[[ "${game}" != *" "* && "${sub}" != *" "* ]] \
    || launch_error "Le chemin du jeu Lindbergh ne doit pas contenir d'espace : ${rel}"

data="${XDG_DATA_HOME:-${HOME}/.local/share}/steambox/lindbergh/${game}"
mnt="${XDG_RUNTIME_DIR:-/tmp}/lindbergh/${game}"
mkdir -p "${data}/upper" "${data}/work" "${mnt}"
# Montage resté d'une partie interrompue.
if mountpoint -q "${mnt}"; then
    fusermount3 -uz "${mnt}" || true
fi
fuse-overlayfs -o "lowerdir=${system_dir}/${game},upperdir=${data}/upper,workdir=${data}/work,ino32_t" "${mnt}" \
    || launch_error "Montage du jeu Lindbergh impossible (fuse-overlayfs) : ${game}"

pid=""
cleanup() {
    cd /
    if [[ -n "${pid}" ]]; then
        kill -TERM "${pid}" 2>/dev/null || true
        wait "${pid}" 2>/dev/null || true
    fi
    fusermount3 -u "${mnt}" 2>/dev/null || fusermount3 -uz "${mnt}" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 143' TERM INT HUP

dir="${mnt}${sub:+/${sub}}"
ini="${dir}/lindbergh.ini"
if [[ ! -f "${ini}" ]]; then
    /usr/local/bin/lindbergh --create config "${dir}" \
        || launch_error "Impossible de créer ${data}/upper${sub:+/${sub}}/lindbergh.ini"
    sed -i 's/^FULLSCREEN = .*/FULLSCREEN = true/' "${ini}"
fi

# Pas d'exec : le montage doit être défait à la fin de la partie. Le loader
# tourne en arrière-plan pour que SIGTERM (Hotkey + Start, svc-pad-hotkeys)
# arrive tout de suite à ce script, qui le relaie (cleanup).
cd "${dir}"
/usr/local/bin/lindbergh --config "${ini}" &
pid=$!
status=0
wait "${pid}" || status=$?
pid=""
exit "${status}"
