#!/bin/bash
# Note le DISPLAY du Xwayland d'une session (22/11) : appelé par la session
# KWin (kwin-stream-session.sh, desktop-session.sh) qui le lui fournit (Xwayland à la demande, mais numéro
# déjà réservé). $1 : desktop (bureau Plasma) ou stream (KWin de Sunshine).
# Lu par desktop_display / stream_display (steambox-env.sh).
printf '%s' "${DISPLAY:-}" > "${XDG_RUNTIME_DIR}/steambox-${1:?usage: note-display.sh desktop|stream}-display"
