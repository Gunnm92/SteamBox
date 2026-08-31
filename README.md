# SteamBox 🎮

Console de jeu conteneurisée pour Unraid : **CachyOS + session Wayland réelle
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
- **Émulateurs standalone** : Cemu, PCSX2, RPCS3, DuckStation, Xemu, Azahar,
  Xenia, melonDS, DOSBox Staging, GZDoom+Freedoom, ShadPS4, Eden (Switch),
  Dolphin, ScummVM, Lindbergh Loader.
- **RetroArch** + cores (FBNeo, MAME, snes9x, mGBA, melonDS, Flycast,
  Dolphin, PPSSPP, Beetle PSX/PCE, mupen64plus…).
- **Frontends** : Steam gamepadui (principal), Pegasus (lancé depuis Steam).
- **Bureau** : XFCE (panel, Thunar, terminal), thème Mc-OS-CTLina sombre,
  clavier fr-mac partout (local, VNC, Moonlight).
- **Divers** : Steam ROM Manager, Flips, Google Chrome, flatpak (+ Flathub).

## Déploiement

Le déploiement réel passe par un **template Unraid** — la référence complète
(volumes, devices, Extra Parameters, règles cgroup) est versionnée dans
**[docs/deploiement-unraid.md](docs/deploiement-unraid.md)**.
`docker-compose.cachyos.yml` en est le miroir pour le développement.

Build et publication de l'image :

```bash
make build                 # build local (--load)
make push                  # build + push vers registry.elfenn.eu/steambox:latest
make push GITHUB_TOKEN=…   # recommandé : évite le rate-limit API GitHub
                           # (~18 requêtes/build, limite anonyme 60/h/IP)
```

## Accès

| Service | Port | Authentification |
|---|---|---|
| noVNC (bureau navigateur) | `6080` | **aucune** — LAN de confiance uniquement |
| Sunshine Web UI | `47990` | compte Sunshine (appairage PIN Moonlight) |
| Flux Moonlight | `47984-48010` | appairage Sunshine |

## Modèle de sécurité

**Le conteneur n'est pas une frontière de sécurité.** C'est une console de
salon : l'utilisateur `arcade` a `sudo NOPASSWD` (montages wsquashfs élevés
en root), les devices d'entrée sont en `666`, le binaire Sunshine porte
`cap_sys_admin` (capture KMS), et noVNC n'a pas de mot de passe. Ce qui le
rend acceptable : réseau **LAN uniquement** — aucun de ces ports ne doit être
exposé sur Internet, directement ou via redirection. Pour un accès distant,
passer par un VPN ou un reverse proxy authentifié en amont.

## Structure du dépôt

```
Dockerfile.cachyos          # l'image — historique des architectures en tête
Makefile                    # build/push (variables REGISTRY/IMAGE/TAG/GITHUB_TOKEN)
docker-compose.cachyos.yml  # miroir dev du template Unraid
docs/deploiement-unraid.md  # source de vérité du déploiement
root-cachyos/
  etc/s6-overlay/           # services s6 (labwc ×2, sunshine, wayvnc, evdev-bridge…)
  etc/udev/rules.d/         # règles manettes (hidraw fallback)
  scripts/                  # session Wayland, init_*, résolution dynamique
  usr/local/bin/            # install driver NVIDIA userspace (matché à l'hôte)
evdev-bridge/               # pont uinput→Wayland pour l'input Sunshine (C, vendored)
Heroic Launcher/            # sauvegarde manuelle de bibliothèque Heroic
Status.md                   # résultats de compatibilité wsquashfs (jeux Windows)
```

## Dépannage express

- **Moonlight figé en basse résolution** → vérifier que `apps.json` contient
  les `prep-cmd` (migré automatiquement depuis l'audit M2) et lire
  `/tmp/set-resolution.log` dans le conteneur.
- **Manette PlayStation détectée mais boutons morts** → vérifier la règle
  cgroup `c 242:* rmw` (voir docs/deploiement-unraid.md) et l'existence de
  `/dev/hidrawN` dans le conteneur.
- **Clavier Moonlight muet après un changement de fenêtre** → réglé par le
  focus-follows-mouse de labwc (rc.xml généré par wayland-session.sh) ;
  contournement : re-changer de fenêtre.
- **Chrome refuse de démarrer** (« profile in use by another computer ») →
  verrou `SingletonLock` d'un ancien hostname, nettoyé à chaque démarrage de
  session depuis le 31/08.
- **Bureau et flux Moonlight inversés** → course wayland-0/1, impossible
  depuis l'audit C1 ; si observé quand même, `docker restart` et ouvrir un
  ticket avec les logs `svc-labwc-headless`.
