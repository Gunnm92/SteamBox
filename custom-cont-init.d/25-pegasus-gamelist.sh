#!/bin/bash
# ArcadeBox — Conversion EmulationStation/ARRM gamelist.xml → Pegasus metadata.pegasus.txt
# Compatible ARRM (wheel, boxart, screenshot, mix) + ES standard (image, marquee, thumbnail)

ROMS_DIR="/userdata/roms"

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

# Permissions
os.system("chown -R abc:users /config/.config/pegasus-frontend 2>/dev/null")
PYEOF
