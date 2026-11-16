# SteamBox 🎮

Console de jeu conteneurisée (Unraid ou tout hôte Docker Linux) : **CachyOS + session Wayland réelle
(labwc/XFCE) + Steam**, streamée par **Sunshine/Moonlight** avec résolution
dynamique, et administrable au navigateur via **noVNC**.

Successeur d'ArcadeBox (X11) puis Waybox — l'historique complet des
architectures essayées et des raisons de chaque pivot vit en tête de
[Dockerfile.cachyos](Dockerfile.cachyos), et chaque contournement du dépôt
est commenté avec sa date et sa validation (« confirmé en direct »).

---

## Architecture

Deux compositeurs labwc (wlroots) tournent côte à côte, pour séparer le
bureau d'administration du flux de jeu :

```
                    ┌────────────────────────── conteneur SteamBox ─────────────────────────┐
                    │                                                                       │
 Navigateur ──────► │ noVNC/websockify :6080 ─► wayvnc ─► labwc BUREAU (wayland-0, DRM/GPU) │
 (admin LAN)        │                                     └─ XFCE : panel, Thunar, menu     │
                    │                                                                       │
 Moonlight ───────► │ Sunshine :47984-48010 ──► capture ─► labwc HEADLESS (wayland-1)       │
 (jeu)              │      │                               └─ Steam gamepadui, jeux, Proton │
                    │      └─ evdev-bridge : clavier/souris virtuels ─► wayland-1           │
                    │      └─ uinput/uhid : manettes virtuelles ─► SDL/hidraw (Steam Input) │
                    │                                                                       │
                    │ s6-overlay supervise le tout (voir root-cachyos/etc/s6-overlay/)      │
                    └───────────────────────────────────────────────────────────────────────┘
```

- **Bureau visible** (`svc-labwc`, `wayland-0`, `DISPLAY=:0`) : session XFCE
  complète sur le GPU via seatd, capturée par wayvnc pour l'accès navigateur.
  Sert à l'administration (fichiers, réglages, lancement manuel des apps).
- **Session streaming** (`svc-labwc-headless`, `wayland-1`, `DISPLAY=:1`) :
  compositeur headless dédié à Sunshine. Sa résolution s'adapte **au client
  Moonlight connecté** (`prep-cmd` → [set-resolution.sh](root-cachyos/scripts/set-resolution.sh)).
  L'invariant « headless = wayland-1 » est garanti : le service refuse de
  démarrer tant que le bureau n'a pas créé `wayland-0`.
- **Entrées Moonlight** : clavier/souris passent par
  [evdev-bridge](evdev-bridge/bridge.c) (protocoles wlroots) ; les manettes
  par les devices virtuels uinput/uhid de Sunshine, lus par SDL et par Steam
  Input (hidraw — voir la règle udev
  [99-steambox-hidraw-fallback.rules](root-cachyos/etc/udev/rules.d/99-steambox-hidraw-fallback.rules)).
  La DualSense virtuelle est en **USB** et non en Bluetooth comme dans le
  Sunshine d'origine : Sunshine est compilé avec ce changement
  (étape `sunshine-usb` de [Dockerfile.prebuilt](Dockerfile.prebuilt)). Il
  est aussi patché pour envoyer les vibrations et les effets de
  gâchette en 5 ms au plus, au lieu d'attendre jusqu'à 100 ms le prochain
  paquet du client. Sans le passage en USB, les jeux à `libScePad` de
  2022 (F1 22…) ignorent la manette.

## Applications Sunshine

Définies dans `apps.json` (généré/migré par
[init_sunshine.sh](root-cachyos/scripts/init_sunshine.sh)) :

| App Moonlight | Contenu |
|---|---|
| **Desktop** | La session headless nue — lancer Steam depuis le menu |
| **Steam Big Picture** | `steam -gamepadui` directement sur wayland-1/Xwayland |
| **Mode SteamOS (Gamescope)** | gamepadui niché dans gamescope 2560×1440@120 (scaling FSR, changement de résolution in-game) |

Chaque app applique la résolution du client à la connexion et revient à
1920×1080 à la déconnexion. Jaquettes Moonlight dans le style de Wolf
(Games on Whales, MIT) : `/usr/share/steambox/sunshine/`.

## Contenu de l'image

- **Jeux** : Steam (+ gamescope), Heroic (Epic/GOG/Amazon, AppImage via AppManager), Wine-tkg +
  DXVK + VKD3D-Proton, wsquashfs-launcher (paquets Batocera) avec wine-tkg
  (arcade) et umu + proton-cachyos / UMU-Proton (jeux PC ; DualSense et
  vibration).
- **Émulateurs standalone** : Cemu (Wii U), PCSX2, RPCS3, DuckStation, Xemu,
  Xenia, melonDS, PPSSPP, Flycast, Vita3K (PS Vita), DOSBox Staging, ShadPS4,
  Eden (Switch), Dolphin, ScummVM, Lindbergh Loader, Supermodel (Model 3).
  Les AppImage (Cemu, PCSX2, RPCS3, DuckStation, Xemu, Xenia, melonDS, PPSSPP,
  Flycast, Vita3K, ShadPS4, Eden, Lindbergh, Steam ROM Manager) ne sont pas dans
  l'image : elles s'installent avec AppManager dans `~/Applications` (persistant),
  et `/usr/local/bin/<nom>` les lance via `root-cachyos/scripts/appimage-launch.sh`
  (nom du fichier reconnu sans tenir compte de la casse : `shadPS4`, `Xenia Canary`…).
  Si l'une manque, EmulationStation affiche laquelle installer.
- **RetroArch** + cores (FBNeo, MAME, snes9x, mGBA, melonDS, Flycast,
  Dolphin, PPSSPP, Beetle PSX/PCE, mupen64plus…).
- **Frontends** : Steam gamepadui (jeux PC), Batocera EmulationStation (jeux rétro/arcade, entrée Moonlight « EmulationStation »).
- **Bureau** : XFCE (panel, Thunar avec miniatures et accès aux partages réseau `smb://`, terminal, notifications xfce4-notifyd), thème, icônes et curseur WhiteSur sombres (style macOS, GTK 2/3/4 et libadwaita),
  même disposition clavier partout (local, VNC, Moonlight — `KEYBOARD_LAYOUT`).
- **Divers** : Steam ROM Manager, Flips, Google Chrome, AppManager (gestion des AppImage).

## Déploiement

Tout ce qui dépend d'une installation (GPU, chemins de l'hôte, clavier,
langue, registre) vit dans un **profil** `profiles/<nom>/` ; le reste du
dépôt est générique.

- **[docs/configuration.md](docs/configuration.md)** — profils et variables
  du conteneur (ludothèque, clavier, langue, GPU).
- **[docs/deploiement-unraid.md](docs/deploiement-unraid.md)** — exemple de
  déploiement réel sur Unraid (profil `unraid-gunnm`) : template, devices,
  Extra Parameters, règles cgroup.

### Build

```bash
make build                 # build local (--load)
make push                  # build + push vers le REGISTRY du profil
                           # (ou PUSH_REGISTRY : même registre en direct sur le LAN)
make push GITHUB_TOKEN=…   # recommandé : évite le rate-limit API GitHub
                           # (~18 requêtes/build, limite anonyme 60/h/IP)
make lint                  # shellcheck + hadolint (via Docker, rien à installer)
```

### Composants précompilés

evdev-bridge, Sunshine (DualSense USB), Batocera EmulationStation,
xfce-panel-launcher et freeimage ne sont **plus compilés à chaque
`make push`**. [Dockerfile.prebuilt](Dockerfile.prebuilt) les construit à la
demande, et ils sont publiés en release GitHub du dépôt (`prebuilt-AAAAMMJJ-HHMM`).
L'image télécharge la dernière release
([prebuilt-fetch](root-cachyos/build/prebuilt-fetch)).

```bash
make prebuilt-check        # compare la dernière release à l'amont (dernier tag
                           # Sunshine, HEAD d'ES et du lanceur XFCE, AUR
                           # freeimage, evdev-bridge/)
make prebuilt              # compile tout dans prebuilt/out/ (aucun registre)
make prebuilt-publish      # publie prebuilt/out/ en release GitHub (gh)
make push                  # l'image prend la nouvelle release
make push PREBUILT_TAG=prebuilt-…   # revenir à une release précédente
```

À relancer quand `prebuilt-check` signale une nouvelle version, après une
modification de `evdev-bridge/`, ou si un build de l'image échoue sur
« bibliothèque manquante … relancer make prebuilt ». CachyOS est une distribution rolling : une
bibliothèque peut changer de soname. Surcharges possibles : `ES_REF`,
`SUNSHINE_TAG`, `XFCE_LAUNCHER_REF`. Les deux Dockerfile partent de
`cachyos/cachyos-v3:latest`, revérifiée à chaque build (`--pull`).

`wsquashfs-launcher` n'est plus dans l'image. `init_wsquashfs.sh` l'installe
une seule fois dans `/config/.local/bin` (le home persistant, comme l'installeur
de son dépôt hors root) s'il est absent ; ensuite c'est son updater qui le
met à jour, pas un redémarrage du conteneur. Le commit installé est celui
fixé au build (`WSQUASHFS_REF`, par défaut le **dernier commit** de `main`,
résolu par `git ls-remote`) ; `make push WSQUASHFS_REF=<branche|tag|commit>`
pour en imposer un autre.
Les `.wsquashfs` sont reconnus par leur extension sous XFCE (type
`application/x-wsquashfs`) : un double-clic les ouvre avec le lanceur.

Les systèmes d'arcade PC (segare, segarw, segaalls, segaer, seganu, typex,
typex2, type-x2, nesicax, konamipc, rawthrills, namcoes3, unis, arcadepc,
adrenaline, globalvr) acceptent
aussi, comme le pack RGS, les dumps `.squashfs` / `.windowsloader` :
`game-launch-arcade.sh` les confie au **Windows arcade loader** de RGS
(`arcade-launcher`, émulation des cartes d'E/S, dongles, retour de force), les
`.wsquashfs` restant à `wsquashfs-launcher`. Le loader n'est pas dans
l'image : copier le dossier `system/rgs/emulators/windows-arcade-loader` du
pack RGS dans `/config/.local/share/windows-arcade-loader`, son GE-Proton
(`system/wine/custom/GE-Proton…`) dans son sous-dossier `runners/`, et
adapter `launcher.yaml` (`runners_dir: runners`,
`squashfs_saves: /home/arcade/games/Batocera/saves`).
Ensuite, `docker exec -it -u arcade SteamBox rgs-update` (`rgs-update.sh`,
équivalent de `rgs_upgrade` / `rgs_theme_upgrade` de RGS) le met à jour :
il lit en flux l'archive `update/v43/update.tar.gz` de RGS (seulement si elle
a changé), n'en garde que le loader et son GE-Proton, conserve
`launcher.yaml` (ligne `runner:` alignée sur RGS), `userprofiles/` et les
prefixes extraits, puis synchronise par rclone les thèmes RGS installés
(ckau-book-PixN…). `rgs-update --check` dit s'il y a du neuf ; `loader` ou
`theme` pour une seule partie. Dans EmulationStation, le système RGS
propose « Mise à jour RGS » (`roms/rgs/Mise à jour RGS.steambox`, lancé
par `rgs-update-es.sh` dans un terminal plein écran ; le contenu du fichier
donne les arguments). Fichiers remplacés gardés dans
`~/.local/share/steambox/rgs-backup/`. BIOS et bezels restent à la main.
exaarcadia (jeux PC de la borne Exa-Arcadia, `.wsquashfs` seulement) passe
directement par `wsquashfs-launcher`.

Sega Lindbergh suit la convention Batocera : un dossier par jeu, et un
fichier `<jeu>.game` à côté de l'exécutable (`2spicy/elf/2spicy.game`).
EmulationStation ne liste que ces `.game` ; `game-launch-lindbergh.sh` lance
l'AppImage Lindbergh Loader (2.x) depuis ce dossier, où elle détecte
l'exécutable. Elle lit `lindbergh.ini` (créé en plein écran au premier
lancement s'il manque), pas l'ancien `lindbergh.conf` de Batocera.
Le loader et les jeux sont en 32 bits : sur le partage Unraid (inodes au-delà
de 2^32), ils ne peuvent pas lire les dossiers. Le jeu est donc monté par
fuse-overlayfs (`ino32_t`) ; ses écritures (EEPROM, SRAM, `lindbergh.ini`)
vont dans `~/.local/share/steambox/lindbergh/<jeu>/upper`, la ludothèque
reste intacte. Les exécutables du jeu y reçoivent aussi le droit d'exécution,
souvent absent sur la ludothèque.

## Accès

| Service | Port | Authentification |
|---|---|---|
| noVNC (bureau navigateur) | `6080` | **aucune** — LAN de confiance uniquement |
| Sunshine Web UI | `47990` | compte Sunshine (appairage PIN Moonlight) |
| Flux Moonlight | `47984-48010` | appairage Sunshine |
| decky-loader | `1337` | écoute sur `127.0.0.1` uniquement (utilisé par Steam, pas joignable du LAN) |

## Modèle de sécurité

**Le conteneur n'est pas une frontière de sécurité.** C'est une console de
salon : les devices d'entrée sont en `666`, le binaire Sunshine porte
`cap_sys_admin` (capture KMS), et noVNC n'a pas de mot de passe. `/dev/input`
est un bind mount du répertoire de l'**hôte** : les règles udev du conteneur
(permissions des manettes virtuelles Sunshine) s'appliquent donc aussi aux
nœuds côté Unraid. Ce qui le
rend acceptable : réseau **LAN uniquement** — aucun de ces ports ne doit être
exposé sur Internet, directement ou via redirection. Pour un accès distant,
passer par un VPN ou un reverse proxy authentifié en amont.

## Structure du dépôt

```
Dockerfile.cachyos          # l'image — historique des architectures en tête
Dockerfile.prebuilt         # composants précompilés (make prebuilt → release GitHub)
Makefile                    # build/push/run/prebuilt (PROFILE, REGISTRY/IMAGE/TAG/GITHUB_TOKEN/WSQUASHFS_REF/PREBUILT_TAG)
prebuilt/check.sh           # make prebuilt-check ; prebuilt/out/ = sortie de make prebuilt (ignorée)
docker-compose.yml          # compose générique, complété par l'override du profil
docs/                       # configuration (profils, variables), déploiement Unraid
profiles/
  example/                  # modèle de profil commenté
  unraid-gunnm/             # déploiement réel : override, env, compat wsquashfs
root-cachyos/
  etc/s6-overlay/           # services s6 (labwc ×2, sunshine, wayvnc, evdev-bridge…)
  etc/udev/rules.d/         # règles manettes (hidraw fallback)
  scripts/                  # session Wayland, init_*, lanceurs, steambox-env.sh (variables)
  build/                    # outils de build (gh-asset-url, install-appimage, prebuilt-fetch)
  usr/local/bin/            # install driver NVIDIA userspace (matché à l'hôte)
evdev-bridge/               # pont uinput→Wayland pour l'input Sunshine (C, vendored, précompilé)
Heroic Launcher/            # sauvegarde locale de bibliothèque Heroic (ignorée par git)
```

## Dépannage express

- **Moonlight figé en basse résolution** → vérifier que `apps.json` contient
  les `prep-cmd` (migré automatiquement depuis l'audit M2) et lire
  `/tmp/set-resolution.log` dans le conteneur.
- **Manette PlayStation détectée mais boutons morts** → vérifier la règle
  cgroup `c 242:* rmw` (voir docker-compose.yml) et l'existence de
  `/dev/hidrawN` dans le conteneur.
- **Clavier Moonlight muet après un changement de fenêtre** → réglé par le
  focus-follows-mouse de labwc (rc.xml généré par labwc-session.sh) ;
  contournement : re-changer de fenêtre.
- **Panneau, fond d'écran ou icône réseau disparus** → chaque composant du
  bureau visible est un service s6 relancé automatiquement :
  `svc-xfce4-panel`, `svc-xfdesktop`, `svc-xfsettingsd`, `svc-nm-applet`.
- **Appli de `~/.config/autostart` jamais lancée** → labwc ne lit pas
  l'autostart XDG : c'est `dex -a -e XFCE`, lancé par `labwc -s` dans
  labwc-session.sh, qui s'en charge au démarrage du bureau (wayland-0
  seulement, pas dans la session headless de Sunshine). Voir son lancement
  dans les logs de `svc-labwc`.
- **Émulateur Qt (Lichii, Eden…) qui se ferme aussitôt dans Steam gamepadui** →
  journal de l'émulateur : « Failed to initialize Wayland surface ». La session
  gamescope (`steam-gamescope-launch.sh`) force `QT_QPA_PLATFORM=xcb` ; sur une
  image plus ancienne, mettre `QT_QPA_PLATFORM=xcb %command%` dans les options
  de lancement du raccourci.
- **Un jeu ne se lance pas depuis EmulationStation** → ES affiche la cause
  (émulateur ou BIOS absent, format non pris en charge…) dans une boîte
  d'erreur : convention Batocera, code de sortie 250 et message dans
  `/tmp/launch_error.log` (`root-cachyos/scripts/launch-error.sh`), doublé
  d'une notification sur le bureau. Détails :
  `$XDG_RUNTIME_DIR/game-launch.log` (commandes) et `game-launch-last.log`
  (sortie du dernier jeu).
- **Alt + F4 ferme le jeu** (clavier, Alt gauche ou droit) : même service
  `svc-pad-hotkeys`, qui lit les claviers dans `/dev/input` pendant une
  partie. Il faut que `arcade` puisse lire ces périphériques (groupe
  `steambox-input`).
- **PS / Xbox + Start ne ferme pas le jeu** → service `svc-pad-hotkeys`
  (journal dans `docker logs`, préfixe `[pad-hotkeys]`) ; le jeu en cours
  est décrit dans `$XDG_RUNTIME_DIR/steambox-game` par `game-launch.sh`.
  Relance manuelle :
  `s6-svc -r /run/service/svc-xfce4-panel`.
- **Chrome refuse de démarrer** (« profile in use by another computer ») →
  verrou `SingletonLock` d'un ancien hostname, nettoyé à chaque démarrage de
  session depuis le 31/08.
- **Bureau et flux Moonlight inversés** → course wayland-0/1, impossible
  depuis l'audit C1 ; si observé quand même, `docker restart` et ouvrir un
  ticket avec les logs `svc-labwc-headless`.
