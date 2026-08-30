#!/bin/bash
# Bureau Wayland réel via labwc (compositeur wlroots) + panneau/bureau XFCE
# — second pivot Waybox (29/08). Remplace la session KWin : ni wayvnc ni
# evdev-bridge (input souris/clavier Sunshine) ne fonctionnent contre KWin,
# qui n'implémente pas les protocoles wlroots dont ces deux outils dépendent
# — voir point 6 de l'historique en tête de Dockerfile.cachyos. labwc est le
# compositeur de l'ancien Dockerfile webstation, où wayvnc fonctionnait déjà.
#
# labwc gère nativement son accès DRM/input via seatd (LIBSEAT_BACKEND=seatd,
# voir ENV du Dockerfile) — tourne de bout en bout en arcade, pas de dance
# root/runuser type Xorg.wrap.

set -e

ARCADE_UID="$(id -u arcade)"
ARCADE_RUNTIME_DIR="/run/user/${ARCADE_UID}"
mkdir -p "${ARCADE_RUNTIME_DIR}"
chown arcade:arcade "${ARCADE_RUNTIME_DIR}"
chmod 700 "${ARCADE_RUNTIME_DIR}"

runuser -u arcade -- env \
    HOME=/home/arcade XDG_RUNTIME_DIR="${ARCADE_RUNTIME_DIR}" \
    QT_QPA_PLATFORM=wayland XDG_CURRENT_DESKTOP=XFCE XDG_SESSION_TYPE=wayland \
    SDL_VIDEODRIVER=wayland,x11 SDL_JOYSTICK_DISABLE_UDEV=1 \
    LIBSEAT_BACKEND=seatd SEATD_VTBOUND=0 \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games" \
    bash -c '
mkdir -p "${HOME}/.config" "${HOME}/.local/share"

# labwc ne lit PAS XKB_DEFAULT_LAYOUT depuis lenvironnement du process qui
# le lance : il a son propre mécanisme, un fichier
# ~/.config/labwc/environment quil charge lui-même au démarrage (doc
# officielle labwc) — confirmé en direct le 30/08 : sans ce fichier précis,
# la variable passée via env/exec est purement et simplement ignorée.
mkdir -p "${HOME}/.config/labwc"
cat > "${HOME}/.config/labwc/environment" <<EOF
XKB_DEFAULT_LAYOUT=fr
XKB_DEFAULT_VARIANT=mac
EOF

# focus-follows-mouse (31/08) : le clavier virtuel Sunshine/evdev-bridge
# perdait le focus après un changement de fenêtre côté client Moonlight
# (overlay Steam, alt-tab, fermeture d'un jeu...) — les touches partaient
# dans le vide jusqu'à ce qu'un nouveau changement de fenêtre le redonne par
# hasard, confirmé en direct. Le clavier virtuel Wayland n'a pas de notion
# de clic pour redemander le focus lui-même, contrairement à une vraie
# souris/clavier physiques ; followMouseRequiresMovement=no comble ça en
# refocalisant sur la fenêtre sous le curseur à CHAQUE changement de
# fenêtre (pas seulement au mouvement de souris) — le curseur virtuel étant
# piloté en continu par evdev-bridge, le focus doit rester juste sans
# action de l'utilisateur. ~/.config/labwc/rc.xml, même mécanisme que
# environment ci-dessus : partagé par les deux compositeurs labwc (bureau
# visible wayland-0 et headless Sunshine wayland-1), même $HOME.
cat > "${HOME}/.config/labwc/rc.xml" <<EOF
<?xml version="1.0"?>
<labwc_config>
  <focus>
    <followMouse>yes</followMouse>
    <followMouseRequiresMovement>no</followMouseRequiresMovement>
    <raiseOnFocus>yes</raiseOnFocus>
  </focus>
</labwc_config>
EOF

# Bus D-Bus de session réel, au chemin standard $XDG_RUNTIME_DIR/bus —
# indépendant du compositeur (identique aux sessions précédentes de ce
# projet). Nécessaire pour wireplumber (audio) et pressure-vessel/Proton
# (jeux Heroic).
if [ ! -S "${XDG_RUNTIME_DIR}/bus" ]; then
    dbus-daemon --session --fork --address="unix:path=${XDG_RUNTIME_DIR}/bus"
fi
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# Thème sombre par défaut pour GTK3/4 — Mc-OS-CTLina-XFCE-Dark (macOS
# Catalina, ajouté le 30/08) + Papirus pour les icônes.
mkdir -p "${HOME}/.config/gtk-3.0" "${HOME}/.config/gtk-4.0"
cat > "${HOME}/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=Mc-OS-CTLina-XFCE-Dark
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Cantarell 10
EOF
cp "${HOME}/.config/gtk-3.0/settings.ini" "${HOME}/.config/gtk-4.0/settings.ini"

xdg-mime default wine.desktop application/x-ms-dos-executable application/x-msi application/x-ms-shortcut application/x-bat 2>/dev/null || true

# Verrou Chrome périmé (audit menu XFCE 31/08) : SingletonLock/-Cookie/
# -Socket dans le profil persistant (/config, monté depuis lhôte) encodent
# le hostname du conteneur au moment où Chrome a été lancé pour la dernière
# fois. Un renommage de conteneur/image (ArcadeBox -> Waybox -> SteamBox)
# laisse un lien SingletonLock pointant sur un hostname qui nexiste plus
# ("WayBox-25845" trouvé en direct) — Chrome refuse alors de démarrer
# ("profile appears to be in use by another Google Chrome process on
# another computer"). Un seul processus Chrome à la fois sur cette session
# arcade : sans risque de le nettoyer inconditionnellement à chaque boot.
rm -f "${HOME}/.config/google-chrome/Singleton"{Lock,Cookie,Socket} 2>/dev/null || true

# PipeWire — audio (PulseAudio via pipewire-pulse) + capture vidéo Sunshine
# (confirmé fonctionnel via KMS contre kwin_wayland le 29/08, labwc étant
# lui aussi un backend DRM direct).
pgrep -x pipewire >/dev/null || pipewire &
sleep 1
pgrep -x wireplumber >/dev/null || wireplumber &
pgrep -x pipewire-pulse >/dev/null || pipewire-pulse &
sleep 1

# unset WAYLAND_DISPLAY avant de lancer labwc : cette variable est fixée
# globalement dans le Dockerfile (ENV WAYLAND_DISPLAY=wayland-0, utile pour
# Sunshine/evdev-bridge qui se connectent APRÈS coup) mais si labwc la voit
# héritée AVANT davoir créé son propre socket, il tente de sy CONNECTER
# comme client imbriqué au lieu de créer son propre backend DRM racine —
# confirmé en direct : "Could not connect to remote display: No such file
# or directory" / "unable to create backend". labwc recrée wayland-0 tout
# seul une fois lancé correctement (premier compositeur du conteneur).
#
# labwc : compositeur racine directement sur le GPU via seatd/libinput, sans
# Xorg. Pas de --xwayland explicite comme kwin_wayland : labwc démarre son
# Xwayland interne automatiquement dès quun client X11 (Steam, Wine,
# Pegasus) en a besoin.
#
# WLR_DRM_DEVICES=/dev/dri/card0 : /sys/class/drm (lecture seule, vue non
# isolée par conteneur) liste les GPU de lhôte multi-GPU (card0/1/2), mais
# /dev/dri/ ne contient QUE celui réellement passé au conteneur (card0) —
# sans ce forçage, wlroots énumère via /sys, essaie card1/card2, et échoue
# ("Could not canonicalize path /dev/dri/cardN: No such file or directory")
# avant même de tester card0. Confirmé en direct le 30/08.
#
# WLR_LIBINPUT_NO_DEVICES=1 : aucun périphérique dinput réel nest visible
# au démarrage du conteneur (rien de branché à cet instant) — wlroots
# refuse de démarrer son backend libinput sans au moins un device par
# défaut ("libinput initialization failed, no input devices"), suggestion
# officielle du message derreur lui-même. evdev-bridge (souris/clavier
# virtuels Sunshine) et les manettes réelles/virtuelles (SDL, pas libinput)
# ne dépendent pas de ce backend, donc aucun impact fonctionnel ici.
# WLR_RENDERER=vulkan essayé puis abandonné (30/08) : active bien le
# support HDR (wp_color_manager_v1 confirmé exposé), MAIS casse
# complètement Sunshine — écran noir et clavier/souris morts sous Moonlight,
# confirmé en direct. La corruption verte/jaune qui avait motivé cet essai
# venait en fait dun ancien prefix Wine reutilise (config figee de lere
# X11), pas dun vrai manque de HDR — un prefix neuf suffit a la corriger.
# Retour au renderer par defaut (GLES2) tant que lincompatibilite
# Vulkan-renderer/capture Sunshine nest pas comprise.
unset WAYLAND_DISPLAY DISPLAY
WLR_DRM_DEVICES=/dev/dri/card0 WLR_LIBINPUT_NO_DEVICES=1 labwc &
LABWC_PID=$!

WAYLAND_SOCKET="${XDG_RUNTIME_DIR}/wayland-0"
TIMEOUT=30
while [ ! -S "${WAYLAND_SOCKET}" ] && [ "${TIMEOUT}" -gt 0 ]; do
    sleep 0.5
    TIMEOUT=$((TIMEOUT - 1))
done

# Panneau/bureau XFCE par-dessus labwc — barre des tâches, menu
# applications, gestionnaire de fichiers (Thunar) accessibles pour
# ladministration. Steam reste linterface principale de la session,
# lancée manuellement depuis ce panneau (pas dautostart, voir décision
# utilisateur 29/08).
#
# xfsettingsd manquait ici (30/08) : cest le démon qui applique réellement
# les changements faits dans xfce4-settings (thème, curseur, scaling...) à
# la session en cours — sans lui les réglages senregistrent mais ne
# sappliquent jamais tant que rien ne les relit. xfce4-panel/nm-applet
# nont pas ce rôle.
xfsettingsd &

# xfconf, pas gtk-3.0/settings.ini (30/08) : une fois xfsettingsd démarré,
# c est LUI l autorité sur le thème/les icônes/la police via sa propre base
# (xfconf) et le protocole XSETTINGS — il écrase silencieusement le
# settings.ini statique écrit plus haut. Attente explicite que xfsettingsd
# soit prêt (xfconfd démarre avec lui) avant d écrire, sinon xfconf-query
# échoue ou écrit dans le vide.
for i in $(seq 1 20); do
    xfconf-query -c xsettings -p /Net/ThemeName >/dev/null 2>&1 && break
    sleep 0.5
done
xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "Mc-OS-CTLina-XFCE-Dark" 2>/dev/null || true
xfconf-query -c xsettings -p /Net/IconThemeName -n -t string -s "Papirus-Dark" 2>/dev/null || true
xfconf-query -c xsettings -p /Gtk/FontName -n -t string -s "Cantarell 10" 2>/dev/null || true

# xfdesktop (30/08) : jamais lancé jusque-là — sans lui, aucun fond
# décran/bureau nest géré du tout (canal xfconf xfce4-desktop vide,
# confirmé en direct), do l impression de bureau "nu" malgré thème/icônes/
# police correctement réglés par ailleurs. monitorHDMI-A-1 codé en dur
# (nom de connecteur réel, cohérent avec le reste du projet) : le dialogue
# graphique "Réglages du bureau" écrit lui sur "monitorUnknown" (mauvaise
# détection de sortie sous Wayland, confirmé en direct) — un changement fait
# depuis ce dialogue nest donc JAMAIS repris par le xfdesktop réellement
# affiché tant quon ne le recopie pas à la main sur cette clé precise.
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorHDMI-A-1/workspace0/last-image \
    -n -t string -s "/usr/share/backgrounds/xfce/xfce-cp-dark.svg" 2>/dev/null || true
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorHDMI-A-1/workspace0/image-style \
    -n -t int -s 5 2>/dev/null || true
xfdesktop &

xfce4-panel &
nm-applet &
/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &

wait "${LABWC_PID}"
'
