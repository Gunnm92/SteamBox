#!/bin/bash
set -e

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
USER_NAME=arcade
XDG_RUNTIME_DIR="/run/user/${PUID}"

# ── 0. Alignement UID/GID sur le volume /config monté (comme PUID/PGID webstation) ─
if [ "$(id -u "${USER_NAME}")" != "${PUID}" ] || [ "$(id -g "${USER_NAME}")" != "${PGID}" ]; then
    groupmod -o -g "${PGID}" "${USER_NAME}"
    usermod -o -u "${PUID}" -g "${PGID}" "${USER_NAME}"
fi
mkdir -p /config
chown "${PUID}:${PGID}" /config
# Le home réel vit sur le volume /config (persistant), pas dans le rootfs image.
if [ ! -d /config/.config ]; then
    cp -a /home/"${USER_NAME}"/. /config/ 2>/dev/null || true
fi
rm -rf /home/"${USER_NAME}"
ln -sfn /config /home/"${USER_NAME}"

# ── 1. Driver NVIDIA userspace (matché au host) ───────────────────────────────
/usr/local/bin/install-nvidia-userspace.sh || echo "[entrypoint] Continuer sans match NVIDIA (voir logs ci-dessus)"

# ── 2. Nettoyage d'un boot précédent ───────────────────────────────────────────
echo "--- [Boot] Nettoyage ---"
killall -9 -q sunshine Hyprland steam seatd wayvnc pipewire wireplumber 2>/dev/null || true
rm -rf "${XDG_RUNTIME_DIR}" /run/seatd.sock /tmp/.X* 2>/dev/null || true
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"
chown "${PUID}:${PGID}" "${XDG_RUNTIME_DIR}"

export XDG_RUNTIME_DIR SEATD_VTBOUND=0 LIBSEAT_BACKEND=seatd

# Permissions génériques input/GPU — device_cgroup_rules côté docker-compose
# gère déjà l'accès cgroup, ceci couvre la permission Unix classique.
chmod 666 /dev/uinput /dev/dri/card* /dev/dri/renderD* /dev/input/event* 2>/dev/null || true

for script in init_system init_audio init_sunshine; do
    if [ -x "/usr/local/bin/scripts/${script}.sh" ]; then
        "/usr/local/bin/scripts/${script}.sh"
    fi
done

# ── 3. Boucle superviseur ──────────────────────────────────────────────────────
while true; do
    echo "--- [Superviseur] Démarrage de la session ---"

    killall -q sunshine Hyprland steam seatd wayvnc 2>/dev/null || true
    sleep 1
    killall -9 -q sunshine Hyprland steam seatd wayvnc 2>/dev/null || true
    rm -rf "${XDG_RUNTIME_DIR}/wayland-0" /run/seatd.sock

    udevadm trigger --action=change --subsystem-match=input 2>/dev/null || true
    udevadm trigger --action=change --subsystem-match=drm 2>/dev/null || true
    sleep 0.5

    echo "    [Superviseur] Démarrage de seatd..."
    seatd -g video &
    SEATD_PID=$!
    TIMEOUT=10
    while [ ! -S /run/seatd.sock ] && [ "${TIMEOUT}" -gt 0 ]; do
        sleep 0.2
        TIMEOUT=$((TIMEOUT - 1))
    done
    chmod 777 /run/seatd.sock 2>/dev/null || true

    echo "    [Superviseur] Lancement de la session Hyprland..."
    runuser -u "${USER_NAME}" -- /usr/local/bin/scripts/hypr-session.sh &
    SESSION_PID=$!

    TIMEOUT=30
    while [ ! -S "${XDG_RUNTIME_DIR}/wayland-0" ] && [ "${TIMEOUT}" -gt 0 ]; do
        sleep 0.5
        TIMEOUT=$((TIMEOUT - 1))
    done

    if [ -S "${XDG_RUNTIME_DIR}/wayland-0" ]; then
        sleep 2
        echo "    [Superviseur] Démarrage de Sunshine et wayvnc..."
        runuser -u "${USER_NAME}" -- env WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
            sunshine "/config/.config/sunshine/sunshine.conf" &
        SUNSHINE_PID=$!
        runuser -u "${USER_NAME}" -- env WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
            wayvnc --websocket --render-cursor --max-fps=60 0.0.0.0 5900 &
        WAYVNC_PID=$!
    else
        echo "    [Superviseur] ERREUR : socket wayland-0 introuvable, Hyprland n'a pas démarré."
    fi

    runuser -u "${USER_NAME}" -- python3 -m http.server 6080 --directory /usr/share/webapps/novnc --bind 0.0.0.0 &
    NOVNC_PID=$!

    while kill -0 "${SESSION_PID}" 2>/dev/null; do
        sleep 1
    done

    echo "--- [Superviseur] Fin de session, redémarrage... ---"
    for pid in "${SUNSHINE_PID:-}" "${WAYVNC_PID:-}" "${NOVNC_PID:-}" "${SEATD_PID:-}"; do
        [ -n "${pid}" ] && kill "${pid}" 2>/dev/null || true
    done
    sleep 1
done
