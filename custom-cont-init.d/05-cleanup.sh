#!/bin/bash
# ArcadeBox — Nettoyage au démarrage
# /dev/shm persiste lors d'un docker restart (pas de rm+run)
# → supprimer audio.lock pour que svc-selkies recrée les sinks PulseAudio
rm -f /dev/shm/audio.lock
echo "[cleanup] audio.lock supprimé"
