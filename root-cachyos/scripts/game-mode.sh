#!/bin/bash
# ArcadeBox — Mode Jeu façon SteamOS : lance Steam Big Picture (gamepadui)
# dans gamescope plutôt que directement sous KWin.
#
# Steam Deck n'utilise KWin qu'en Mode Bureau — le Mode Jeu (celui réellement
# testé/supporté par Valve pour Big Picture et Remote Play) tourne sous
# gamescope, le micro-compositeur maison de Valve. Nos soucis de rendu sous
# KWin (écran noir Big Picture, capture GLX Remote Play cassée malgré
# UnredirectFullscreen et une vraie session standard) sont vraisemblablement
# des angles morts spécifiques à KWin que Valve n'a jamais eu de raison de
# tester. Confirmé en direct : gamescope crée bien une vraie fenêtre
# imbriquée dans notre session X11/KWin (backend sdl).
#
# Ferme l'instance Steam existante avant de relancer dans gamescope : Steam
# n'autorise qu'une seule instance (verrou singleton) — un second lancement
# se contente de transmettre la commande à l'instance existante et quitte
# aussitôt, sans jamais passer par gamescope.
set -e

if pgrep -f "steamrt64/steam -srt-logger-opened" >/dev/null 2>&1; then
    echo "[game-mode] Fermeture de l'instance Steam existante..."
    /config/.local/share/Steam/steamrt64/steam -shutdown 2>/dev/null || true
    TIMEOUT=20
    while pgrep -f "steamrt64/steam -srt-logger-opened" >/dev/null 2>&1 && [ "${TIMEOUT}" -gt 0 ]; do
        sleep 0.5
        TIMEOUT=$((TIMEOUT - 1))
    done
fi

RESOLUTION="$(xdpyinfo | awk '/dimensions:/ {print $2}')"
WIDTH="${RESOLUTION%x*}"
HEIGHT="${RESOLUTION#*x}"

exec gamescope --backend sdl -W "${WIDTH:-1920}" -H "${HEIGHT:-1080}" -f -e -- steam -gamepadui
