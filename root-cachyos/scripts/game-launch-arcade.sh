#!/bin/bash
# Lanceur des systèmes d'arcade PC (06/11) : un même dossier de roms mêle
# deux formats, comme chez RGS (es_systems_segare.cfg… : .wsquashfs et
# .squashfs/.windowsloader sur le même système) :
#   - .wsquashfs : prefix Wine + autorun.cmd → wsquashfs-launcher (inchangé) ;
#   - .squashfs / .windowsloader : dump brut du jeu + <gameid>.windowsloader
#     (l'exe à lancer) → arcade-launcher, le « Windows arcade loader » de RGS.
#     Il monte lui-même l'image (squashfuse + fuse-overlayfs), crée son prefix,
#     injecte les DLL qui émulent le matériel de la borne (JVS, NESiCA,
#     dongle, retour de force) et gère manettes/clavier/pistolets d'après le
#     profil du jeu (systemprofiles/<système>/<gameid>.yaml).
# Le loader n'est pas dans l'image : il vit dans le home persistant
# (${WAL_DIR}), mis à jour depuis le pack RGS sans reconstruire l'image.
# launcher.yaml y est adapté à SteamBox (runner dans runners/, écritures dans
# saves/<système>/<image> comme Batocera ; l'original : launcher.yaml.rgs).
set -euo pipefail

# shellcheck source=launch-error.sh
. /usr/local/bin/scripts/launch-error.sh

ROM="${1:?usage : $0 <jeu.wsquashfs|jeu.squashfs|dossier/jeu.windowsloader>}"
WSQUASHFS="${HOME}/.local/bin/wsquashfs-launcher"
WAL_DIR="${WAL_DIR:-${HOME}/.local/share/windows-arcade-loader}"

case "${ROM,,}" in
    *.wsquashfs)
        exec "${WSQUASHFS}" "${ROM}"
        ;;
    *.squashfs|*.windowsloader)
        if [[ ! -x "${WAL_DIR}/arcade-launcher" ]]; then
            launch_error "windows-arcade-loader absent de ${WAL_DIR} (dossier" \
                "system/rgs/emulators/windows-arcade-loader du pack RGS, son GE-Proton dans runners/)"
        fi
        # Un seul jeu à la fois (06/11) : chaque partie ouvre 127.0.0.1:33700.
        # Un jeu resté ouvert (lancé depuis une ES remplacée par une
        # reconnexion Moonlight : invisible) faisait échouer tous les
        # lancements suivants, sans autre trace que « Address already in
        # use » dans le journal. pgrep -x (nom exact) : -f se trouverait
        # lui-même dans la ligne de commande de ce script.
        if running=$(pgrep -x -u "$(id -u)" arcade-launcher); then
            pid="${running%%$'\n'*}"
            # argv : arcade-launcher run <jeu> ... ; || true : processus
            # terminé entre-temps (set -e, pipefail)
            game=$(tr '\0' '\n' < "/proc/${pid}/cmdline" 2>/dev/null | sed -n '3p') || true
            launch_error "Un jeu d'arcade tourne déjà : $(basename "${game:-?}" .squashfs)" \
                "(processus ${pid}). Quitte-le (Hotkey + Start) ou arrête-le" \
                "(kill -TERM ${pid}) avant d'en lancer un autre."
        fi
        cd "${WAL_DIR}"
        exec "${WAL_DIR}/arcade-launcher" run "${ROM}" --root "${WAL_DIR}"
        ;;
    *)
        echo "format non pris en charge : ${ROM}" >&2
        exit 1
        ;;
esac
