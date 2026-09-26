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

## Applications Sunshine

Définies dans `apps.json` (généré/migré par
[init_sunshine.sh](root-cachyos/scripts/init_sunshine.sh)) :

| App Moonlight | Contenu |
|---|---|
| **Desktop** | La session headless nue — lancer Steam depuis le menu |
| **Steam Big Picture** | `steam -gamepadui` directement sur wayland-1/Xwayland |
| **Mode SteamOS (Gamescope)** | gamepadui niché dans gamescope 2560×1440@120 (scaling FSR, changement de résolution in-game) |

Chaque app applique la résolution du client à la connexion et revient à
1920×1080 à la déconnexion.

## Contenu de l'image

- **Jeux** : Steam (+ gamescope), Heroic (Epic/GOG/Amazon), Wine-staging +
  DXVK + VKD3D-Proton, wsquashfs-launcher (paquets Batocera).
- **Émulateurs standalone** : Cemu (Wii U), PCSX2, RPCS3, DuckStation, Xemu,
  Xenia, melonDS, PPSSPP, Flycast, Vita3K (PS Vita), DOSBox Staging, ShadPS4,
  Eden (Switch), Dolphin, ScummVM, Lindbergh Loader, Supermodel (Model 3),
  TeknoParrotUI (lanceur natif, jeux toujours sous Wine).
- **RetroArch** + cores (FBNeo, MAME, snes9x, mGBA, melonDS, Flycast,
  Dolphin, PPSSPP, Beetle PSX/PCE, mupen64plus…).
- **Frontends** : Steam gamepadui (jeux PC), Batocera EmulationStation (jeux rétro/arcade, entrée Moonlight « EmulationStation »).
- **Bureau** : XFCE (panel, Thunar, terminal), thème WhiteSur sombre (style macOS, GTK 2/3/4 et libadwaita),
  même disposition clavier partout (local, VNC, Moonlight — `KEYBOARD_LAYOUT`).
- **Divers** : Steam ROM Manager, Flips, Google Chrome, flatpak (+ Flathub).

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
make push GITHUB_TOKEN=…   # recommandé : évite le rate-limit API GitHub
                           # (~18 requêtes/build, limite anonyme 60/h/IP)
make lint                  # shellcheck + hadolint (via Docker, rien à installer)
```

## Accès

| Service | Port | Authentification |
|---|---|---|
| noVNC (bureau navigateur) | `6080` | **aucune** — LAN de confiance uniquement |
| Sunshine Web UI | `47990` | compte Sunshine (appairage PIN Moonlight) |
| Flux Moonlight | `47984-48010` | appairage Sunshine |
| decky-loader | `1337` | écoute sur `127.0.0.1` uniquement (utilisé par Steam, pas joignable du LAN) |

## Modèle de sécurité

**Le conteneur n'est pas une frontière de sécurité.** C'est une console de
salon : l'utilisateur `arcade` a `sudo NOPASSWD` (montages wsquashfs élevés
en root), les devices d'entrée sont en `666`, le binaire Sunshine porte
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
Makefile                    # build/push/run (PROFILE, REGISTRY/IMAGE/TAG/GITHUB_TOKEN)
docker-compose.yml          # compose générique, complété par l'override du profil
docs/                       # configuration (profils, variables), déploiement Unraid
profiles/
  example/                  # modèle de profil commenté
  unraid-gunnm/             # déploiement réel : override, env, compat wsquashfs
root-cachyos/
  etc/s6-overlay/           # services s6 (labwc ×2, sunshine, wayvnc, evdev-bridge…)
  etc/udev/rules.d/         # règles manettes (hidraw fallback)
  scripts/                  # session Wayland, init_*, lanceurs, steambox-env.sh (variables)
  build/                    # outils de build (gh-asset-url, install-appimage)
  usr/local/bin/            # install driver NVIDIA userspace (matché à l'hôte)
evdev-bridge/               # pont uinput→Wayland pour l'input Sunshine (C, vendored)
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
  Relance manuelle :
  `s6-svc -r /run/service/svc-xfce4-panel`.
- **Chrome refuse de démarrer** (« profile in use by another computer ») →
  verrou `SingletonLock` d'un ancien hostname, nettoyé à chaque démarrage de
  session depuis le 31/08.
- **Bureau et flux Moonlight inversés** → course wayland-0/1, impossible
  depuis l'audit C1 ; si observé quand même, `docker restart` et ouvrir un
  ticket avec les logs `svc-labwc-headless`.
