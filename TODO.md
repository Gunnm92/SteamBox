# Reste à faire

Petits chantiers à reprendre, à compléter au fur et à mesure.

## Affichage

- [ ] **HDR dans la session Steam** : mettre en place le support HDR (gamescope, Sunshine/Moonlight).
- [ ] **Icônes Sunshine** : corriger les icônes des entrées XFCE, Steam Gamescope et Steam.

## Manettes

- [ ] **DualSense** : améliorer le support (audio, retours haptiques, gâchettes adaptatives…).
- [ ] **Vibrations (jeux XInput)** : aucune vibration. Le noyau Unraid n'a pas `hid-playstation` : la DualSense virtuelle de Sunshine est vue en `hid-generic`, sans force feedback côté evdev — ni GE-Proton, ni UMU-Proton (SDL), ni wine-tkg ne peuvent la faire vibrer. Piste : faire émuler à Sunshine une manette Xbox 360 (réglage `gamepad`), dont la vibration passe par evdev puis est renvoyée à la DualSense du client — au prix de la DualSense native pour les jeux `HIDRAW=1`. En `HIDRAW=1`, la chaîne hidraw → Sunshine (`libvirtualhid`) → Moonlight transmet bien la vibration « compatible » (testé le 30/09 en envoyant un rapport `0x31`) : Until Dawn vibre et a même ses retours haptiques (la DualSense virtuelle déclare les rapports Bluetooth `0x32`–`0x39` qui portent les haptiques en BT : la chaîne les transmet) ; RIDE 6 n'a ni vibration ni haptiques.
- [ ] **Haptiques audio de la DualSense (RIDE 6 et jeux récents)** — diagnostic du 30/09 (trace `WINEDEBUG=+hid,+hid_report`) : RIDE 6 envoie 23 386 rapports `0x31` sur 23 387 avec le drapeau `0x02` « sélection haptique » et les moteurs à 0, aucun rapport haptique Bluetooth `0x32`–`0x39` : il joue ses haptiques comme un **son** (4 canaux, dont 2 pour les actionneurs) sur la carte son intégrée de la DualSense, méthode USB. Côté SteamBox, la DualSense virtuelle de Sunshine n'est qu'un périphérique HID : aucune sortie audio « DualSense » dans Wine, le flux part nulle part. Solution à construire :
  1. créer une sortie audio virtuelle « DualSense » (PipeWire, 4 canaux 48 kHz) que le jeu associe à la manette — sous Windows il la retrouve par l'identifiant de conteneur commun au périphérique HID et au périphérique audio : à reproduire dans Wine ;
  2. récupérer les 2 canaux haptiques et les convertir en rapports haptiques Bluetooth (`0x32`…, format documenté par la rétro-ingénierie de la DualSense) écrits sur la manette virtuelle (`/dev/hidraw*`), qui suivent alors le chemin déjà fonctionnel d'Until Dawn (Sunshine → Moonlight → dongle PS5 du client).
- [ ] **`HIDRAW=1` inopérant sur des jeux « compatibles DualSense »** (The Devil in Me, Street Fighter V) : la DualSense brute arrive bien au jeu (hidraw ouvert par winedevice) mais le jeu ne réagit pas. Pistes : support DualSense du jeu qui passe par Steam Input/l'API Steam ; DualSense virtuelle de Sunshine déclarée en Bluetooth (bus 0005), dont le format diffère peut-être d'une vraie. En attendant, ces jeux marchent en mode XInput (sans `HIDRAW=1`).

## Jeux Windows / arcade

- [ ] **TeknoParrot** : les paramètres ne sont pas conservés, revoir leur gestion.
- [ ] **Compatibilité arcade** : voir comment améliorer les jeux qui passent mal. Yu-Gi-Oh! 5D's DT6 réglé le 30/09 (image refaite : TeknoParrot récent, `d3dx9_43` builtin, faux ping `tools/fakeping-dinput8` de wsquashfs-launcher) ; d'autres jeux Konami e-amusement peuvent avoir le même ping ICMP (il vient de `libavs-win32.dll`). GTI Club réglé le 30/09 : image refaite avec `WINE=system` (wine-tkg refuse sa réservation de 450 Mo), faux ping, `GAME_VERSION` ; son émulateur JVS (`JVSEmuGT3.dll`) plante si aucune manette n'est connectée au lancement.
- [ ] **Castlevania – The Arcade (DemulShooter)** : démarre sous le Wine WoW64 du système (wine-tkg : échec `mmap` du son) puis plante pendant que sa carte d'I/O répond « notReady » — DemulShooter (pistolet) démarre mais sa config vise une souris de la machine Batocera d'origine (`VID_845E&PID_0001`). Corriger aussi `taskill` → `taskkill` dans son `launch.bat`.
- [ ] **Street Fighter V** : ne se lance pas du tout depuis ES (pas encore analysé).
- [ ] **Application de gestion des wsquashfs (vraie interface graphique)** : créer / modifier un ou plusieurs `.wsquashfs` (extraction, ajout de fichiers, repack), générer et éditer les `autorun.cmd` (`WINE=`, `HIDRAW`, `GAME_VERSION`…), à la place des scripts faits à la main — gérer les images est aujourd'hui beaucoup trop long. Application à part : le lanceur (`wsquashfs-launcher`) reste tel quel, il convient parfaitement.

## Déjà repérés

- [ ] **Steam Big Picture sans gamescope** : Steam ne reconnaît pas la fenêtre des jeux lancés par un raccourci (Heroic, wsquashfs) : sons d'interface, et Steam Input garde la manette.
