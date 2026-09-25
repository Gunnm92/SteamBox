#!/bin/bash
# Variables d'installation de SteamBox (25/09), à sourcer — le SEUL endroit
# où les scripts lisent ce qui dépend de l'installation (chemins de la
# ludothèque, clavier, langue, GPU). Valeurs fournies par l'environnement du
# conteneur (env_file du profil, voir profiles/), valeurs par défaut
# génériques sinon. Les services s6 les reçoivent via with-contenv.
# shellcheck disable=SC2034  # variables lues par les scripts qui sourcent

# Ludothèque : GAMES_DIR/{roms,bios,saves} par défaut (arborescence
# Batocera). Chaque dossier peut être placé ailleurs individuellement —
# GAMES_ROMS_DIR existait déjà avant ce fichier, gardé tel quel.
GAMES_DIR="${GAMES_DIR:-/config/games}"
ROMS_DIR="${GAMES_ROMS_DIR:-${GAMES_DIR}/roms}"
BIOS_DIR="${GAMES_BIOS_DIR:-${GAMES_DIR}/bios}"
SAVES_DIR="${GAMES_SAVES_DIR:-${GAMES_DIR}/saves}"

# Clavier (XKB) : bureau labwc, clavier virtuel Sunshine (evdev-bridge) et
# VNC (wayvnc). Ex. fr + mac pour un AZERTY Mac, us + vide pour un QWERTY.
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-us}"
KEYBOARD_VARIANT="${KEYBOARD_VARIANT:-}"

# Langue : variable standard LANG du conteneur (ex. fr_FR.UTF-8, avec
# LANGUAGE=fr_FR:fr), lue telle quelle par le bureau et les applis ;
# STEAMBOX_LANG = même valeur sans l'encodage, pour EmulationStation
# (system.language) et Sunshine. Locales compilées dans l'image : en_US et
# celles d'EXTRA_LOCALES (Dockerfile).
STEAMBOX_LANG="${LANG:-en_US.UTF-8}"
STEAMBOX_LANG="${STEAMBOX_LANG%%.*}"
if [[ "${STEAMBOX_LANG}" == "C" || "${STEAMBOX_LANG}" == "POSIX" ]]; then
    STEAMBOX_LANG=en_US
fi

# GPU : nvidia | amd | intel, "auto" = détection (voir gpu_vendor). NVIDIA
# demande aussi LIBVA_DRIVER_NAME=nvidia dans l'environnement (VA-API via
# nvidia-vaapi-driver) ; AMD/Intel : libva trouve seule radeonsi/iHD.
GPU_VENDOR="${GPU_VENDOR:-auto}"

# Fabricant du GPU passé au conteneur. NVIDIA : module du pilote visible
# (/proc/driver/nvidia, injecté par le runtime nvidia). Sinon identifiant
# PCI du premier /dev/dri/card* réellement présent — /sys/class/drm liste
# aussi les GPU de l'hôte non passés au conteneur (voir wayland-session.sh).
gpu_vendor() {
    local card id
    if [[ "${GPU_VENDOR}" != "auto" ]]; then
        echo "${GPU_VENDOR}"; return
    fi
    if [[ -e /proc/driver/nvidia/version ]]; then
        echo nvidia; return
    fi
    for card in /dev/dri/card*; do
        [[ -e "${card}" ]] || continue
        id=$(cat "/sys/class/drm/$(basename "${card}")/device/vendor" 2>/dev/null)
        case "${id}" in
            0x10de) echo nvidia; return ;;
            0x1002) echo amd; return ;;
            0x8086) echo intel; return ;;
        esac
    done
    echo unknown
}

# Premier /dev/dri/card* présent dans le conteneur (wlroots, voir
# wayland-session.sh : card0 n'est pas garanti).
first_drm_card() {
    local card
    for card in /dev/dri/card*; do
        [[ -e "${card}" ]] && { echo "${card}"; return; }
    done
    echo /dev/dri/card0
}
