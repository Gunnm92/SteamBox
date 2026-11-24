# Deux KWin à la place des deux labwc — conception

> **24/11 : phase 2 remplacée** par `2026-11-24-selkies-plasma-design.md` (Selkies + Plasma, krfb et noVNC abandonnés, labwc et XFCE retirés).

Date : 24/11/2026 · Statut : à valider

## Pourquoi

Steam Remote Play / Steam Link donnent un écran noir : Steam capture par
PipeWire (portail ScreenCast), et sous labwc headless + NVIDIA le portail wlr
ne fournit aucune image exploitable (dmabuf non importé, cf.
`scripts/steam-link-launch.sh` et l'essai gamescope du 25/10). Sunshine, qui
copie labwc directement, est le seul à marcher.

Steam Headless v2 (`josh5/steam-headless:2`, analysé le 24/11) fait tourner
le même ensemble avec `kwin_wayland --virtual`, xdg-desktop-portal-kde
pré-autorisé, Steam en `-pipewire -pipewire-dmabuf` et Sunshine en
`capture = kwin`. Remote Play marchait d'ailleurs ici sous KDE X11 (25/08,
`2e9454c`).

Ce qui avait fait abandonner KWin fin août est levé ou contournable :

| Blocage d'août | Aujourd'hui |
|---|---|
| Plasma complet exige `systemd --user` | on lance `kwin_wayland` seul, sans plasmashell |
| souris Sunshine ignorée par libinput (udev) | udevd supervisé ; libinput lit déjà les entrées Sunshine en mode DRM (22/11) |
| wayvnc limité à wlroots | remplacé par krfb (portail RemoteDesktop) |

## Objectifs

- Moonlight **et** Steam Remote Play / Steam Link fonctionnels sur le bureau
  de streaming, image et entrées comprises.
- Deux bureaux distincts, chacun avec sa résolution (choix utilisateur, option
  B) :
  - **wayland-0** : bureau du navigateur (noVNC), `DESKTOP_RESOLUTION` ;
  - **wayland-1** : bureau Moonlight / Remote Play, résolution du client.
- Le mode DRM sur le dongle HDMI (HDR, session Steam gamescope) continue de
  marcher.

## Hors objectifs

- Plasma complet (plasmashell, ksmserver) : on garde xfce4-panel et
  xfdesktop, qui tournent sous KWin (layer-shell).
- Remplacer noVNC par du WebRTC comme SHUI.
- Toucher aux manettes (SDL hors udev, ds5-usbip) : chemin inchangé.

## Ce qui serait un échec même si « ça marche »

- Le navigateur et Moonlight qui se volent les entrées ou la résolution.
- Une fenêtre de choix du portail qui bloque un stream (personne pour cliquer).
- Une régression du HDR ou de la session gamescope en DRM.

## Contraintes

- s6-overlay, pas de systemd ; conteneur `network_mode: host`, RTX 3090
  (pilote 620).
- Pas de build de l'image par Claude : `make lint` seulement, l'utilisateur
  fait `make push`. Les essais se font à la main dans le conteneur `SteamBox`.
- Tester dans le contexte réel (scripts d'init en root, `HOME=/root`), vérifier
  qu'aucun jeu ne tourne avant un test et prévenir l'utilisateur.
- Répercuter partout : Dockerfile, scripts, README, `install.sh`, `--help`.

## Approches envisagées

- **A. Un seul KWin pour tout** (modèle Steam Headless) : un seul bureau,
  plus simple, mais le navigateur subit la résolution de Moonlight. Écartée :
  l'utilisateur veut deux bureaux distincts.
- **B. Deux KWin (retenue par l'utilisateur)** : même découpage qu'aujourd'hui,
  KWin à la place de labwc des deux côtés.
- **C. KWin seulement sur wayland-1** : plus petit, mais garde labwc/wayvnc pour
  le navigateur et ne règle pas le reste. Écartée.

## Conception

### Compositeurs

- `svc-labwc` → **svc-kwin** (wayland-0) : `kwin_wayland --virtual --xwayland
  --socket wayland-0 --width/--height` depuis `DESKTOP_RESOLUTION`, **sans
  libinput** (entrées uniquement par VNC).
- `svc-labwc-stream` → **svc-kwin-stream** (wayland-1) :
  - sans dongle : `kwin_wayland --virtual --libinput --socket wayland-1`, qui
    lit les souris/claviers uinput de Sunshine ;
  - avec dongle : `kwin_wayland --drm` sur la carte retenue par
    `stream_drm_card` (HDR natif de KWin).
- Variables reprises de Steam Headless : `KWIN_DRM_DEVICES` (rendu GPU),
  `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1`, `KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1`.
- L'ordre wayland-0 puis wayland-1 et les garde-fous actuels sont conservés.

### Portails

- Un bus D-Bus de session par compositeur (déjà le cas pour wayland-1 via
  `dbus-run-session`), chacun avec son xdg-desktop-portal-kde lié au bon
  `WAYLAND_DISPLAY`.
- Pré-autorisation au démarrage, comme Steam Headless :
  `flatpak permission-set kde-authorized screencast "" yes` et idem
  `remote-desktop`.
- `kde-portals.conf` à la place de `xfce-portals.conf` (wlr).

### Streaming

- Sunshine : `capture = kwin` en virtuel, `kms` conservé en DRM (HDR).
- Steam : wrapper `/usr/local/bin/steam` passe à `-pipewire -pipewire-dmabuf`.
- `evdev-bridge` retiré si libinput dans KWin suffit (phase 0).
- `set-resolution.sh` / `reset-resolution.sh` : `kscreen-doctor` à la place
  de `wlr-randr`.

### Bureau du navigateur

- `svc-wayvnc` → **svc-krfb** : krfb sans interface sur wayland-0, en
  écoute sur 127.0.0.1:5900, derrière le `svc-websockify` / noVNC existant.
- Disposition clavier (`KEYBOARD_LAYOUT`, `VNC_MAC_ISO_KEYS`) reportée sur KWin
  (`kxkbrc`).

### Paquets

Ajout de `kwin`, `xdg-desktop-portal-kde`, `krfb`, `libkscreen`
(`kscreen-doctor`) ; retrait de `labwc`, `wayvnc`, `xdg-desktop-portal-wlr`,
`wlr-randr` une fois tout validé. Le thème WhiteSur couvre déjà KWin
(décorations Aurorae) — à confirmer.

## Phases

**Phase 0 — essai jetable dans le conteneur (rien dans l'image).** Sur
wayland-1 puis wayland-0, à la main, Steam arrêté avec l'accord de
l'utilisateur :

1. KWin virtuel sur wayland-1, Sunshine en `capture kwin` : image Moonlight.
2. Souris/clavier Moonlight par `--libinput` (le point le plus risqué).
3. Steam `-pipewire -pipewire-dmabuf` + portail KDE pré-autorisé : image
   Steam Link sur un jeu 3D.
4. KWin virtuel sur wayland-0 + krfb + noVNC : image et entrées.
5. Dongle : KWin `--drm`, capture KMS, HDR.

Chaque point raté s'arrête là et revient à l'utilisateur avant tout repli.

**Phase 1 — intégration dans l'image** (après validation de la phase 0) :
services s6, scripts, Dockerfile, README, `install.sh`, `--help`, `make lint`.
L'utilisateur construit et pousse.

**Phase 2 — ménage** : retrait de labwc, wayvnc, evdev-bridge et des
commentaires devenus faux (historique en tête de `Dockerfile.cachyos` mis à
jour).

## Choix faits par Claude (à corriger si besoin)

- xfce4-panel/xfdesktop gardés sous KWin plutôt que plasmashell (Plasma exige
  systemd --user).
- krfb plutôt que krdp : il garde noVNC tel quel (krdp imposerait un client
  RDP web).
- `--libinput` sur le seul KWin de streaming, pour qu'aucun des deux bureaux
  ne capte les entrées de l'autre.

## Laissé au constructeur

- Nommage exact des services et ordre des dépendances s6.
- Où écrire la configuration KWin (`kwinrc`, `kxkbrc`) et les fichiers de
  portail.
- Détail de la session Steam gamescope en DRM (arrêt/relance du KWin de
  streaming à la place de labwc).

## Résultats de la phase 0 (essai du 24/11)

| Essai | Résultat |
|---|---|
| T1 KWin `--drm` sur le dongle + Sunshine `capture=kwin` | ✅ image Moonlight, NVENC H.264/HEVC |
| T1 résolution | ✅ `kscreen-doctor` (il faut l'**id** du mode, pas son nom) |
| T2 entrées Moonlight | ✅ libinput de KWin (session « noop », DRM uniquement) |
| T3 Steam Link | ✅ après UNE autorisation de partage (fenêtre KDE) ; capture « Desktop PipeWire NV12 + NVENC HEVC », `dmabuf: 0` (copie mémoire) |
| T4 KWin `--virtual` sur wayland-1 | ❌ non fait : KWin 6.8 en virtuel ne lit **aucune** entrée (plus d'option `--libinput`) → labwc headless gardé sans dongle |
| T5 bureau noVNC : KWin `--virtual` + krfb | ✅ image, souris, clavier via le portail (`kde-authorized`/`remote-desktop`) ; mot de passe aléatoire injecté dans `mandatory.json` de noVNC (6080 inchangé) ; ❌ **résolution dynamique** : krfb ignore SetDesktopSize ; essai `/resize` dans websockify + `steambox-resize.js` → le mode KWin change côté serveur mais l'ensemble ne suit pas encore côté navigateur (à reprendre) |
| T6 HDR | ✅ KWin HDR seulement avec `KWIN_FORCE_ASSUME_HDR_SUPPORT=1` (EDID du dongle sans BT.2020) ; Moonlight HDR en `capture=kms` ; `capture=kwin` reste 8 bits SDR |

Constats annexes :
- `kde-authorized` ne sert qu'au bureau à distance ; la capture d'écran (ScreenCast) exige un jeton de restauration obtenu une fois à la main.
- krfb écoute en dur sur `0.0.0.0` et exige un mot de passe ; accepté par l'utilisateur (même exposition que noVNC sur 6080).
- Jeux Proton : HDR seulement en Wayland natif (`PROTON_ENABLE_WAYLAND=1 PROTON_ENABLE_HDR=1`), non testé.

Phase 1 (bureau de streaming sous KWin avec dongle) : fusionnée le 24/11 (`918c3e7`).
Phase 2 restante : bureau noVNC sous KWin + krfb, avec résolution dynamique à finir.
