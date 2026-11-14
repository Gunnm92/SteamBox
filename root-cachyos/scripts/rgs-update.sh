#!/bin/bash
# Mise à jour du pack RGS dans SteamBox (14/11) — l'équivalent de rgs_upgrade
# et rgs_theme_upgrade de RGS (dépôt RGS-MBU/RGS_MBU-R-Batocera-Configuration,
# v43.1), réduit à ce que SteamBox reprend de RGS et adapté à son arborescence.
#
#   loader : le « Windows arcade loader » de RGS (arcade-launcher, DLL wal_*,
#     profils systemprofiles/, prefixes de wine-prefix/) et son GE-Proton.
#     RGS ne publie que l'archive complète update/v43/update.tar.gz (≈ 2 Go,
#     tout /userdata) : elle est lue en flux, sans être stockée, et seuls
#     system/rgs/emulators/windows-arcade-loader/ et
#     system/wine/custom/GE-Proton*/ en sont extraits (le GE-Proton seulement
#     s'il n'est pas déjà installé). Rien n'est téléchargé si l'archive n'a
#     pas changé depuis la dernière mise à jour (date + taille HTTP).
#     Gardé de SteamBox : launcher.yaml (runners/, saves) — l'original de RGS
#     est rafraîchi dans launcher.yaml.rgs et seule la ligne runner: suit la
#     sienne — userprofiles/ (réglages utilisateur, nouveaux fichiers
#     seulement) et les prefixes déjà extraits de wine-prefix/. Les fichiers
#     que RGS retire (anciens prefixes, ses « rm » de rgs_upgrade) partent
#     aussi ; les anciens GE-Proton sont supprimés sauf le précédent.
#   theme : les thèmes RGS installés (ckau-book-PixN, Hypermax-Plus-PixN,
#     Carbon-PixN, ckau-book), synchronisés par rclone depuis le serveur HTTP
#     de RGS comme dans rgs_theme_upgrade (sans configuration rclone : remote
#     :http en ligne). Les addons CkauNui ajoutés au thème le 06/11 portent les
#     mêmes noms que ceux du serveur et ne sont pas touchés.
#   Pas repris : BIOS et bezels (choix du 06/11, à la main), batocera.conf,
#   es_settings.cfg et es_systems (SteamBox génère les siens).
#
# Tout fichier remplacé ou supprimé est gardé dans
# ~/.local/share/steambox/rgs-backup/<date>/ (les deux dernières mises à jour).
# À lancer en arcade : docker exec -it -u arcade SteamBox rgs-update
set -euo pipefail

RGS_URL="${RGS_URL:-http://rgsretro1986.ds78102.seedhost.eu}"
ARCHIVE_URL="${RGS_URL}/update/v43/update.tar.gz"
WAL_DIR="${WAL_DIR:-${HOME}/.local/share/windows-arcade-loader}"
THEMES_DIR="${HOME}/.emulationstation/themes"
BACKUP_ROOT="${HOME}/.local/share/steambox/rgs-backup"
STAMP="${WAL_DIR}/.rgs-update"

usage() {
    cat <<EOF
Usage : rgs-update [loader|theme|all] [--check] [--force]

Met à jour depuis le serveur de RGS :
  loader   le Windows arcade loader (${WAL_DIR}) et son GE-Proton
  theme    les thèmes RGS installés dans ${THEMES_DIR}
  all      les deux (par défaut)

  --check  dit seulement si le loader a une mise à jour (aucune écriture)
  --force  retélécharge le loader même si l'archive RGS n'a pas changé

Sauvegarde des fichiers remplacés : ${BACKUP_ROOT}/<date>/
EOF
}

what="all"; check=0; force=0
for arg in "$@"; do
    case "${arg}" in
        loader|theme|all) what="${arg}" ;;
        --check) check=1 ;;
        --force) force=1 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

die() { echo "rgs-update : $*" >&2; exit 1; }

[[ "$(id -u)" != 0 ]] || die "à lancer en arcade (docker exec -u arcade), pas en root"

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/rgs-update.lock"
flock -n 9 || die "une mise à jour est déjà en cours"

stamp_backup="$(date +%Y%m%d-%H%M%S)"
backup="${BACKUP_ROOT}/${stamp_backup}"

# ── Windows arcade loader ─────────────────────────────────────────────────────
update_loader() {
    local remote current new_runner old_runner r
    [[ -x "${WAL_DIR}/arcade-launcher" ]] \
        || die "${WAL_DIR}/arcade-launcher absent : installer d'abord le loader (voir README)"

    remote=$(curl -sfIL "${ARCHIVE_URL}" \
        | tr -d '\r' | awk -F': ' 'tolower($1)=="last-modified"{lm=$2} tolower($1)=="content-length"{len=$2} END{print lm" / "len}')
    [[ "${remote}" != " / " ]] || die "serveur RGS injoignable (${ARCHIVE_URL})"
    current=$(cat "${STAMP}" 2>/dev/null || true)
    if [[ "${remote}" == "${current}" && ${force} == 0 ]]; then
        echo "Loader : à jour (archive RGS du ${remote% / *})."
        return
    fi
    if (( check )); then
        echo "Loader : mise à jour disponible (archive RGS du ${remote% / *}, installée : ${current:-inconnue})."
        return
    fi
    # Comme game-launch-arcade.sh : pgrep -x, -f se trouverait lui-même.
    if pgrep -x -u "$(id -u)" arcade-launcher >/dev/null; then
        die "un jeu d'arcade tourne (arcade-launcher) : le quitter avant la mise à jour"
    fi

    # Global (pas local) : le trap EXIT s'exécute hors de la fonction.
    staging="${WAL_DIR}.maj"
    rm -rf "${staging}"
    mkdir -p "${staging}"
    trap 'rm -rf "${staging}"' EXIT

    echo "Loader : lecture de l'archive RGS (${remote##* / } octets, ${remote% / *})…"
    local -a have=()
    for r in "${WAL_DIR}"/runners/*/; do [[ -d "${r}" ]] && have+=("$(basename "${r}")"); done
    # Extraction en flux : membres renommés vers loader/ et runners/, liens
    # durs suivis, filtre « tar » (pas de chemin absolu ni de sortie du dossier).
    local -a progress=(-sS)
    [[ -t 2 ]] && progress=(--progress-bar)
    curl -fL --retry 3 "${progress[@]}" "${ARCHIVE_URL}" \
        | python3 -I -c '
import re, sys, tarfile
dest, have = sys.argv[1], set(sys.argv[2:])
LOADER = "system/rgs/emulators/windows-arcade-loader/"
WINE = "system/wine/custom/"
def target(name):
    name = re.sub(r"^(\./)+", "", name)
    if name.startswith(LOADER):
        return "loader/" + name[len(LOADER):]
    if name.startswith(WINE + "GE-Proton"):
        rest = name[len(WINE):]
        if rest.split("/")[0] not in have:
            return "runners/" + rest
    return None
found = 0
with tarfile.open(fileobj=sys.stdin.buffer, mode="r|gz") as tf:
    for m in tf:
        t = target(m.name)
        if t is None:
            continue
        if m.islnk():
            m.linkname = target(m.linkname) or m.linkname
        m.name = t
        tf.extract(m, dest, filter="tar")
        found += t.startswith("loader/")
print(f"  {found} fichiers du loader extraits", file=sys.stderr)
' "${staging}" "${have[@]}"

    [[ -x "${staging}/loader/arcade-launcher" ]] \
        || die "arcade-launcher absent de l'archive (chemin changé chez RGS ?) : rien n'a été modifié"

    old_runner=$(sed -n 's/^runner: *//p' "${WAL_DIR}/launcher.yaml")
    new_runner=$(sed -n 's/^runner: *//p' "${staging}/loader/launcher.yaml")

    mkdir -p "${backup}/windows-arcade-loader"
    # Fusion : tout ce que livre RGS, sauf les réglages SteamBox, les
    # runners, les réglages utilisateur et les prefixes déjà extraits ;
    # --delete retire ce que RGS a retiré (gardé dans la sauvegarde).
    rsync -a --delete --backup --backup-dir="${backup}/windows-arcade-loader" \
        --exclude=/launcher.yaml --exclude=/launcher.yaml.rgs --exclude=/.rgs-update \
        --exclude=/runners/ --exclude=/userprofiles/ --exclude='/wine-prefix/*/' \
        "${staging}/loader/" "${WAL_DIR}/"
    cp "${staging}/loader/launcher.yaml" "${WAL_DIR}/launcher.yaml.rgs"
    if [[ -d "${staging}/loader/userprofiles" ]]; then
        rsync -a --ignore-existing "${staging}/loader/userprofiles/" "${WAL_DIR}/userprofiles/"
    fi

    # GE-Proton : celui que le launcher.yaml de RGS demande.
    if [[ -n "${new_runner}" && -d "${staging}/runners/${new_runner}" ]]; then
        mv "${staging}/runners/${new_runner}" "${WAL_DIR}/runners/"
    fi
    if [[ -n "${new_runner}" && -d "${WAL_DIR}/runners/${new_runner}" ]]; then
        if [[ "${new_runner}" != "${old_runner}" ]]; then
            cp -a "${WAL_DIR}/launcher.yaml" "${backup}/windows-arcade-loader/launcher.yaml"
            sed -i "s/^runner: .*/runner: ${new_runner}/" "${WAL_DIR}/launcher.yaml"
            echo "  runner : ${old_runner} → ${new_runner}"
        fi
        for r in "${WAL_DIR}"/runners/*/; do
            r=$(basename "${r}")
            if [[ "${r}" != "${new_runner}" && "${r}" != "${old_runner}" ]]; then
                echo "  ancien runner supprimé : ${r}"
                rm -rf "${WAL_DIR:?}/runners/${r}"
            fi
        done
    else
        echo "  ATTENTION : runner ${new_runner:-?} de RGS introuvable, ${old_runner} gardé" >&2
    fi

    # Réglages ajoutés par RGS à launcher.yaml : à reporter à la main.
    local keys
    keys=$(comm -23 <(sed -n 's/^\([a-z_]*\):.*/\1/p' "${WAL_DIR}/launcher.yaml.rgs" | sort -u) \
                    <(sed -n 's/^\([a-z_]*\):.*/\1/p' "${WAL_DIR}/launcher.yaml" | sort -u))
    [[ -z "${keys}" ]] || echo "  ATTENTION : nouveaux réglages dans launcher.yaml.rgs, à reporter dans launcher.yaml : ${keys//$'\n'/, }" >&2

    echo "${remote}" > "${STAMP}"
    rm -rf "${staging}"
    echo "Loader : mis à jour (archive RGS du ${remote% / *})."
}

# ── Thèmes ────────────────────────────────────────────────────────────────────
update_themes() {
    local theme opts any=0
    local remote=":http,url='${RGS_URL}/':update/Themes"
    for theme in ckau-book-PixN Hypermax-Plus-PixN Carbon-PixN ckau-book; do
        [[ -d "${THEMES_DIR}/${theme}" ]] || continue
        any=1
        (( check )) && { echo "Thème ${theme} : installé (synchronisé sans --check)"; continue; }
        echo "Thème ${theme} : synchronisation…"
        opts=(--config /dev/null --checkers 16 --backup-dir "${backup}/themes/${theme}")
        [[ -t 1 ]] && opts+=(--progress)
        # Comme RGS : pas les vidéos de Hypermax-Plus (trop lourdes).
        [[ "${theme}" == Hypermax-Plus-PixN ]] && opts+=(--exclude '/_inc/videos/**')
        rclone sync "${remote}/${theme}" "${THEMES_DIR}/${theme}" "${opts[@]}"
    done
    (( any )) || echo "Aucun thème RGS installé dans ${THEMES_DIR}."
    (( check )) || echo "Thèmes : à jour (relancer EmulationStation pour les recharger)."
}

case "${what}" in
    loader) update_loader ;;
    theme)  update_themes ;;
    all)    update_loader; update_themes ;;
esac

# Sauvegardes : les deux dernières mises à jour (dossiers vides retirés).
if [[ -d "${backup}" ]]; then
    find "${backup}" -depth -type d -empty -delete
fi
if [[ -d "${BACKUP_ROOT}" ]]; then
    find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d | sort | head -n -2 | xargs -r rm -rf
fi
