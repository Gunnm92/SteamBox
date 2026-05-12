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
    cabextract \
    p7zip-full && \
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

# ── 6. Patch NvFBC ───────────────────────────────────────────────────────────
RUN curl -fsSL "https://raw.githubusercontent.com/keylase/nvidia-patch/master/patch-fbc.sh" \
      -o /usr/local/bin/patch-nvfbc.sh && chmod +x /usr/local/bin/patch-nvfbc.sh

# ── 7. Steam + Sunshine ───────────────────────────────────────────────────────
RUN \
  add-apt-repository multiverse && apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    steam-installer steam-devices && \
  SUNSHINE_URL=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/LizardByte/Sunshine/releases/latest" \
    | grep "browser_download_url.*ubuntu-24.04-amd64\.deb" | cut -d'"' -f4) && \
  [ -n "${SUNSHINE_URL}" ] || { echo "FATAL: SUNSHINE_URL vide"; exit 1; } && \
  curl -fSL --retry 3 -o /tmp/sunshine.deb "${SUNSHINE_URL}" && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/sunshine.deb && \
  apt-get autoclean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ── 8. Heroic + Pegasus ───────────────────────────────────────────────────────
RUN \
  HEROIC_DEB_URL=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest" \
    | awk -F '(": "|")' '/browser_download_url.*amd64\.deb/ {print $3}' | head -1) && \
  [ -n "${HEROIC_DEB_URL}" ] || { echo "FATAL: HEROIC_DEB_URL vide"; exit 1; } && \
  curl -fSL --retry 3 -o /tmp/heroic.deb "${HEROIC_DEB_URL}" && \
  apt-get install -y /tmp/heroic.deb && \
  PEGASUS_URL=$(curl -K /etc/gh_curlrc --retry 2 -sX GET \
    "https://api.github.com/repos/mmatyas/pegasus-frontend/releases" \
    | awk -F '"' '/browser_download_url.*x11-static\.zip/{print $4; exit}') && \
  [ -n "${PEGASUS_URL}" ] || { echo "FATAL: PEGASUS_URL vide"; exit 1; } && \
  curl -fSL --retry 3 -o /tmp/pegasus.zip "${PEGASUS_URL}" && \
  unzip /tmp/pegasus.zip pegasus-fe -d /usr/local/bin/ && \
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
    | awk -F '"' '/browser_download_url.*\.AppImage"/{print $4; exit}') && \
  [ -n "${SRM_URL}" ] || { echo "FATAL: SRM_URL vide"; exit 1; } && \
  curl -fSL --retry 3 -o /tmp/srm.AppImage "${SRM_URL}" && \
  chmod +x /tmp/srm.AppImage && cd /tmp && ./srm.AppImage --appimage-extract && \
  mv /tmp/squashfs-root /opt/steam-rom-manager && \
  ln -sf /opt/steam-rom-manager/AppRun /usr/local/bin/steam-rom-manager && \
  SRM_ICON=$(find /opt/steam-rom-manager -name "*.png" | head -1) && \
  { [ -n "$SRM_ICON" ] && cp "$SRM_ICON" /usr/share/pixmaps/steam-rom-manager.png || true; } && \
  printf '[Desktop Entry]\nType=Application\nName=Steam ROM Manager\nExec=/usr/local/bin/steam-rom-manager --no-sandbox\nIcon=steam-rom-manager\nTerminal=false\nCategories=Game;\n' \
    > /usr/share/applications/steam-rom-manager.desktop && \
  rm -rf /tmp/* /var/tmp/*

# ── 10. wsquashfs-batocera ────────────────────────────────────────────────────
COPY ArcadeBox/wsquashfs-batocera /usr/local/bin/wsquashfs-batocera
RUN chmod +x /usr/local/bin/wsquashfs-batocera

EXPOSE 3001
VOLUME /config
