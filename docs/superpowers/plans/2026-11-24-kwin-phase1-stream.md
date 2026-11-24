# Phase 1 — KWin pour le bureau de streaming (wayland-1, dongle)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** quand une sortie DRM est branchée (dongle HDMI), le compositeur de
streaming wayland-1 devient `kwin_wayland --drm` au lieu de labwc, pour que
Moonlight **et** Steam Remote Play / Steam Link fonctionnent.

**Architecture :** `svc-labwc-stream` lance KWin quand `stream_drm_card` trouve
une sortie, labwc headless sinon (inchangé). KWin tourne sur un bus D-Bus de
session dédié (`$XDG_RUNTIME_DIR/bus-stream`) avec le portail KDE ; un script
de session note l'environnement dans un fichier lu par Sunshine et les
lanceurs. Le bureau noVNC (wayland-0, labwc + wayvnc) ne change pas.

**Tech Stack :** bash, s6-overlay, KWin 6.8, xdg-desktop-portal-kde,
libkscreen (`kscreen-doctor`), Sunshine (`capture=kms`).

**Spec :** `docs/superpowers/specs/2026-11-24-kwin-deux-compositeurs-design.md`
**Essai qui valide chaque valeur ci-dessous :** `docs/superpowers/plans/2026-11-24-kwin-phase0-essai.md`
(scripts de l'essai : `/tmp/kwin-essai/*.sh` dans le conteneur, recopiés en annexe).

## Global Constraints

- Commentaires et messages en **français**, style du dépôt (commentaires datés
  « (24/11) », expliquant le pourquoi). Ne pas supprimer les commentaires
  historiques existants, ajouter à côté.
- **Interdit** : `make build`, `make push`, tout `docker build`. Seule
  vérification : `make lint` (shellcheck `-S warning` + hadolint), qui doit
  passer. `DOCKER_HOST=tcp://docker-socket-proxy:2375 DOCKER_TLS_VERIFY=`.
- Ne pas toucher au conteneur `SteamBox` en cours d'exécution.
- Utilisateur `arcade`, `XDG_RUNTIME_DIR=/run/user/$(id -u arcade)`.
- Noms fixes (interface entre tâches) :
  - fichier marqueur `$XDG_RUNTIME_DIR/steambox-stream-compositor`, contenu
    `kwin` ou `labwc` ;
  - fichier d'environnement `$XDG_RUNTIME_DIR/steambox-stream-session.env`
    (lignes `CLE=valeur` : `DISPLAY`, `WAYLAND_DISPLAY`,
    `DBUS_SESSION_BUS_ADDRESS`, `XDG_CURRENT_DESKTOP`) ;
  - bus `unix:path=$XDG_RUNTIME_DIR/bus-stream`.
- Variables KWin validées : `KWIN_DRM_DEVICES=<carte>`,
  `KWIN_FORCE_ASSUME_HDR_SUPPORT=1` (EDID du dongle sans BT.2020),
  `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1`, `KWIN_SCREENSHOT_NO_PERMISSION_CHECKS=1`,
  `XDG_CURRENT_DESKTOP=KDE`, `XDG_SESSION_TYPE=wayland`.
- Commande KWin validée :
  `kwin_wayland --drm --xwayland --socket wayland-1 --no-lockscreen --exit-with-session <script>`.
- Commit par tâche, message conventionnel en français, terminé par
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Branche
  `feat/kwin-stream`. Jamais de push.

## Review Focus

1. **Sans dongle** : tout doit rester exactement comme avant (labwc headless,
   evdev-bridge, `wlr-randr`, capture wlr) → chaque tâche garde la branche labwc.
2. **Redémarrage du service** (s6 relance, session gamescope qui fait
   `s6-svc -d` puis `-u`) : le bus `bus-stream` et les fichiers de session
   d'un ancien KWin ne doivent pas être réutilisés périmés.
3. **Steam lancé hors Sunshine** (raccourci `steam-link-launch.sh`) : doit
   parler au portail du bus `bus-stream`, sinon Steam Link retombe en capture
   X11 (écran noir / `PipewireRequired`).
4. **Premier lancement de Steam** : le portail KDE affiche une fenêtre de choix
   d'écran une seule fois (jeton persistant ensuite dans
   `~/.local/share/flatpak/db/screencast`) → à documenter dans le README.
5. **Ordre de démarrage** : Sunshine ne doit pas lire le fichier d'environnement
   avant que KWin l'ait écrit.

---

### Task 1 : compositeur de streaming KWin

**Files :**
- Create : `root-cachyos/scripts/kwin-stream-session.sh`
- Modify : `root-cachyos/etc/s6-overlay/s6-rc.d/svc-labwc-stream/run`
- Modify : `root-cachyos/scripts/steambox-env.sh` (ajouter deux fonctions)

**Interfaces :**
- Produces : `stream_compositor()` dans `steambox-env.sh` → affiche `kwin` ou
  `labwc` (contenu du marqueur, `labwc` s'il est absent) ;
  `stream_session_env()` → exporte les variables du fichier
  `steambox-stream-session.env` s'il existe (retour 1 sinon).

- [ ] **Étape 1 :** `kwin-stream-session.sh` (lancé par KWin en arcade, via
  `--exit-with-session`) : écrit `steambox-stream-session.env` (variables
  listées plus haut, écriture dans un `.tmp` puis `mv`), écrit `$DISPLAY` dans
  `steambox-stream-display` (comme `note-display.sh stream`), lance
  `dbus-update-activation-environment --all`, pré-autorise le bureau à
  distance du portail :
  `gdbus call --session --dest org.freedesktop.impl.portal.PermissionStore --object-path /org/freedesktop/impl/portal/PermissionStore --method org.freedesktop.impl.portal.PermissionStore.SetPermission kde-authorized true remote-desktop "" "['yes']"`,
  puis `exec sleep infinity`.
- [ ] **Étape 2 :** dans `svc-labwc-stream/run`, branche `STREAM_CONNECTOR`
  non vide : supprimer `steambox-stream-session.env`, `steambox-stream-display`
  et le socket `bus-stream` périmés ; écrire `kwin` dans le marqueur ; lancer
  en arcade `dbus-daemon --session --address=unix:path=$XDG_RUNTIME_DIR/bus-stream --fork`
  puis `exec runuser -u arcade -- env … kwin_wayland …` avec les variables des
  Global Constraints et `DBUS_SESSION_BUS_ADDRESS` du bus. Garder `ulimit`,
  l'attente de wayland-0, `s6-svperms` et le fichier
  `steambox-stream-output`. Branche headless : écrire `labwc` dans le marqueur,
  reste inchangé.
- [ ] **Étape 3 :** `make lint` → attendu : aucune erreur.
- [ ] **Étape 4 :** commit `feat(stream): KWin en DRM pour le bureau Moonlight/Remote Play`.

### Task 2 : Sunshine et lanceurs sur le bus KWin

**Files :**
- Modify : `root-cachyos/etc/s6-overlay/s6-rc.d/svc-sunshine/run`
- Modify : `root-cachyos/scripts/steam-link-launch.sh`
- Modify : `root-cachyos/scripts/stream-exec.sh` (seulement si les variables
  héritées de Sunshine ne suffisent pas)

**Interfaces :**
- Consumes : `stream_compositor`, `stream_session_env` (Task 1).

- [ ] **Étape 1 :** `svc-sunshine/run` : si `stream_compositor` = `kwin`,
  attendre (10 s max, comme l'attente actuelle de `steambox-stream-display`)
  `steambox-stream-session.env`, appeler `stream_session_env` et passer
  `DBUS_SESSION_BUS_ADDRESS` et `XDG_CURRENT_DESKTOP=KDE` à Sunshine, plus
  `KWIN_WAYLAND_NO_PERMISSION_CHECKS=1`. `capture=kms` reste choisi comme
  aujourd'hui (sortie DRM). Branche labwc inchangée.
- [ ] **Étape 2 :** `steam-link-launch.sh` : si `kwin`, ne plus faire
  `dbus-run-session` ; `stream_session_env`, `XDG_CURRENT_DESKTOP=KDE`, puis
  `exec steam -gamepadui` sur le bus `bus-stream`. Sinon comportement actuel.
  Mettre à jour son bloc de commentaires (« ÉTAT CONNU ») : Steam Link marche
  sous KWin (essai du 24/11).
- [ ] **Étape 3 :** `make lint` → attendu : aucune erreur.
- [ ] **Étape 4 :** commit `feat(stream): Sunshine et Steam Link sur le bus du KWin de streaming`.

### Task 3 : résolution par kscreen-doctor

**Files :**
- Modify : `root-cachyos/scripts/set-resolution.sh`

- [ ] **Étape 1 :** si `stream_compositor` = `kwin` : `stream_session_env`,
  puis `kscreen-doctor -o` (sortie à nettoyer des codes couleur
  `sed 's/\x1b\[[0-9;]*m//g'`). Sortie = 3e champ de la ligne `Output:`.
  Modes = ligne `Modes:`, éléments `id:LxH@F` (retirer `*` et `!`).
  Choisir la définition avec `fit_resolution` (existant) puis le mode de
  fréquence la plus proche de `FPS`, et appliquer
  `kscreen-doctor output.<sortie>.mode.<id> output.<sortie>.scale.1`
  (**l'id**, le nom `LxH@F.00` est refusé). Même journal
  `/tmp/set-resolution.log`. Branche labwc (`wlr-randr`) inchangée.
  Référence validée : annexe A.
- [ ] **Étape 2 :** `make lint` → attendu : aucune erreur.
- [ ] **Étape 3 :** commit `feat(stream): set-resolution par kscreen-doctor sous KWin`.

### Task 4 : image et documentation

**Files :**
- Modify : `Dockerfile.cachyos`
- Modify : `README.md`

- [ ] **Étape 1 :** Dockerfile : ajouter `kwin xdg-desktop-portal-kde libkscreen`
  à la liste de paquets qui contient déjà `xdg-desktop-portal-wlr` (ligne ~328),
  avec un commentaire (24/11). Wrapper `/usr/local/bin/steam` (ligne ~692) :
  `-pipewire -pipewire-dmabuf` ; compléter son commentaire. Ajouter un point 7
  à l'historique en tête de fichier : « KWin (Wayland, DRM) pour le seul bureau
  de streaming, 24/11 » avec les causes levées (udev réglé, wayvnc non
  concerné, Steam Link validé, HDR forcé par `KWIN_FORCE_ASSUME_HDR_SUPPORT`).
- [ ] **Étape 2 :** README : schéma et section « Session streaming » (KWin avec
  dongle, labwc sans) ; une section « Steam Remote Play / Steam Link » : au
  premier lancement de Steam, se connecter en Moonlight sur « Bureau » et
  valider la fenêtre de partage d'écran (écran HDMI, autoriser la
  restauration) ; une seule fois.
- [ ] **Étape 3 :** `make lint` → attendu : aucune erreur.
- [ ] **Étape 4 :** commit `docs: KWin pour le bureau de streaming, Steam Link`.

---

## Annexe A — set-resolution.sh validé dans l'essai

```bash
INFO=$(KD -o)
OUTPUT=$(awk '/^Output:/ {print $3; exit}' <<<"${INFO}")
MODES=$(awk '/Modes:/ { for (i = 2; i <= NF; i++) { gsub(/[*!]/, "", $i); split($i, m, ":"); print m[2], m[1] } }' <<<"${INFO}")
RES=$(cut -d' ' -f1 <<<"${MODES}" | cut -d@ -f1 | sort -u | fit_resolution "${WIDTH}" "${HEIGHT}")
read -r MODE MODEID <<<"$(awk -v res="${RES}" -v fps="${FPS}" '{ split($1, m, "@") } m[1] == res { d = m[2] - fps; if (d < 0) d = -d; if (best == "" || d < bd) { best = $0; bd = d } } END { print best }' <<<"${MODES}")"
KD "output.${OUTPUT}.mode.${MODEID}" "output.${OUTPUT}.scale.1"
```
