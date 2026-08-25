#!/bin/bash
# ArcadeBox — Génération automatique des métadonnées Pegasus Frontend.
# Crée un metadata.pegasus.txt dans chaque dossier système de /userdata/roms/
# et met à jour game_dirs.txt pour que Pegasus scanne les bons répertoires.
#
# Portage du script custom-cont-init.d/20-pegasus.sh + 25-pegasus-gamelist.sh
# de l'ancienne image webstation (linuxserver) — ce mécanisme n'existe plus
# ici (vrai s6-overlay, pas de custom-cont-init.d) : appelé depuis
# init-system/run comme les autres init_*.sh. Adapté pour wsquashfs-launcher
# (github.com/Gunnm92/wsquashfs-launcher) qui a remplacé le script
# wsquashfs-batocera embarqué dans l'ancienne image.
#
# La génération des metadata ne s'exécute qu'une seule fois (déjà fait sur
# le volume /config persistant). Pour forcer une régénération : pegasus-update
set -e

ROMS_DIR="/userdata/roms"
PEGASUS_CFG="/config/.config/pegasus-frontend"
CORES="/usr/lib/libretro"
RA="retroarch -L"
# Les .wsquashfs viennent de Batocera, qui tourne intégralement en root (pas
# d'utilisateur non-root chez eux) : les fichiers à l'intérieur sont packagés
# root:root avec des permissions parfois restrictives (ex: rw-r-----). Notre
# session KDE/wine tourne en tant qu'"arcade" (non-root) — squashfuse monte le
# paquet en préservant ces UID/permissions d'origine, donc "arcade" se voit
# refuser la lecture (confirmé en direct : erreurs "Permission denied" sur
# autorun.cmd, jeu qui ne démarre pas). Confirmé aussi que les fichiers ne
# sont PAS corrompus : le même paquet non modifié se lance sans erreur une
# fois élevé en root. sudo -E (accès NOPASSWD déjà configuré pour arcade)
# élève le montage/lancement en root tout en gardant DISPLAY/XDG_RUNTIME_DIR
# d'arcade, donc la session graphique et l'audio (PipeWire) restent accessibles.
WSQUASHFS="sudo -E /usr/local/bin/wsquashfs-launcher"
FLAG_FILE="${PEGASUS_CFG}/.metadata-generated"

[ -d "${ROMS_DIR}" ] || exit 0
mkdir -p "${PEGASUS_CFG}"

# ── Mapping systèmes ──────────────────────────────────────────────────────────
# Format : "Nom affiché|extensions (sans point)|commande de lancement"
declare -A SYSTEMS

# ── Windows / Arcade PC (wsquashfs-launcher) ──────────────────────────────────
SYSTEMS["windows"]="Windows|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["windows3x"]="Windows 3.x|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["windows9x"]="Windows 9x|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["win311"]="Windows 3.11|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["win95"]="Windows 95|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["nesicax"]="NESiCAxLive|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["nesicax2"]="NESiCAxLive 2|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["typex"]="Taito Type X|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["typex2"]="Taito Type X2|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["type-x"]="Taito Type X|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["arcadepc"]="Arcade PC|wsquashfs,zip|${WSQUASHFS} \"{file.path}\""
SYSTEMS["rawthrills"]="Raw Thrills|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["cave3rd"]="Cave 3rd|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["konamipc"]="Konami PC|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["konamilcd"]="Konami LCD|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["namco2x6"]="Namco System 2x6|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["namcoes3"]="Namco ES3|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["chihiro"]="Sega Chihiro|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["triforce"]="Namco Triforce|wsquashfs,zip|${WSQUASHFS} \"{file.path}\""
SYSTEMS["ikemen"]="Ikemen|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["unis"]="Unis|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["exl100"]="EXL100|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["pc"]="PC (DOS/Windows)|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["dos"]="MS-DOS|wsquashfs,exe,com,bat|${WSQUASHFS} \"{file.path}\""

# ── Standalone launchers ──────────────────────────────────────────────────────
SYSTEMS["lindbergh"]="Sega Lindbergh|elf,sh,zip|/usr/local/bin/lindbergh \"{file.path}\""
SYSTEMS["model3"]="Sega Model 3|zip|/usr/local/bin/supermodel -res=1920,1080 -fullscreen \"{file.path}\""
SYSTEMS["model2"]="Sega Model 2|zip|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["model1"]="Sega Model 1|zip|${RA} ${CORES}/mame_libretro.so \"{file.path}\""

# ── Arcade (MAME / FBNeo) ─────────────────────────────────────────────────────
# Verifie en direct contre /usr/lib/libretro (ls) - la version precedente de
# ce mapping (portee telle quelle de l'ancienne image webstation) referencait
# des noms de core qui n'ont jamais ete installes ici (fbalpha2012_*, neocd,
# gearsystem, yabasanshiro, snes9x2010, citra2018, virtualjaguar, mednafen_ngp/
# lynx/pcfx, pcsx2, opera) et pointait CORES vers un dossier vide
# (~/.config/retroarch/cores au lieu de /usr/lib/libretro, ou pacman installe
# reellement les cores) - aucun de ces systemes n'a donc jamais fonctionne.
# Cores installes en plus pour combler les ecarts : fbneo, picodrive,
# beetle-pce(-fast), beetle-supergrafx, snes9x, melonds, scummvm. Systemes
# sans core disponible dans les depots retires (neogeocd, jaguar, pcfx, ngp,
# lynx, ps2, 3do) plutot que de laisser une reference morte.
SYSTEMS["arcade"]="Arcade|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["mame"]="MAME|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["fbneo"]="FBNeo|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["fba"]="FBA|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
# FBNeo est un core unifie moderne qui couvre CPS-1/2/3 et Neo Geo - remplace
# les anciens cores fbalpha2012_* separes, plus maintenus/disponibles.
SYSTEMS["cps1"]="CPS-1|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["cps2"]="CPS-2|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["cps3"]="CPS-3|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["neogeo"]="Neo Geo|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["atomiswave"]="Atomiswave|zip,7z|${RA} ${CORES}/flycast_libretro.so \"{file.path}\""
SYSTEMS["naomi"]="Sega NAOMI|zip,7z,chd|${RA} ${CORES}/flycast_libretro.so \"{file.path}\""
SYSTEMS["naomi2"]="Sega NAOMI 2|zip,7z,chd|${RA} ${CORES}/flycast_libretro.so \"{file.path}\""
SYSTEMS["naomigd"]="Sega NAOMI GD-ROM|zip,7z,chd|${RA} ${CORES}/flycast_libretro.so \"{file.path}\""
SYSTEMS["stv"]="Sega ST-V|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["hikaru"]="Sega Hikaru|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""

# ── Sega (RetroArch) ──────────────────────────────────────────────────────────
SYSTEMS["megadrive"]="Mega Drive|md,bin,smd,gen,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["genesis"]="Genesis|md,bin,smd,gen,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["sega32x"]="Sega 32X|32x,bin,md,zip,7z|${RA} ${CORES}/picodrive_libretro.so \"{file.path}\""
SYSTEMS["segacd"]="Sega CD|iso,chd,cue,bin|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["megacd"]="Mega CD|iso,chd,cue,bin|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
# Genesis Plus GX est multi-systeme (couvre aussi Master System/Game Gear/
# SG-1000) - gearsystem_libretro.so n'a jamais ete disponible dans les depots.
SYSTEMS["mastersystem"]="Master System|sms,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["mark3"]="Sega Mark III|sms,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["sg-1000"]="SG-1000|sg,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["sg1000"]="SG-1000|sg,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["gamegear"]="Game Gear|gg,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["saturn"]="Saturn|iso,chd,cue,bin,mdf|${RA} ${CORES}/yabause_libretro.so \"{file.path}\""
SYSTEMS["saturnjp"]="Saturn JP|iso,chd,cue,bin,mdf|${RA} ${CORES}/yabause_libretro.so \"{file.path}\""
SYSTEMS["dreamcast"]="Dreamcast|chd,cdi,gdi,iso|${RA} ${CORES}/flycast_libretro.so \"{file.path}\""

# ── Nintendo (RetroArch) ──────────────────────────────────────────────────────
SYSTEMS["snes"]="Super Nintendo|sfc,smc,fig,bs,zip,7z|${RA} ${CORES}/snes9x_libretro.so \"{file.path}\""
SYSTEMS["sfc"]="Super Famicom|sfc,smc,fig,zip,7z|${RA} ${CORES}/snes9x_libretro.so \"{file.path}\""
SYSTEMS["supergrafx"]="SuperGrafx|pce,sgx,bin,zip,7z|${RA} ${CORES}/mednafen_supergrafx_libretro.so \"{file.path}\""
SYSTEMS["gamecube"]="GameCube|iso,rvz,chd,gcm|${RA} ${CORES}/dolphin_libretro.so \"{file.path}\""
SYSTEMS["gc"]="GameCube|iso,rvz,chd,gcm|${RA} ${CORES}/dolphin_libretro.so \"{file.path}\""
SYSTEMS["wii"]="Wii|iso,wbfs,rvz,chd|${RA} ${CORES}/dolphin_libretro.so \"{file.path}\""
# Pas de core libretro 3DS disponible (citra2018 jamais installe ni maintenu,
# citra lui-meme discontinue) - redirige vers Azahar, deja installe en
# standalone dans cette image (voir plus haut dans le Dockerfile).
SYSTEMS["3ds"]="Nintendo 3DS|3ds,3dsx,cci,cxi,zip|/usr/local/bin/azahar \"{file.path}\""
SYSTEMS["n3ds"]="Nintendo 3DS|3ds,3dsx,cci,cxi,zip|/usr/local/bin/azahar \"{file.path}\""

# ── NEC (RetroArch) ───────────────────────────────────────────────────────────
SYSTEMS["pcengine"]="PC Engine|pce,bin,ccd,img,zip,7z|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["tg16"]="TurboGrafx-16|pce,bin,ccd,img,zip,7z|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["pcenginecd"]="PC Engine CD|iso,chd,cue,bin|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["tg-cd"]="TurboGrafx CD|iso,chd,cue,bin|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""

# ── ScummVM (RetroArch) ───────────────────────────────────────────────────────
SYSTEMS["scummvm"]="ScummVM|scummvm,zip|${RA} ${CORES}/scummvm_libretro.so \"{file.path}\""

# ── Fonction de génération des metadata ───────────────────────────────────────
generate_metadata() {
    local GAME_DIRS_FILE="${PEGASUS_CFG}/game_dirs.txt"
    > "${GAME_DIRS_FILE}"
    local generated=0 skipped=0

    for system_dir in "${ROMS_DIR}"/*/; do
        local system
        system=$(basename "${system_dir}")
        local meta_file="${system_dir}metadata.pegasus.txt"

        if [[ -z "${SYSTEMS[$system]+x}" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        local display_name extensions launch_cmd
        IFS='|' read -r display_name extensions launch_cmd <<< "${SYSTEMS[$system]}"

        local has_game=false
        IFS=',' read -ra ext_list <<< "$extensions"
        for ext in "${ext_list[@]}"; do
            if compgen -G "${system_dir}*.${ext}" > /dev/null 2>&1; then
                has_game=true
                break
            fi
        done

        if [[ "$has_game" == "false" ]]; then
            skipped=$((skipped + 1))
            continue
        fi

        cat > "${meta_file}" <<EOF
collection: ${display_name}
shortname: ${system}
extensions: ${extensions}
launch: ${launch_cmd}
EOF

        echo "${system_dir}" >> "${GAME_DIRS_FILE}"
        echo "[pegasus] ${system} → ${meta_file}"
        generated=$((generated + 1))
    done

    echo "[pegasus] ${generated} systèmes configurés, ${skipped} ignorés"
    date -u +%Y-%m-%dT%H:%M:%SZ > "${FLAG_FILE}"
}

# ── Reconstruction rapide de game_dirs.txt depuis les metadata existants ──────
rebuild_game_dirs() {
    local GAME_DIRS_FILE="${PEGASUS_CFG}/game_dirs.txt"
    > "${GAME_DIRS_FILE}"
    local count=0
    for system_dir in "${ROMS_DIR}"/*/; do
        if [[ -f "${system_dir}metadata.pegasus.txt" ]]; then
            echo "${system_dir}" >> "${GAME_DIRS_FILE}"
            count=$((count + 1))
        fi
    done
    echo "[pegasus] game_dirs.txt reconstruit — ${count} systèmes"
}

# ── Génération conditionnelle ─────────────────────────────────────────────────
if [[ -f "${FLAG_FILE}" ]]; then
    echo "[pegasus] Metadata déjà générés ($(cat "${FLAG_FILE}")) — reconstruction game_dirs.txt uniquement"
    echo "[pegasus] Pour forcer une mise à jour : pegasus-update"
    rebuild_game_dirs
else
    echo "[pegasus] Première génération des metadata..."
    generate_metadata
fi

# ── Import gamelist.xml (EmulationStation/ARRM) → metadata.pegasus.txt ────────
# Contrairement à la génération ci-dessus, tourne à chaque démarrage : safe et
# idempotent (saute les jeux déjà présents dans metadata.pegasus.txt), donc
# capture les gamelist.xml ajoutés après la première génération.
python3 - "${ROMS_DIR}" <<'PYEOF'
import sys, os, xml.etree.ElementTree as ET

roms_dir = sys.argv[1]
converted_total = 0

# Mapping tag XML → clé Pegasus asset
ASSET_MAP = [
    ("screenshot", "assets.screenshot"),
    ("image",      "assets.poster"),
    ("boxart",     "assets.box-front"),
    ("wheel",      "assets.logo"),
    ("mix",        "assets.background"),
    ("marquee",    "assets.marquee"),
    ("thumbnail",  "assets.box-front"),
    ("video",      "assets.video"),
]

def resolve(system_dir, path):
    if not path:
        return None
    path = path.lstrip("./").lstrip("/")
    return os.path.join(system_dir, path)

def convert_date(d):
    if not d or d.startswith("0000"):
        return None
    # Format : 20050101T000000
    if len(d) >= 8:
        return f"{d[0:4]}-{d[4:6]}-{d[6:8]}"
    return None

for system in sorted(os.listdir(roms_dir)):
    system_dir = os.path.join(roms_dir, system)
    gamelist   = os.path.join(system_dir, "gamelist.xml")
    meta_file  = os.path.join(system_dir, "metadata.pegasus.txt")

    if not os.path.isfile(gamelist) or not os.path.isfile(meta_file):
        continue

    # Lire les fichiers déjà présents dans metadata.pegasus.txt
    try:
        existing = open(meta_file).read()
    except Exception:
        existing = ""

    try:
        tree = ET.parse(gamelist)
        root = tree.getroot()
    except ET.ParseError as e:
        print(f"[pegasus-xml] {system} : XML invalide — {e}")
        continue

    converted = 0
    entries = []

    for game in root.findall("game"):
        path_raw = (game.findtext("path") or "").strip()
        if not path_raw:
            continue
        filename = os.path.basename(path_raw)

        # Skip si déjà présent
        if f"file: {filename}" in existing:
            continue

        name    = (game.findtext("name")        or os.path.splitext(filename)[0]).strip()
        desc    = (game.findtext("desc")        or "").strip()
        dev     = (game.findtext("developer")   or "").strip()
        pub     = (game.findtext("publisher")   or "").strip()
        genre   = (game.findtext("genre")       or "").strip()
        players = (game.findtext("players")     or "").strip()
        rating  = (game.findtext("rating")      or "").strip()
        date    = convert_date(game.findtext("releasedate") or "")

        lines = ["", f"game: {name}", f"file: {filename}"]
        if desc:    lines.append(f"description: {desc}")
        if dev:     lines.append(f"developer: {dev}")
        if pub:     lines.append(f"publisher: {pub}")
        if genre:   lines.append(f"genre: {genre}")
        if players: lines.append(f"players: {players}")
        if rating:  lines.append(f"rating: {rating}")
        if date:    lines.append(f"release: {date}")

        # Assets — premier fichier existant par clé Pegasus (évite doublons de clé)
        used_keys = set()
        for xml_tag, peg_key in ASSET_MAP:
            if peg_key in used_keys:
                continue
            val = (game.findtext(xml_tag) or "").strip()
            if not val:
                continue
            abs_path = resolve(system_dir, val)
            if abs_path and os.path.isfile(abs_path):
                lines.append(f"{peg_key}: {abs_path}")
                used_keys.add(peg_key)

        entries.append("\n".join(lines))
        converted += 1

    if entries:
        with open(meta_file, "a") as f:
            f.write("\n".join(entries) + "\n")
        print(f"[pegasus-xml] {system} : {converted} jeux importés")
        converted_total += converted

print(f"[pegasus-xml] Total : {converted_total} jeux importés depuis les gamelist.xml")
PYEOF

# ── Script de mise à jour manuelle ───────────────────────────────────────────
cat > /usr/local/bin/pegasus-update << 'EOF'
#!/bin/bash
echo "[pegasus-update] Suppression du flag et régénération des metadata..."
rm -f /config/.config/pegasus-frontend/.metadata-generated
exec /usr/local/bin/scripts/init_pegasus.sh
EOF
chmod +x /usr/local/bin/pegasus-update

# ── Permissions ───────────────────────────────────────────────────────────────
chown -R arcade:arcade "${PEGASUS_CFG}" 2>/dev/null || true
