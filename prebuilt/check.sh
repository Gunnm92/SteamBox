#!/bin/bash
# make prebuilt-check (15/11) — compare les versions de la dernière release
# des composants précompilés (versions.txt, voir Dockerfile.prebuilt) avec
# l'amont, sans rien compiler. Code 0 : tout est à jour ; code 2 : au moins
# un composant est en retard, relancer make prebuilt puis make prebuilt-publish.
#
# Usage : prebuilt/check.sh <owner/repo>   (gh doit être authentifié)
set -euo pipefail

repo="${1:?usage: prebuilt/check.sh <owner/repo>}"
root="$(cd "$(dirname "$0")/.." && pwd)"

if ! current=$(gh release download --repo "${repo}" --pattern versions.txt --output - 2>/dev/null); then
    echo "Aucune release précompilée sur ${repo} : lancer make prebuilt puis make prebuilt-publish."
    exit 2
fi
tag=$(gh release view --repo "${repo}" --json tagName --jq .tagName)
echo "Dernière release : ${tag}"

# Valeur enregistrée pour un composant (2e champ et suivants de sa ligne).
recorded() { printf '%s\n' "${current}" | awk -v n="$1" '$1 == n { $1 = ""; sub(/^ /, ""); print }'; }

stale=0
report() { # <nom> <enregistré> <amont> <à jour 0|1>
    if [ "$4" = 1 ]; then
        printf '  %-14s à jour      %s\n' "$1" "$2"
    else
        printf '  %-14s PÉRIMÉ      %s -> %s\n' "$1" "${2:-absent}" "$3"
        stale=1
    fi
}

# Batocera ES : HEAD de la branche par défaut ; enregistré "<hash court> (<date>)".
rec=$(recorded batocera-es)
up=$(git ls-remote https://github.com/batocera-linux/batocera-emulationstation.git HEAD | cut -f1)
h=${rec%% *}
report batocera-es "${rec}" "${up:0:7}" "$([ -n "${h}" ] && [ "${up#"${h}"}" != "${up}" ] && echo 1 || echo 0)"

# evdev-bridge : dernier commit du dossier dans ce dépôt (modifications non
# commitées ignorées, comme pour make prebuilt).
rec=$(recorded evdev-bridge)
up=$(git -C "${root}" log -1 --format=%H -- evdev-bridge)
report evdev-bridge "${rec}" "${up:0:7}" "$([ -n "${rec}" ] && [ "${up#"${rec}"}" != "${up}" ] && echo 1 || echo 0)"

# xfce-launcher : HEAD de main ; enregistré = hash complet.
rec=$(recorded xfce-launcher)
up=$(git ls-remote https://github.com/novik133/xfce-panel-launcher.git HEAD | cut -f1)
report xfce-launcher "${rec:0:7}" "${up:0:7}" "$([ -n "${rec}" ] && [ "${rec}" = "${up}" ] && echo 1 || echo 0)"

# freeimage : version du paquet AUR ; enregistré "freeimage-<ver>-<rel>-<arch>".
rec=$(recorded freeimage)
up=$(curl -fsSL 'https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=freeimage' \
     | grep -oE '"Version":"[^"]*"' | cut -d'"' -f4 || true)
report freeimage "${rec}" "${up:-AUR injoignable}" \
    "$([ -n "${up}" ] && [[ "${rec}" == "freeimage-${up}-"* ]] && echo 1 || echo 0)"

if [ "${stale}" = 1 ]; then
    echo "Mise à jour : make prebuilt && make prebuilt-publish, puis make push."
    exit 2
fi
echo "Tous les composants précompilés sont à jour."
