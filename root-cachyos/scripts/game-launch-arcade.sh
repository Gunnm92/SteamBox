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

ROM="${1:?usage : $0 <jeu.wsquashfs|jeu.squashfs|dossier/jeu.windowsloader>}"
WSQUASHFS="${HOME}/.local/bin/wsquashfs-launcher"
WAL_DIR="${WAL_DIR:-${HOME}/.local/share/windows-arcade-loader}"

case "${ROM,,}" in
    *.wsquashfs)
        exec "${WSQUASHFS}" "${ROM}"
        ;;
    *.squashfs|*.windowsloader)
        if [[ ! -x "${WAL_DIR}/arcade-launcher" ]]; then
            echo "windows-arcade-loader absent de ${WAL_DIR} (dossier du pack RGS :" >&2
            echo "  system/rgs/emulators/windows-arcade-loader + son GE-Proton dans runners/)" >&2
            exit 1
        fi
        cd "${WAL_DIR}"
        exec "${WAL_DIR}/arcade-launcher" run "${ROM}" --root "${WAL_DIR}"
        ;;
    *)
        echo "format non pris en charge : ${ROM}" >&2
        exit 1
        ;;
esac
