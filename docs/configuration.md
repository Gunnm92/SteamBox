# Configuration d'une installation

Tout ce qui dépend d'une installation (GPU, chemins de l'hôte, clavier,
langue, registre) vit dans un **profil** : `profiles/<nom>/`. Le reste du
dépôt est générique.

| Fichier du profil | Rôle |
|---|---|
| `compose.override.yml` | GPU (runtime nvidia ou `/dev/dri`), volumes, PUID/PGID, TZ |
| `env` | variables du conteneur : ludothèque, clavier, langue (voir ci-dessous) |
| `profile.mk` | build/push : `REGISTRY`, commande `DOCKER`, `BUILD_ARGS` |

Modèle commenté : [profiles/example/](../profiles/example/) — le fichier
`env` y liste chaque variable avec sa valeur par défaut.

Démarrer sa propre installation :

```bash
cp -r profiles/example profiles/maison     # puis adapter les trois fichiers
echo 'PROFILE = maison' > local.mk         # profil par défaut de make (non versionné)
make build                                 # image locale steambox:latest
make run                                   # docker compose avec l'override du profil
```

`profiles/unraid-gunnm/` est un déploiement réel (Unraid, template Docker,
RTX 3090) : sa référence complète — volumes, devices, Extra Parameters,
règles cgroup — est dans
[deploiement-unraid.md](deploiement-unraid.md).

## Variables du conteneur

Lues par [steambox-env.sh](../root-cachyos/scripts/steambox-env.sh), toutes
facultatives :

| Variable | Défaut | Rôle |
|---|---|---|
| `GAMES_DIR` | `/config/games` | Ludothèque au format Batocera : `roms/<système>/`, `bios/`, `saves/` |
| `GAMES_ROMS_DIR`, `GAMES_BIOS_DIR`, `GAMES_SAVES_DIR` | `$GAMES_DIR/…` | Chaque dossier séparément |
| `KEYBOARD_LAYOUT`, `KEYBOARD_VARIANT` | `us`, vide | Disposition XKB (ex. `fr` + `mac`) |
| `LANG`, `LANGUAGE` | `en_US.UTF-8` | Langue du bureau, d'EmulationStation et de Sunshine |
| `GPU_VENDOR` | `auto` | `nvidia` / `amd` / `intel` — choisit l'encodeur Sunshine (nvenc / vaapi) |
| `LIBVA_DRIVER_NAME` | vide | `nvidia` sur GPU NVIDIA (AMD/Intel : détection libva) |

Locales disponibles : `en_US` + `EXTRA_LOCALES` (build-arg, défaut
`fr_FR de_DE es_ES it_IT pt_BR`).

**GPU AMD/Intel** : pilotes Mesa et encodage VA-API prévus, mais **non testés
sur matériel** (développé et validé sur NVIDIA uniquement).
