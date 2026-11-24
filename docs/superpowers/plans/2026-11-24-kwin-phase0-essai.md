# Phase 0 — essai jetable de KWin dans le conteneur

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** prouver, à la main dans le conteneur `SteamBox` et sans toucher à
l'image, que KWin rend Moonlight **et** Steam Link fonctionnels sur wayland-1,
et que le bureau du navigateur tient sur un second KWin.

**Architecture :** on arrête les services s6 concernés, on lance à la place
`kwin_wayland` avec un bus D-Bus de session fixe par compositeur, puis
Sunshine, Steam et krfb à la main sur ce bus. Chaque tâche finit par un
constat écrit ; un échec arrête tout et revient à l'utilisateur.

**Tech Stack :** KWin 6.8.3, xdg-desktop-portal-kde 6.8.3, krfb 26.08.3,
libkscreen 6.8.3 (dépôts CachyOS), sunshine-ds (capture `kwin` présente),
s6-overlay.

**Spec :** `docs/superpowers/specs/2026-11-24-kwin-deux-compositeurs-design.md`

## Global Constraints

- Conteneur `SteamBox`, Docker via `DOCKER_HOST=tcp://docker-socket-proxy:2375 DOCKER_TLS_VERIFY=`.
- Utilisateur `arcade` (uid 99), `XDG_RUNTIME_DIR=/run/user/99`.
- Rien dans l'image ni dans le dépôt, hors ce plan et la section résultats du spec.
- Avant chaque tâche qui arrête Steam ou un compositeur : vérifier qu'aucun jeu
  ne tourne (`pgrep -a -x steam`, `pgrep -a wine`) et prévenir l'utilisateur.
- `pkill`/`pgrep` par nom exact (`-x`) ou PID, jamais `-f` dans `bash -c`.
- Journaux de l'essai dans `/config/logs/kwin-essai-*.log`.
- Dongle branché : sortie `HDMI-A-1`, carte donnée par `stream_drm_card`
  (`/usr/local/bin/scripts/steambox-env.sh`).
- Tout échec : on note le symptôme et le journal, on s'arrête, on demande avant
  tout repli.

## Review Focus

1. **Steam déjà lancé** (cas actuel) : un second Steam se contente de rendre la
   main à l'ancien, qui resterait sur labwc → T3 arrête Steam explicitement et
   vérifie l'absence de processus avant relance.
2. **Fenêtre de choix du portail** au premier Steam Link : personne pour
   cliquer → T3 vérifie qu'aucune fenêtre de choix n'apparaît (écran Moonlight).
3. **Changement de résolution par Moonlight** (client ≠ 1920x1080) :
   `set-resolution.sh` n'est pas porté → T1 essaie `kscreen-doctor` à la main.
4. **Deux KWin qui se disputent les entrées** : seul celui de wayland-1 lit
   libinput → T5 vérifie que la souris Moonlight ne bouge pas le bureau
   noVNC, et inversement.
5. **Sunshine refusé par KWin** (contrôle d'autorisations) → T1 lance avec
   `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` et vérifie l'absence de
   « zkde_screencast_unstable_v1 not found » dans le journal.

---

### Task 0 : préparation

- [ ] **Étape 1 :** vérifier qu'aucun jeu ne tourne ; prévenir l'utilisateur que
  Steam, Sunshine et le labwc de streaming vont être arrêtés.
- [ ] **Étape 2 :** installer les paquets (root, conteneur) :
  `pacman -S --needed --noconfirm kwin xdg-desktop-portal-kde krfb libkscreen`
  Attendu : `pacman -Q kwin krfb` répond `6.8.3…` / `26.08.3…`.
- [ ] **Étape 3 :** noter l'état de départ : `s6-svstat` des services
  `svc-labwc`, `svc-labwc-stream`, `svc-sunshine`, `svc-evdev-bridge`,
  `svc-wayvnc`, et le contenu de `steambox-stream-output`.

### Task 1 : KWin en DRM sur wayland-1 + Moonlight (image)

- [ ] **Étape 1 :** `s6-svc -d` sur `svc-sunshine`, `svc-evdev-bridge`,
  `svc-labwc-stream` ; arrêter Steam (`steam -shutdown`, puis vérifier
  `pgrep -x steam` vide).
- [ ] **Étape 2 :** en arcade, bus fixe
  `dbus-daemon --session --address=unix:path=/run/user/99/bus-stream --fork`,
  puis avec `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/99/bus-stream`,
  `XDG_CURRENT_DESKTOP=KDE`, `KWIN_DRM_DEVICES=<carte>`,
  `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` :
  `kwin_wayland --drm --xwayland --socket wayland-1 --no-lockscreen`.
  Attendu : socket `/run/user/99/wayland-1`, journal sans erreur fatale,
  sortie `HDMI-A-1` active (`kscreen-doctor -o`).
- [ ] **Étape 3 :** Sunshine à la main, même environnement que
  `svc-sunshine/run`, avec `capture=kwin`. Attendu : journal sans
  « zkde_screencast_unstable_v1 not found ».
- [ ] **Étape 4 (utilisateur) :** connexion Moonlight sur « Bureau ». Attendu :
  image du KWin (fond noir et curseur suffisent), fluide.
- [ ] **Étape 5 :** `kscreen-doctor output.HDMI-A-1.mode.<mode du client>`.
  Attendu : Moonlight suit la nouvelle résolution.

### Task 2 : entrées Moonlight

- [ ] **Étape 1 (utilisateur) :** bouger la souris, cliquer, taper dans un
  `konsole` ou `xfce4-terminal` lancé sur wayland-1. Attendu : tout répond.
  Sinon : noter `libinput list-devices` et le journal KWin, s'arrêter.

### Task 3 : Steam Link (le but)

- [ ] **Étape 1 :** pré-autoriser sur le bus de wayland-1 :
  `flatpak permission-set kde-authorized screencast "" yes` et idem
  `remote-desktop`.
- [ ] **Étape 2 :** lancer Steam sur ce bus :
  `/usr/bin/steam -pipewire -pipewire-dmabuf -steamos3 -steampal -steamdeck -gamepadui`
  (WAYLAND_DISPLAY=wayland-1, DISPLAY de l'Xwayland de KWin).
- [ ] **Étape 3 (utilisateur) :** Steam Link (client 10.10.10.94) lance un jeu
  3D. Attendu : image du jeu, aucune fenêtre de choix de partage d'écran.
- [ ] **Étape 4 :** `streaming_log.txt` de Steam. Attendu : capture
  « PipeWire » (pas « Desktop X11 »), pas de `k_ECaptureFailedReason…`.

### Task 4 : KWin virtuel sur wayland-1 (cas sans dongle)

- [ ] **Étape 1 :** arrêter KWin, Sunshine et Steam de T1-T3, puis relancer
  KWin avec `--virtual --libinput --width 1920 --height 1080` au lieu de
  `--drm`.
- [ ] **Étape 2 :** refaire T1 étapes 3-4 et T2. Attendu : image et entrées.
- [ ] **Étape 3 :** refaire T3 étapes 2-4 (Steam Link). Attendu : image du jeu.

### Task 5 : bureau du navigateur sur KWin (wayland-0)

- [ ] **Étape 1 :** prévenir l'utilisateur (le bureau noVNC va disparaître) ;
  `s6-svc -d` sur `svc-xfce4-panel`, `svc-xfdesktop`, `svc-xfsettingsd`,
  `svc-wayvnc`, `svc-labwc`.
- [ ] **Étape 2 :** bus `bus-desktop`, puis
  `kwin_wayland --virtual --xwayland --socket wayland-0 --width/--height`
  depuis `DESKTOP_RESOLUTION`, sans `--libinput`. Lancer `xfce4-panel` et
  `xfdesktop` dessus.
- [ ] **Étape 3 :** pré-autoriser le portail de ce bus, lancer krfb sans
  fenêtre en écoute sur 127.0.0.1:5900 (mot de passe dans `krfbrc`).
  Attendu : `ss -ltn` montre 5900.
- [ ] **Étape 4 (utilisateur) :** noVNC dans le navigateur. Attendu : panneau
  XFCE visible, souris et clavier, résolution propre ; la souris Moonlight ne
  bouge pas ce bureau.

### Task 6 : HDR sur le dongle

- [ ] **Étape 1 :** relancer le KWin de wayland-1 en `--drm` (T1), activer le
  HDR : `kscreen-doctor output.HDMI-A-1.hdr.enable`.
- [ ] **Étape 2 :** Sunshine en `capture=kms`. **(utilisateur)** Moonlight en
  HDR sur un jeu HDR. Attendu : flux HDR annoncé par Moonlight.

### Task 7 : retour à l'état initial et bilan

- [ ] **Étape 1 :** tuer par PID tout ce qui a été lancé à la main, `s6-svc -u`
  sur les services arrêtés ; vérifier wayland-0/wayland-1 recréés par labwc,
  Sunshine et noVNC comme avant.
- [ ] **Étape 2 :** ajouter une section « Résultats phase 0 » au spec (tâche par
  tâche : réussi / échoué, symptôme, journal), puis commit :
  `git add docs/superpowers/specs/2026-11-24-kwin-deux-compositeurs-design.md`
  `git commit -m "docs(spec): résultats de l'essai KWin (phase 0)"`.
