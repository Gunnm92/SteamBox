#!/bin/bash
# Fonctions partagées des lanceurs de jeux (game-launch-*.sh), à sourcer.
#
# mount_squashfs_rom <fichier.squashfs> : monte l'image en lecture seule et
# place le point de montage dans $MOUNTED_DIR — variable globale, PAS un
# echo à capturer via $(...) : la fonction tournerait alors dans un
# sous-shell, dont le trap EXIT démonterait l'image aussitôt. Même principe
# que Batocera (fs/squashfs.py) : les jeux namco2x6 et PS3 sont livrés en
# .squashfs. squashfuse tourne en
# arcade, sans sudo : /dev/fuse est en 666 dans ce conteneur (vérifié le
# 22/09). Point de montage sous $XDG_RUNTIME_DIR (tmpfs vidé à chaque boot
# par init-system) ; un montage resté d'un lancement précédent interrompu
# est démonté avant d'être réutilisé. Démontage automatique à la sortie du
# lanceur (trap EXIT) — le lanceur doit donc attendre l'émulateur, pas
# l'exec.

# BIOS_DIR / SAVES_DIR, lus par les lanceurs qui sourcent ce fichier.
# shellcheck source=steambox-env.sh
. /usr/local/bin/scripts/steambox-env.sh

_GAME_MOUNTS=()
_game_unmount_all() {
    local m
    for m in "${_GAME_MOUNTS[@]}"; do
        fusermount3 -u "${m}" 2>/dev/null || fusermount -u "${m}" 2>/dev/null || true
        rmdir "${m}" 2>/dev/null || true
    done
}
trap _game_unmount_all EXIT

mount_squashfs_rom() {
    local rom="$1" base mnt
    base="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/game-roms"
    mnt="${base}/$(basename "${rom}" .squashfs)"
    mkdir -p "${mnt}"
    if mountpoint -q "${mnt}"; then
        fusermount3 -u "${mnt}" 2>/dev/null || fusermount -u "${mnt}" 2>/dev/null || true
    fi
    squashfuse "${rom}" "${mnt}" || { echo "game-launch : montage impossible de ${rom}" >&2; return 1; }
    _GAME_MOUNTS+=("${mnt}")
    # shellcheck disable=SC2034  # lue par le lanceur appelant
    MOUNTED_DIR="${mnt}"
}
