#!/bin/bash
# SteamBox — Génération automatique des métadonnées Pegasus Frontend.
# Crée un metadata.pegasus.txt dans chaque dossier système de
# /home/arcade/games/Batocera/roms/ et met à jour game_dirs.txt pour que
# Pegasus scanne les bons répertoires.
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
# (sans risque depuis le 22/09 : un metadata.pegasus.txt existant, scrapé ou
# non, n'est jamais réécrit — seule sa ligne launch: gérée est mise à jour).
set -e

# Plus sous /userdata (15/09, reliquat d'un montage séparé et redondant —
# voir la même note dans init_retroarch.sh) : /home/arcade est un symlink
# vers /config, et /config/games est déjà le montage du parent
# /mnt/user/Game, qui contient Batocera/ — mêmes fichiers, un seul montage.
# Surchargeables (22/09) pour tester ce script sur une copie de la
# ludothèque sans toucher aux vrais fichiers.
ROMS_DIR="${PEGASUS_ROMS_DIR:-/home/arcade/games/Batocera/roms}"
PEGASUS_CFG="${PEGASUS_CFG_DIR:-/config/.config/pegasus-frontend}"
# Table des systèmes (émulateur, extensions, commande) : pegasus-systems.sh.
# shellcheck source=pegasus-systems.sh
. /usr/local/bin/scripts/pegasus-systems.sh
FLAG_FILE="${PEGASUS_CFG}/.metadata-generated"

[ -d "${ROMS_DIR}" ] || exit 0
mkdir -p "${PEGASUS_CFG}"

# ── Fonction de génération des metadata ───────────────────────────────────────
generate_metadata() {
    local GAME_DIRS_FILE="${PEGASUS_CFG}/game_dirs.txt"
    : > "${GAME_DIRS_FILE}"
    local generated=0 skipped=0

    for system_dir in "${ROMS_DIR}"/*/; do
        local system
        system=$(basename "${system_dir}")
        local meta_file="${system_dir}metadata.pegasus.txt"

        # Jamais d'écrasement (22/09) : un metadata.pegasus.txt existant vient
        # le plus souvent d'un scraper (descriptions, visuels, 205 dossiers
        # sur la ludothèque réelle) — l'ancien "cat >" plus bas le remplaçait
        # par un en-tête nu à chaque pegasus-update. Leur commande de
        # lancement vient du fichier metafiles/ (write_command_metafile).
        if [[ -f "${meta_file}" ]]; then
            echo "${system_dir}" >> "${GAME_DIRS_FILE}"
            skipped=$((skipped + 1))
            continue
        fi

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

        # Pas de launch: ici (22/09) : la commande vient du fichier de
        # commandes metafiles/ (write_command_metafile, source unique).
        cat > "${meta_file}" <<EOF
collection: ${display_name}
shortname: ${system}
extensions: ${extensions}
EOF

        # mtime remis à l'epoch (22/09) : ce fichier vient d'être réécrit
        # avec l'en-tête seul, donc plus récent que gamelist.xml — la garde
        # mtime de l'import plus bas le sautait, et un pegasus-update
        # effaçait toutes les fiches de jeux (noms, descriptions, visuels)
        # sans jamais les réimporter. Epoch = "à réimporter".
        touch -d @0 "${meta_file}"

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
    : > "${GAME_DIRS_FILE}"
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

# ── Commandes de lancement : fichier de commandes Pegasus (22/09) ────────────
# Cause réelle de "beaucoup d'émulateurs ne fonctionnent pas" (lastrun.log :
# "Cannot launch the game ... because there is no launch command defined for
# it") : les metadata.pegasus.txt de la ludothèque viennent de RomM —
# collection, fiches, visuels, mais aucune ligne launch:.
#
# Ces fichiers restent INTACTS (RomM les réécrit à chaque synchronisation, et
# c'est lui qui en a la charge). Les commandes vivent dans un fichier à nous,
# dans le dossier "metafiles" global de Pegasus — mécanisme standard, lu AVANT
# les dossiers de jeux (PegasusProvider.cpp, find_all_metafiles). L'ordre est
# indispensable : un jeu copie la commande de sa collection au moment où il
# est créé (SearchContext.cpp, create_game_for/game_add_to), et Pegasus
# fusionne les collections de même nom (get_or_create_collection) — notre
# "collection: X / launch: ..." déclaré en premier s'applique donc aux jeux
# que le fichier RomM ajoute ensuite à X.
#
# Une entrée par nom de collection RomM :
#   - commande directe de l'émulateur quand la collection correspond à une
#     seule commande (cas standard) ;
#   - lanceur générique pegasus-launch.sh (choix de l'émulateur d'après le
#     dossier de plateforme du jeu) quand RomM regroupe des plateformes aux
#     émulateurs différents sous un même nom (20 dossiers arcade => "Arcade")
#     ou quand une partie des jeux du dossier est dans un format non pris en
#     charge (le lanceur l'indique au lieu d'un échec muet).
# Régénéré à chaque démarrage depuis pegasus-systems.sh : un émulateur changé
# là-bas est pris en compte au redémarrage suivant, sans toucher la
# ludothèque.
write_command_metafile() {
    local tsv system entry display_name extensions launch_cmd bin core ok
    tsv=$(mktemp)
    local -a missing=()
    for system_dir in "${ROMS_DIR}"/*/; do
        system=$(basename "${system_dir}")
        [[ -f "${system_dir}metadata.pegasus.txt" ]] || continue
        entry="${SYSTEMS[$system]:-}"
        [[ -n "${entry}" ]] || continue
        IFS='|' read -r display_name extensions launch_cmd <<< "${entry}"
        read -r -a words <<< "${launch_cmd}"
        bin="${words[0]}"
        [[ "${bin}" == "sudo" ]] && bin="${words[2]}"
        core=$(grep -oE '/[^ "]*_libretro\.so' <<< "${launch_cmd}" || true)
        ok=1
        if ! command -v "${bin}" >/dev/null 2>&1 || [[ -n "${core}" && ! -e "${core}" ]]; then
            ok=0
            missing+=("${system}")
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "${system}" "${system_dir}metadata.pegasus.txt" "${extensions}" "${launch_cmd}" "${ok}" >> "${tsv}"
    done
    if (( ${#missing[@]} )); then
        echo "[pegasus] ${#missing[@]} plateforme(s) sans émulateur/cœur installé (Core Downloader de RetroArch pour les cœurs) : ${missing[*]}"
    fi

    mkdir -p "${PEGASUS_CFG}/metafiles"
    python3 - "${tsv}" "${PEGASUS_CFG}/metafiles/steambox.metadata.pegasus.txt" <<'METAFILE_EOF'
import collections, os, sys

GENERIC = '/usr/local/bin/scripts/pegasus-launch.sh "{file.path}"'
MARK = "# steambox:launch-auto (ligne suivante gérée par init_pegasus.sh)"

def ext_ok(fname, exts, base):
    if "/" in exts and os.path.isdir(os.path.join(base, fname)):
        return True
    return "." in fname and fname.rsplit(".", 1)[1].lower() in exts

groups = collections.OrderedDict()
for row in open(sys.argv[1], encoding="utf-8"):
    system, path, exts, launch, ok = row.rstrip("\n").split("\t")
    try:
        text = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError) as e:
        print(f"[pegasus] {system} : illisible ({e}) — ignoré")
        continue

    # Nettoyage unique des lignes launch: que la version du 22/09 ajoutait
    # DANS les fichiers RomM (repérées par leur marqueur, rien d'autre n'est
    # touché) : remplacement atomique, possible en arcade car les dossiers de
    # plateforme lui appartiennent, même quand le fichier est à root.
    if MARK in text:
        lines, out, i = text.split("\n"), [], 0
        while i < len(lines):
            if lines[i] == MARK:
                i += 2 if i + 1 < len(lines) and lines[i + 1].startswith("launch:") else 1
                continue
            out.append(lines[i]); i += 1
        tmp = path + ".steambox-tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                f.write("\n".join(out))
            os.chmod(tmp, os.stat(path).st_mode & 0o777)
            os.replace(tmp, path)
            text = "\n".join(out)
            print(f"[pegasus] {system} : anciennes lignes launch retirées du fichier RomM")
        except OSError as e:
            print(f"[pegasus] {system} : nettoyage impossible ({e})")

    col = next((l.split(":", 1)[1].strip() for l in text.split("\n") if l.startswith("collection:")), None)
    if not col:
        continue
    base = os.path.dirname(path)
    exts_set = {x.lower() for x in exts.split(",") if x}
    games = [l[5:].strip() for l in text.split("\n") if l.startswith("file:")]
    all_ok = all(ext_ok(g, exts_set, base) for g in games)
    groups.setdefault(col, []).append((system, launch, ok == "1", all_ok))

out = ["# Commandes de lancement SteamBox — GÉNÉRÉ à chaque démarrage par",
       "# init_pegasus.sh, ne pas modifier à la main (émulateurs : voir",
       "# pegasus-systems.sh). Lu par Pegasus avant les fichiers RomM des",
       "# dossiers de jeux, qui eux restent intacts.", ""]
direct = generic = 0
for col, members in groups.items():
    usable = [m for m in members if m[2]]
    if not usable:
        continue
    launches = {m[1] for m in members}
    if len(members) == 1 and members[0][3]:
        cmd, kind = members[0][1], "direct"
        direct += 1
    else:
        cmd, kind = GENERIC, "générique"
        generic += 1
    out += [f"# {', '.join(m[0] for m in members)} ({kind})", f"collection: {col}", f"launch: {cmd}", ""]

dest = sys.argv[2]
tmp = dest + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    f.write("\n".join(out))
os.replace(tmp, dest)
print(f"[pegasus] fichier de commandes : {direct} collection(s) en commande directe, {generic} via le lanceur générique -> {dest}")
METAFILE_EOF
    rm -f "${tsv}"
}
write_command_metafile

# ── Import gamelist.xml (EmulationStation/ARRM) → metadata.pegasus.txt ────────
# Contrairement à la génération ci-dessus, s'exécute (le script Python) à
# chaque démarrage : safe et idempotent (saute les jeux déjà présents dans
# metadata.pegasus.txt), donc capture les gamelist.xml ajoutés après la
# première génération. Mais chaque système individuel est ignoré tant que
# son gamelist.xml n'a pas changé depuis le dernier import (garde mtime,
# audit 2026-08-26, voir plus bas) — le coût réel à chaque boot reste
# proportionnel aux systèmes modifiés, pas à la ludothèque entière.
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
    # Retrait du préfixe "./" (22/09) : lstrip("./") retirait n'importe
    # quelle suite de "." et "/" en tête, pas le préfixe — "../media/x.png"
    # devenait "media/x.png" et un nom commençant par "." perdait son point.
    while path.startswith("./"):
        path = path[2:]
    path = path.lstrip("/")
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

    # Garde mtime (audit 2026-08-26) : ce bloc tourne à CHAQUE démarrage sur
    # TOUTE la ludothèque (parcours XML complet + un os.path.isfile() par
    # asset et par jeu, à travers le partage Unraid FUSE/shfs) — sur une
    # grosse collection, plusieurs minutes passées avant même que Xorg ne
    # démarre, puisque init-system est un oneshot bloquant dont dépendent
    # tous les autres services. metadata.pegasus.txt n'est ré-écrit
    # (append) QUE quand ce système importe au moins un nouveau jeu — si son
    # gamelist.xml n'a pas été modifié depuis, il n'y a par construction rien
    # de nouveau à y trouver.
    if os.path.getmtime(gamelist) <= os.path.getmtime(meta_file):
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
# Garde de propriétaire (audit F4, 05/09, même motif qu'init_system.sh) :
# évite un chown -R inconditionnel à chaque boot une fois déjà correct.
TARGET_OWNER="${PUID:-1000}:${PGID:-1000}"
CURRENT_OWNER=$(stat -c '%u:%g' "${PEGASUS_CFG}" 2>/dev/null || echo "")
[ "${CURRENT_OWNER}" = "${TARGET_OWNER}" ] || chown -R "${TARGET_OWNER}" "${PEGASUS_CFG}" 2>/dev/null || true
