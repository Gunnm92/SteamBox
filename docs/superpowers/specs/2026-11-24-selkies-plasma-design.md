# Bureau navigateur : Selkies + Plasma, fin de labwc et XFCE

Date : 24/11/2026. Remplace la phase 2 de
`2026-11-24-kwin-deux-compositeurs-design.md` (krfb + noVNC abandonnés).

## Constat (essai du 24/11 dans le conteneur)

- Selkies 2.2.1 (pixelflux 2.2.3) branché sur le labwc headless du bureau
  (`wayland_host_display`) : image et entrées OK, mais **deux pointeurs**. Le
  backend headless de wlroots n'a pas de plan curseur : le pointeur est peint
  dans l'image capturée, et le navigateur dessine le sien.
- Selkies avec **son propre compositeur** et KWin imbriqué dedans : un seul
  pointeur (KWin le donne par `wl_pointer.set_cursor`, Selkies l'envoie au
  navigateur), le bureau suit la taille de la fenêtre du navigateur.
- Le compositeur de Selkies n'a pas de Xwayland : KWin reste indispensable
  (Steam, Wine/Proton, outils X11).
- Plasma imbriqué (`startplasma-wayland`) démarre sans systemd (repli
  ksmserver) une fois `plasma-desktop` installé (sans lui : « starting
  invalid corona org.kde.plasma.desktop », plasmashell quitte en 1).
- `/tmp/.X11-unix` est recréé en 0755 par arcade (l'init efface `/tmp/.X*`) :
  KWin refuse alors ses sockets X (« no sticky bit ») et **aucun KWin n'a de
  Xwayland**, y compris celui du streaming depuis la phase 1.
- KWin 6.8 lancé directement (`kwin_wayland --xwayland`) ne crée pas les
  sockets X : c'est `kwin_wayland_wrapper` qui le fait, mais il ignore
  `--socket` (premier `wayland-N` libre). Un lanceur qui prépare les sockets
  X (descripteurs ≥ 20 : en 3-5, Xwayland n'acceptait aucun client) puis
  exécute `kwin_wayland --socket <nom>` est validé.
- Selkies trouve tout seul le compositeur des applis s'il n'y a **qu'un seul
  autre socket `wayland-<chiffres>`** dans `XDG_RUNTIME_DIR` ; sinon il injecte
  dans son propre compositeur et « every non-ASCII key » est perdue — cause
  probable du clavier Mac inutilisable.

## Décisions (utilisateur)

- Bureau navigateur : Selkies (compositeur propre) → KWin → **Plasma**.
- **labwc, XFCE, wayvnc, websockify/noVNC, evdev-bridge retirés.**
- **Dongle HDMI obligatoire** pour Moonlight/Remote Play : sans sortie
  branchée, pas de compositeur de streaming ni de Sunshine (KWin `--virtual`
  ne lit aucune entrée, phase 0 T4).

## Conception

- Sockets : Selkies prend `wayland-1` (smithay commence à 1, jamais 0 — vu au
  premier démarrage de l'image, 24/11) ; Plasma (wrapper) prend le premier
  libre qu'il choisit (`wayland-2` au premier essai : le wrapper ne commence
  pas non plus à 0), nom jamais écrit en dur — publié par desktop-session.sh ; le KWin du streaming passe de
  `wayland-1` à **`$XDG_RUNTIME_DIR/stream/wayland-stream`** (25/11 : dans un
  sous-dossier, que Selkies ne parcourt pas — à la racine, il l'adoptait au
  démarrage avant que Plasma n'existe ; ignoré par la
  détection de Selkies, et que le wrapper de Plasma ne peut pas prendre).
- Plasma sur le bus de session principal (`/run/user/99/bus`, svc-dbus-session) :
  le streaming a déjà son bus (`bus-stream`).
- Selkies sur le port **6080** (celui de noVNC), HTTPS auto-signé (certificat
  créé au premier démarrage dans `/config/selkies/`), sans mot de passe par
  défaut ; `DESKTOP_PASSWORD` active l'authentification basique.
- Disposition clavier : `KEYBOARD_LAYOUT`/`KEYBOARD_VARIANT` écrits dans
  `kxkbrc` à chaque démarrage. `VNC_MAC_ISO_KEYS` et le keycodes XKB
  `steambox` (spécifiques à wayvnc) disparaissent.
- Bureau de Moonlight (« Desktop ») : plasmashell seul sur le KWin du
  streaming, à la place du trio XFCE.
- Selkies installé en venv épinglé (`/opt/selkies`, `selkies==2.2.1`).
