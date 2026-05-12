#!/bin/bash
# Initialisation ArcadeBox

# Arborescence des ROMs (noms de systèmes Batocera)
mkdir -p /userdata/roms/{arcade,naomi,naomi2,atomiswave,model2,model3,lindbergh,dreamcast,windows}
mkdir -p /userdata/{bios,saves,screenshots,music}
mkdir -p /userdata/system/wine-bottles/windows
mkdir -p /userdata/system/wine/custom

# Dossiers de config applicatifs
mkdir -p \
  /config/.config/pegasus-frontend \
  /config/.config/retroarch \
  /config/mame \
  /config/heroic \
  /config/skyscraper \
  /config/romvault/DatRoot

# Préconfig Pegasus
if [ ! -f /config/.config/pegasus-frontend/game_dirs.txt ] || \
   grep -q '/config/userdata/' /config/.config/pegasus-frontend/game_dirs.txt 2>/dev/null; then
  cat > /config/.config/pegasus-frontend/game_dirs.txt << 'EOF'
/userdata/roms/arcade
/userdata/roms/naomi
/userdata/roms/naomi2
/userdata/roms/atomiswave
/userdata/roms/model2
/userdata/roms/model3
/userdata/roms/lindbergh
/userdata/roms/dreamcast
/userdata/roms/windows
EOF
fi

# Permissions
chown -R abc:users /userdata /config/mame /config/heroic /config/skyscraper /config/romvault 2>/dev/null || true
find /userdata/system/wine-bottles -maxdepth 4 -not -user abc -exec chown abc:users {} + 2>/dev/null || true
chown abc:abc /defaults 2>/dev/null || true

# Patch NvFBC (débloque desktop capture GPU pour Sunshine)
if [[ -f /usr/local/bin/patch-nvfbc.sh ]]; then
    bash /usr/local/bin/patch-nvfbc.sh 2>/dev/null || true
    echo "/patched-lib" > /etc/ld.so.conf.d/000-patched-nvidia.conf
    ldconfig 2>/dev/null || true
fi

# Decky Loader
mkdir -p /config/homebrew/{plugins,themes,settings,services,data}
if [[ -f /opt/decky-loader/PluginLoader && ! -f /config/homebrew/services/PluginLoader ]]; then
    cp /opt/decky-loader/PluginLoader /config/homebrew/services/PluginLoader
    chmod +x /config/homebrew/services/PluginLoader
fi
chown -R abc:users /config/homebrew 2>/dev/null || true



# Mettre à jour l'autostart labwc depuis /defaults si le bloc dbus-launch problématique est présent
if grep -q 'dbus-launch' /config/.config/labwc/autostart 2>/dev/null; then
    cp /defaults/autostart_wayland /config/.config/labwc/autostart
fi

# Corriger le .desktop Steam (steam-installer met "Install Steam" comme nom)
if [[ -f /usr/share/applications/steam.desktop ]] && grep -q "Install Steam" /usr/share/applications/steam.desktop; then
    sed -i 's/^Name=.*/Name=Steam/' /usr/share/applications/steam.desktop
fi

# Autostart Steam via XDG (requis pour dex --autostart)
mkdir -p /config/.config/autostart
if [[ ! -f /config/.config/autostart/steam.desktop ]]; then
    cat > /config/.config/autostart/steam.desktop << 'EOF'
[Desktop Entry]
Name=Steam
Exec=steam -silent %U
Icon=steam
Terminal=false
Type=Application
Categories=Network;FileTransfer;Game;
X-GNOME-Autostart-enabled=true
EOF
fi

# uinput + input : accès manettes/périphériques pour abc
if [[ -e /dev/uinput ]]; then
    chmod 0666 /dev/uinput
    UINPUT_GID=$(stat -c '%g' /dev/uinput 2>/dev/null)
    if [[ -n "$UINPUT_GID" && "$UINPUT_GID" != "0" ]]; then
        getent group "$UINPUT_GID" &>/dev/null || groupadd -g "$UINPUT_GID" uinput 2>/dev/null || true
        usermod -aG "$UINPUT_GID" abc 2>/dev/null || true
    fi
fi
for dev in /dev/input/event* /dev/input/js*; do
    [[ -e "$dev" ]] && chmod 0666 "$dev" 2>/dev/null || true
done
