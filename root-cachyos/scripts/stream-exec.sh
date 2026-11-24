#!/bin/bash
# Lance une commande dans la session streamée par Sunshine (KWin de
# streaming, wayland-stream), avec le DISPLAY réel de son Xwayland (22/11, voir
# stream_display dans steambox-env.sh) — utilisé par les entrées apps.json
# (EmulationStation) au lieu d'un « env DISPLAY=:1 » codé en dur.
# shellcheck source=steambox-env.sh
. /usr/local/bin/scripts/steambox-env.sh
export WAYLAND_DISPLAY="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/stream/wayland-stream"
DISPLAY="$(stream_display)"
export DISPLAY
exec "$@"
