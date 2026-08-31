#!/bin/bash
# SteamBox (CachyOS) — Installation driver NVIDIA userspace, matché à la
# version du host. Adapté de custom-cont-init.d/10-nvidia.sh (image webstation) :
# même approche .run agnostique à la distro, mais paquet nvidia-utils Arch
# absent (on ne connaît pas la version du host au moment du build), donc
# appelé au runtime par l'entrypoint plutôt que par un hook d'init webstation.

set -uo pipefail

CACHE_DIR="/config/nvidia-drivers"
LOG_FILE="${CACHE_DIR}/install.log"
mkdir -p "${CACHE_DIR}"

extract_driver_version() {
    grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

nvidia_host_driver_version=$(
    nvidia-smi --version 2>/dev/null | grep -i "driver version" | extract_driver_version
)
if [ -z "${nvidia_host_driver_version}" ]; then
    nvidia_host_driver_version=$(
        nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | extract_driver_version
    )
fi
if [ -z "${nvidia_host_driver_version}" ]; then
    nvidia_host_driver_version=$(
        grep -oE 'Kernel Module[[:space:]]+[0-9.]+' /proc/driver/nvidia/version 2>/dev/null \
            | extract_driver_version
    )
fi

if [ -z "${nvidia_host_driver_version}" ]; then
    echo "[nvidia] Impossible de détecter la version driver — skip (pas de GPU NVIDIA ?)"
    exit 0
fi

echo "[nvidia] Version driver host : ${nvidia_host_driver_version}"

# Téléchargement/cache du .run déplacé ici (avant le garde "déjà installé"
# plus bas) : install_nvngx_wine_dll (voir plus bas) a besoin de RUN_FILE
# même quand les modules Xorg sont déjà en place et que le script sortirait
# sinon avant d'avoir jamais défini cette variable.
RUN_FILE="${CACHE_DIR}/NVIDIA-Linux-x86_64-${nvidia_host_driver_version}.run"

if [ ! -f "${RUN_FILE}" ]; then
    echo "[nvidia] Téléchargement du driver ${nvidia_host_driver_version}..."
    declare -a SOURCES=(
        "https://download.nvidia.com/XFree86/Linux-x86_64/${nvidia_host_driver_version}/NVIDIA-Linux-x86_64-${nvidia_host_driver_version}.run"
        "https://us.download.nvidia.com/XFree86/Linux-x86_64/${nvidia_host_driver_version}/NVIDIA-Linux-x86_64-${nvidia_host_driver_version}.run"
        "https://international.download.nvidia.com/XFree86/Linux-x86_64/${nvidia_host_driver_version}/NVIDIA-Linux-x86_64-${nvidia_host_driver_version}.run"
    )
    downloaded=false
    for url in "${SOURCES[@]}"; do
        echo "[nvidia]   essai : ${url}"
        if wget -q -O "${RUN_FILE}.tmp" "${url}" 2>&1; then
            mv "${RUN_FILE}.tmp" "${RUN_FILE}"
            downloaded=true
            break
        else
            rm -f "${RUN_FILE}.tmp"
            echo "[nvidia]   échec"
        fi
    done
    if [ "${downloaded}" != "true" ]; then
        echo "[nvidia] ERREUR : téléchargement impossible pour ${nvidia_host_driver_version} — DLSS/modules Xorg ne pourront pas être (ré)installés"
    fi
fi
chmod +x "${RUN_FILE}" 2>/dev/null || true

# L'installeur NVIDIA place nvidia_drv.so et libglxserver_nvidia.so dans
# /usr/lib64/xorg/modules/... par défaut avec les options --no-x-check
# --no-distro-scripts utilisées ici (désactivent sa détection auto du
# layout Xorg de la distro). Ça fonctionne par coïncidence sur CachyOS/Arch
# mais pas sur Ubuntu/Debian (Xorg n'y cherche que /usr/lib/xorg/modules,
# sans "64") — confirmé en direct : GLX servi par le module générique Xorg
# ("server glx vendor string: SGI") au lieu de NVIDIA, tout OpenGL retombe
# sur le rendu logiciel llvmpipe malgré un vrai GPU disponible. --x-module-
# path plus bas règle ça pour une INSTALLATION FRAÎCHE, mais ce correctif
# ne suffit pas seul : si le driver est déjà "installé" (version identique
# détectée ci-dessous), le script s'arrête avant d'atteindre l'installeur
# et les liens ne sont jamais créés/réparés. fix_xorg_module_paths corrige
# ça dans TOUS les cas (frais ou déjà présent), en symlinkant depuis
# lib64 si besoin.
#
# [ ! -L "${f}" ] AJOUTÉ (bug constaté en direct sur CachyOS 27/08) : sur
# Arch, /usr/lib64 est un symlink VERS /usr/lib (pas deux dossiers séparés
# comme Ubuntu/Debian) — donc le symlink créé par CETTE fonction au premier
# démarrage (ex: libglxserver_nvidia.so -> .../libglxserver_nvidia.so.VER)
# est LUI-MÊME visible par le glob "*nvidia*" au démarrage suivant (même
# dossier réel, vu via l'alias lib64). Sans ce garde, le script re-symlinkait
# ce lien sur lui-même via le chemin lib64 → boucle ("Too many levels of
# symbolic links"), Xorg ne charge plus le module GLX NVIDIA → écran noir
# (VNC et Moonlight identiquement, rendu cassé au niveau X, pas un bug
# client). En ignorant les entrées qui sont déjà des liens symboliques (donc
# nos propres liens d'un run précédent), seul le vrai fichier installé par
# le .run est jamais utilisé comme source — idempotent sur Arch, sans effet
# sur Ubuntu/Debian où lib64 et lib sont réellement distincts.
fix_xorg_module_paths() {
    mkdir -p /usr/lib/xorg/modules/extensions /usr/lib/xorg/modules/drivers
    for f in /usr/lib64/xorg/modules/extensions/*nvidia*; do
        [ -e "${f}" ] && [ ! -L "${f}" ] || continue
        ln -sf "${f}" "/usr/lib/xorg/modules/extensions/$(basename "${f}")"
    done
    for f in /usr/lib64/xorg/modules/drivers/*nvidia*; do
        [ -e "${f}" ] && [ ! -L "${f}" ] || continue
        ln -sf "${f}" "/usr/lib/xorg/modules/drivers/$(basename "${f}")"
    done
}

# Audit DLSS du 30/08 : nvngx.dll/_nvngx.dll (le loader NGX, différent de
# nvngx_dlss.dll fourni par chaque jeu) ne sont PAS installés par
# nvidia-container-toolkit (qui ne monte que les .so), ni par --install-
# compat32-libs ci-dessous (fichiers Windows, absents d'une install Linux
# normale) — pourtant bien présents dans l'archive .run elle-même. Proton/
# GE-Proton les cherche à la création d'un prefix dans un dossier "nvidia/
# wine/" juste à côté de la vraie libGLX_nvidia.so.VERSION en cours d'usage
# (résolu ici via ldconfig, pas un chemin figé — coïncide avec /usr/lib sur
# CachyOS/Arch mais pas garanti ailleurs), et copie silencieusement RIEN si
# absent (confirmé en direct : jeu DX12 + Streamline fonctionnel mais DLSS
# invisible, seul FSR proposé). Extrait une fois depuis le .run déjà en
# cache (même version que le host, pas de téléchargement séparé) et posé à
# cet endroit — un prefix Proton déjà créé avant ce fix doit recevoir une
# copie manuelle dans son propre drive_c/windows/system32/.
install_nvngx_wine_dll() {
    local libglx
    libglx=$(ldconfig -p 2>/dev/null | awk '/libGLX_nvidia\.so\./ {print $NF; exit}')
    [ -n "${libglx}" ] || return 0
    local nvidia_wine_dir
    nvidia_wine_dir="$(dirname "$(readlink -f "${libglx}")")/nvidia/wine"
    [ -f "${nvidia_wine_dir}/nvngx.dll" ] && return 0

    local extract_dir="${CACHE_DIR}/extract-${nvidia_host_driver_version}"
    if [ ! -f "${extract_dir}/nvngx.dll" ]; then
        rm -rf "${extract_dir}"
        "${RUN_FILE}" --extract-only --target "${extract_dir}" >/dev/null 2>&1
    fi
    if [ -f "${extract_dir}/nvngx.dll" ]; then
        mkdir -p "${nvidia_wine_dir}"
        cp "${extract_dir}/nvngx.dll" "${extract_dir}/_nvngx.dll" "${nvidia_wine_dir}/"
        chmod 644 "${nvidia_wine_dir}/nvngx.dll" "${nvidia_wine_dir}/_nvngx.dll"
        echo "[nvidia] nvngx.dll/_nvngx.dll (DLSS) installés dans ${nvidia_wine_dir}"
    else
        echo "[nvidia] nvngx.dll introuvable dans le .run ${nvidia_host_driver_version} — DLSS indisponible sous Proton"
    fi
}

# Bug corrigé (audit 2026-08-26) : "installed_version" était dérivé de
# nvidia-smi, exactement comme "nvidia_host_driver_version" ci-dessus —
# nvidia-smi rapporte TOUJOURS la version du module noyau de l'hôte, que les
# modules X server de ce .run (nvidia_drv.so, libglxserver_nvidia.so) aient
# ou non déjà été installés dans CE conteneur. Les deux valeurs étaient donc
# structurellement toujours égales : la branche "déjà installé, rien à
# faire" était prise à CHAQUE démarrage, et le .run n'était en réalité
# jamais exécuté. Resté sans conséquence pratique jusqu'ici (le runtime
# nvidia-container-toolkit injecte déjà les libs GL/Vulkan userspace, seuls
# les modules Xorg ci-dessous dépendaient réellement de ce script), mais
# rendait ce garde inopérant. On trace maintenant nous-mêmes, dans un fichier
# sur /config (persistant), la version pour laquelle CE script a réellement
# terminé une installation Xorg — seule source fiable de "déjà fait".
INSTALLED_STAMP="${CACHE_DIR}/xorg-modules-version"
installed_version=""
if [ -f "${INSTALLED_STAMP}" ] && [ -e /usr/lib/xorg/modules/drivers/nvidia_drv.so ]; then
    installed_version=$(cat "${INSTALLED_STAMP}")
fi

if [ "${installed_version}" = "${nvidia_host_driver_version}" ]; then
    echo "[nvidia] Modules Xorg ${installed_version} déjà installés — rien à faire"
    fix_xorg_module_paths
    install_nvngx_wine_dll
    exit 0
fi

echo "[nvidia] Installé : ${installed_version:-aucun} → cible : ${nvidia_host_driver_version}"

if [ ! -f "${RUN_FILE}" ]; then
    echo "[nvidia] ERREUR : ${RUN_FILE} absent (échec de téléchargement) — impossible d'installer les modules Xorg"
    exit 1
fi

echo "[nvidia] Installation en cours... (log : ${LOG_FILE})"

INSTALL_ARGS=(
    --silent
    --accept-license
    --skip-depmod
    --skip-module-unload
    --no-kernel-module-source
    --install-compat32-libs
    --no-nouveau-check
    --no-nvidia-modprobe
    --no-systemd
    --no-distro-scripts
    --no-rpms
    --no-backup
    --no-check-for-alternate-installs
    --no-libglx-indirect
    --no-install-libglvnd
    --no-x-check
    # --no-x-check + --no-distro-scripts désactivent la détection auto du
    # layout Xorg de la distro — l'installeur retombe alors sur un chemin
    # générique /usr/lib64/xorg/modules. Ça se trouve marcher sur CachyOS/
    # Arch (Xorg y cherche aussi dans ce chemin) mais PAS sur Ubuntu/Debian
    # (Xorg n'y cherche que /usr/lib/xorg/modules, sans "64") — confirmé en
    # direct : nvidia_drv.so installé mais introuvable par Xorg, fallback
    # silencieux sur le driver "modeset" générique, échec ensuite ("AddScreen
    # /ScreenInit failed"). Chemin forcé explicitement, valable sur les deux.
    --x-module-path=/usr/lib/xorg/modules
)

major_version=$(echo "${nvidia_host_driver_version}" | cut -d'.' -f1)
if [ "${major_version}" -ge 500 ] 2>/dev/null; then
    INSTALL_ARGS+=(--no-kernel-modules)
else
    INSTALL_ARGS+=(--no-kernel-module)
fi

"${RUN_FILE}" "${INSTALL_ARGS[@]}" >"${LOG_FILE}" 2>&1
exit_code=$?

# Filet de sécurité même après une installation fraîche : --x-module-path
# ne couvre pas forcément tous les sous-chemins (ex: modules/extensions/
# pour libglxserver_nvidia.so) selon la version de l'installeur.
fix_xorg_module_paths
install_nvngx_wine_dll

installed_after=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | extract_driver_version)
if [ "${installed_after}" = "${nvidia_host_driver_version}" ]; then
    echo "[nvidia] Installation réussie — ${installed_after}"
    echo "${nvidia_host_driver_version}" > "${INSTALLED_STAMP}"
elif [ ${exit_code} -eq 0 ]; then
    echo "[nvidia] Installation réussie (exit 0)"
    echo "${nvidia_host_driver_version}" > "${INSTALLED_STAMP}"
else
    non_busy_errors=$(grep "^ERROR" "${LOG_FILE}" | grep -v "Device or resource busy" | wc -l)
    if [ "${non_busy_errors}" -eq 0 ]; then
        echo "[nvidia] Installation OK (fichiers toolkit déjà en place, erreurs 'busy' ignorées)"
        echo "${nvidia_host_driver_version}" > "${INSTALLED_STAMP}"
    else
        echo "[nvidia] ERREUR installation (code ${exit_code}) — voir ${LOG_FILE}"
        tail -20 "${LOG_FILE}"
        exit 1
    fi
fi
