#!/bin/bash
# "detached" de l'entrée Sunshine "Desktop" : le KWin de streaming
# (wayland-stream) ne lance rien lui-même, "Desktop" sous Moonlight donnait
# un écran vide sans ce script (05/09). Lance plasmashell (panneau, menu,
# fond) sur ce KWin depuis le 24/11 — XFCE (xfsettingsd, xfdesktop,
# xfce4-panel) avant, retiré avec labwc.
#
# Bus bus-stream (celui du KWin de streaming, publié par
# kwin-stream-session.sh) : plasmashell est unique PAR BUS, et le bureau
# navigateur a déjà le sien sur le bus principal.
set -uo pipefail

XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_RUNTIME_DIR
# shellcheck source=steambox-env.sh
. /usr/local/bin/scripts/steambox-env.sh
# Exports explicites plutôt que confiance dans l'héritage de l'environnement
# de Sunshine : ce projet a déjà été pris en défaut plusieurs fois par une
# variable supposée héritée qui ne l'était pas. Refus franc sans session
# (pas de dongle, ou KWin arrêté par une session Mode SteamOS).
if ! stream_session_env; then
    echo "[sunshine-desktop] session KWin de streaming absente (steambox-stream-session.env)" >&2
    exit 1
fi
export XDG_CURRENT_DESKTOP=KDE QT_QPA_PLATFORM=wayland

PIDFILE="${XDG_RUNTIME_DIR}/sunshine-desktop.pid"

# Idempotent : Sunshine relance ce "detached" à chaque connexion à l'app
# "Desktop", pas seulement au premier lancement. $$ est stable à travers le
# exec plus bas (remplace l'image du process sans changer son PID) : ce
# PID reste celui de plasmashell tant qu'il tourne.
if [ -f "${PIDFILE}" ] && kill -0 "$(cat "${PIDFILE}" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi
echo "$$" > "${PIDFILE}"

# Configuration à part (24/11) : le bureau navigateur fait tourner un autre
# plasmashell avec le même HOME, et deux instances qui réécrivent le même
# plasma-org.kde.plasma.desktop-appletsrc se marchent dessus (panneaux,
# disposition par écran). Seul plasmashell est séparé, par un paquet de shell
# copié sous un autre identifiant (org.steambox.stream → fichier
# plasma-org.steambox.stream-appletsrc) : les applis lancées depuis ce bureau
# gardent le ~/.config commun (pas de XDG_CONFIG_HOME à part, qu'elles
# hériteraient). Copie refaite si celle du système a changé (mise à jour de
# Plasma).
SRC=/usr/share/plasma/shells/org.kde.plasma.desktop
SHELL_DIR="${HOME}/.local/share/plasma/shells/org.steambox.stream"
SRC_SUM=$(sha256sum "${SRC}/metadata.json" 2>/dev/null | cut -d' ' -f1)
if [ ! -e "${SHELL_DIR}/metadata.json" ] || [ "$(cat "${SHELL_DIR}/.steambox-src" 2>/dev/null)" != "${SRC_SUM}" ]; then
    rm -rf "${SHELL_DIR}"
    mkdir -p "$(dirname "${SHELL_DIR}")"
    cp -r "${SRC}" "${SHELL_DIR}"
    printf '%s' "${SRC_SUM}" > "${SHELL_DIR}/.steambox-src"
    python3 -I -c 'import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["KPlugin"]["Id"] = "org.steambox.stream"
json.dump(d, open(p, "w"), indent=4)' "${SHELL_DIR}/metadata.json"
fi
mkdir -p "${HOME}/.config" "${HOME}/.local/share"
cd "${HOME}" || exit 1

exec plasmashell --shell-plugin org.steambox.stream
