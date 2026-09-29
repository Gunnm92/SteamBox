# Reste à faire

Petits chantiers à reprendre, à compléter au fur et à mesure.

## Affichage

- [ ] **HDR dans la session Steam** : mettre en place le support HDR (gamescope, Sunshine/Moonlight).
- [ ] **Icônes Sunshine** : corriger les icônes des entrées XFCE, Steam Gamescope et Steam.

## Manettes

- [ ] **DualSense** : améliorer le support (audio, retours haptiques, gâchettes adaptatives…).

## Jeux Windows / arcade

- [ ] **TeknoParrot** : les paramètres ne sont pas conservés, revoir leur gestion.
- [ ] **Compatibilité arcade** : voir comment améliorer les jeux qui passent mal (ex. Yu-Gi-Oh!).

## Déjà repérés

- [ ] **Steam Big Picture sans gamescope** : Steam ne reconnaît pas la fenêtre des jeux lancés par un raccourci (Heroic, wsquashfs) : sons d'interface, et Steam Input garde la manette.
- [ ] **Makefile** : passer `WSQUASHFS_REF=<sha du dernier commit de wsquashfs-launcher>` au build (raw.githubusercontent sert une version en cache quelques minutes après un push).
