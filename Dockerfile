FROM lscr.io/linuxserver/webstation:latest

ARG BUILD_DATE
ARG VERSION
ARG GITHUB_TOKEN=""
LABEL build_version="ArcadeBox version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="arcadebox"

ENV TITLE="ArcadeBox" \
    DXVK_FILTER_DEVICE_NAME=NVIDIA \
    VKD3D_FILTER_DEVICE_NAME=NVIDIA

# ── 0. GitHub auth ────────────────────────────────────────────────────────────
RUN if [ -n "${GITHUB_TOKEN}" ]; then \
      printf 'header = "Authorization: token %s"\n' "${GITHUB_TOKEN}" > /etc/gh_curlrc; \
    else \
      touch /etc/gh_curlrc; \
    fi

# ── 1. Outils système + audio ─────────────────────────────────────────────────
RUN \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    binutils \
    dos2unix \
    kmod \
    libasound2-plugins \
    pciutils \
    unzip \
    wget \
    gamemode \
    dex \
    mako-notifier \
    rsync \
    nano \
    xmlstarlet \
    mangohud \
    cabextract \
    p7zip-full \
    mpv \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-libav && \
  apt-get autoclean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── 2. Lindbergh Loader ───────────────────────────────────────────────────────
RUN \
  curl -fSL -o /tmp/lindbergh.app \
    "https://github.com/lindbergh-loader/lindbergh-loader/releases/download/v2.1.4/lindbergh-loader.AppImage" && \
  chmod +x /tmp/lindbergh.app && cd /tmp && ./lindbergh.app --appimage-extract && \
  { [ -L squashfs-root ] && mv AppDir /opt/lindbergh && rm -f squashfs-root || mv squashfs-root /opt/lindbergh; } && \
  ln -s /opt/lindbergh/AppRun /usr/local/bin/lindbergh && \
  DTOP=$(find /opt/lindbergh -maxdepth 4 -name "*.desktop" 2>/dev/null | head -1) && \
  { [ -n "$DTOP" ] && cp "$DTOP" /usr/share/applications/lindbergh.desktop || \
    printf '[Desktop Entry]\nType=Application\nName=Lindbergh Loader\nExec=/usr/local/bin/lindbergh\nCategories=Game;Emulator;\nTerminal=false\n' \
      > /usr/share/applications/lindbergh.desktop; } && \
  sed -i -e 's|^Exec=.*|Exec=/usr/local/bin/lindbergh|' \
         -e '/^TryExec=/d' -e '/^Path=/d' /usr/share/applications/lindbergh.desktop && \
  rm -rf /tmp/*

# ── 3. Supermodel (Sega Model 3) ─────────────────────────────────────────────
RUN \
  SUPERMODEL_URL=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/trzy/Supermodel/releases/latest" \
    | awk -F '[""]' '/browser_download_url.*[Ll]inux.*\.tar/ {print $4}' | head -1) && \
  if [ -n "${SUPERMODEL_URL}" ]; then \
    curl -o /tmp/supermodel.tar.gz -L "${SUPERMODEL_URL}" && \
    mkdir -p /opt/supermodel && \
    tar -xzf /tmp/supermodel.tar.gz -C /opt/supermodel --strip-components=1 && \
    ln -s /opt/supermodel/supermodel /usr/local/bin/supermodel; \
  else \
    echo "Supermodel: pas de release Linux, skip"; \
  fi && \
  rm -rf /tmp/*

# ── 4. Wine Staging + DXVK + VKD3D-Proton ────────────────────────────────────
RUN \
  dpkg --add-architecture i386 && \
  mkdir -pm755 /etc/apt/keyrings && \
  curl -sL https://dl.winehq.org/wine-builds/winehq.key \
    | gpg --dearmor > /etc/apt/keyrings/winehq-archive.key && \
  OS_CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}") && \
  curl -sL "https://dl.winehq.org/wine-builds/ubuntu/dists/${OS_CODENAME}/winehq-${OS_CODENAME}.sources" \
    -o /etc/apt/sources.list.d/winehq.sources && \
  apt-get update && \
  apt-get install --install-recommends -y winehq-staging winetricks && \
  apt-get install --no-install-recommends -y libpulse0:i386 libasound2:i386 && \
  DXVK_VERSION=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/doitsujin/dxvk/releases/latest" \
    | awk -F '[""]' '/tag_name/ {print $4; exit}' | sed 's/v//') && \
  [ -n "${DXVK_VERSION}" ] || { echo "FATAL: DXVK_VERSION vide"; exit 1; } && \
  curl -o /tmp/dxvk.tar.gz -L \
    "https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz" && \
  tar -xzf /tmp/dxvk.tar.gz -C /opt/ && mv /opt/dxvk-${DXVK_VERSION} /opt/dxvk && \
  VKD3D_VERSION=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases/latest" \
    | awk -F '[""]' '/tag_name/ {print $4; exit}' | sed 's/v//') && \
  [ -n "${VKD3D_VERSION}" ] || { echo "FATAL: VKD3D_VERSION vide"; exit 1; } && \
  curl -o /tmp/vkd3d.tar.zst -L \
    "https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v${VKD3D_VERSION}/vkd3d-proton-${VKD3D_VERSION}.tar.zst" && \
  tar -xf /tmp/vkd3d.tar.zst -C /opt/ && mv /opt/vkd3d-proton-${VKD3D_VERSION} /opt/vkd3d && \
  WINE64_DIR=/usr/lib/x86_64-linux-gnu/wine/x86_64-windows && \
  WINE32_DIR=/usr/lib/x86_64-linux-gnu/wine/i386-windows && \
  mkdir -p "$WINE64_DIR" "$WINE32_DIR" && \
  cp /opt/dxvk/x64/*.dll "$WINE64_DIR/" && cp /opt/dxvk/x32/*.dll "$WINE32_DIR/" && \
  cp /opt/vkd3d/x64/*.dll "$WINE64_DIR/" && cp /opt/vkd3d/x86/*.dll "$WINE32_DIR/" && \
  apt-get autoclean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── 4b. Wine Gecko + Mono ─────────────────────────────────────────────────────
RUN \
  GECKO_VERSION=$(curl -fsSL "https://raw.githubusercontent.com/wine-mirror/wine/refs/heads/master/dlls/appwiz.cpl/addons.c" \
    | grep -oP '(?<=GECKO_VERSION ")[^"]+' | head -1) && \
  MONO_VERSION=$(curl -fsSL "https://raw.githubusercontent.com/wine-mirror/wine/refs/heads/master/dlls/appwiz.cpl/addons.c" \
    | grep -oP '(?<=MONO_VERSION ")[^"]+' | head -1) && \
  mkdir -p /usr/share/wine/gecko /usr/share/wine/mono && \
  for arch in x86 x86_64; do \
    curl -fsSL --retry 3 -o "/usr/share/wine/gecko/wine-gecko-${GECKO_VERSION}-${arch}.msi" \
      "https://dl.winehq.org/wine/wine-gecko/${GECKO_VERSION}/wine-gecko-${GECKO_VERSION}-${arch}.msi" || true; \
  done && \
  curl -fsSL --retry 3 -o "/tmp/wine-mono.tar.xz" \
    "https://dl.winehq.org/wine/wine-mono/${MONO_VERSION}/wine-mono-${MONO_VERSION}-x86.tar.xz" && \
  tar -xf /tmp/wine-mono.tar.xz -C /usr/share/wine/mono && \
  rm -f /tmp/wine-mono.tar.xz

# ── 5. wsquashfs deps + Skyscraper ────────────────────────────────────────────
RUN \
  apt-get update && \
  apt-get install --no-install-recommends -y \
    squashfuse squashfs-tools fuse-overlayfs gamescope && \
  apt-get install --no-install-recommends -y \
    git qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools \
    libqt5sql5-sqlite libqt5xml5 && \
  git clone --depth 1 https://github.com/muldjord/skyscraper.git /tmp/skyscraper && \
  cd /tmp/skyscraper && qmake && make -j$(nproc) && make install && \
  apt-get autoclean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── 6. NVIDIA Vulkan ICD + outils + Patch NvFBC ──────────────────────────────
# Les libs NVIDIA (.so) sont injectées au runtime par nvidia-container-toolkit.
# On installe ici uniquement les outils et les fichiers statiques nécessaires :
#   - vulkan-tools     : vulkaninfo, vkcube (debug / vérification GPU)
#   - libvulkan-dev    : headers + loader Vulkan (pour build DXVK/VKD3D si besoin)
#   - nvidia_icd.json  : ICD Vulkan NVIDIA dans /usr/share/vulkan/icd.d/
#     (le toolkit le crée dans /etc/vulkan/icd.d/ mais pas dans /usr/share/)
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
      vulkan-tools \
      libvulkan-dev \
      libvulkan1:i386 && \
    apt-get autoclean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://raw.githubusercontent.com/keylase/nvidia-patch/master/patch-fbc.sh" \
      -o /usr/local/bin/patch-nvfbc.sh && chmod +x /usr/local/bin/patch-nvfbc.sh

# ── 7. Steam + Sunshine ───────────────────────────────────────────────────────
RUN \
  add-apt-repository multiverse && apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    steam-installer steam-devices && \
  sed -i 's|^Exec=/usr/games/steam|Exec=env XDG_RUNTIME_DIR=/config/.XDG WAYLAND_DISPLAY=wayland-0 SDL_VIDEODRIVER=wayland SDL_JOYSTICK_DISABLE_UDEV=1 /usr/games/steam|' \
    /usr/share/applications/steam.desktop && \
  UBUNTU_VER=$(. /etc/os-release && echo "${VERSION_ID}") && \
  SUNSHINE_JSON=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/LizardByte/Sunshine/releases/latest") && \
  SUNSHINE_URL=$(echo "${SUNSHINE_JSON}" \
    | grep "browser_download_url.*ubuntu-${UBUNTU_VER}-amd64\.deb" | cut -d'"' -f4) && \
  if [ -z "${SUNSHINE_URL}" ]; then \
    SUNSHINE_URL=$(echo "${SUNSHINE_JSON}" \
      | grep -o "https://[^\"]*ubuntu-[0-9.]*-amd64\.deb" | sort -V | tail -1); \
    echo "Sunshine: aucun paquet pour Ubuntu ${UBUNTU_VER}, repli sur ${SUNSHINE_URL}"; \
  fi && \
  [ -n "${SUNSHINE_URL}" ] || { echo "FATAL: SUNSHINE_URL vide"; exit 1; } && \
  curl -fSL --retry 3 -o /tmp/sunshine.deb "${SUNSHINE_URL}" && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/sunshine.deb && \
  apt-get autoclean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── 8. Heroic + Pegasus ───────────────────────────────────────────────────────
# wayland-0 = socket labwc (compositor affiché) ; wayland-1 = Selkies (capture)
RUN \
  HEROIC_DEB_URL=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest" \
    | awk -F '(": "|")' '/browser_download_url.*amd64\.deb/ {print $3}' | head -1) && \
  [ -n "${HEROIC_DEB_URL}" ] || { echo "FATAL: HEROIC_DEB_URL vide"; exit 1; } && \
  curl -fSL --retry 3 -o /tmp/heroic.deb "${HEROIC_DEB_URL}" && \
  apt-get install -y /tmp/heroic.deb && \
  sed -i 's|^Exec=/opt/Heroic/heroic|Exec=env DISPLAY=:0 XDG_RUNTIME_DIR=/config/.XDG WAYLAND_DISPLAY=wayland-0 ELECTRON_OZONE_PLATFORM_HINT=wayland /opt/Heroic/heroic|' \
    /usr/share/applications/heroic.desktop && \
  PEGASUS_URL=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/mmatyas/pegasus-frontend/releases" \
    | awk -F '"' '/browser_download_url.*amd64\.deb/{print $4; exit}') && \
  [ -n "${PEGASUS_URL}" ] || { echo "FATAL: PEGASUS_URL vide"; exit 1; } && \
  apt-get update && \
  curl -fSL --retry 3 -o /tmp/pegasus.deb "${PEGASUS_URL}" && \
  apt-get install -y --no-install-recommends qtwayland5 /tmp/pegasus.deb && \
  apt-get autoclean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── 9. Decky Loader + Steam ROM Manager ──────────────────────────────────────
RUN \
  DECKY_URL=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/SteamDeckHomebrew/decky-loader/releases/latest" \
    | awk -F '"' '/browser_download_url.*\/PluginLoader"/{print $4; exit}') && \
  [ -n "${DECKY_URL}" ] || { echo "FATAL: DECKY_URL vide"; exit 1; } && \
  mkdir -p /opt/decky-loader && \
  curl -fSL --retry 3 -o /opt/decky-loader/PluginLoader "${DECKY_URL}" && \
  chmod +x /opt/decky-loader/PluginLoader && \
  SRM_URL=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/SteamGridDB/steam-rom-manager/releases/latest" \
    | awk -F '"' '/browser_download_url.*\.AppImage"/ && !/arm64/{print $4; exit}') && \
  [ -n "${SRM_URL}" ] || { echo "FATAL: SRM_URL vide"; exit 1; } && \
  curl -fSL --retry 3 -o /tmp/srm.AppImage "${SRM_URL}" && \
  chmod +x /tmp/srm.AppImage && cd /tmp && ./srm.AppImage --appimage-extract && \
  mv /tmp/squashfs-root /opt/steam-rom-manager && \
  chmod -R a+rX /opt/steam-rom-manager && \
  ln -sf /opt/steam-rom-manager/AppRun /usr/local/bin/steam-rom-manager && \
  SRM_ICON=$(find /opt/steam-rom-manager -name "*.png" | head -1) && \
  { [ -n "$SRM_ICON" ] && cp "$SRM_ICON" /usr/share/pixmaps/steam-rom-manager.png || true; } && \
  printf '[Desktop Entry]\nType=Application\nName=Steam ROM Manager\nExec=/usr/local/bin/steam-rom-manager --no-sandbox\nIcon=steam-rom-manager\nTerminal=false\nCategories=Game;\n' \
    > /usr/share/applications/steam-rom-manager.desktop && \
  rm -rf /tmp/* /var/tmp/*

# ── 9b. PipeWire + portail xdg (capture d'écran Wayland) ─────────────────────
# Permet à Steam Remote Play de capturer via PipeWire (option -pipewire) au lieu
# de la capture X11 d'Xwayland, qui dépend de la fenêtre filmée.
# Activé au runtime par ARCADEBOX_PIPEWIRE=true — sans quoi rien n'est démarré.
#
# pipewire-pulse est volontairement EXCLU : Selkies capture l'audio via
# PulseAudio (output.monitor), les deux se disputeraient le socket.
# xdg-desktop-portal est déjà présent dans l'image de base ; on ajoute le
# backend wlroots, qui parle le zwlr_screencopy exposé par labwc.
RUN \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    pipewire \
    wireplumber \
    xdg-desktop-portal-wlr \
    dbus-bin && \
  dpkg -l pipewire-pulse 2>/dev/null | grep -q '^ii' && \
    { echo "FATAL: pipewire-pulse installé, conflit avec PulseAudio"; exit 1; } || true && \
  apt-get autoclean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── 9b2. Patch Selkies — ne pas détruire l'affichage sans client actif ───────
# Quand le dernier client navigateur Selkies se déconnecte (ou passe en arrière
# plan : la page envoie STOP_VIDEO via la Page Visibility API, même sans fermer
# l'onglet), reconfigure_displays() réduit le bureau virtuel à 1x1 et supprime
# tous les moniteurs xrandr. Sunshine (Moonlight) capture ce même moniteur
# partagé — sans lien avec l'état d'un client Selkies — et se retrouve figé.
# On neutralise uniquement ce nettoyage destructeur ; le reste de la logique
# (arrêt des pipelines d'encodage Selkies) reste intact.
RUN python3 - <<'PYEOF'
import pathlib
p = pathlib.Path("/lsiopy/lib/python3.14/site-packages/selkies/selkies.py")
old = '''                if not self.display_clients:
                    data_logger.warning("No display clients connected. Video pipelines remain stopped.")
                    _, _, _, _, screen_name = await get_new_res("1x1")
                    if screen_name:
                        current_monitors = await self._get_current_monitors()
                        for monitor_name in current_monitors:
                            await self._run_command(["xrandr", "--delmonitor", monitor_name], f"cleanup monitor {monitor_name}")
                    return'''
new = '''                if not self.display_clients:
                    # ArcadeBox: ne jamais réduire/supprimer l'affichage virtuel ici —
                    # Sunshine (Moonlight) peut en dépendre indépendamment de tout
                    # client Selkies actif.
                    data_logger.warning("No display clients connected. Leaving display as-is (ArcadeBox patch).")
                    return'''
content = p.read_text()
if old not in content:
    raise SystemExit(
        "FATAL: bloc de nettoyage selkies.py introuvable — le paquet selkies de "
        "l'image de base a changé, ce patch doit être mis à jour"
    )
p.write_text(content.replace(old, new, 1))
print("[arcadebox] Patch selkies.py appliqué (pas de reset d'affichage sans client)")
PYEOF

# ── 9b3. wayvnc + noVNC — accès bureau indépendant de Selkies ────────────────
# Selkies (service Python) est couplé à la supervision des process du bureau :
# l'arrêter fait tomber labwc/Sunshine/Steam en cascade (testé), donc on le
# garde tel quel. Mais son cycle de vie côté client (connexion/déconnexion/mise
# en arrière-plan) réduit ou détruit l'affichage virtuel partagé avec Sunshine.
# wayvnc capture labwc via le même protocole wlr-screencopy que Sunshine, sans
# dépendre d'aucun service Python — un second consommateur totalement
# indépendant, pour l'accès bureau/config jeux à la place de l'UI web Selkies.
RUN \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    wayvnc \
    novnc && \
  apt-get autoclean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── 9c. evdev-bridge (injection input Wayland pour Sunshine) ─────────────────
# Sunshine (version stable) n'injecte la souris/clavier que via uinput sur
# Linux — le support natif zwlr_virtual_pointer/zwp_virtual_keyboard n'est
# encore qu'une PR ouverte, non mergée (LizardByte/Sunshine#4972). Or labwc
# tourne ici imbriqué dans selkies-desktop, sans backend libinput : rien ne
# lit jamais les devices uinput "Mouse/Keyboard passthrough" créés par
# Sunshine à la connexion d'un client Moonlight.
#
# evdev-bridge comble ce trou : il lit ces devices uinput directement et
# rejoue les événements dans labwc via les protocoles Wayland
# zwlr_virtual_pointer_manager_v1 / zwp_virtual_keyboard_manager_v1, que
# labwc supporte nativement. Source : github.com/Desarso/evdev-bridge
# (pas de licence explicite dans le dépôt — usage privé uniquement, jamais
# republié).
RUN \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    gcc \
    libc6-dev \
    libwayland-dev \
    libxkbcommon-dev && \
  apt-get autoclean && rm -rf /var/lib/apt/lists/*
COPY ArcadeBox/evdev-bridge /tmp/evdev-bridge
RUN \
  make -C /tmp/evdev-bridge && \
  install -Dm755 /tmp/evdev-bridge/evdev-bridge-native /usr/local/bin/evdev-bridge-native && \
  rm -rf /tmp/evdev-bridge && \
  apt-get purge -y gcc libc6-dev libwayland-dev libxkbcommon-dev && \
  apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# ── 10. wsquashfs-batocera ────────────────────────────────────────────────────
COPY ArcadeBox/wsquashfs-batocera /usr/local/bin/wsquashfs-batocera
RUN chmod +x /usr/local/bin/wsquashfs-batocera

# ── 11. Surcouche s6 + defaults ArcadeBox ────────────────────────────────────
# init-arcadebox : oneshot s6-rc exécuté avant init-services (donc avant svc-de).
COPY ArcadeBox/root/ /
RUN chmod +x /etc/s6-overlay/s6-rc.d/init-arcadebox/run \
             /etc/s6-overlay/s6-rc.d/svc-evdev-bridge/run \
             /etc/s6-overlay/s6-rc.d/svc-wayvnc/run \
             /etc/s6-overlay/s6-rc.d/svc-novnc-web/run \
             /defaults/steam-gaming-mode.sh

EXPOSE 3001
VOLUME /config
