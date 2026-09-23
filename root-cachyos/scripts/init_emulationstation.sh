#!/bin/bash
# Configuration de Batocera EmulationStation (24/09) — frontend des jeux
# rétro/arcade, remplace Pegasus (SDL 2.0.20 embarquée incapable de lire la
# DualSense virtuelle de Sunshine, build X11 uniquement, glue maison pour
# réécrire les metadata.pegasus.txt de RomM). ES lit directement les
# gamelist.xml de la ludothèque, médias compris (./covers/..., ./videos/...),
# tels que RomM/Batocera les écrivent.
#
# Lancé à chaque démarrage par init-system/run, en root, APRÈS
# init_retroarch (les commandes RetroArch de la table pointent vers le
# dossier de cœurs utilisateur qu'il repeuple).
set -e

ES_HOME="/config/.emulationstation"
ROMS_DIR="${GAMES_ROMS_DIR:-/home/arcade/games/Batocera/roms}"
IMAGE_THEMES="/usr/share/emulationstation/themes"
OWNER="$(id -u arcade):$(id -g arcade)"

mkdir -p "${ES_HOME}/themes"

# Thème par défaut (Carbon, celui de Batocera) : lien vers la copie de
# l'image — ES (build non-Batocera) ne cherche les thèmes QUE dans
# ~/.emulationstation/themes. Un thème déjà présent (installé ou choisi par
# l'utilisateur) n'est jamais remplacé.
for theme in "${IMAGE_THEMES}"/*/; do
    [ -d "${theme}" ] || continue
    name=$(basename "${theme}")
    [ -e "${ES_HOME}/themes/${name}" ] || ln -s "${theme%/}" "${ES_HOME}/themes/${name}"
done

# Réglages par défaut, uniquement au premier démarrage : ensuite c'est ES
# (menu Réglages) qui fait foi.
# SaveGamelistsOnExit=false : les gamelist.xml appartiennent à RomM
# (synchronisation) — ES ne doit pas les réécrire (compteurs de parties...).
if [ ! -f "${ES_HOME}/es_settings.cfg" ]; then
    cat > "${ES_HOME}/es_settings.cfg" <<'EOF'
<?xml version="1.0"?>
<config>
  <string name="ThemeSet" value="es-theme-carbon" />
  <string name="Language" value="fr_FR" />
  <bool name="ParseGamelistOnly" value="false" />
  <bool name="SaveGamelistsOnExit" value="false" />
</config>
EOF
    echo "[emulationstation] es_settings.cfg par défaut créé"
fi

# es_systems.cfg régénéré à chaque démarrage depuis game-systems.sh (seule
# source de vérité des émulateurs) — un système ajouté ou un dossier de
# plateforme créé dans la ludothèque apparaît au redémarrage suivant.
if [ -d "${ROMS_DIR}" ]; then
    tmp="${ES_HOME}/es_systems.cfg.new"
    /usr/local/bin/scripts/es-systems-gen.sh > "${tmp}"
    mv -f "${tmp}" "${ES_HOME}/es_systems.cfg"
    echo "[emulationstation] es_systems.cfg : $(grep -c '<system>' "${ES_HOME}/es_systems.cfg") systèmes"
else
    echo "[emulationstation] ${ROMS_DIR} absent — es_systems.cfg non régénéré"
fi

# Manettes : es_input.cfg utilisateur jamais touché. La base (clavier,
# DualSense virtuelle Sunshine, manettes Batocera) est dans
# /opt/batocera-es/es_input.cfg, consultée par ES quand le fichier
# utilisateur ne connaît pas une manette.

chown -h "${OWNER}" "${ES_HOME}" "${ES_HOME}/themes" "${ES_HOME}"/es_*.cfg 2>/dev/null || true
