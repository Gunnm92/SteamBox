#!/bin/bash
# ArcadeBox — Installation driver NVIDIA userspace (matching version du host)
# Placé dans /config/custom-cont-init.d/ → exécuté par s6 avant les services
#
# Le driver kernel tourne sur le host ; on installe ici uniquement les libs
# userspace (--no-kernel-modules) pour avoir la bonne version dans le conteneur.

CACHE_DIR="/config/nvidia-drivers"
LOG_FILE="${CACHE_DIR}/install.log"
mkdir -p "${CACHE_DIR}"

# ── 1. Détecter la version driver du host ─────────────────────────────────────

# nvidia-smi --query-gpu échoue si version mismatch → utiliser --version ou /proc.
# On extrait un numéro de version, jamais le dernier champ : en cas d'erreur
# nvidia-smi affiche des phrases comme "... use nvidia-smi -q instead", et un
# awk '{print $NF}' renvoyait alors "instead" comme numéro de version.
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
    # Format : "NVRM version: NVIDIA UNIX ... Kernel Module  610.43.03  ..."
    nvidia_host_driver_version=$(
        grep -oE 'Kernel Module[[:space:]]+[0-9.]+' /proc/driver/nvidia/version 2>/dev/null \
            | extract_driver_version
    )
fi

if [ -z "${nvidia_host_driver_version}" ]; then
    echo "[nvidia] Impossible de détecter la version driver — skip"
    exit 0
fi

echo "[nvidia] Version driver host : ${nvidia_host_driver_version}"

# ── 2. Vérifier si déjà installé à la bonne version ──────────────────────────

installed_version=$(nvidia-settings --version 2>/dev/null \
    | grep -i "version" \
    | extract_driver_version)

if [ "${installed_version}" = "${nvidia_host_driver_version}" ]; then
    echo "[nvidia] Driver ${installed_version} déjà installé — rien à faire"
    exit 0
fi

echo "[nvidia] Installé : ${installed_version:-aucun} → cible : ${nvidia_host_driver_version}"

# ── 3. Télécharger le .run si absent du cache ─────────────────────────────────

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
        if wget -q --show-progress --progress=bar:force:noscroll \
                -O "${RUN_FILE}.tmp" "${url}" 2>&1; then
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
        echo "[nvidia] Vérifier manuellement : https://download.nvidia.com/XFree86/Linux-x86_64/"
        exit 1
    fi
fi

# ── 4. Installation (userspace uniquement, sans module kernel) ─────────────────

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

# --no-kernel-modules (drivers >= 500) vs --no-kernel-module (drivers < 500)
major_version=$(echo "${nvidia_host_driver_version}" | cut -d'.' -f1)
if [ "${major_version}" -ge 500 ] 2>/dev/null; then
    INSTALL_ARGS+=(--no-kernel-modules)
else
    INSTALL_ARGS+=(--no-kernel-module)
fi

# NB : l'ancien patch du flag --no-multigpu visait /etc/cont-init.d/70-configure_xorg.sh,
# répertoire qui n'existe plus (s6-overlay v3) — le sed était sans effet et a été retiré.

"${RUN_FILE}" "${INSTALL_ARGS[@]}" >"${LOG_FILE}" 2>&1
exit_code=$?

# Les fichiers "Device or resource busy" sont déjà montés par nvidia-container-toolkit
# à la bonne version → erreurs non fatales, vérifier nvidia-settings pour confirmer
installed_after=$(nvidia-settings --version 2>/dev/null | grep -i "version" | extract_driver_version)
if [ "${installed_after}" = "${nvidia_host_driver_version}" ]; then
    echo "[nvidia] Installation réussie — nvidia-settings ${installed_after}"
elif [ ${exit_code} -eq 0 ]; then
    echo "[nvidia] Installation réussie — $(nvidia-settings --version 2>/dev/null | grep version | head -1)"
else
    # Vérifier si seules les erreurs "busy" sont présentes (fichiers déjà montés par toolkit)
    non_busy_errors=$(grep "^ERROR" "${LOG_FILE}" | grep -v "Device or resource busy" | wc -l)
    if [ "${non_busy_errors}" -eq 0 ]; then
        echo "[nvidia] Installation OK (fichiers toolkit déjà en place, erreurs 'busy' ignorées)"
    else
        echo "[nvidia] ERREUR installation (code ${exit_code}) — voir ${LOG_FILE}"
        tail -20 "${LOG_FILE}"
        exit 1
    fi
fi
