#!/bin/bash
# ArcadeBox — Ajoute abc au groupe propriétaire de /dev/uinput et /dev/input/*
# (GID 71 sur l'hôte, cf. group_add dans docker-compose.yml).
#
# Le --group-add Docker ajoute bien ce GID au process racine du conteneur,
# mais s6-setuidgid (utilisé par tous les services : svc-de, svc-evdev-bridge,
# etc.) recalcule les groupes supplémentaires depuis /etc/group à chaque bascule
# vers abc — ça écrase silencieusement le --group-add. En faisant de 71 un
# membre RÉEL et persistant du compte abc dans /etc/group, chaque appel
# s6-setuidgid abc le récupère naturellement, peu importe le service.

if ! getent group 71 >/dev/null 2>&1; then
    groupadd -g 71 hostinput 2>/dev/null || true
fi

if ! id -nG abc 2>/dev/null | grep -qw "$(getent group 71 | cut -d: -f1)"; then
    usermod -aG 71 abc
    echo "[arcadebox] abc ajouté au groupe GID 71 (/dev/input, /dev/uinput)"
fi
