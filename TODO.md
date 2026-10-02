# Reste à faire

Petits chantiers à reprendre, à compléter au fur et à mesure.

## Affichage

- [ ] **HDR dans la session Steam** : mettre en place le support HDR (gamescope, Sunshine/Moonlight).

## Manettes

- [ ] **DualSense** : améliorer le support (audio, retours haptiques, gâchettes adaptatives…).
- [ ] **Haptiques audio de la DualSense (RIDE 6 et jeux récents)** — la vibration classique marche depuis le 30/09 (Unraid bêta : `hid-playstation`, DualSense virtuelle avec force feedback) sous proton-cachyos, UMU-Proton et wine-tkg, et en `HIDRAW=1` la chaîne hidraw → Sunshine → Moonlight transmet vibration et haptiques Bluetooth (Until Dawn). Reste RIDE 6 — diagnostic du 30/09 (trace `WINEDEBUG=+hid,+hid_report`) : RIDE 6 envoie 23 386 rapports `0x31` sur 23 387 avec le drapeau `0x02` « sélection haptique » et les moteurs à 0, aucun rapport haptique Bluetooth `0x32`–`0x39` : il joue ses haptiques comme un **son** (4 canaux, dont 2 pour les actionneurs) sur la carte son intégrée de la DualSense, méthode USB. Côté SteamBox, la DualSense virtuelle de Sunshine n'est qu'un périphérique HID : aucune sortie audio « DualSense » dans Wine, le flux part nulle part. Solution à construire :
  Depuis le 02/10, la DualSense de Sunshine est en USB : en USB, les jeux jouent normalement leurs haptiques en audio — à vérifier sur Until Dawn, dont les haptiques passaient jusqu'ici par les rapports Bluetooth `0x32`+, et l'étape 2 ci-dessous est à revoir (une DualSense USB n'a pas ces rapports). Piste : [vds](https://github.com/hurryman2212/vds) — vraie DualSense USB avec carte son (module noyau `vds_hcd`, haptiques audio → rapports Bluetooth), mais il faut un module noyau sur l'hôte Unraid et l'adapter pour qu'il lise la manette de Sunshine au lieu d'une vraie manette Bluetooth.
  1. créer une sortie audio virtuelle « DualSense » (PipeWire, 4 canaux 48 kHz) que le jeu associe à la manette — sous Windows il la retrouve par l'identifiant de conteneur commun au périphérique HID et au périphérique audio : à reproduire dans Wine ;
  2. récupérer les 2 canaux haptiques et les convertir en rapports haptiques Bluetooth (`0x32`…, format documenté par la rétro-ingénierie de la DualSense) écrits sur la manette virtuelle (`/dev/hidraw*`), qui suivent alors le chemin déjà fonctionnel d'Until Dawn (Sunshine → Moonlight → dongle PS5 du client).
- [x] **`HIDRAW=1` inopérant sur des jeux « compatibles DualSense »** (F1 22, The Devil in Me) — résolu le 02/10 : leurs `libScePad` de 2022 refusent la DualSense **Bluetooth** de Sunshine (énumérée, jamais ouverte) et n'acceptent qu'une DualSense USB. Sunshine est désormais compilé dans l'image avec le profil `dualsense_usb` de libvirtualhid (étape `sunshine-usb` du Dockerfile) — validé sur les jeux DualSense, XInput et ES. wsquashfs-launcher, distribué à part, a aussi un pont (`dualsense-usb-bridge`, `HIDRAW=1`) qui ne s'active qu'en présence d'une DualSense **Bluetooth** (Sunshine d'origine, vraie manette appairée) : jamais dans SteamBox.

## Jeux Windows / arcade

- [ ] **TeknoParrot** : les paramètres ne sont pas conservés, revoir leur gestion.
- [ ] **Compatibilité arcade** : voir comment améliorer les jeux qui passent mal. Yu-Gi-Oh! 5D's DT6 réglé le 30/09 (image refaite : TeknoParrot récent, `d3dx9_43` builtin, faux ping `tools/fakeping-dinput8` de wsquashfs-launcher) ; d'autres jeux Konami e-amusement peuvent avoir le même ping ICMP (il vient de `libavs-win32.dll`). GTI Club réglé le 30/09 : image refaite avec `WINE=system`, faux ping, `GAME_VERSION` — `WINE=system` n'est plus nécessaire depuis la correction de la pile (wine-tkg OK le 30/09), à retirer de son image ; son émulateur JVS (`JVSEmuGT3.dll`) plante si aucune manette n'est connectée au lancement.
- [ ] **Castlevania – The Arcade (DemulShooter)** : l'échec `mmap` du son sous wine-tkg venait de la pile illimitée (corrigé le 30/09 : tourne sous wine-tkg, fenêtre noire en attente d'I/O). Sous le Wine WoW64, il démarrait puis plantait pendant que sa carte d'I/O répond « notReady » — DemulShooter (pistolet) démarre mais sa config vise une souris de la machine Batocera d'origine (`VID_845E&PID_0001`). Corriger aussi `taskill` → `taskkill` dans son `launch.bat`.
- [ ] **Street Fighter V** : ne se lance pas du tout depuis ES (pas encore analysé).
- [ ] **Application de gestion des wsquashfs (vraie interface graphique)** : créer / modifier un ou plusieurs `.wsquashfs` (extraction, ajout de fichiers, repack), générer et éditer les `autorun.cmd` (`WINE=`, `HIDRAW`, `GAME_VERSION`…), à la place des scripts faits à la main — gérer les images est aujourd'hui beaucoup trop long. Application à part : le lanceur (`wsquashfs-launcher`) reste tel quel, il convient parfaitement. Spec : `docs/wsquashfs-manager.md` du dépôt wsquashfs-launcher (9ce861c), points à décider en section 7.

## Déjà repérés

- [ ] **Steam Big Picture sans gamescope** : Steam ne reconnaît pas la fenêtre des jeux lancés par un raccourci (Heroic, wsquashfs) : sons d'interface, et Steam Input garde la manette.
