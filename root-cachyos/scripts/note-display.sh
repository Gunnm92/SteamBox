#!/bin/bash
# Note le DISPLAY du Xwayland de labwc (22/11) : lancé par « labwc -s »,
# qui le lui fournit dès son démarrage (Xwayland à la demande, mais numéro
# déjà réservé). $1 : desktop (bureau noVNC) ou stream (labwc de Sunshine).
# Lu par desktop_display / stream_display (steambox-env.sh).
printf '%s' "${DISPLAY:-}" > "${XDG_RUNTIME_DIR}/steambox-${1:?usage: note-display.sh desktop|stream}-display"
