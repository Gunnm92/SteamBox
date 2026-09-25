#!/bin/bash
# Génère es_systems.cfg (Batocera EmulationStation) depuis la table des
# systèmes de game-systems.sh — même source de vérité que les lanceurs : un
# seul endroit pour les émulateurs. Chaque jeu est lancé par le lanceur
# générique (game-launch.sh), qui déduit la plateforme du dossier et
# applique la commande de la table. Seuls les systèmes dont le dossier
# existe dans ROMS_DIR sont déclarés (ES masque de toute façon les vides,
# mais inutile de les lui faire scanner).
# Usage : es-systems-gen.sh > ~/.emulationstation/es_systems.cfg
set -uo pipefail
# shellcheck source=game-systems.sh
. /usr/local/bin/scripts/game-systems.sh

ROMS_DIR="${GAMES_ROMS_DIR:-/home/arcade/games/Batocera/roms}"
LAUNCH="/usr/local/bin/scripts/game-launch.sh"

# Nom de thème/plateforme Batocera pour les dossiers de roms nommés
# autrement (convention RomM, renommages : "win" au lieu de "windows"...).
# Sans correspondance, le thème (Carbon) n'a pas de visuel pour le système :
# 34 systèmes s'affichaient sans logo ni image, dont Windows (confirmé le
# 25/09 en comparant es_systems.cfg aux art/logos de Carbon). Systèmes
# arcade sans visuel propre : famille du constructeur, sinon "arcade".
declare -A THEME_ALIAS=(
    [win]=windows            [type-x]=typex           [arcadepc]=arcade
    [rawthrills]=arcade      [unis]=arcade            [nesicax]=taito
    [nesicax2]=taito         [segaalls]=sega          [segaer]=sega
    [seganu]=sega            [segare]=sega            [segarw]=sega
    [namcoes3]=namco         [konamipc]=konami        [konamilcd]=konami
    [igspgm]=igs             [stv]=segastv            [dc]=dreamcast
    [ngc]=gc                 [sms]=mastersystem       [sfam]=sfc
    [sega32]=sega32x         [acpc]=amstradcpc        [atari-st]=atarist
    [jaguar]=atarijaguar     [lynx]=atarilynx         [neogeoaes]=neogeo
    [neo-geo-pocket]=ngp     [neo-geo-pocket-color]=ngpc
    [pc-fx]=pcfx             [turbografx-cd]=pcenginecd
    [vic-20]=vic20           [wonderswan-color]=wonderswancolor
    [zxs]=zxspectrum
)

xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"
    printf '%s' "$s"
}

echo '<?xml version="1.0"?>'
echo '<systemList>'
while IFS= read -r sys; do
    [[ -d "${ROMS_DIR}/${sys}" ]] || continue
    IFS='|' read -r fullname extensions _ <<< "${SYSTEMS[$sys]}"
    exts=""
    IFS=',' read -ra list <<< "$extensions"
    for e in "${list[@]}"; do
        [[ -z "$e" || "$e" == "/" ]] && continue
        exts+=".${e,,} .${e^^} "
    done
    # Système "jeux en dossier" seulement ("/" dans la table, ex. scummvm) :
    # ES ne reconnaît un dossier comme jeu que si son nom porte une
    # extension déclarée — pas le cas de dossiers aux noms libres.
    if [[ -z "$exts" ]]; then
        echo "es-systems-gen: ${sys} ignoré (jeux en dossier sans extension)" >&2
        continue
    fi
    cat <<EOF
  <system>
    <name>${sys}</name>
    <fullname>$(xml_escape "$fullname")</fullname>
    <path>${ROMS_DIR}/${sys}</path>
    <extension>${exts% }</extension>
    <command>${LAUNCH} %ROM%</command>
    <platform>${THEME_ALIAS[$sys]:-$sys}</platform>
    <theme>${THEME_ALIAS[$sys]:-$sys}</theme>
  </system>
EOF
done < <(printf '%s\n' "${!SYSTEMS[@]}" | sort)
echo '</systemList>'
