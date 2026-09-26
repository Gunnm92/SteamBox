# SteamBox Live — console de salon démarrée sur clé USB, système en RAM

> Plan pour un développement ultérieur, dans un **dépôt dédié**. Rédigé le 26/09/2026.

## Contexte
L'utilisateur apprécie le système SteamBox (conteneur Unraid : CachyOS, labwc, XFCE WhiteSur,
Sunshine/Moonlight, noVNC) et en veut une version **native pour son home server physique branché à la TV**.

- **Matériel** : AMD Ryzen AI Max+ 395 (Strix Halo), iGPU Radeon 8060S (RDNA 3.5), **128 Go de mémoire
  unifiée** partagée entre le CPU et le GPU. Le disque est dédié aux données et formatable.
- **Sur la TV** : Steam (jeux locaux) et **Moonlight client** vers SteamBox. La session se lance
  **quand la DualSense s'allume** et se ferme quand elle s'éteint. Le PC reste allumé.
- **Administration à distance** par noVNC, comme SteamBox.
- **Démarrage sur clé USB, système entier en RAM, conçu pour la vitesse** (pas forcément en squashfs).
  But : **redémarrer sur un système propre, et le personnaliser ou le reconstruire sans jamais toucher aux
  données**.
- **Tout ce qui est à l'utilisateur est sur le disque** : applis Flatpak et AppImage, configuration,
  bibliothèque Steam, appairages Bluetooth, réseau.
- **Construction de l'ISO** : à décider plus tard, sur l'Unraid ou par GitHub Actions.

Ce qu'offrent déjà les dépôts CachyOS (vérifié le 26/09) :
- `archiso` 90 ;
- le profil ISO officiel `CachyOS/CachyOS-Live-ISO`, maintenu (dossier `archiso/`) ;
- `gamescope` 3.16 et `gamescope-session-git` ;
- `steam` (multilib), `moonlight-qt` 6.1, `flatpak`, `bluez`.

Le méta-paquet `cachyos-handheld` est écarté : il tire Plasma et le matériel du Steam Deck.

## Architecture

```
Clé USB (Ventoy + ISO) ──boot──► image système (EROFS) copiée en RAM + overlay tmpfs ─► clé retirable
                                   │  système jetable : chaque redémarrage repart de l'image
Disque (btrfs, étiquette SBDATA) ──► /home (config, Steam, ~/Applications AppImage),
                                     /var/lib/flatpak, /var/lib/bluetooth, réseau, SSH, machine-id
DualSense allumée (BT) ─udev─► steambox-tv.service ─► gamescope-session + Steam Big Picture
                                   │                    └─ Moonlight (natif) comme appli Steam
DualSense éteinte > 2 min ─────────┘ session arrêtée, écran éteint, PC allumé
Admin : labwc headless + XFCE WhiteSur ─► wayvnc (127.0.0.1) ─► websockify/noVNC :6080  + SSH
```

### Système en RAM, conçu pour la vitesse
- **Format EROFS** plutôt que squashfs : archiso le propose (`airootfs_image_type="erofs"`). EROFS est
  fait pour des lectures rapides en accès aléatoire, avec peu de CPU. Compression **lz4** (légère) ou
  aucune compression : avec 128 Go de mémoire, garder quelques Go non compressés en RAM ne coûte rien et
  supprime toute décompression.
- **`copytoram`** : l'image entière est copiée en RAM au démarrage. Plus aucune lecture sur la clé, qui
  peut être retirée. Au-dessus, archiso monte un **overlay en tmpfs** : ce qui change pendant la session
  (paquets installés à la volée, fichiers système) disparaît au redémarrage. C'est ce qui rend le
  système « immuable ».
- **Mémoire unifiée** : ce qui est en RAM est pris sur les 128 Go partagés avec le GPU. Il faut donc
  mesurer l'empreinte (système + overlay) et réserver la mémoire du GPU en conséquence :
  - taille du GTT, par exemple `amdgpu.gttsize` / `ttm.pages_limit` sur la ligne de commande du noyau ;
  - réglage de la mémoire vidéo dans le BIOS (UMA).
  Cible : image < 6 Go en RAM.
- Pour personnaliser le système, on reconstruit l'image, puis on redémarre dessus. Les données ne sont
  jamais touchées.

## Organisation : dépôt dédié
Nouveau dépôt **`steambox-live`**, comme l'a demandé l'utilisateur.
- `archiso/` : profil dérivé de `CachyOS-Live-ISO/archiso`, allégé (pas d'installateur Calamares). Il
  contient `packages.x86_64`, `profiledef.sh` (EROFS, `copytoram`), `pacman.conf`, les fichiers de
  démarrage GRUB/EFI et `airootfs/` (unités systemd, règles udev, scripts).
- `build.sh` : prépare les éléments partagés, puis lance `mkarchiso`. L'endroit où il tourne sera choisi
  plus tard.
- **Code partagé avec SteamBox**, repris plutôt que réécrit. Dépôt SteamBox en **sous-module git** figé
  sur un commit, ou fichiers vendorés s'ils divergent :
  - `root-cachyos/scripts/labwc-session.sh` et `xfce-defaults.sh` : bureau d'administration, clavier,
    thème labwc assorti au thème GTK ;
  - la logique `desktop_exec` de `desktop-env.sh`, transposée en unités systemd `--user` au lieu de s6 ;
  - l'installation de WhiteSur (thème, icônes, curseur, libadwaita) du Dockerfile SteamBox, à sortir dans
    un script de build commun (`install-whitesur`) qui reprend les 4 pièges documentés de l'installateur ;
  - la vérification des icônes des `.desktop` et le `fc-cache -s` final : glycin tué par seccomp si le
    cache de polices est incomplet ;
  - les réglages wayvnc et websockify/noVNC de SteamBox, dont la page d'accueil (`resize=scale`,
    `reconnect`).

## Étapes

### 1. Système live minimal en RAM, avec persistance
- Paquets :
  - `linux-cachyos` (noyau récent, nécessaire pour Strix Halo), `amd-ucode`, `linux-firmware` ;
  - `mesa`, `vulkan-radeon` et leurs versions `lib32` ;
  - `networkmanager`, `bluez`, `openssh`, `flatpak`.
  Plus le démarrage EROFS et `copytoram`.
- Utilisateur `arcade` (uid 1000), `sudo`, sans mot de passe root. Clé SSH déposée au build.
- **Disque de données** : un outil `sb-setup-disk /dev/nvmeXnY`, lancé une seule fois à la main, formate
  le disque en btrfs avec l'étiquette `SBDATA` et les sous-volumes `@home`, `@flatpak`, `@bluetooth`,
  `@nm`, `@ssh`, `@state`.
- Au démarrage, des unités de montage systemd (par étiquette) montent `/home` et relient
  `/var/lib/flatpak`, `/var/lib/bluetooth`, `/etc/NetworkManager/system-connections`, les clés d'hôte SSH
  et le `machine-id`.
- Sans disque `SBDATA`, le système démarre en mode éphémère avec un message clair, au lieu d'échouer.

### 2. Session TV déclenchée par la DualSense
- `steambox-tv.service` (système, `User=arcade`, `PAMName=login`, `TTYPath=/dev/tty1`) ouvre une vraie
  session logind sur le seat, nécessaire à gamescope, puis lance `gamescope-session` avec
  `steam -gamepadui`.
- Une règle udev démarre le service quand une manette apparaît : DualSense `054c:0ce6` et `0df2`, avec
  une liste extensible. Sur machine physique, `hid-playstation` est présent, donc evdev fonctionne.
- **Arrêt** : quand la manette disparaît, un minuteur de 2 minutes (réglable) arrête la session si elle
  n'est pas revenue entre-temps. C'est ce qui protège contre une coupure passagère ou une mise en veille
  de la manette. La TV perd alors le signal et se met d'elle-même en veille.
- Moonlight : `moonlight-qt` natif (dans l'image), ajouté comme appli non-Steam dans Steam. C'est à faire
  une fois, le réglage est gardé dans `/home`. SteamBox est découvert automatiquement sur le réseau local.
- Appairage de la DualSense : une fois, via le bureau d'administration ou `bluetoothctl`. Il reste
  enregistré sur le disque.

### 3. Administration à distance (noVNC)
- Bureau d'administration **headless** : labwc (`WLR_BACKENDS=headless`), XFCE avec WhiteSur, wayvnc
  sur `127.0.0.1:5900`, websockify/noVNC sur `:6080`. Ce sont des unités systemd `--user`, relancées
  automatiquement, sur le modèle des services s6 de SteamBox.
- Il reste indépendant de la session TV, donc toujours disponible.
- SSH avec clé uniquement. noVNC reste réservé au réseau local. Mot de passe wayvnc en option.

### 4. Applications et mises à jour
- **Flatpak** (Flathub) dans `/var/lib/flatpak`, sur le disque. **AppImage** dans `~/Applications`, sur
  le disque. La configuration et la bibliothèque Steam sont dans `/home`, sur le disque.
- Mise à jour du système : reconstruire l'ISO et la copier sur une clé **Ventoy**, à côté de la
  précédente. On garde ainsi un retour arrière d'un choix au démarrage.
- Optionnel : un bureau TV (labwc + XFCE WhiteSur) accessible depuis Steam par « Passer au bureau »,
  sur le modèle de `os-session-select.sh` de SteamBox.

## Points encore ouverts
- Où construire l'ISO (Unraid ou GitHub Actions) : à trancher avant l'étape 1.
- Répartition de la mémoire unifiée entre le système en RAM et le GPU (GTT, UMA du BIOS) : à mesurer
  sur la machine.
- Allumer la TV automatiquement (HDMI-CEC) : pas de CEC sur les GPU AMD. Il faudrait un adaptateur
  Pulse-Eight USB. Hors périmètre sauf demande.
- Réseau : Ethernet ou Wi-Fi ? Et quel adaptateur Bluetooth ? À vérifier sur la machine, notamment la
  stabilité de la reconnexion de la DualSense.

## Vérification
1. **QEMU** (UEFI, ISO et disque virtuel), avec `testiso.sh` du profil CachyOS :
   - démarrage en RAM : la clé se retire après le boot ;
   - mesure de l'empreinte mémoire et du temps de démarrage, EROFS lz4 contre non compressé ;
   - `sb-setup-disk` fonctionne sur le disque virtuel ;
   - un fichier dans `/home`, une appli Flatpak et une connexion réseau survivent à un redémarrage ;
   - un paquet installé à la volée dans le système **disparaît** au redémarrage.
2. **Déclenchement par manette, sans matériel**, en simulant une DualSense via uhid comme pour SteamBox :
   - le branchement démarre `steambox-tv.service` ;
   - le débranchement l'arrête après le délai, et une reconnexion pendant le délai l'annule.
3. **noVNC** : `http://<ip>:6080` affiche le bureau WhiteSur d'administration, et SSH par clé fonctionne.
4. **Sur la machine Strix Halo** (clé Ventoy) :
   - démarrage en RAM, disque `SBDATA` monté ;
   - DualSense allumée : Steam Big Picture à l'écran ;
   - Moonlight vers SteamBox : un jeu en streaming, et un jeu en local ;
   - DualSense éteinte : session fermée après 2 minutes ;
   - rallumage : la session revient.
