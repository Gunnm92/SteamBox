# Reste à faire

Petits chantiers à reprendre, à compléter au fur et à mesure.

## Affichage

- [ ] **HDR dans la session Steam** : mettre en place le support HDR (gamescope, Sunshine/Moonlight).
- [ ] **Icônes Sunshine** : corriger les icônes des entrées XFCE, Steam Gamescope et Steam.

## Manettes

- [ ] **DualSense** : améliorer le support (audio, retours haptiques, gâchettes adaptatives…).

## Jeux Windows / arcade

- [ ] **TeknoParrot** : les paramètres ne sont pas conservés, revoir leur gestion.
- [ ] **Compatibilité arcade** : voir comment améliorer les jeux qui passent mal. Yu-Gi-Oh! 5D's DT6 réglé le 30/09 (image refaite : TeknoParrot récent, `d3dx9_43` builtin, faux ping `tools/fakeping-dinput8` de wsquashfs-launcher) ; d'autres jeux Konami e-amusement peuvent avoir le même ping ICMP.
## Déjà repérés

- [ ] **Steam Big Picture sans gamescope** : Steam ne reconnaît pas la fenêtre des jeux lancés par un raccourci (Heroic, wsquashfs) : sons d'interface, et Steam Input garde la manette.
- [ ] **Makefile** : passer `WSQUASHFS_REF=<sha du dernier commit de wsquashfs-launcher>` au build (raw.githubusercontent sert une version en cache quelques minutes après un push).
