#!/bin/bash
# Préparation système one-shot, avant la boucle superviseur.
set -e

if [ ! -f /etc/locale.gen.done ]; then
    printf 'fr_FR.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n' > /etc/locale.gen
    locale-gen
    touch /etc/locale.gen.done
fi

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
