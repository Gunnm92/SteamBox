# SteamBox 🎮

Console de jeu conteneurisée (Unraid ou tout hôte Docker Linux) : **CachyOS + KDE Plasma/KWin
(Wayland) + Steam**, streamée par **Sunshine/Moonlight** avec résolution
dynamique, et administrable au navigateur via **Selkies**.

Successeur d'ArcadeBox (X11) puis Waybox — l'historique complet des
architectures essayées et des raisons de chaque pivot vit en tête de
[Dockerfile.cachyos](Dockerfile.cachyos), et chaque contournement du dépôt
est commenté avec sa date et sa validation (« confirmé en direct »).

---

## Architecture

Deux bureaux tournent côte à côte, pour séparer le bureau d'administration
du flux de jeu :

```
                    ┌────────────────────────── conteneur SteamBox ─────────────────────────┐
                    │                                                                       │
 Navigateur ──────► │ Selkies :6080 (HTTPS) ─► compositeur Selkies (wayland-1)              │
 (admin LAN)        │                            └─ KWin imbriqué (wayland-N) ─► Plasma     │
                    │                                                                       │
 Moonlight ───────► │ Sunshine :47984-48010 ──► KMS ─► KWin STREAM (stream/wayland-stream) │
 (jeu)              │      │                               └─ Steam gamepadui, jeux, Proton │
                    │      └─ clavier/souris virtuels ─► libinput de KWin                   │
                    │      └─ uinput/uhid : manettes virtuelles ─► SDL/hidraw (Steam Input) │
                    │                                                                       │
                    │ s6-overlay supervise le tout (voir root-cachyos/etc/s6-overlay/)      │
                    └───────────────────────────────────────────────────────────────────────┘
```

- **Bureau d'administration** (`svc-selkies` + `svc-plasma`) : Selkies sert le
  bureau sur `https://<hôte>:6080` (certificat auto-signé à accepter une fois)
  et fait tourner son propre compositeur (`wayland-1`, encodage NVENC) ;
  **Plasma** s'y imbrique (`startplasma-wayland`, son KWin sur le premier `wayland-N` libre,
  Xwayland à la demande). Le bureau prend la taille de la fenêtre du
  navigateur, et le pointeur est dessiné par le navigateur (un seul pointeur,
  sans latence). L'environnement de la session (`DISPLAY`, `WAYLAND_DISPLAY`,
  bus, `XAUTHORITY`) est publié dans `$XDG_RUNTIME_DIR/steambox-desktop-session.env`.
  Sert à l'administration (fichiers, réglages, lancement manuel des apps).
- **Session streaming** (`svc-kwin-stream`, socket `$XDG_RUNTIME_DIR/stream/wayland-stream`, `DISPLAY` noté dans `$XDG_RUNTIME_DIR/steambox-stream-display`, lu par Sunshine et `stream-exec.sh`) :
  **KWin** (`kwin_wayland --drm`) sur un **dongle HDMI factice** branché sur
  le GPU (détecté, ou `STREAM_OUTPUT`). **Le dongle est obligatoire** : sans
  sortie branchée, ni KWin de streaming ni Sunshine (KWin en `--virtual` ne
  lit aucune entrée). KWin pilote la sortie en DRM et Sunshine la capture en **KMS**
  (seule capture qui transmet le HDR). Sa résolution s'adapte **au client Moonlight
  connecté** (`prep-cmd` → [set-resolution.sh](root-cachyos/scripts/set-resolution.sh),
  `kscreen-doctor`, parmi les modes du dongle : la plus grande définition qui
  tient dans celle du client, le pilote NVIDIA refusant les modes sur mesure).
  Le socket a un nom non numéroté pour que Selkies ne le confonde jamais avec
  le KWin de Plasma.
- **Session Steam HDR** (« Mode SteamOS (Gamescope) ») : le
  `prep-cmd` ([steam-gamescope-session.sh](root-cachyos/scripts/steam-gamescope-session.sh))
  arrête le KWin de streaming, lance gamescope, qui pilote seul le dongle en
  DRM, HDR actif, et attend qu'il y affiche une image
  ([drm-output-fb.py](root-cachyos/scripts/drm-output-fb.py)) avant que
  Sunshine ne commence la capture ; à la fermeture, KWin reprend la sortie. Sunshine capture en KMS
  dans les deux cas. Dongle dont l'EDID n'annonce pas le BT.2020 : profil
  Lua dans `~/.config/gamescope/scripts/` (`supported = true`,
  `eotf = gamescope.eotf.pq`, colorimétrie BT.2020, `matches` sur
  marque/modèle de l'EDID).
- **Xwayland** : les deux KWin en ont un. `/tmp/.X11-unix` est recréé en
  `1777` au démarrage (sans le sticky bit, KWin refuse ses sockets X), et le
  KWin de streaming passe par [kwin-launch.py](root-cachyos/scripts/kwin-launch.py),
  qui prépare les sockets X comme `kwin_wayland_wrapper` tout en gardant un
  nom de socket Wayland fixe.
- **Entrées Moonlight** : clavier/souris lus par la libinput du KWin de
  streaming ; les manettes
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
| **Desktop** | Le bureau Plasma (`plasmashell`) sur le KWin de streaming — lancer Steam depuis le menu |
| **Steam Big Picture** | `steam -gamepadui` directement sur le KWin de streaming/Xwayland (`steam-bigpicture-launch.sh`, jeux Wine en X11) |
| **Mode SteamOS (Gamescope)** | gamepadui niché dans gamescope à la résolution du client (scaling FSR, changement de résolution in-game), avec son propre `XDG_RUNTIME_DIR` sans socket Wayland du bureau |

Chaque app applique la résolution du client à la connexion et revient à
1920×1080 à la déconnexion. Jaquettes Moonlight dans le style de Wolf
(Games on Whales, MIT) : `/usr/share/steambox/sunshine/`.

## Session streaming

Le compositeur de la session streamée est KWin en DRM sur le dongle HDMI
factice (détecté au démarrage de `svc-kwin-stream`, marqueur
`steambox-stream-compositor`) :

| | |
|---|---|
| Compositeur | `kwin_wayland --drm` par `kwin-launch.py`, socket `$XDG_RUNTIME_DIR/stream/wayland-stream` (sous-dossier : invisible pour Selkies) |
| Capture Sunshine | KMS (transmet le HDR) |
| D-Bus | bus dédié `bus-stream`, noté dans `steambox-stream-session.env` |
| Portails | `xdg-desktop-portal-kde` (RemoteDesktop pré-autorisé, ScreenCast) |
| Réglages d'écran | « Réglages de l'écran (KDE) » (`systemsettings kcm_kscreen`), `kscreen-doctor` pour la résolution |

Sans dongle, `svc-kwin-stream` et `svc-sunshine` restent en attente (message
« dongle HDMI requis » dans `docker logs`) ; le bureau navigateur fonctionne.

Sunshine et Steam Link utilisent le bus de KWin ; `set-resolution.sh`
règle la résolution du dongle avec `kscreen-doctor`. Le HDR du dongle passe
par `KWIN_FORCE_ASSUME_HDR_SUPPORT=1` : son EDID (« LLV F0501-4K ») annonce le
PQ sans le BT.2020 qu'exige KWin. Les jeux Proton ne proposent le HDR que
si `PROTON_ENABLE_WAYLAND=1` et `PROTON_ENABLE_HDR=1` sont posés (en X11, pas
de HDR).

### Steam Remote Play / Steam Link

Au premier lancement de Steam dans la session streamée, une seule fois :

1. Se connecter en Moonlight sur l'application **Bureau**.
2. Quand Steam demande le partage d'écran, choisir l'écran HDMI (le dongle)
   et autoriser la restauration de la session de partage.

Précisions (24/11, KWin) :

- Steam doit être lancé par l'entrée **Steam (Steam Link)** (`steam-link-launch.sh`,
  le seul lanceur sur le bus de KWin) ou par une application Sunshine ; lancé
  autrement, il ne trouve pas le portail KDE.
- La fenêtre de partage d'écran apparaît sur l'écran du dongle : elle se voit
  via Moonlight, application **Bureau**.
- Cocher la restauration de la session, sinon la question revient à chaque lancement.
- Le jeton de restauration est gardé dans `~/.local/share/flatpak/db/screencast`
  (sous `/config`, donc persistant). Pour le réinitialiser, supprimer ce fichier.

## Contenu de l'image

- **Jeux** : Steam (+ gamescope), Heroic (Epic/GOG/Amazon, AppImage via AppManager), Wine-tkg +
  DXVK + VKD3D-Proton, wsquashfs-launcher (paquets Batocera) avec wine-tkg
  (arcade) et umu (jeux PC ; DualSense et vibration). Les Proton ne sont pas
  dans l'image : `wsquashfs-launcher --setup proton-cachyos` (Proton par
  défaut, UMU-Proton en repli avec `--setup`) et `--setup ge-proton` les
  installent dans `/config/.local/share/Steam/compatibilitytools.d`, vus
  aussi par Steam.
- **Génération d'images** : [MAKO Renderer](https://github.com/eugeniosegala/MAKO),
  couche Vulkan (jeux Vulkan, DXVK et VKD3D-Proton, émulateurs en rendu
  Vulkan ; pas l'OpenGL), 64 et 32 bits. Modèle MAKO FG libre, sans DLL
  (modèles LSFG de Lossless Scaling en option avec un `Lossless.dll` à soi,
  en FP32 : `allow_fp16 = false`), upscaling (MAKO Scaler, ou LS1 avec ce
  même DLL) et shaders. Vérifier un DLL : `mako-cli inspect-dll --dll <chemin>
  --ls1 ls1` ou `--lsfg --no-fp16`. Profils dans `mako-ui` (menu « MAKO Renderer
  Configuration »), fichier `~/.config/mako-render/conf.toml` ; MAKO n'agit
  que sur un programme lancé par `mako-launch` ET visé par un profil
  (« Processus associés » : `duckstation-qt`, `retroarch`, `pcsx2-qt`, exe
  Windows…), ou imposé par `MAKO_PROFILE`. Depuis EmulationStation : option
  « Génération d'images (MAKO) » par système (Réglages des jeux >
  Configuration avancée par système) ou par jeu (Options avancées du jeu),
  avec « Profil MAKO » pour imposer un profil.
- **Émulateurs standalone** : Cemu (Wii U), PCSX2, RPCS3, DuckStation, Xemu,
  Xenia, melonDS, PPSSPP, Flycast, Vita3K (PS Vita), DOSBox Staging, ShadPS4,
  Eden (Switch), Dolphin, ScummVM, Lindbergh Loader, Supermodel (Model 3).
  Les AppImage (Cemu, PCSX2, RPCS3, DuckStation, Xemu, Xenia, melonDS, PPSSPP,
  Flycast, Vita3K, ShadPS4, Eden, Lindbergh, Steam ROM Manager) ne sont pas dans
  l'image : elles s'installent avec AppManager dans `~/Applications` (persistant),
  et `/usr/local/bin/<nom>` les lance via `root-cachyos/scripts/appimage-launch.sh`
  (nom du fichier reconnu sans tenir compte de la casse : `shadPS4`, `Xenia Canary`…).
  Si l'une manque, EmulationStation affiche laquelle installer.
- **RetroArch** (paquet du système, à jour à chaque rebuild) + cores (FBNeo,
  MAME, snes9x, mGBA, melonDS, Flycast, Dolphin, PPSSPP, Beetle PSX/PCE,
  mupen64plus…).
- **Frontends** : Steam gamepadui (jeux PC), Batocera EmulationStation (jeux rétro/arcade, entrée Moonlight « EmulationStation »).
- **Bureau** : KDE Plasma (Dolphin avec miniatures et accès aux partages réseau `smb://`, Konsole, Kate, volume par plasma-pa, pavucontrol pour le volume par canal — dosage du surround des sorties Sunshine —, notifications de Plasma), thème GTK, icônes et curseur WhiteSur sombres pour les applis GTK (GTK 2/3/4 et libadwaita),
  même disposition clavier partout (navigateur, Moonlight — `KEYBOARD_LAYOUT`/`KEYBOARD_VARIANT`, écrits dans `kxkbrc`).
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

Sunshine (DualSense USB), Batocera EmulationStation et freeimage ne sont
**plus compilés à chaque
`make push`**. [Dockerfile.prebuilt](Dockerfile.prebuilt) les construit à la
demande, et ils sont publiés en release GitHub du dépôt (`prebuilt-AAAAMMJJ-HHMM`).
L'image télécharge la dernière release
([prebuilt-fetch](root-cachyos/build/prebuilt-fetch)).

```bash
make prebuilt-check        # compare la dernière release à l'amont (dernier tag
                           # Sunshine, HEAD d'ES, AUR freeimage)
make prebuilt              # compile tout dans prebuilt/out/ (aucun registre)
make prebuilt-publish      # publie prebuilt/out/ en release GitHub (gh)
make push                  # l'image prend la nouvelle release
make push PREBUILT_TAG=prebuilt-…   # revenir à une release précédente
```

À relancer quand `prebuilt-check` signale une nouvelle version, ou si un build de l'image échoue sur
« bibliothèque manquante … relancer make prebuilt ». CachyOS est une distribution rolling : une
bibliothèque peut changer de soname. Surcharges possibles : `ES_REF`,
`SUNSHINE_TAG`. Les deux Dockerfile partent de
`cachyos/cachyos-v3:latest`, revérifiée à chaque build (`--pull`).

`wsquashfs-launcher` n'est pas dans l'image : il vit dans `/config/.local/bin`
(le home persistant), installé par l'installeur de son dépôt, et son updater
le met à jour, pas un redémarrage du conteneur.
Les `.wsquashfs` sont reconnus par leur extension sur le bureau (type
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
| Selkies (bureau navigateur, HTTPS auto-signé) | `6080` | aucune par défaut ; `DESKTOP_PASSWORD` active l'authentification basique (identifiant `arcade`) |
| Sunshine Web UI | `47990` | compte Sunshine (appairage PIN Moonlight) |
| Flux Moonlight | `47984-48010` | appairage Sunshine |
| decky-loader | `1337` | écoute sur `127.0.0.1` uniquement (utilisé par Steam, pas joignable du LAN) |

## Modèle de sécurité

**Le conteneur n'est pas une frontière de sécurité.** C'est une console de
salon : les devices d'entrée sont en `666`, le binaire Sunshine porte
`cap_sys_admin` (capture KMS), et le bureau navigateur n'a pas de mot de
passe sauf `DESKTOP_PASSWORD`. `/dev/input`
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
Makefile                    # build/push/run/prebuilt (PROFILE, REGISTRY/IMAGE/TAG/GITHUB_TOKEN/PREBUILT_TAG)
prebuilt/check.sh           # make prebuilt-check ; prebuilt/out/ = sortie de make prebuilt (ignorée)
docker-compose.yml          # compose générique, complété par l'override du profil
docs/                       # configuration (profils, variables), déploiement Unraid
profiles/
  example/                  # modèle de profil commenté
  unraid-gunnm/             # déploiement réel : override, env, compat wsquashfs
root-cachyos/
  etc/s6-overlay/           # services s6 (selkies, plasma, kwin-stream, sunshine…)
  etc/udev/rules.d/         # règles manettes (hidraw fallback)
  scripts/                  # sessions Plasma/KWin, init_*, lanceurs, steambox-env.sh (variables)
  build/                    # outils de build (gh-asset-url, install-appimage, prebuilt-fetch)
  usr/local/bin/            # install driver NVIDIA userspace (matché à l'hôte)
Heroic Launcher/            # sauvegarde locale de bibliothèque Heroic (ignorée par git)
```

## Dépannage express

- **Moonlight figé en basse résolution** → vérifier que `apps.json` contient
  les `prep-cmd` (migré automatiquement depuis l'audit M2) et lire
  `/tmp/set-resolution.log` dans le conteneur.
- **Manette PlayStation détectée mais boutons morts** → vérifier la règle
  cgroup `c 242:* rmw` (voir docker-compose.yml) et l'existence de
  `/dev/hidrawN` dans le conteneur.
- **Clavier faux (pas AZERTY), presse-papiers muet ou touches non ASCII
  perdues dans le navigateur** → Selkies n'envoie pas les entrées au KWin de
  Plasma. Son journal (`docker logs`) doit dire « Wayland app compositor
  'wayland-N' (auto-detected) » avec le socket de Plasma (celui de
  `steambox-desktop-session.env`). Il ne doit y avoir à la racine de
  `/run/user/<uid>` que `wayland-1` (Selkies) et celui de Plasma : le
  streaming est rangé dans `stream/wayland-stream`, sinon Selkies l'adopte
  au démarrage (vu le 25/11).
- **Bureau navigateur vide ou figé** → `s6-svc -r /run/service/svc-plasma`
  (la session Plasma) ; `svc-selkies` relance aussi Plasma derrière lui.
- **Appli de `~/.config/autostart` jamais lancée** → Plasma lit l'autostart
  XDG lui-même ; une AppImage Qt sans greffon Wayland passe en X11
  (`QT_QPA_PLATFORM="wayland;xcb"` dans la session).
- **Moonlight : « dongle HDMI requis » dans les logs** → aucune sortie
  branchée sur le GPU du conteneur : Sunshine ne démarre pas sans dongle.
- **Émulateur Qt (Lichii, Eden…) qui se ferme aussitôt dans Steam gamepadui** →
  journal de l'émulateur : « Failed to initialize Wayland surface ». La session
  gamescope (`steam-gamescope-launch.sh`) force `QT_QPA_PLATFORM=xcb` ; sur une
  image plus ancienne, mettre `QT_QPA_PLATFORM=xcb %command%` dans les options
  de lancement du raccourci.
- **Jeu Wine (.wsquashfs) qui plante aussitôt dans Steam gamepadui** (Unreal :
  « CreateSwapChainResult failed », log Steam : « [Gamescope WSI] Failed to get
  Wayland objects », fenêtre d'erreur visible sur le bureau) → Wine s'était ouvert
  en Wayland sur le bureau au lieu de gamescope. La session
  gamescope a désormais son propre `XDG_RUNTIME_DIR`
  (`/run/user/<uid>/gamescope-session`, liens vers bus, PipeWire, Pulse…, sans
  `wayland-*`) : les jeux passent en X11 dans gamescope. Sur une image plus
  ancienne : `WINEDLLOVERRIDES=winewayland.drv=d %command%` dans les options de
  lancement.
- **Big Picture (sans gamescope) qui navigue à la manette pendant une partie**
  (sons de navigation en fond) → jeu Wine ouvert en Wayland natif : Steam ne
  voit pas sa fenêtre. L'entrée Sunshine passe par `steam-bigpicture-launch.sh`,
  qui impose le pilote x11 de Wine (contournement, au prix de l'affichage
  Wayland natif dans cette session). Inopérant si Steam tournait déjà sur le
  bureau avant l'ouverture de Big Picture.
- **Select ouvre aussi le menu du jeu (comme Start)** → Select cliquait aussi le
  pavé tactile de la DualSense virtuelle (option Sunshine
  `ds4_back_as_touchpad_click`, active par défaut). Désactivée dans
  `sunshine.conf` depuis le 22/11 (migration v14) ; vérifier qu'elle n'y a pas
  été remise à `enabled`.
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
  `s6-svc -r /run/service/svc-pad-hotkeys`.
- **Chrome refuse de démarrer** (« profile in use by another computer ») →
  verrou `SingletonLock` d'un ancien hostname, nettoyé à chaque démarrage de
  session depuis le 31/08.
- **Bureau et flux Moonlight inversés** → impossible depuis le 24/11 : le
  streaming a un socket fixe (`stream/wayland-stream`), le bureau ceux de
  Selkies et de Plasma.
