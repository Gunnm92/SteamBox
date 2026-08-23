#!/bin/bash
# ArcadeBox (CachyOS) — Installation driver NVIDIA userspace, matché à la
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

installed_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | extract_driver_version)

if [ "${installed_version}" = "${nvidia_host_driver_version}" ]; then
    echo "[nvidia] Driver ${installed_version} déjà installé — rien à faire"
    exit 0
fi

echo "[nvidia] Installé : ${installed_version:-aucun} → cible : ${nvidia_host_driver_version}"

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
        echo "[nvidia] ERREUR : téléchargement impossible pour ${nvidia_host_driver_version}"
        exit 1
    fi
fi

echo "[nvidia] Installation en cours... (log : ${LOG_FILE})"
chmod +x "${RUN_FILE}"

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
)

major_version=$(echo "${nvidia_host_driver_version}" | cut -d'.' -f1)
if [ "${major_version}" -ge 500 ] 2>/dev/null; then
    INSTALL_ARGS+=(--no-kernel-modules)
else
    INSTALL_ARGS+=(--no-kernel-module)
fi

"${RUN_FILE}" "${INSTALL_ARGS[@]}" >"${LOG_FILE}" 2>&1
exit_code=$?

installed_after=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | extract_driver_version)
if [ "${installed_after}" = "${nvidia_host_driver_version}" ]; then
    echo "[nvidia] Installation réussie — ${installed_after}"
elif [ ${exit_code} -eq 0 ]; then
    echo "[nvidia] Installation réussie (exit 0)"
else
    non_busy_errors=$(grep "^ERROR" "${LOG_FILE}" | grep -v "Device or resource busy" | wc -l)
    if [ "${non_busy_errors}" -eq 0 ]; then
        echo "[nvidia] Installation OK (fichiers toolkit déjà en place, erreurs 'busy' ignorées)"
    else
        echo "[nvidia] ERREUR installation (code ${exit_code}) — voir ${LOG_FILE}"
        tail -20 "${LOG_FILE}"
        exit 1
    fi
fi
