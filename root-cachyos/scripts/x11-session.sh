#!/bin/bash
# Bureau KDE en session X11 réelle (Xorg + driver NVIDIA direct sur le GPU,
# pas Xvfb) plutôt que Wayland — après deux échecs concrets sous Wayland,
# testés en direct sur un conteneur jetable :
#   - wayvnc ne fonctionne QUE sur les compositeurs wlroots, confirmé dans
#     son propre README ("Gnome, KDE and Weston are not supported").
#   - le périphérique souris virtuel créé par Sunshine n'était jamais tagué
#     ID_INPUT_MOUSE par udev en temps réel sous KWin (cause exacte non
#     élucidée), rendant la souris inopérante.
# X11 règle wayvnc structurellement (x11vnc fonctionne avec n'importe quel
# gestionnaire de fenêtres X11, capture native au protocole, pas de
# fragmentation par compositeur). La souris, elle, restait cassée sous X11
# aussi au départ (Sunshine utilise de vrais périphériques uinput, pas
# XTest — udev ne persistait jamais ses tags en temps réel dans ce
# conteneur, cause exacte jamais élucidée) : réglée en forçant le pilote
# X11 historique 'evdev' (indépendant d'udev) sur les périphériques
# Sunshine, voir xorg.conf.d/99-sunshine-input.conf.
#
# Ce script tourne EN ROOT (contrairement à hypr-session.sh/kde-session.sh
# avant lui) : Xorg.wrap refuse de lancer le serveur X pour un utilisateur
# non-root sans session console/logind enregistrée ("Only console users are
# allowed to run the X server") — confirmé en direct, notre utilisateur
# arcade n'a jamais de session logind (pas de systemd). Seul Xorg lui-même
# doit rester root ; la session Plasma (startplasma-x11) tourne comme arcade
# via runuser plus bas, connectée au serveur X déjà démarré.

set -e

XORG_CONF="/etc/X11/xorg-arcadebox.conf"
ARCADE_UID="$(id -u arcade)"
ARCADE_RUNTIME_DIR="/run/user/${ARCADE_UID}"

# xorg.conf généré au runtime : le BusID PCI du GPU dépend de l'hôte, pas
# connu au moment du build. lspci liste parfois plusieurs GPU NVIDIA (hôtes
# multi-GPU) même si un seul est passé au conteneur — nvidia-smi ne
# rapporte que celui réellement assigné (NVIDIA_VISIBLE_DEVICES), donc
# c'est la source fiable ici plutôt que lspci brut.
BUS_ID_RAW=$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader 2>/dev/null | head -1)
if [ -n "${BUS_ID_RAW}" ]; then
    BUS=$(echo "${BUS_ID_RAW}" | cut -d: -f2 | sed 's/^0*//')
    DEV=$(echo "${BUS_ID_RAW}" | cut -d: -f3 | cut -d. -f1 | sed 's/^0*//')
    FUNC=$(echo "${BUS_ID_RAW}" | cut -d. -f2)
    XORG_BUS_ID="PCI:${BUS:-0}:${DEV:-0}:${FUNC:-0}"
else
    echo "[x11-session] ATTENTION : BusID NVIDIA introuvable via nvidia-smi, Xorg risque d'échouer."
    XORG_BUS_ID="PCI:1:0:0"
fi
echo "[x11-session] BusID NVIDIA détecté : ${XORG_BUS_ID}"

cat > "${XORG_CONF}" <<EOF
Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection

Section "Device"
    Identifier "Device0"
    Driver "nvidia"
    BusID "${XORG_BUS_ID}"
    Option "TripleBuffer" "true"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Device0"
    Option "ForceCompositionPipeline" "true"
EndSection
EOF

Xorg :0 -config "${XORG_CONF}" -seat seat0 -noreset -novtswitch &
XORG_PID=$!
trap 'kill "${XORG_PID}" 2>/dev/null || true' EXIT

TIMEOUT=30
while ! DISPLAY=:0 xdpyinfo >/dev/null 2>&1 && [ "${TIMEOUT}" -gt 0 ]; do
    sleep 0.5
    TIMEOUT=$((TIMEOUT - 1))
done
if [ "${TIMEOUT}" -le 0 ]; then
    echo "[x11-session] ERREUR : Xorg n'a jamais répondu, abandon."
    exit 1
fi
echo "[x11-session] Xorg prêt."

# Doit être fait en root : /etc/xdg/menus/ appartient à root, arcade ne
# peut pas y écrire — confirmé en direct (cp silencieusement en échec sous
# "|| true", applications.menu jamais créé, menu KDE vide en conséquence).
[ -f /etc/xdg/menus/applications.menu ] || \
    cp /etc/xdg/menus/plasma-applications.menu /etc/xdg/menus/applications.menu 2>/dev/null || true

# À partir d'ici, tout tourne comme arcade (pas de raison d'avoir kwin/
# plasmashell en root) — mais ce script reste root en premier plan pour
# que le trap ci-dessus nettoie Xorg quand la session se termine.
runuser -u arcade -- env \
    HOME=/home/arcade DISPLAY=:0 XDG_RUNTIME_DIR="${ARCADE_RUNTIME_DIR}" \
    QT_QPA_PLATFORM=xcb XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=x11 \
    KDE_SESSION_VERSION=6 SDL_VIDEODRIVER=x11 SDL_JOYSTICK_DISABLE_UDEV=1 \
    bash -c '
mkdir -p "${HOME}/.config" "${HOME}/.local/share"

# GTK ne suit pas automatiquement le thème Plasma comme le font les
# applications Qt (intégration native via plasma-integration) — breeze-gtk
# fournit le thème mais il faut le sélectionner explicitement.
mkdir -p "${HOME}/.config/gtk-3.0" "${HOME}/.config/gtk-4.0"
cat > "${HOME}/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Breeze-Dark
gtk-icon-theme-name=Papirus-Dark
EOF
cp "${HOME}/.config/gtk-3.0/settings.ini" "${HOME}/.config/gtk-4.0/settings.ini"

# Pas d'\''écran de verrouillage : aucun mécanisme de login ici, un
# verrouillage serait une impasse définitive plutôt qu'\''une protection utile.
kwriteconfig6 --file "${HOME}/.config/kscreenlockerrc" --group Daemon --key Autolock false 2>/dev/null || true

touch "${HOME}/.local/share/user-places.xbel"

# Thème sombre par défaut pour les applications Qt/Plasma (GTK est réglé
# séparément ci-dessus) — sans ça Arch installe Breeze en clair par défaut.
kwriteconfig6 --file "${HOME}/.config/kdeglobals" --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop 2>/dev/null || true
kwriteconfig6 --file "${HOME}/.config/kdeglobals" --group General --key ColorScheme BreezeDark 2>/dev/null || true
kwriteconfig6 --file "${HOME}/.config/kwinrc" --group org.kde.kdecoration2 --key theme Breeze 2>/dev/null || true

# Desactive l optimisation KWin qui bypass le compositeur pour les fenetres
# plein ecran (unredirect) - confirme en direct : cause exacte d ecran noir
# pour Steam Big Picture (fenetre CEF/Chromium plein ecran) sur ce driver
# NVIDIA, sans doute lie a la meme famille de bugs GLX/compositeur que la
# capture bureau de Steam Remote Play.
kwriteconfig6 --file "${HOME}/.config/kwinrc" --group Compositing --key UnredirectFullscreen false 2>/dev/null || true

# Thème de curseur — sans ça, confirmé en direct sous KWin/Wayland : curseur
# invisible. Gardé par précaution ici aussi.
kwriteconfig6 --file "${HOME}/.config/kcminputrc" --group Mouse --key cursorTheme breeze_cursors 2>/dev/null || true
kwriteconfig6 --file "${HOME}/.config/kcminputrc" --group Mouse --key cursorSize 24 2>/dev/null || true

# Reconstruit la base d'\''applications (kickoff/menu) — nécessaire pour que nos
# .desktop personnalisés (Steam, Sunshine, Chrome, émulateurs...) apparaissent.
# (applications.menu lui-même est copié plus haut, en root : /etc/xdg/menus/
# appartient à root, arcade ne peut pas y écrire.)
kbuildsycoca6 2>/dev/null || true

# PipeWire — gardé uniquement pour l'\''audio de Sunshine (PulseAudio via
# pipewire-pulse) ; la capture vidéo sous X11 passe par NvFBC, pas PipeWire.
# Protégé par pgrep : un redémarrage de svc-kde relance ce script, mais
# pipewire/pipewire-pulse survivent (le socket déjà lié fait échouer une
# deuxième instance) alors que wireplumber (simple client, pas de socket à
# lui) démarrait une deuxième fois sans erreur — confirmé en direct : deux
# wireplumber en concurrence sur le même graphe PipeWire faisaient planter
# Steam (segfault) au moment ou il crée son null sink de streaming.
pgrep -x pipewire >/dev/null || pipewire &
sleep 1
pgrep -x wireplumber >/dev/null || wireplumber &
pgrep -x pipewire-pulse >/dev/null || pipewire-pulse &
sleep 1

# startplasma-x11 (vraie session standard, avec ksmserver/kded6/plasma_session)
# plutot que kwin_x11+plasmashell lances a la main : le blocage supposement
# du a systemd --user ne concernait que startplasma-WAYLAND, jamais reteste
# specifiquement pour X11 depuis. Confirme en direct sur conteneur jetable :
# demarre sans blocage malgre les echecs (ignores) de org.freedesktop.systemd1,
# panneau par defaut charge automatiquement (plus besoin du hack qdbus/
# loadTemplate precedent). Piste principale aussi pour l ecran noir de Steam
# Remote Play (capture GLX cassee sous notre lancement a la main non standard) -
# a confirmer en usage reel, Valve ne testant/supportant que de vraies sessions.
dbus-run-session startplasma-x11
'
