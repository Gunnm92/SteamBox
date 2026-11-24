# Selkies + Plasma Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer le bureau navigateur labwc + XFCE + wayvnc/noVNC par Selkies → KWin → Plasma, et retirer labwc, XFCE et evdev-bridge de l'image.

**Architecture:** Selkies démarre son propre compositeur (`wayland-0`) et sert le bureau sur le port 6080. `startplasma-wayland` s'y imbrique (son KWin prend `wayland-1`, Xwayland à la demande). Le KWin du streaming passe à `wayland-stream`, lancé par un lanceur qui prépare les sockets X, et n'existe plus sans dongle.

**Tech Stack:** s6-overlay, bash, Python 3 (lanceur), Selkies 2.2.1 / pixelflux 2.2.3 (venv pip), KDE Plasma 6.8 / KWin 6.8, Sunshine.

**Spec:** `docs/superpowers/specs/2026-11-24-selkies-plasma-design.md`

## Global Constraints

- Jamais de build de l'image : vérification par `make lint` ; l'utilisateur fait `make push`.
- Tout en français (commentaires, messages de log, doc), dans le style des fichiers existants (date du changement entre parenthèses).
- Chaque évolution répercutée partout : Dockerfile.cachyos, README.md, docs/configuration.md, profiles/*/env, Makefile/prebuilt, TODO.md.
- Noms de sockets figés : Selkies `wayland-0`, Plasma `wayland-1` (choisi par le wrapper KWin, jamais écrit en dur ailleurs que dans le fichier publié par la session), streaming `wayland-stream`.
- `selkies==2.2.1` épinglé (composant d'infrastructure, comme s6-overlay).
- Port du bureau : 6080. HTTPS auto-signé ; authentification basique seulement si `DESKTOP_PASSWORD` est non vide.
- Pas de commit de `.claude/settings.local.json`. Commits en Conventional Commits français + ligne Co-Authored-By.

## Review Focus

- Redémarrage de Selkies seul (`s6-svc -r svc-selkies`) : Plasma doit mourir avec lui et revenir derrière (s6), sur `wayland-1` à nouveau, sans socket périmé adopté par Selkies.
- Arrêt du KWin de streaming par la session Steam gamescope pendant que Plasma redémarre : le wrapper ne doit jamais prendre `wayland-stream` (nom non numéroté) et le KWin de streaming doit retrouver son nom à la relance.
- Conteneur sans dongle : aucun service en boucle de relance (svc-kwin-stream et svc-sunshine attendent sans quitter), message clair dans les logs.
- Clavier Mac (`KEYBOARD_LAYOUT=fr`, `KEYBOARD_VARIANT=mac`) depuis le navigateur : « @ », « < », « > », « € », accents morts doivent arriver dans Konsole.
- Premier démarrage d'un `/config` neuf : certificat créé, `kxkbrc` écrit, Plasma sans fenêtre d'assistant bloquante.

---

### Task 1: Socle X11 et lanceur KWin

**Files:**
- Modify: `root-cachyos/etc/s6-overlay/s6-rc.d/init-system/run:59-62`
- Create: `root-cachyos/scripts/kwin-launch.py` (copie de `/tmp/claude-99/-config-workspace-SteamBox/e348b689-10ea-453b-a965-da59668ee706/scratchpad/kwin-xwayland-launch.py`, validé le 24/11)

**Interfaces:**
- Produces: `/usr/local/bin/scripts/kwin-launch.py <arguments kwin_wayland…>` — exécute `kwin_wayland --xwayland-fd 20 --xwayland-fd 21 --xwayland-display :N --xwayland-initfd 22 --xwayland-init-display :M <arguments>` ; sort en erreur si `/tmp/.X11-unix` n'a pas le sticky bit.

- [ ] **Step 1:** Dans init-system, juste après `chown … "${XDG_RUNTIME_DIR}"` : `install -d -m 1777 -o root -g root /tmp/.X11-unix` avec un commentaire (KWin refuse ses sockets X sans sticky bit ; recréé en 0755 par arcade sinon).
- [ ] **Step 2:** Copier le lanceur, shebang `#!/usr/bin/python3 -I`, `chmod 755` (le `COPY root-cachyos/scripts/` existant l'installe).
- [ ] **Step 3:** `make lint` → aucun avertissement nouveau.
- [ ] **Step 4:** Commit `fix(x11): sticky bit de /tmp/.X11-unix et lanceur KWin à socket fixe`.

### Task 2: KWin de streaming sur `wayland-stream`, dongle obligatoire, sans labwc ni evdev-bridge

**Files:**
- Rename: `svc-labwc-stream` → `svc-kwin-stream` (dossier s6 et son entrée `root-cachyos/etc/s6-overlay/user-bundles.d/user/contents.d/` ; mettre à jour `svc-sunshine/dependencies.d`)
- Delete: `svc-evdev-bridge/`, `evdev-bridge/`, étape evdev-bridge de `Dockerfile.prebuilt` (l.30-…), `prebuilt-fetch evdev-bridge` et son `ldd` dans `Dockerfile.cachyos:1216-1219`, `EVDEV_REF` du Makefile (l.75), bloc evdev-bridge de `prebuilt/check.sh:39-43`
- Modify: toutes les occurrences de `wayland-1` hors docs historiques (`grep -rn wayland-1 root-cachyos`) → `wayland-stream` ; `steambox-env.sh:149` (`-S "${d}/wayland-stream"`)
- Modify: `svc-sunshine/run` (attente de `wayland-stream`)

**Interfaces:**
- Consumes: `kwin-launch.py` (Task 1).
- Produces: socket `$XDG_RUNTIME_DIR/wayland-stream` ; `steambox-stream-compositor` contient toujours `kwin` ou est absent ; `steambox-stream-output` vide = pas de dongle.

- [ ] **Step 1:** Dans `svc-kwin-stream/run`, supprimer l'attente de `wayland-0` (Selkies l'a, mais l'ordre ne compte plus : nom fixe) et toute la branche labwc headless. Sans sortie branchée : `echo "[kwin-stream] aucune sortie branchée : dongle HDMI requis pour Moonlight/Remote Play"` puis `exec sleep infinity`. Avec sortie : remplacer `kwin_wayland --drm --xwayland --socket wayland-1` par `/usr/local/bin/scripts/kwin-launch.py --drm --xwayland --socket wayland-stream`.
- [ ] **Step 2:** `svc-sunshine/run` : sans `steambox-stream-output` non vide → même message et `exec sleep infinity` (pas de boucle s6).
- [ ] **Step 3:** Renommer `wayland-1` partout dans `root-cachyos/` ; relire `steam-gamescope-session.sh`, `set-resolution.sh`, `stream-exec.sh`, `steam-link-launch.sh` : retirer les branches `stream_compositor == labwc` / `wlr-randr` (KWin seul subsiste, `kscreen-doctor`).
- [ ] **Step 4:** Retirer evdev-bridge (fichiers ci-dessus) et la règle udev 3b du Dockerfile **seulement si** son commentaire la lie uniquement à labwc/evdev-bridge ; sinon la garder et le noter dans le message de commit.
- [ ] **Step 5:** Vérifier : `grep -rn "wayland-1\|labwc\|evdev" root-cachyos Makefile prebuilt Dockerfile.*` → seules des mentions historiques datées en commentaire ; `make lint` propre.
- [ ] **Step 6:** Commit `refactor(stream): KWin sur wayland-stream, dongle requis, fin de labwc et evdev-bridge`.

### Task 3: Selkies sur le port 6080, fin de wayvnc/noVNC

**Files:**
- Modify: `Dockerfile.cachyos` — retirer `wayvnc` (l.353), le `pip install websockify` (l.1228) et tout le bloc noVNC (l.1230-1275) ; ajouter une étape `python3 -m venv /opt/selkies && /opt/selkies/bin/pip install --no-cache-dir selkies==2.2.1` avec contrôle `FATAL` si `/opt/selkies/bin/selkies` absent
- Create: `root-cachyos/etc/s6-overlay/s6-rc.d/svc-selkies/{run,type,dependencies.d/svc-dbus-session,dependencies.d/svc-pipewire-pulse}` + entrée dans `root-cachyos/etc/s6-overlay/user-bundles.d/user/contents.d/` (retirer celles des services supprimés à chaque tâche)
- Delete: `svc-wayvnc/`, `svc-websockify/`, `scripts/websockify-nocache.py`, `etc/xkb/keycodes/steambox`, `VNC_MAC_ISO_KEYS` de `steambox-env.sh`

**Interfaces:**
- Produces: socket `wayland-0` (compositeur de Selkies) ; `https://<hôte>:6080`.

- [ ] **Step 1:** `svc-selkies/run` : refuser de démarrer si un `wayland-0` vivant existe déjà (exit 1, s6 relance) ; créer `/config/selkies/` (arcade) et, absent, un certificat `openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj /CN=SteamBox` ; puis `exec runuser -u arcade -- env -u WAYLAND_DISPLAY -u DISPLAY HOME=/home/arcade XDG_RUNTIME_DIR=… SELKIES_WAYLAND=true SELKIES_PORT=6080 SELKIES_ADDR=0.0.0.0 SELKIES_ENABLE_HTTPS=true SELKIES_HTTPS_CERT=… SELKIES_HTTPS_KEY=… SELKIES_ENABLE_CURSORS=true SELKIES_USE_BROWSER_CURSORS=true` plus, si `DESKTOP_PASSWORD` non vide, `SELKIES_ENABLE_BASIC_AUTH=true SELKIES_BASIC_AUTH_PASSWORD=…`, et `/opt/selkies/bin/selkies`. `ulimit -S -s 8192` comme les autres compositeurs.
- [ ] **Step 2:** `make lint` propre ; `grep -rn "wayvnc\|websockify\|novnc\|VNC_MAC_ISO_KEYS" root-cachyos Dockerfile.cachyos` vide hors historique daté.
- [ ] **Step 3:** Commit `feat(desktop): Selkies sert le bureau sur 6080 à la place de noVNC`.

### Task 4: Session Plasma dans Selkies, fin de labwc et XFCE sur le bureau

**Files:**
- Create: `svc-plasma/{run,type,dependencies.d/svc-selkies}` ; `root-cachyos/scripts/plasma-session.sh` ; `root-cachyos/scripts/desktop-session.sh` + son `.desktop` dans `/etc/xdg/autostart/steambox-desktop-session.desktop` (`OnlyShowIn=KDE;`)
- Delete: `svc-labwc/`, `svc-xfsettingsd/`, `svc-xfdesktop/`, `svc-xfce4-panel/`, `scripts/{wayland-session,labwc-session,xdg-autostart,xfce-defaults,desktop-env}.sh`
- Modify: `Dockerfile.cachyos:347-353` — retirer `labwc xfdesktop xfce4-panel xfce4-settings xfce4-appfinder xfce4-terminal thunar mousepad xfce4-taskmanager xfce4-pulseaudio-plugin tumbler xfce4-notifyd dex xdg-desktop-portal-wlr wlr-randr`, ajouter `plasma-desktop dolphin konsole kate plasma-pa` ; retirer le contrôle notifyd (l.395), le wrapper `xfdesktop-settings` (l.737-739), le contrôle `libxfce-launcher.so` (l.972) ; `Dockerfile.prebuilt` étape xfce-launcher (l.93-118), Makefile `XFCE_LAUNCHER_REF`, `prebuilt/check.sh:45-48`
- Modify: `steambox-env.sh` — `desktop_display` lit `DISPLAY` dans `steambox-desktop-session.env` ; ajouter `desktop_session_env` (même format que `stream_session_env`)

**Interfaces:**
- Consumes: `wayland-0` (Task 3).
- Produces: `$XDG_RUNTIME_DIR/steambox-desktop-session.env` (`DISPLAY`, `WAYLAND_DISPLAY`, `DBUS_SESSION_BUS_ADDRESS`, `XDG_CURRENT_DESKTOP`, écrit en .tmp puis renommé) et `steambox-desktop-display` (via `note-display.sh desktop`) ; lus par tout script qui lançait une appli sur `wayland-0`.

- [ ] **Step 1:** `plasma-session.sh` (en arcade) : écrire `~/.config/kxkbrc` groupe `[Layout]` (`LayoutList=${KEYBOARD_LAYOUT}`, `VariantList=${KEYBOARD_VARIANT}`, `Use=true`, `Model=apple` si variante `mac`) avec `kwriteconfig6` ; garder les blocs utiles de l'ancien `labwc-session.sh` (fc-cache, xdg-mime wine, verrou Chrome, fallbacks GTK WhiteSur) ; `export WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=${XDG_RUNTIME_DIR}/bus XDG_SESSION_TYPE=wayland KWIN_WAYLAND_NO_PERMISSION_CHECKS=1` ; `unset DISPLAY` ; `exec startplasma-wayland`.
- [ ] **Step 2:** `svc-plasma/run` : attendre `wayland-0` vivant 30 s (sinon exit 1), `ulimit -S -s 8192`, `exec runuser -u arcade -- env … /usr/local/bin/scripts/plasma-session.sh`.
- [ ] **Step 3:** `desktop-session.sh` (autostart Plasma) : publier l'env de session et `note-display.sh desktop` comme `kwin-stream-session.sh`, puis `dbus-update-activation-environment --all`.
- [ ] **Step 4:** Remplacer chaque `WAYLAND_DISPLAY=wayland-0` / `desktop_exec` restant (`grep -rn "wayland-0\|desktop_exec" root-cachyos`) par la lecture de `desktop_session_env`, sauf `svc-selkies` et `svc-plasma`.
- [ ] **Step 5:** `make lint` propre ; `grep -rni "xfce\|xfconf\|labwc\|wlr-randr\|dex " root-cachyos Dockerfile.* Makefile prebuilt` → historique daté seulement.
- [ ] **Step 6:** Commit `feat(desktop): Plasma imbriqué dans Selkies, fin de labwc et XFCE`.

### Task 5: « Desktop » de Moonlight sous Plasma

**Files:**
- Rename: `scripts/sunshine-desktop-xfce.sh` → `scripts/sunshine-desktop.sh` ; `scripts/stop-desktop-xfce.sh` → `scripts/stop-desktop.sh` (PID file `sunshine-desktop.pid`)
- Modify: `scripts/init_sunshine.sh` (apps.json : chemins des deux scripts), `exit-to-desktop.sh`, `os-session-select.sh` si elles citent XFCE

- [ ] **Step 1:** `sunshine-desktop.sh` : env lu par `stream_session_env` (bus `bus-stream`, `WAYLAND_DISPLAY=wayland-stream`, `DISPLAY` de `stream_display`), `XDG_CURRENT_DESKTOP=KDE`, `exec plasmashell` (garde l'idempotence par PID file).
- [ ] **Step 2:** `make lint` ; `grep -rn "desktop-xfce" .` vide.
- [ ] **Step 3:** Commit `feat(stream): le bureau Moonlight lance plasmashell`.

### Task 6: Documentation et ménage

**Files:** `README.md` (schéma l.22-25, sections bureau, ports l.267, sécurité l.276, arborescence l.297), `docs/configuration.md` (`DESKTOP_RESOLUTION` : supprimer, le bureau suit le navigateur ; `VNC_MAC_ISO_KEYS` : supprimer ; ajouter `DESKTOP_PASSWORD`), `profiles/*/env`, `docker-compose.yml`, `TODO.md`, en-tête historique de `Dockerfile.cachyos` (nouveau point : Selkies + Plasma, 24/11), Makefile l.88, note en tête de `docs/superpowers/specs/2026-11-24-kwin-deux-compositeurs-design.md` (« phase 2 remplacée par … »).

- [ ] **Step 1:** Mettre à jour chaque fichier ; README : dongle HDMI requis pour Moonlight/Remote Play, bureau en `https://<hôte>:6080` (certificat auto-signé à accepter).
- [ ] **Step 2:** `make lint` ; `grep -rn "noVNC\|wayvnc\|labwc\|XFCE\|DESKTOP_RESOLUTION" README.md docs/configuration.md profiles docker-compose.yml` → rien d'actuel.
- [ ] **Step 3:** Commit `docs: bureau Selkies + Plasma, dongle requis`.

### Task 7: Vérification après `make push` (par l'utilisateur, puis en direct)

- [ ] `https://<hôte>:6080` : bureau Plasma, un seul pointeur, la taille suit la fenêtre.
- [ ] Clavier Mac dans Konsole : `@ < > € é ^e` ; log Selkies : `auto-detected` (plus de « Multiple candidate »).
- [ ] Copier-coller navigateur ↔ Konsole dans les deux sens.
- [ ] `DISPLAY=$(desktop_display) xrandr` répond ; Steam démarre sur le bureau.
- [ ] Moonlight « Desktop » (plasmashell) et session Steam gamescope : image, entrées, retour au bureau ; `ls /run/user/99` montre `wayland-0`, `wayland-1`, `wayland-stream`.
- [ ] `s6-svc -r /run/service/svc-selkies` : Plasma revient, Selkies réadopte `wayland-1`.
