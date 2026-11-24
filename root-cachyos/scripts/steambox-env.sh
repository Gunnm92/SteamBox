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

# Résolution du bureau headless (noVNC), LARGEURxHAUTEUR[@Hz] (22/11).
DESKTOP_RESOLUTION="${DESKTOP_RESOLUTION:-1920x1080}"

# Clavier (XKB) : bureau labwc, clavier virtuel Sunshine (evdev-bridge) et
# VNC (wayvnc). Ex. fr + mac pour un AZERTY Mac, us + vide pour un QWERTY.
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT:-us}"
KEYBOARD_VARIANT="${KEYBOARD_VARIANT:-}"
# VNC_MAC_ISO_KEYS=1 : noVNC depuis un Mac à clavier ISO (« @ » et « < »
# inversés) — échange ces deux touches pour wayvnc seul (svc-wayvnc).
# Activé par défaut avec la variante mac : qui choisit un AZERTY Mac tape
# depuis un Mac ; 0 pour le forcer à l'arrêt.
if [ "${KEYBOARD_VARIANT}" = mac ]; then
    VNC_MAC_ISO_KEYS="${VNC_MAC_ISO_KEYS:-1}"
else
    VNC_MAC_ISO_KEYS="${VNC_MAC_ISO_KEYS:-0}"
fi

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
# nvidia-vaapi-driver) ; AMD : libva trouve seule radeonsi. Intel : détecté,
# mais plus de pilote dans l'image (20/11), encodage logiciel.
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

# Sortie streamée par Sunshine (22/11) : le labwc de Sunshine (wayland-1)
# pilote en DRM une sortie branchée du GPU du conteneur — un dongle HDMI
# factice, aucun écran — et Sunshine la capture en KMS (seule capture qui
# transmet le HDR) ; la session Steam y passe gamescope seul, en DRM HDR.
# Sans sortie branchée, labwc reste headless et Sunshine capture par wlr
# (comportement d'avant). STREAM_OUTPUT : auto (défaut), headless, ou le nom
# d'un connecteur (HDMI-A-1, DP-1…).
STREAM_OUTPUT="${STREAM_OUTPUT:-auto}"

# stream_drm_card : /dev/dri/cardN du conteneur dont dépend une sortie
# branchée, le connecteur et son dossier /sys (modes), sur une ligne
# (« /dev/dri/card0 HDMI-A-1 /sys/class/drm/card0-HDMI-A-1 ») ;
# rien si aucune ou si STREAM_OUTPUT=headless. /sys/class/drm liste les
# cartes de l'hôte (numérotation différente) : rapprochées de /dev/dri par
# leur numéro de périphérique (226:N).
stream_drm_card() {
    local dev majmin sys conn name
    [[ "${STREAM_OUTPUT}" == headless ]] && return
    for dev in /dev/dri/card*; do
        [[ -e "${dev}" ]] || continue
        majmin="$((16#$(stat -c %t "${dev}"))):$((16#$(stat -c %T "${dev}")))"
        for sys in /sys/class/drm/card*; do
            [[ "$(cat "${sys}/dev" 2>/dev/null)" == "${majmin}" ]] || continue
            for conn in "${sys}"-*; do
                name="${conn##*/}"; name="${name#"${sys##*/}"-}"
                if [[ "${STREAM_OUTPUT}" == auto ]]; then
                    [[ "$(cat "${conn}/status" 2>/dev/null)" == connected ]] || continue
                elif [[ "${name}" != "${STREAM_OUTPUT}" ]]; then
                    continue
                fi
                echo "${dev} ${name} ${conn}"
                return
            done
        done
    done
}

# DISPLAY des deux Xwayland (22/11) : labwc réserve le premier numéro libre
# à son démarrage, et le donne à sa commande -s, qui le note dans
# $XDG_RUNTIME_DIR (steambox-desktop-display : bureau noVNC, par
# xdg-autostart.sh ; steambox-stream-display : labwc de Sunshine). Lus au
# lancement de chaque appli plutôt que codés en dur (:0 / :1) : l'ordre de
# démarrage, ou un redémarrage d'un des labwc, pouvait inverser les numéros
# (vu en direct : bureau sur :2, Sunshine sur :0, EmulationStation sur un :1
# inexistant). Repli sur l'ancienne valeur si le fichier manque.
desktop_display() {
    local d
    d=$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u arcade)}/steambox-desktop-display" 2>/dev/null)
    echo "${d:-:0}"
}
stream_display() {
    local d
    d=$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u arcade)}/steambox-stream-display" 2>/dev/null)
    echo "${d:-:1}"
}

# stream_compositor : compositeur du streaming en cours, « kwin » ou « labwc »
# (24/11, phase 1 KWin). Écrit au démarrage de svc-labwc-stream dans le
# marqueur steambox-stream-compositor ; labwc si le marqueur manque (avant
# KWin, ou service jamais démarré depuis le redémarrage).
stream_compositor() {
    local c
    c=$(cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u arcade)}/steambox-stream-compositor" 2>/dev/null)
    echo "${c:-labwc}"
}

# stream_session_env : exporte les variables de la session KWin de streaming
# (steambox-stream-session.env, écrit par kwin-stream-session.sh). Retour 1
# s'il n'existe pas, ou si le socket wayland-1 manque (24/11 : session gamescope
# en cours, KWin arrêté, fichier d'environnement périmé). Lu ligne à ligne,
# sans évaluation du contenu.
stream_session_env() {
    local d="${XDG_RUNTIME_DIR:-/run/user/$(id -u arcade)}" k v
    local f="${d}/steambox-stream-session.env"
    [[ -r "${f}" && -S "${d}/wayland-1" ]] || return 1
    while IFS='=' read -r k v; do
        if [[ -n "${k}" ]]; then
            export "${k}=${v}"
        fi
    done < "${f}"
}

# fit_resolution <largeur> <hauteur> : parmi les définitions « LxH » lues
# sur l'entrée standard (modes d'une sortie DRM), la plus grande qui tient
# dans celle du client — à surface égale, le format le plus proche ; aucune
# ne tient : la plus petite. Le pilote NVIDIA refuse en DRM tout mode absent
# de l'EDID (essayé le 22/11 : 2560x1600, 1920x1200, 3440x1440 refusés sur
# le dongle) ; Moonlight affiche alors l'image avec de fines bandes.
fit_resolution() {
    awk -v cw="$1" -v ch="$2" '
        { split($1, r, "x"); w = r[1] + 0; h = r[2] + 0; if (!w || !h) next
          ar = w / h - cw / ch; if (ar < 0) ar = -ar
          if (w <= cw && h <= ch) {
              if (fit == "" || w * h > fa || (w * h == fa && ar < far)) { fit = $1; fa = w * h; far = ar }
          } else if (small == "" || w * h < sa) { small = $1; sa = w * h } }
        END { print (fit != "" ? fit : small) }'
}
