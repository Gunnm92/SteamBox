# ArcadeBox 🕹️

Conteneur Docker clé en main pour émuler et lancer des jeux d'arcade (MAME, Lindbergh, Atomiswave...) et des jeux Windows, piloté par **Pegasus Frontend** sous **X11**.

> Inspiré de [linuxserver/docker-webstation](https://github.com/linuxserver/docker-webstation) pour la liste des émulateurs,  
> mais basé sur X11 (au lieu de Wayland) pour une meilleure compatibilité logicielle et matérielle.

---

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Architecture](#architecture)
- [Composants inclus](#composants-inclus)
- [Ressources nécessaires](#ressources-nécessaires)
- [Installation](#installation)
- [Configuration](#configuration)
- [Interface web (desktop)](#interface-web-desktop)
- [Outils de gestion des ROMs](#outils-de-gestion-des-roms)
- [Intégration wsquashfs](#intégration-wsquashfs)
- [Intégration Heroic Launcher](#intégration-heroic-launcher)
- [Pegasus Frontend](#pegasus-frontend)
- [Variables d'environnement](#variables-denvironnement)
- [Volumes](#volumes)

---

## Fonctionnalités

- **Frontend unifié** : Pegasus Frontend (X11) comme point d'entrée pour tous les jeux
- **Desktop web** : Openbox + noVNC — accès navigateur sans client VNC, avec gestionnaire de fichiers et terminal
- **Arcade natif** : MAME, Flycast (Naomi/Atomiswave), Model2 Emulator, Supermodel
- **Lindbergh** : support Sega Lindbergh via émulateur dédié (en cours de développement)
- **Multi-systèmes** : RetroArch avec cores pré-installés
- **Jeux Windows** : Wine + DXVK + VKD3D + Heroic Launcher (Epic Games, GOG, Amazon)
- **wsquashfs** : lancement de fichiers `.wsquashfs` Batocera via `wsquashfs-launcher`
- **Outils ROMs** : chdman, 7-zip, RomVault, Skyscraper pour gérer et scraper les ROMs
- **X11** : affichage natif X11, compatible avec tous les pilotes GPU (Intel, AMD, Nvidia) et VNC/Xvfb
- **GPU** : accélération matérielle via `/dev/dri` (Mesa / Vulkan)
- **Audio** : PulseAudio + ALSA
- **Persistance** : sauvegardes et configs dans `/config`

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    ArcadeBox Container                   │
│                                                          │
│   Navigateur ──► noVNC :8080 ──► X11 Display (:0)       │
│                                        │                 │
│          ┌─────────────────────────────┤                 │
│          │      Openbox WM             │                 │
│          │  ┌──────────┐ ┌──────────┐ │                 │
│          │  │  Pegasus │ │ PCManFM  │ │                 │
│          │  │ Frontend │ │(fichiers)│ │                 │
│          │  └────┬─────┘ └──────────┘ │                 │
│          │       │ lance              Xvfb/X11           │
│          └───────┼────────────────────┘                 │
│                  │                                       │
│    ┌─────────────┴──────────────┐                        │
│    │         Émulateurs         │                        │
│    │ MAME │ RetroArch │ Flycast │                        │
│    │ Model2 │ Supermodel │ ...  │                        │
│    └─────────────┬──────────────┘                        │
│                  │                                       │
│    ┌─────────────┴──────────────┐                        │
│    │       Jeux Windows         │                        │
│    │ Heroic │ Wine │ DXVK/VKD3D │                        │
│    │ wsquashfs-launcher (.wsq)  │                        │
│    └────────────────────────────┘                        │
│                                                          │
│  GPU: /dev/dri ──► Mesa/Vulkan                           │
└──────────────────────────────────────────────────────────┘
```

---

## Composants inclus

### Frontend

| Logiciel | Rôle |
|----------|------|
| [Pegasus Frontend](https://pegasus-frontend.org/) | Interface graphique unifiée |

### Arcade & Émulateurs

| Logiciel | Systèmes cibles |
|----------|-----------------|
| [MAME](https://www.mamedev.org/) | Arcade universel (CPS, Neo-Geo, Naomi...) |
| [RetroArch](https://www.retroarch.com/) | Multi-systèmes (cores MAME2003+, FBNeo, etc.) |
| [Flycast](https://github.com/flyinghead/flycast) | Sega Dreamcast, Naomi, Atomiswave |
| [Model2 Emulator](https://github.com/BlueSkyE1/model2) | Sega Model 2 (Virtua Fighter, Daytona USA) |
| [Supermodel](https://www.supermodel3.com/) | Sega Model 3 (Scud Race, Virtual On) |
| Lindbergh Emulator | Sega Lindbergh (House of the Dead 4, After Burner Climax) |

### Jeux Windows

| Logiciel | Rôle |
|----------|------|
| [Heroic Launcher](https://heroicgameslauncher.com/) | Client Epic Games, GOG, Amazon |
| [Wine](https://www.winehq.org/) (staging) | Compatibilité Windows |
| [DXVK](https://github.com/doitsujin/dxvk) | DirectX 9/10/11 → Vulkan |
| [VKD3D-Proton](https://github.com/HansKristian-Work/vkd3d-proton) | DirectX 12 → Vulkan |
| [winetricks](https://github.com/Winetricks/winetricks) | Installation de runtimes Windows |

### Packaging `.wsquashfs`

| Logiciel | Rôle |
|----------|------|
| [wsquashfs-launcher](../wsquashfs-launcher/) | Lance les fichiers `.wsquashfs` (format Batocera) |
| squashfuse | Montage en lecture des archives squashfs |
| fuse-overlayfs | OverlayFS pour les sauvegardes isolées |

### Interface & Desktop

| Logiciel | Rôle |
|----------|------|
| Xvfb / X11 | Serveur d'affichage X11 (headless) |
| [Openbox](http://openbox.org/) | Gestionnaire de fenêtres X11 léger |
| tint2 | Barre des tâches |
| [x11vnc](https://github.com/LibVNC/x11vnc) | Serveur VNC sur le display X11 |
| [noVNC](https://github.com/novnc/noVNC) | Client VNC HTML5 (accès navigateur :8080) |
| [PCManFM](https://github.com/lxde/pcmanfm) | Gestionnaire de fichiers graphique |
| [xterm](https://invisible-island.net/xterm/) | Terminal X11 |
| Mesa + Vulkan | Accélération GPU open-source |
| PulseAudio | Serveur audio |

### Outils de gestion des ROMs

| Logiciel | Rôle |
|----------|------|
| `chdman` (MAME tools) | Création/vérification/extraction de fichiers CHD |
| `castool` / `floptool` | Conversion d'images de médias MAME |
| `p7zip` / `zip` / `unrar` | Compression et extraction d'archives ROM |
| [RomVault](https://www.romvault.com/) | Audit et organisation de ROMs via fichiers DAT |
| [Skyscraper](https://github.com/muldjord/skyscraper) | Scraping de métadonnées et artworks pour Pegasus |
| `xmlstarlet` | Manipulation de fichiers DAT/XML MAME |
| `dos2unix` | Normalisation des fins de ligne (autorun.cmd) |
| `wget` / `curl` | Téléchargement de DAT files et mises à jour |

---

## Ressources nécessaires

### Système hôte

- **OS** : Linux (kernel ≥ 5.15 recommandé)
- **GPU** : AMD ou Intel (Mesa/Vulkan open-source) — Nvidia possible avec `nvidia-container-toolkit`
- **RAM** : minimum 4 Go, 8 Go recommandés pour les émulateurs lourds
- **CPU** : x86-64, SSE4.2+

### Dépôts / Sources à intégrer au build

| Ressource | URL | Usage |
|-----------|-----|-------|
| MAME | https://github.com/mamedev/mame | Émulateur arcade universel |
| RetroArch | https://github.com/libretro/RetroArch | Frontend multi-cores |
| Flycast | https://github.com/flyinghead/flycast | Dreamcast/Naomi/Atomiswave |
| Model2 Emulator | https://github.com/BlueSkyE1/model2 | Sega Model 2 |
| Supermodel | https://github.com/trzy/Supermodel | Sega Model 3 |
| Pegasus Frontend | https://pegasus-frontend.org/tools/deploy/ | Frontend principal |
| Heroic Launcher | https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases | Epic/GOG/Amazon |
| Wine Staging | https://wine-staging.com/ | Compatibilité Windows |
| DXVK | https://github.com/doitsujin/dxvk/releases | DX→Vulkan |
| VKD3D-Proton | https://github.com/HansKristian-Work/vkd3d-proton/releases | DX12→Vulkan |
| wsquashfs-launcher | `../wsquashfs-launcher/` (ce dépôt) | Lancement .wsquashfs |
| noVNC | https://github.com/novnc/noVNC | Accès web X11 |
| Skyscraper | https://github.com/muldjord/skyscraper | Scraping métadonnées Pegasus |
| RomVault | https://www.romvault.com/ | Audit et gestion de collections ROM |

### ROMs & Assets (non fournis)

- **ROMs** : placer dans `/config/userdata/roms/<système>/` en respectant les noms Batocera (`arcade`, `naomi`, `model2`, `windows`...)
- **BIOS** : placer dans `/config/userdata/bios/` (ex: `dc_boot.bin`, `naomi.zip`, `awbios.zip`)
- **Artworks Pegasus** : scraping via [skraper.net](https://www.skraper.net/) ou [screenscraper.fr](https://www.screenscraper.fr/)

---

## Installation

### Prérequis hôte

```bash
# FUSE pour wsquashfs-launcher
sudo modprobe fuse
echo "fuse" | sudo tee -a /etc/modules

# Accès GPU
sudo usermod -aG video,render $USER
```

### docker-compose.yml

```yaml
services:
  arcadebox:
    image: arcadebox:latest
    build: .
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Europe/Paris
      - DISPLAY=:0
      - RESOLUTION=1920x1080
      - VNC_PORT=5900
      - NOVNC_PORT=8080
    volumes:
      - ./config:/config                       # configs applicatives
      - ./userdata:/config/userdata            # ROMs, BIOS, saves
      - /tmp/.X11-unix:/tmp/.X11-unix:rw       # X11 socket hôte (optionnel)
    ports:
      - "8080:8080"                            # noVNC (accès navigateur)
      - "5900:5900"                            # VNC direct
    devices:
      - /dev/dri:/dev/dri                      # GPU
      - /dev/fuse:/dev/fuse                    # FUSE pour wsquashfs
    cap_add:
      - SYS_ADMIN                              # nécessaire pour FUSE/OverlayFS
    security_opt:
      - apparmor:unconfined
    shm_size: "1gb"
    restart: unless-stopped
```

### Lancement

```bash
docker compose up -d
# Accès via navigateur : http://localhost:8080
```

---

## Configuration

### Structure `/config`

Structure conforme à Batocera — les noms de dossiers sont les identifiants système reconnus par Batocera/Pegasus/RetroArch.

```
/config/
├── userdata/
│   ├── roms/
│   │   ├── arcade/          # MAME (CPS, Neo-Geo, PGM...)
│   │   ├── naomi/           # Sega Naomi (Flycast)
│   │   ├── naomi2/          # Sega Naomi 2 (Flycast)
│   │   ├── atomiswave/      # Sammy Atomiswave (Flycast)
│   │   ├── model2/          # Sega Model 2
│   │   ├── model3/          # Sega Model 3 (Supermodel)
│   │   ├── lindbergh/       # Sega Lindbergh
│   │   ├── dreamcast/       # Sega Dreamcast (Flycast)
│   │   └── windows/         # Jeux Windows (.wsquashfs, .exe via Heroic)
│   ├── bios/                # Fichiers BIOS (dc_boot.bin, naomi.zip...)
│   ├── saves/               # Sauvegardes (toutes plateformes)
│   ├── screenshots/         # Captures d'écran
│   └── music/               # Musique de fond Pegasus
├── pegasus/                 # Config et métadonnées Pegasus
│   └── collections/         # Fichiers .pegasus.txt par collection
├── retroarch/               # Config RetroArch
├── mame/                    # Config + NVRAM MAME
├── heroic/                  # Config et bibliothèque Heroic
├── romvault/
│   └── DatRoot/             # Fichiers DAT No-Intro / MAME / Redump
└── skyscraper/              # Cache et config Skyscraper
```

---

## Interface web (desktop)

Le conteneur expose un bureau X11 complet accessible via navigateur sur le port **8080**, sans logiciel à installer côté client.

```
http://localhost:8080
```

La pile d'affichage :

```
Xvfb (:0) → Openbox WM → x11vnc → noVNC (WebSocket) → navigateur
```

**Ce que vous trouverez sur le bureau :**

| Élément | Raccourci / accès |
|---------|-------------------|
| Pegasus Frontend | Lancé au démarrage en plein écran |
| PCManFM (fichiers) | Clic droit bureau → Gestionnaire de fichiers |
| xterm (terminal) | Clic droit bureau → Terminal |
| tint2 (barre des tâches) | En bas de l'écran |

**Démarrage de session :** un script `~/.config/openbox/autostart` lance automatiquement Pegasus en plein écran. Pour revenir au bureau (administration, gestion des ROMs), appuyer sur `Super+D` ou faire `Alt+F4` sur Pegasus.

**Accès VNC direct** (client lourd) : port **5900**.

---

## Outils de gestion des ROMs

### chdman — gestion des fichiers CHD

```bash
# Créer un CHD depuis un fichier bin/cue
chdman createcd -i jeu.cue -o jeu.chd

# Vérifier l'intégrité d'un CHD
chdman verify -i jeu.chd

# Extraire un CHD vers bin/cue
chdman extractcd -i jeu.chd -o jeu.cue
```

### 7-zip — archives ROM

```bash
# Extraire une ROM zippée
7z x rom.zip -o/config/roms/arcade/

# Recompresser un dossier de ROMs
7z a -tzip roms_mame.zip /config/roms/arcade/*

# Vérifier l'intégrité d'une archive
7z t rom.zip
```

### RomVault — audit de collections

RomVault utilise des fichiers **DAT** (No-Intro, MAME, Redump) pour auditer et trier les ROMs :

1. Télécharger les DAT files depuis [No-Intro](https://www.no-intro.org/) ou [MAME](https://www.mamedev.org/release.html)
2. Placer les DAT dans `/config/romvault/DatRoot/`
3. Pointer RomVault vers `/config/roms/` comme `RomRoot`
4. Lancer l'audit pour identifier les ROMs manquantes, corrompues ou en double

### Skyscraper — scraping Pegasus

[Skyscraper](https://github.com/muldjord/skyscraper) récupère les métadonnées et artworks depuis ScreenScraper, IGDB, etc. et génère les fichiers `metadata.pegasus.txt` directement.

```bash
# Scraper une collection MAME
Skyscraper -p arcade -s screenscraper -u login:motdepasse \
           -i /config/userdata/roms/arcade/ \
           --flags unattend

# Générer les métadonnées Pegasus
Skyscraper -p arcade -f pegasus -i /config/userdata/roms/arcade/
```

Le résultat est écrit dans `/config/roms/arcade/media/` et `/config/roms/arcade/metadata.pegasus.txt`, directement lisibles par Pegasus.

---

## Intégration wsquashfs

Les fichiers `.wsquashfs` (format Batocera) sont lancés via [wsquashfs-launcher](../wsquashfs-launcher/).

```
# Dans metadata.pegasus.txt
collection: Windows Arcade (wsquashfs)
extensions: wsquashfs
launch: wsquashfs-launcher "{file.path}"
```

Les sauvegardes sont isolées par jeu dans `~/.local/share/wsquashfs/saves/<nom-du-jeu>/`.  
Pour pointer vers `/config/userdata/saves/wsquashfs/`, définir la variable d'environnement :

```bash
WSQUASHFS_SAVES_DIR=/config/userdata/saves/wsquashfs
```

---

## Intégration Heroic Launcher

Heroic gère les bibliothèques Epic Games Store, GOG et Amazon Games sans compte Windows.

```
# Dans metadata.pegasus.txt
collection: Epic Games
launch: heroic launch {file.path}
```

La config Heroic est persistée dans `/config/heroic/`.

---

## Pegasus Frontend

Pegasus est le frontend principal. Les collections se définissent via des fichiers `metadata.pegasus.txt` dans `/config/pegasus/collections/`.

**Exemple MAME :**

```
collection: Arcade (MAME)
shortname: mame
extensions: zip, chd
launch: mame -rompath /config/userdata/roms/arcade/ {file.basename}

game: Donkey Kong
file: dkong.zip
developer: Nintendo
year: 1981
```

**Exemple Flycast (Naomi) :**

```
collection: Naomi / Atomiswave
shortname: naomi
extensions: zip, bin, dat
launch: flycast "{file.path}"

game: Ikaruga
file: ikaruga.zip
developer: Treasure
year: 2001
```

---

## Variables d'environnement

| Variable | Défaut | Description |
|----------|--------|-------------|
| `PUID` | `1000` | UID de l'utilisateur dans le conteneur |
| `PGID` | `1000` | GID de l'utilisateur dans le conteneur |
| `TZ` | `Etc/UTC` | Fuseau horaire |
| `RESOLUTION` | `1920x1080` | Résolution de l'écran virtuel (Xvfb) |
| `VNC_PORT` | `5900` | Port VNC |
| `NOVNC_PORT` | `8080` | Port noVNC (accès web) |
| `DISPLAY` | `:0` | Display X11 |
| `WSQUASHFS_SAVES_DIR` | `~/.local/share/wsquashfs/saves` | Répertoire des sauvegardes wsquashfs |

---

## Volumes

| Chemin conteneur | Rôle |
|------------------|------|
| `/config` | Configurations applicatives (Pegasus, RetroArch, MAME...) |
| `/config/userdata` | ROMs, BIOS, saves, screenshots |
| `/dev/dri` | Accélération GPU |
| `/dev/fuse` | Support FUSE pour wsquashfs |
| `/tmp/.X11-unix` | Socket X11 hôte (mode passthrough) |
