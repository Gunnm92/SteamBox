# Reste à faire

Petits chantiers à reprendre, à compléter au fur et à mesure.

## Affichage

- [ ] **HDR dans la session Steam** : mettre en place le support HDR (gamescope, Sunshine/Moonlight).
- [ ] **Icônes Sunshine** : corriger les icônes des entrées XFCE, Steam Gamescope et Steam.

## Manettes

- [ ] **DualSense** : améliorer le support (audio, retours haptiques, gâchettes adaptatives…).

## Jeux Windows / arcade

- [ ] **TeknoParrot** : les paramètres ne sont pas conservés, revoir leur gestion.
- [ ] **Compatibilité arcade** : voir comment améliorer les jeux qui passent mal. Yu-Gi-Oh! 5D's DT6 réglé le 30/09 (image refaite : TeknoParrot récent, `d3dx9_43` builtin, faux ping `tools/fakeping-dinput8` de wsquashfs-launcher) ; d'autres jeux Konami e-amusement peuvent avoir le même ping ICMP (il vient de `libavs-win32.dll`). GTI Club réglé le 30/09 : image refaite avec `WINE=system` (wine-tkg refuse sa réservation de 450 Mo), faux ping, `GAME_VERSION` ; son émulateur JVS (`JVSEmuGT3.dll`) plante si aucune manette n'est connectée au lancement.
- [ ] **Castlevania – The Arcade (DemulShooter)** : démarre sous le Wine WoW64 du système (wine-tkg : échec `mmap` du son) puis plante pendant que sa carte d'I/O répond « notReady » — DemulShooter (pistolet) démarre mais sa config vise une souris de la machine Batocera d'origine (`VID_845E&PID_0001`). Corriger aussi `taskill` → `taskkill` dans son `launch.bat`.
## Déjà repérés

- [ ] **Steam Big Picture sans gamescope** : Steam ne reconnaît pas la fenêtre des jeux lancés par un raccourci (Heroic, wsquashfs) : sons d'interface, et Steam Input garde la manette.
- [ ] **Makefile** : passer `WSQUASHFS_REF=<sha du dernier commit de wsquashfs-launcher>` au build (raw.githubusercontent sert une version en cache quelques minutes après un push).
