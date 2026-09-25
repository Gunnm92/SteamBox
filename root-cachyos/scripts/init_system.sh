#!/bin/bash
# Préparation système one-shot, avant la boucle superviseur.
set -e

# Plus de locale-gen ici (25/09) : il réécrivait /etc/locale.gen avec
# fr_FR + en_US seules et reconstruisait l'archive des locales au premier
# démarrage, effaçant celles compilées dans l'image (EXTRA_LOCALES, voir
# Dockerfile) — vérifié après déploiement : de_DE/es_ES/it_IT/pt_BR absentes.

mkdir -p /config/.config/sunshine /config/.local/share/Steam

# chown -R sur TOUT /config est un piège : /config/games n'est pas un
# dossier de config du conteneur mais un montage séparé pointant vers la
# bibliothèque de jeux existante de l'utilisateur (ROMs Batocera + médias,
# Epic, Steam Prefix, VR...) — observé en direct : plusieurs centaines de
# milliers de fichiers, un chown -R dessus prenait encore plus de 15 minutes
# sans avoir fini. Cette bibliothèque n'a jamais besoin d'appartenir à
# arcade (souvent déjà en 0777, accessible peu importe le propriétaire) et
# ne doit JAMAIS être parcourue ici.
#
# On chown seulement les sous-dossiers que CE conteneur crée et doit
# effectivement posséder, jamais l'arborescence /config entière — et,
# comme avant, seulement si l'ownership n'est pas déjà correcte.
TARGET_OWNER="${PUID:-1000}:${PGID:-1000}"
for d in /config/.config /config/.local /config/.cache /config/.steam \
         /config/.nv /config/nvidia-drivers /config/.pki \
         /config/.bash_history /config/.bash_logout /config/.bash_profile /config/.bashrc; do
    [ -e "${d}" ] || continue
    CURRENT_OWNER=$(stat -c '%u:%g' "${d}" 2>/dev/null || echo "")
    [ "${CURRENT_OWNER}" = "${TARGET_OWNER}" ] || chown -R "${TARGET_OWNER}" "${d}"
done
