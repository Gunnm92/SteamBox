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
killall -9 -q sunshine Hyprland steam seatd wayvnc websockify pipewire wireplumber 2>/dev/null || true
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

# ── 2a. udevd — nécessaire pour le hotplug (souris/clavier virtuels Sunshine) ──
# Sans démon udev tournant en continu, les périphériques uinput que Sunshine
# crée à la connexion d'un client (ex: "Mouse passthrough") existent bien au
# niveau noyau (/proc/bus/input/devices) mais libinput/Hyprland ne les
# détecte jamais : udevd tournant en continu les capte nativement via
# netlink dès leur création, sans avoir besoin de rejouer quoi que ce soit.
#
# IMPORTANT : ne JAMAIS faire `udevadm trigger` sur le sous-système input.
# /sys reflète le vrai matériel de l'hôte (non isolé par les namespaces
# Docker), donc un trigger rejoue aussi les uevents des VRAIS clavier/souris
# de l'hôte Unraid, qu'udevd matérialise alors comme périphériques dans le
# conteneur — exactement l'incident déjà rencontré sur l'image webstation.
# Sans trigger, seuls les nouveaux hotplugs (les devices virtuels créés
# après coup par Sunshine) sont capturés ; le matériel déjà présent avant
# le démarrage d'udevd n'est jamais découvert. Testé et confirmé en direct.
if ! pgrep -f systemd-udevd >/dev/null; then
    /usr/lib/systemd/systemd-udevd --daemon
    sleep 1
    udevadm trigger --action=add --subsystem-match=drm 2>/dev/null || true
    udevadm settle --timeout=5 2>/dev/null || true
fi

# ── 2b. D-Bus système + NetworkManager (non-géré) ──────────────────────────────
# Nécessaire uniquement pour que Steam trouve un client NetworkManager D-Bus
# et sorte de "waiting for network" — NetworkManager.conf (unmanaged-devices=*)
# l'empêche de toucher aux vraies interfaces de l'hôte (network_mode: host).
[ -f /etc/machine-id ] || dbus-uuidgen --ensure=/etc/machine-id
mkdir -p /run/dbus
if [ ! -S /run/dbus/system_bus_socket ]; then
    dbus-daemon --system --fork
fi
if ! pgrep -x NetworkManager >/dev/null; then
    NetworkManager --no-daemon &
fi

# ── 3. Boucle superviseur ──────────────────────────────────────────────────────
while true; do
    echo "--- [Superviseur] Démarrage de la session ---"

    killall -q sunshine Hyprland steam seatd wayvnc websockify 2>/dev/null || true
    sleep 1
    killall -9 -q sunshine Hyprland steam seatd wayvnc websockify 2>/dev/null || true
    rm -rf "${XDG_RUNTIME_DIR}"/wayland-* "${XDG_RUNTIME_DIR}/.wayland-socket-name" /run/seatd.sock

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
    rm -f "${XDG_RUNTIME_DIR}/.wayland-socket-name"
    runuser -u "${USER_NAME}" -- /usr/local/bin/scripts/hypr-session.sh &
    SESSION_PID=$!

    TIMEOUT=30
    while [ ! -f "${XDG_RUNTIME_DIR}/.wayland-socket-name" ] && [ "${TIMEOUT}" -gt 0 ]; do
        sleep 0.5
        TIMEOUT=$((TIMEOUT - 1))
    done
    WAYLAND_SOCK_NAME=$(cat "${XDG_RUNTIME_DIR}/.wayland-socket-name" 2>/dev/null || true)

    if [ -n "${WAYLAND_SOCK_NAME}" ] && [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_SOCK_NAME}" ]; then
        sleep 2
        echo "    [Superviseur] Démarrage de Sunshine et wayvnc (${WAYLAND_SOCK_NAME})..."
        # Sunshine/wayvnc peuvent crasher sans que ça ne tue la session
        # Hyprland — on les respawn en boucle tant que la session tourne,
        # plutôt que de les laisser morts jusqu'au prochain cycle complet.
        (
            while kill -0 "${SESSION_PID}" 2>/dev/null; do
                runuser -u "${USER_NAME}" -- env WAYLAND_DISPLAY="${WAYLAND_SOCK_NAME}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" DISPLAY=:0 \
                    sunshine "/config/.config/sunshine/sunshine.conf"
                kill -0 "${SESSION_PID}" 2>/dev/null && sleep 2
            done
        ) &
        SUNSHINE_PID=$!
        # wayvnc --websocket (0.10.1) crashe (double free) dès qu'un client
        # websocket se connecte — bug upstream connu (any1/wayvnc#319). On
        # sert le RFB brut en interne (5901) et on websocket-ifie via
        # websockify, l'architecture noVNC classique/éprouvée, plutôt que
        # de dépendre de l'implémentation websocket native de wayvnc.
        (
            while kill -0 "${SESSION_PID}" 2>/dev/null; do
                runuser -u "${USER_NAME}" -- env WAYLAND_DISPLAY="${WAYLAND_SOCK_NAME}" XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
                    wayvnc --render-cursor --max-fps=60 127.0.0.1 5901
                kill -0 "${SESSION_PID}" 2>/dev/null && sleep 2
            done
        ) &
        WAYVNC_PID=$!
        (
            while kill -0 "${SESSION_PID}" 2>/dev/null; do
                websockify 0.0.0.0:5900 127.0.0.1:5901
                kill -0 "${SESSION_PID}" 2>/dev/null && sleep 2
            done
        ) &
        WEBSOCKIFY_PID=$!
    else
        echo "    [Superviseur] ERREUR : aucun socket Wayland détecté, Hyprland n'a pas démarré."
    fi

    runuser -u "${USER_NAME}" -- python3 -m http.server 6080 --directory /usr/share/webapps/novnc --bind 0.0.0.0 &
    NOVNC_PID=$!

    while kill -0 "${SESSION_PID}" 2>/dev/null; do
        sleep 1
    done

    echo "--- [Superviseur] Fin de session, redémarrage... ---"
    for pid in "${SUNSHINE_PID:-}" "${WAYVNC_PID:-}" "${WEBSOCKIFY_PID:-}" "${NOVNC_PID:-}" "${SEATD_PID:-}"; do
        [ -n "${pid}" ] && kill "${pid}" 2>/dev/null || true
    done
    sleep 1
done
