#!/bin/bash
# SteamBox (CachyOS) — Extraction du DLL DLSS (nvngx.dll/_nvngx.dll) depuis
# l'installeur .run NVIDIA officiel, matché à la version du driver host.
#
# Réduit (audit M4, 05/09) depuis une version qui installait aussi les
# modules Xorg (nvidia_drv.so, libglxserver_nvidia.so, --install-compat32-
# libs) — legs d'une architecture antérieure à labwc/Xwayland (voir
# Dockerfile.cachyos, points 4-5 de l'historique) : il n'y a plus AUCUN
# Xorg dans cette architecture, ces modules ne sont jamais chargés par
# personne. Avant ce correctif, chaque changement de version driver hôte
# déclenchait l'installeur .run COMPLET pour poser des fichiers morts, ET
# laissait l'extraction intermédiaire sur disque indéfiniment (cache
# persistant sur /config, jamais nettoyé) — mesuré en direct le 05/09 :
# 2,2 Go dans /config/nvidia-drivers pour deux DLL de 30 Mo au total.
# Seule la partie DLSS (nvngx.dll/_nvngx.dll, cherchée par Proton/GE-Proton
# dans un dossier "nvidia/wine/" à la création d'un prefix) reste
# nécessaire : le runtime nvidia-container-toolkit injecte déjà toutes les
# libs GL/Vulkan userspace réelles au démarrage du conteneur, indépendamment
# de ce script.

set -uo pipefail

CACHE_DIR="/config/nvidia-drivers"
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

# libGLX_nvidia.so.<version> (posée par nvidia-container-toolkit au
# démarrage du conteneur, résolue via ldconfig plutôt qu'un chemin figé —
# coïncide avec /usr/lib sur CachyOS/Arch mais pas garanti ailleurs) sert
# de repère pour savoir où Proton/GE-Proton ira chercher nvngx.dll.
libglx=$(ldconfig -p 2>/dev/null | awk '/libGLX_nvidia\.so\./ {print $NF; exit}')
if [ -z "${libglx}" ]; then
    echo "[nvidia] libGLX_nvidia introuvable — runtime nvidia-container-toolkit pas encore prêt, DLSS non installé cette fois"
    exit 0
fi
nvidia_wine_dir="$(dirname "$(readlink -f "${libglx}")")/nvidia/wine"
if [ -f "${nvidia_wine_dir}/nvngx.dll" ]; then
    echo "[nvidia] nvngx.dll déjà en place pour ${nvidia_host_driver_version} — rien à faire"
    exit 0
fi

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
        echo "[nvidia] ERREUR : téléchargement impossible pour ${nvidia_host_driver_version} — DLSS indisponible sous Proton"
        exit 0
    fi
fi
chmod +x "${RUN_FILE}" 2>/dev/null || true

# Extraction dans un dossier TEMPORAIRE, supprimé immédiatement après copie
# (audit M4, 05/09) — contrairement à l'ancienne version qui gardait cette
# extraction en cache indéfiniment sur /config pour un usage différé
# (l'install Xorg) qui n'existe plus ici.
extract_dir=$(mktemp -d "${CACHE_DIR}/extract-XXXXXX")
"${RUN_FILE}" --extract-only --target "${extract_dir}" >/dev/null 2>&1

if [ -f "${extract_dir}/nvngx.dll" ]; then
    mkdir -p "${nvidia_wine_dir}"
    cp "${extract_dir}/nvngx.dll" "${extract_dir}/_nvngx.dll" "${nvidia_wine_dir}/"
    chmod 644 "${nvidia_wine_dir}/nvngx.dll" "${nvidia_wine_dir}/_nvngx.dll"
    echo "[nvidia] nvngx.dll/_nvngx.dll (DLSS) installés dans ${nvidia_wine_dir}"
else
    echo "[nvidia] nvngx.dll introuvable dans le .run ${nvidia_host_driver_version} — DLSS indisponible sous Proton"
fi

rm -rf "${extract_dir}"
