#!/bin/bash
# SteamBox — Lance un programme Windows (.exe, .msi) avec un Proton déjà
# installé dans l'image (umu-run), sans rien télécharger pour chaque programme.
# Même principe qu'aibox-run-exe : un préfixe Wine partagé, donc les
# dépendances (.NET, VC++…) ne s'installent qu'une fois.
#
#   run-exe PROGRAMME.exe [arguments…]        (ou double-clic dans Thunar)
#
# Proton : PROTON dans ~/.config/steambox/proton.conf (nom d'un dossier des
# compatibilitytools.d, ou chemin complet) ; sinon le proton-cachyos le plus
# récent de l'image. Les jeux d'arcade 32 bits (wine-tkg, préfixes win32) ne
# passent pas par ici : Proton ne lance pas ces préfixes (voir Dockerfile).
# Préfixe : ~/.local/share/steambox/wine/default (WINEPREFIX=… pour un autre).
# Journal : ~/.cache/steambox/run-exe/<programme>.log
set -euo pipefail
[[ $# -ge 1 ]] || { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
file="$(realpath "$1")"; shift
[[ -f "$file" ]] || { echo "$file introuvable." >&2; exit 1; }

conf="${HOME}/.config/steambox/proton.conf"
PROTON=""
# shellcheck disable=SC1090
[[ -r "$conf" ]] && . "$conf"
dirs=("${HOME}/.local/share/Steam/compatibilitytools.d" /usr/share/steam/compatibilitytools.d)
if [[ -n "$PROTON" && "$PROTON" != /* ]]; then
    for d in "${dirs[@]}"; do [[ -d "$d/$PROTON" ]] && { PROTON="$d/$PROTON"; break; }; done
fi
if [[ -z "$PROTON" ]]; then
    PROTON="$(for d in "${dirs[@]}"; do ls -d "$d"/proton-cachyos* 2>/dev/null; done | sort -V | tail -n 1 || true)"
fi
if [[ -n "$PROTON" ]]; then export PROTONPATH="$PROTON"; fi   # sinon : umu choisit

export WINEPREFIX="${WINEPREFIX:-${HOME}/.local/share/steambox/wine/default}"
export GAMEID="${GAMEID:-umu-default}"
mkdir -p "$WINEPREFIX" "${HOME}/.cache/steambox/run-exe"
log="${HOME}/.cache/steambox/run-exe/$(basename "$file").log"
cd "$(dirname "$file")"

case "${file,,}" in
    *.msi) set -- msiexec /i "$file" "$@" ;;
    *)     set -- "$file" "$@" ;;
esac
{ echo "== $(date) : $*"; echo "Proton : ${PROTONPATH:-umu (par défaut)}  Préfixe : $WINEPREFIX"; } >> "$log"
exec umu-run "$@" >> "$log" 2>&1
