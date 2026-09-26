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

LAUNCH="/usr/local/bin/scripts/game-launch.sh"

# Nom de thème/plateforme Batocera pour les dossiers de roms nommés
# autrement (convention RomM, renommages : "win" au lieu de "windows"...).
# Sans correspondance, le thème n'a pas de visuel pour le système (Windows
# s'affichait sans logo ni image, 25/09). Systèmes arcade sans visuel
# propre : famille du constructeur, sinon "arcade".
# Repli SEULEMENT si le thème actif ne connaît pas le nom d'origine :
# ckau-book-PixN a ses propres visuels segare, namcoes3, nesicax... que
# l'alias remplaçait par le logo générique de la famille (vu le 25/09).
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

# Logos du thème actif (ThemeSet d'es_settings.cfg), par nom sans
# extension : les thèmes Batocera nomment leurs visuels d'après le système
# (Carbon : art/logos/sega.svg, ckau-book : _inc/logos/segare.svg). Logos
# seulement : ckau-book a aussi des fonds jaguar.png/lynx.png hérités de
# Retrobat, mais son logo et sa mise en page sont atarijaguar/atarilynx.
# Dossier ES d'arcade par défaut, PAS ${HOME} : init_emulationstation tourne
# en root au démarrage — ${HOME}=/root, thème actif introuvable, et tous les
# alias s'appliquaient (visuels segare/namcoes3/konamipc… perdus, 26/09).
ES_HOME="${ES_HOME:-/home/arcade/.emulationstation}"
theme_set=$(grep -o 'name="ThemeSet" value="[^"]*"' "${ES_HOME}/es_settings.cfg" 2>/dev/null | cut -d'"' -f4)
declare -A THEME_NAMES=()
theme_found=""
for d in "${ES_HOME}/themes/${theme_set}" "/usr/share/emulationstation/themes/${theme_set}"; do
    [[ -n "$theme_set" && -d "$d" ]] || continue
    while IFS= read -r n; do THEME_NAMES[$n]=1; done < <(
        find -L "$d" -type f -path '*/logos/*' -printf '%f\n' 2>/dev/null \
            | sed 's/\.[^.]*$//' | sort -u)
    theme_found="$d"
    break
done
if [[ -z "${theme_found}" ]]; then
    echo "es-systems-gen: thème actif '${theme_set:-?}' introuvable (${ES_HOME}), alias appliqués partout" >&2
fi

theme_name() {
    local sys="$1"
    [[ -n "${THEME_NAMES[$sys]:-}" ]] && { echo "$sys"; return; }
    echo "${THEME_ALIAS[$sys]:-$sys}"
}

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
    theme=$(theme_name "$sys")
    cat <<EOF
  <system>
    <name>${sys}</name>
    <fullname>$(xml_escape "$fullname")</fullname>
    <path>${ROMS_DIR}/${sys}</path>
    <extension>${exts% }</extension>
    <command>${LAUNCH} %ROM%</command>
    <platform>${theme}</platform>
    <theme>${theme}</theme>
  </system>
EOF
done < <(printf '%s\n' "${!SYSTEMS[@]}" | sort)
echo '</systemList>'
