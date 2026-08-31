# Déploiement Unraid — référence du template SteamBox

**Source de vérité du déploiement réel** (audit C3, 31/08/2026). Le conteneur
de production est créé par un template Unraid (onglet Docker), pas par
`docker-compose.cachyos.yml` — ce dernier est maintenu aligné sur ce document
pour le développement. **Toute modification du template doit être reportée
ici et dans le compose**, et inversement : la dérive est réelle (la règle
cgroup 226 a disparu du template sans signal lors d'un ajout manuel le 31/08).

Extrait de `docker inspect SteamBox` sur le conteneur en production le
31/08/2026.

## Image

```
registry.elfenn.eu/steambox:latest
```

Publiée par `make push` depuis ce dépôt (voir Makefile).

## Réglages de base

| Champ | Valeur |
|---|---|
| Nom du conteneur | `SteamBox` |
| Hostname | `SteamBox` (stable — un changement invalide des verrous type Chrome `SingletonLock`) |
| Network | `host` (requis : seatd/udev, découverte LAN Sunshine) |
| Console shell | bash |

## Variables d'environnement

| Variable | Valeur | Rôle |
|---|---|---|
| `PUID` | `99` | UID Unraid standard (`nobody`) |
| `PGID` | `100` | GID Unraid standard (`users`) |
| `TZ` | `Europe/Paris` | |
| `NVIDIA_VISIBLE_DEVICES` | `GPU-993ff90a-304b-da13-1287-c533c1073ab4` | UUID de la RTX 3090 dédiée |
| `NVIDIA_DRIVER_CAPABILITIES` | `all` | NVENC + graphique + compute |

## Volumes

| Hôte | Conteneur | Rôle |
|---|---|---|
| `/mnt/user/appdata/steambox/` | `/config` | Home persistant d'`arcade` (configs, Steam, Sunshine). **Jamais** `/mnt/user/appdata/arcadebox` (structure incompatible) |
| `/mnt/user/Game/Batocera/` | `/userdata` | ROMs, BIOS, saves — layout Batocera |
| `/mnt/user/Game` | `/config/games` | Bibliothèque de jeux complète — **ne jamais `chown -R`** (centaines de milliers de fichiers, voir init_system.sh) |
| `/mnt/user/Download/` | `/config/Downloads` | |
| `/dev/input/` | `/dev/input/` | Bind du **répertoire** entier : les périphériques uinput créés par Sunshine à chaque connexion apparaissent dynamiquement |

## Devices

| Device | Rôle |
|---|---|
| `/dev/fuse` | wsquashfs-launcher (squashfuse / fuse-overlayfs) |
| `/dev/uinput` | Clavier/souris virtuels Sunshine |
| `/dev/uhid` | Manettes virtuelles Sunshine (libvirtualhid — rumble, tactile/gyro) |

`/dev/dri` n'est **pas** listé : injecté par le runtime nvidia via
`NVIDIA_VISIBLE_DEVICES`.

## Extra Parameters

```
--runtime=nvidia --ipc=host --shm-size=2g
--cap-add=SYS_NICE --cap-add=SYS_ADMIN
--group-add=71
--device-cgroup-rule='c 13:* rmw'
--device-cgroup-rule='c 226:* rmw'
--device-cgroup-rule='c 242:* rmw'
--security-opt apparmor=unconfined --security-opt seccomp=unconfined
```

Justification des trois règles cgroup — **les trois sont requises** :

- `c 13:*` — `/dev/input/*` (clavier/souris/manettes, réels et virtuels).
- `c 226:*` — `/dev/dri/*`. Redondante avec le runtime nvidia mais gardée
  explicite : c'est elle qui a silencieusement disparu du template le 31/08.
- `c 242:*` — `/dev/hidraw*`. Sans elle, Steam Input ne reçoit **aucun
  bouton** des manettes PlayStation (DualShock/DualSense) alors que Sunshine
  les détecte — vécu le 31/08. Fonctionne de pair avec la règle udev
  `99-steambox-hidraw-fallback.rules` de l'image (mknod explicite du nœud).

## Points d'attention

- **Politique de redémarrage** : le conteneur inspecté est en `restart: no` —
  après un reboot de l'hôte ou un crash, il ne repart pas seul. Activer
  l'auto-start dans l'interface Unraid si ce n'est pas voulu.
- **Recréation vs redémarrage** : les règles cgroup et devices sont figées à
  la **création** du conteneur — un simple restart ne suffit pas après une
  modification des Extra Parameters, il faut appliquer/recréer.
- **Modèle de sécurité** : le conteneur n'est pas une frontière de sécurité
  (sudo NOPASSWD, devices en 666, cap SYS_ADMIN) — voir README, section
  « Modèle de sécurité ». Ne jamais exposer ses ports hors du LAN.
