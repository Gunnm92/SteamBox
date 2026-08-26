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

# DRI3 se règle au niveau serveur (section Extensions), pas comme option du
# pilote — mis par erreur dans Section "Device" au premier essai, rejeté
# avec "(WW) modeset(0): Option "DRI3" is not used" (confirmé en direct,
# xdpyinfo -queryExtensions ne listait toujours que DRI2 après). Sans DRI3,
# tout client GLX/EGL (glxinfo, GTK, OpenGL natif dans Wine) retombe
# silencieusement sur le rendu logiciel llvmpipe au lieu du vrai GPU -
# confirmé en direct : "OpenGL renderer string: llvmpipe" malgré "direct
# rendering: Yes". Sans conséquence pour les jeux DXVK/VKD3D (Vulkan direct
# vers le pilote NVIDIA, ne passe pas par ce chemin), mais casse tout
# OpenGL réel.
Section "Extensions"
    Option "DRI3" "Enable"
EndSection

# Aucune section Monitor jusqu'ici (audit 2026-08-26) : sans EDID (sortie
# headless/virtuelle), le mode et le taux de rafraîchissement retenus par le
# pilote NVIDIA ne sont pas garantis stables d'un démarrage à l'autre — un
# décalage entre le refresh du serveur X et le fps réellement encodé par
# Sunshine produit du judder qu'aucun réglage d'encodeur ne corrige ensuite.
# Rend 1920x1080@60 disponible et préféré, AVEC repli explicite sur
# "nvidia-auto-select" (comportement précédent) dans la SubSection Display
# plus bas — jamais un mode unique sans filet, non vérifié en direct sur ce
# matériel, qui pourrait casser l'affichage plutôt que le stabiliser.
Section "Monitor"
    Identifier "Monitor0"
    Option "DPMS" "false"
    Option "ModeValidation" "AllowNonEdidModes, NoMaxPClkCheck, NoEdidMaxPClkCheck"
    Modeline "1920x1080_60.00" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Device0"
    Monitor "Monitor0"
    Option "ForceCompositionPipeline" "true"
    SubSection "Display"
        # "1920x1080_60.00" en tête (préféré) puis "nvidia-auto-select" en
        # repli — conserve le comportement précédent (choix automatique du
        # pilote) si ce mode explicite est refusé pour une raison imprévue,
        # plutôt que de forcer un seul mode sans filet.
        Modes "1920x1080_60.00" "nvidia-auto-select"
    EndSubSection
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
# Version Plasma variable selon la distro : 6 sur CachyOS/Arch (rolling),
# 5.27 sur Ubuntu 24.04 (noble n'a pas encore Plasma 6) — confirmé en
# direct sur Ubuntu : kwriteconfig6/kbuildsycoca6 absents, seuls les
# binaires suffixés "5" existent. KDE_SESSION_VERSION et les commandes
# kwriteconfig/kbuildsycoca détectés dynamiquement ci-dessous pour que ce
# script reste commun aux deux variantes sans divergence.
if command -v kwriteconfig6 >/dev/null 2>&1; then
    KDE_SESSION_VER=6
else
    KDE_SESSION_VER=5
fi

# GSK_RENDERER=cairo : les applis GTK4 (ex. zenity — popup EULA de
# steam-installer) se mappaient bien côté X11 (fenêtre positionnée,
# IsViewable) mais ne peignaient jamais aucun pixel, avec en boucle
# "MESA: error: Failed to attach to x11 shm". Tracé en direct (strace) :
# juste avant l'échec, le code appelle geteuid()/getuid() (= 99, arcade) et
# abandonne — GSK (le moteur de rendu accéléré de GTK4, DRI3/Mesa) refuse le
# SHM X11 quand le client n'est pas root, très probablement lié à Xorg qui
# tourne en root ici (cf. commentaire en tête de fichier) pendant que la
# session tourne en arcade. Les applis Qt/KDE (systemsettings, kwin,
# plasmashell) ne sont pas touchées, seul GSK est concerné. Forcer le rendu
# logiciel cairo (pas de DRI3/GL) contourne le problème à la racine —
# confirmé en direct : la popup Steam s'affiche et devient utilisable.
runuser -u arcade -- env \
    HOME=/home/arcade DISPLAY=:0 XDG_RUNTIME_DIR="${ARCADE_RUNTIME_DIR}" \
    QT_QPA_PLATFORM=xcb XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=x11 \
    KDE_SESSION_VERSION="${KDE_SESSION_VER}" SDL_VIDEODRIVER=x11 SDL_JOYSTICK_DISABLE_UDEV=1 \
    GSK_RENDERER=cairo \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games" \
    bash -c '
mkdir -p "${HOME}/.config" "${HOME}/.local/share"

# Bus D-Bus de session RÉEL, au chemin standard $XDG_RUNTIME_DIR/bus —
# remplace dbus-run-session (portait le bus, mais seulement accessible aux
# enfants directs de startplasma-x11 plus bas, pas aux autres processus
# arcade comme wireplumber ou les jeux Proton lancés depuis Heroic).
# Confirmé en direct, deux bugs distincts causés par cette absence :
#   - wireplumber : tente de lancer "dbus-launch" (absent sur Ubuntu, non
#     installé par défaut) faute de bus trouvable -> aucun routage audio,
#     pipewire/pipewire-pulse tournent mais sans effet ("plus de son").
#   - pressure-vessel (Steam Runtime, invoqué par Heroic/umu-launcher pour
#     Proton) : "bwrap: Cant find source path /run/pressure-vessel/bus" ->
#     bloque tout lancement de jeu Proton avant même la phase de rendu.
if [ ! -S "${XDG_RUNTIME_DIR}/bus" ]; then
    dbus-daemon --session --fork --address="unix:path=${XDG_RUNTIME_DIR}/bus"
fi
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

KWRITECONFIG=$(command -v kwriteconfig6 || command -v kwriteconfig5)
KBUILDSYCOCA=$(command -v kbuildsycoca6 || command -v kbuildsycoca5)

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
"${KWRITECONFIG}" --file "${HOME}/.config/kscreenlockerrc" --group Daemon --key Autolock false 2>/dev/null || true

touch "${HOME}/.local/share/user-places.xbel"

# Thème sombre par défaut pour les applications Qt/Plasma (GTK est réglé
# séparément ci-dessus) — sans ça Arch installe Breeze en clair par défaut.
"${KWRITECONFIG}" --file "${HOME}/.config/kdeglobals" --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop 2>/dev/null || true
"${KWRITECONFIG}" --file "${HOME}/.config/kdeglobals" --group General --key ColorScheme BreezeDark 2>/dev/null || true
"${KWRITECONFIG}" --file "${HOME}/.config/kwinrc" --group org.kde.kdecoration2 --key theme Breeze 2>/dev/null || true

# Desactive l optimisation KWin qui bypass le compositeur pour les fenetres
# plein ecran (unredirect) - confirme en direct : cause exacte d ecran noir
# pour Steam Big Picture (fenetre CEF/Chromium plein ecran) sur ce driver
# NVIDIA, sans doute lie a la meme famille de bugs GLX/compositeur que la
# capture bureau de Steam Remote Play.
#
# Reglage global plutot qu une regle de fenetre ciblee sur Steam Big Picture :
# volontaire (audit 2026-08-26). Une regle par WM_CLASS serait plus fine
# (naffecterait pas les autres jeux plein ecran) mais son identifiant exact
# (WM_CLASS de la fenetre CEF/gamepadui) na jamais ete verifie en direct sur
# ce conteneur - un mauvais identifiant reintroduirait silencieusement
# l ecran noir corrige ici. A affiner uniquement en le verifiant sur un
# conteneur de test (xprop WM_CLASS sur la fenetre Steam BP), jamais en prod.
"${KWRITECONFIG}" --file "${HOME}/.config/kwinrc" --group Compositing --key UnredirectFullscreen false 2>/dev/null || true

# Reglages de latence de composition (audit 2026-08-26) : independants du
# unredirect ci-dessus, sans risque connu de regression ecran noir -
# LatencyPolicy Low reduit la file d attente de rendu de KWin ; blur/contrast
# et les animations d interface n ont aucune utilite en streaming/manette et
# ajoutent un cout de composition a chaque frame.
"${KWRITECONFIG}" --file "${HOME}/.config/kwinrc" --group Compositing --key LatencyPolicy Low 2>/dev/null || true
"${KWRITECONFIG}" --file "${HOME}/.config/kwinrc" --group Plugins --key blurEnabled false 2>/dev/null || true
"${KWRITECONFIG}" --file "${HOME}/.config/kwinrc" --group Plugins --key contrastEnabled false 2>/dev/null || true
"${KWRITECONFIG}" --file "${HOME}/.config/kdeglobals" --group KDE --key AnimationDurationFactor 0 2>/dev/null || true

# Thème de curseur — sans ça, confirmé en direct sous KWin/Wayland : curseur
# invisible. Gardé par précaution ici aussi.
"${KWRITECONFIG}" --file "${HOME}/.config/kcminputrc" --group Mouse --key cursorTheme breeze_cursors 2>/dev/null || true
"${KWRITECONFIG}" --file "${HOME}/.config/kcminputrc" --group Mouse --key cursorSize 24 2>/dev/null || true

# Reconstruit la base d'\''applications (kickoff/menu) — nécessaire pour que nos
# .desktop personnalisés (Steam, Sunshine, Chrome, émulateurs...) apparaissent.
# (applications.menu lui-même est copié plus haut, en root : /etc/xdg/menus/
# appartient à root, arcade ne peut pas y écrire.)
"${KBUILDSYCOCA}" 2>/dev/null || true

# Association .exe/.msi/.bat -> Wine pour lancement automatique depuis Dolphin.
# wine.desktop declare bien ces MimeType (paquet wine-staging), mais rien ne
# le definit comme gestionnaire par defaut sans cet appel explicite - sans
# ca, double-clic sur un .exe dans Dolphin ne fait rien.
xdg-mime default wine.desktop application/x-ms-dos-executable application/x-msi application/x-ms-shortcut application/x-bat 2>/dev/null || true

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
# Plus besoin de dbus-run-session ici : DBUS_SESSION_BUS_ADDRESS pointe deja
# vers le bus reel demarre plus haut.
startplasma-x11
'
