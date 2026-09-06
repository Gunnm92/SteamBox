#!/bin/bash
# SteamBox (CachyOS) — Extraction du DLL DLSS (nvngx.dll/_nvngx.dll) et des
# libs userspace NVIDIA 32 bits, depuis l'installeur .run NVIDIA officiel
# matché à la version du driver host.
#
# Réduit (audit M4, 05/09) depuis une version qui installait aussi les
# modules Xorg (nvidia_drv.so, libglxserver_nvidia.so) — legs d'une
# architecture antérieure à labwc/Xwayland (voir Dockerfile.cachyos, points
# 4-5 de l'historique) : il n'y a plus AUCUN Xorg dans cette architecture,
# ces modules ne sont jamais chargés par personne. Avant ce correctif,
# chaque changement de version driver hôte déclenchait l'installeur .run
# COMPLET pour poser des fichiers morts, ET laissait l'extraction
# intermédiaire sur disque indéfiniment (cache persistant sur /config,
# jamais nettoyé) — mesuré en direct le 05/09 : 2,2 Go dans
# /config/nvidia-drivers pour deux DLL de 30 Mo au total.
#
# Compat32 réintroduit (06/09, audit log wine "Sega Rally 2") : l'audit M4
# avait aussi supprimé --install-compat32-libs en le confondant avec les
# modules Xorg — or nvidia-container-toolkit n'injecte QUE les libs 64 bits
# au démarrage du conteneur ; sans les libs NVIDIA 32 bits, TOUT jeu Windows
# 32 bits (l'immense majorité des wsquashfs — start.bat lance en général un
# .exe PE32, pas PE32+) retombe silencieusement sur llvmpipe (rendu logiciel
# CPU) — confirmé en direct : "MESA-EGL: ... failed to create dri2 screen",
# "wined3d_guess_card No card selector available for card vendor 0000
# (using GL_RENDERER llvmpipe...)". Set minimal identifié en direct (pas de
# CUDA/OpenCL/vidéo, seulement GL/EGL/GBM) : glcore+eglcore+glsi+tls+
# allocator+gpucomp (dépendance de glcore) + GLX_nvidia/EGL_nvidia eux-mêmes
# + egl-gbm (chemin de rendu réellement pris ici : EGL_PLATFORM_GBM/DRM
# direct, pas GLX/X11 classique — le symlink /usr/lib32/gbm/nvidia-drm_gbm.so
# est nécessaire en plus, sans quoi libgbm ne trouve aucun backend NVIDIA et
# retombe sur dri_gbm.so, qui ne sait rien faire d'une carte NVIDIA sans
# nouveau). lib32-libglvnd/lib32-mesa restent le paquet Arch (dispatch GL/EGL
# générique, vendor-neutre) — on n'installe QUE l'implémentation vendor
# NVIDIA par-dessus, jamais les fichiers glvnd eux-mêmes (risque de
# désaccord de version avec le paquet Arch déjà en place).

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
    echo "[nvidia] libGLX_nvidia introuvable — runtime nvidia-container-toolkit pas encore prêt, rien installé cette fois"
    exit 0
fi
nvidia_wine_dir="$(dirname "$(readlink -f "${libglx}")")/nvidia/wine"

# Chemin 32 bits Arch/CachyOS — cette image n'a qu'une seule distro cible
# (voir pacman/multilib dans Dockerfile.cachyos), pas besoin de détecter
# /usr/lib/i386-linux-gnu façon Debian.
LIB32_DIR="/usr/lib32"

need_dlss=false
[ -f "${nvidia_wine_dir}/nvngx.dll" ] || need_dlss=true

need_compat32=false
if [ -d "${LIB32_DIR}" ] && [ ! -f "${LIB32_DIR}/libGLX_nvidia.so.${nvidia_host_driver_version}" ]; then
    need_compat32=true
fi

if [ "${need_dlss}" = false ] && [ "${need_compat32}" = false ]; then
    echo "[nvidia] DLSS + libs 32 bits déjà en place pour ${nvidia_host_driver_version} — rien à faire"
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
# mktemp -u (ne crée rien, donne juste un nom) : --extract-only crée
# lui-même le dossier cible et REFUSE s'il existe déjà ("The directory
# ... already exists") — avec un mktemp -d classique (qui pré-crée le
# dossier), cet appel échouait silencieusement depuis toujours (stderr vers
# /dev/null) et n'a donc jamais réellement extrait quoi que ce soit,
# confirmé en direct le 06/09.
extract_dir=$(mktemp -u -d "${CACHE_DIR}/extract-XXXXXX")
"${RUN_FILE}" --extract-only --target "${extract_dir}" >/dev/null 2>&1

if [ "${need_dlss}" = true ]; then
    if [ -f "${extract_dir}/nvngx.dll" ]; then
        mkdir -p "${nvidia_wine_dir}"
        cp "${extract_dir}/nvngx.dll" "${extract_dir}/_nvngx.dll" "${nvidia_wine_dir}/"
        chmod 644 "${nvidia_wine_dir}/nvngx.dll" "${nvidia_wine_dir}/_nvngx.dll"
        echo "[nvidia] nvngx.dll/_nvngx.dll (DLSS) installés dans ${nvidia_wine_dir}"
    else
        echo "[nvidia] nvngx.dll introuvable dans le .run ${nvidia_host_driver_version} — DLSS indisponible sous Proton"
    fi
fi

if [ "${need_compat32}" = true ]; then
    compat32_src="${extract_dir}/32"
    if [ -d "${compat32_src}" ]; then
        # Set minimal GL/EGL/GBM — jamais les fichiers CUDA/OpenCL/vidéo
        # (libnvidia-cuda/opencl/nvvm/ptxjitcompiler/tileiras/encode/fbc/
        # vdpau/opticalflow), inutiles pour du rendu 3D et qui gonfleraient
        # /usr/lib32 de plusieurs centaines de Mo pour rien.
        declare -a compat32_files=(
            "libGLX_nvidia.so.${nvidia_host_driver_version}"
            "libEGL_nvidia.so.${nvidia_host_driver_version}"
            "libnvidia-glsi.so.${nvidia_host_driver_version}"
            "libnvidia-tls.so.${nvidia_host_driver_version}"
            "libnvidia-glcore.so.${nvidia_host_driver_version}"
            "libnvidia-eglcore.so.${nvidia_host_driver_version}"
            "libnvidia-gpucomp.so.${nvidia_host_driver_version}"
            "libnvidia-allocator.so.${nvidia_host_driver_version}"
            # libnvidia-glvkspirv.so : compilateur SPIR-V, requis par l'ICD
            # Vulkan NVIDIA (/etc/vulkan/icd.d/nvidia_icd.json pointe sur
            # libGLX_nvidia.so.0, déjà couvert ci-dessus, mais celui-ci
            # dlopen ce compilateur au premier device — sans lui
            # vkCreateInstance réussit mais vkEnumeratePhysicalDevices
            # renvoie 0 device, confirmé en direct). Nécessaire pour tout
            # jeu 32 bits passant par VKD3D/DXVK plutôt que par GL/wined3d.
            "libnvidia-glvkspirv.so.${nvidia_host_driver_version}"
        )
        copied_any=false
        for f in "${compat32_files[@]}"; do
            if [ -f "${compat32_src}/${f}" ]; then
                cp -f "${compat32_src}/${f}" "${LIB32_DIR}/${f}"
                copied_any=true
            else
                echo "[nvidia] compat32 : ${f} absent du .run ${nvidia_host_driver_version}"
            fi
        done
        # libnvidia-egl-gbm.so a son propre numéro de version (ex: 1.1.3),
        # indépendant de la version du driver — recherché par motif plutôt
        # que par nom figé. Chemin de rendu réellement pris par les jeux
        # 32 bits ici (EGL_PLATFORM_GBM/DRM direct, pas GLX/X11 classique) :
        # sans cette lib ET le symlink gbm/ ci-dessous, libgbm retombe sur
        # le backend Mesa générique, qui ne sait rien faire d'une carte
        # NVIDIA (pas de nouveau chargé) — confirmé en direct : llvmpipe.
        egl_gbm_src=$(find "${compat32_src}" -maxdepth 1 -name 'libnvidia-egl-gbm.so.*' -print -quit 2>/dev/null)
        if [ -n "${egl_gbm_src}" ]; then
            cp -f "${egl_gbm_src}" "${LIB32_DIR}/$(basename "${egl_gbm_src}")"
            copied_any=true
        else
            echo "[nvidia] compat32 : libnvidia-egl-gbm.so absent du .run ${nvidia_host_driver_version}"
        fi
        if [ "${copied_any}" = true ]; then
            ldconfig
            mkdir -p "${LIB32_DIR}/gbm"
            ln -sf ../libnvidia-allocator.so.1 "${LIB32_DIR}/gbm/nvidia-drm_gbm.so"
            echo "[nvidia] Libs userspace NVIDIA 32 bits installées dans ${LIB32_DIR} pour ${nvidia_host_driver_version}"
        fi
    else
        echo "[nvidia] compat32 : dossier 32/ absent du .run ${nvidia_host_driver_version} (driver sans support 32 bits ?)"
    fi
fi

rm -rf "${extract_dir}"
