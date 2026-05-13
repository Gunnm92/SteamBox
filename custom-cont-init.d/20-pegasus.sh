#!/bin/bash
# ArcadeBox — Génération automatique des métadonnées Pegasus-fe
# Crée un metadata.pegasus.txt dans chaque dossier système de /userdata/roms/
# et met à jour game_dirs.txt pour que Pegasus scanne les bons répertoires.
#
# Placé dans /config/custom-cont-init.d/ → exécuté au démarrage par s6

ROMS_DIR="/userdata/roms"
PEGASUS_CFG="/config/.config/pegasus-frontend"
CORES="/config/steam/steamapps/common/RetroArch/cores"
RA="retroarch -L"
WSQUASHFS="/usr/local/bin/wsquashfs-batocera"

mkdir -p "${PEGASUS_CFG}"

# ── Mapping systèmes ──────────────────────────────────────────────────────────
# Format : "Nom affiché|extensions (sans point)|commande de lancement"
declare -A SYSTEMS

# ── Windows / Arcade PC (wsquashfs-batocera) ──────────────────────────────────
SYSTEMS["windows"]="Windows|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["windows3x"]="Windows 3.x|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["windows9x"]="Windows 9x|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["win311"]="Windows 3.11|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["win95"]="Windows 95|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["nesicax"]="NESiCAxLive|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["nesicax2"]="NESiCAxLive 2|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["typex"]="Taito Type X|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["typex2"]="Taito Type X2|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["type-x"]="Taito Type X|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["arcadepc"]="Arcade PC|wsquashfs,zip|${WSQUASHFS} \"{file.path}\""
SYSTEMS["rawthrills"]="Raw Thrills|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["cave3rd"]="Cave 3rd|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["konamipc"]="Konami PC|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["konamilcd"]="Konami LCD|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["namco2x6"]="Namco System 2x6|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["namcoes3"]="Namco ES3|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["chihiro"]="Sega Chihiro|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["triforce"]="Namco Triforce|wsquashfs,zip|${WSQUASHFS} \"{file.path}\""
SYSTEMS["ikemen"]="Ikemen|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["unis"]="Unis|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["exl100"]="EXL100|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["pc"]="PC (DOS/Windows)|wsquashfs,exe,bat|${WSQUASHFS} \"{file.path}\""
SYSTEMS["dos"]="MS-DOS|wsquashfs,exe,com,bat|${WSQUASHFS} \"{file.path}\""

# ── Standalone launchers ──────────────────────────────────────────────────────
SYSTEMS["lindbergh"]="Sega Lindbergh|elf,sh,zip|/usr/local/bin/lindbergh \"{file.path}\""
SYSTEMS["model3"]="Sega Model 3|zip|/usr/local/bin/supermodel -res=1920,1080 -fullscreen \"{file.path}\""
SYSTEMS["model2"]="Sega Model 2|zip|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["model1"]="Sega Model 1|zip|${RA} ${CORES}/mame_libretro.so \"{file.path}\""

# ── Arcade (MAME / FBA) ───────────────────────────────────────────────────────
SYSTEMS["arcade"]="Arcade|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["mame"]="MAME|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["fbneo"]="FBNeo|zip,7z|${RA} ${CORES}/fbalpha_libretro.so \"{file.path}\""
SYSTEMS["fba"]="FBA|zip,7z|${RA} ${CORES}/fbalpha_libretro.so \"{file.path}\""
SYSTEMS["cps1"]="CPS-1|zip,7z|${RA} ${CORES}/fbalpha2012_cps1_libretro.so \"{file.path}\""
SYSTEMS["cps2"]="CPS-2|zip,7z|${RA} ${CORES}/fbalpha2012_cps2_libretro.so \"{file.path}\""
SYSTEMS["cps3"]="CPS-3|zip,7z|${RA} ${CORES}/fbalpha2012_cps3_libretro.so \"{file.path}\""
SYSTEMS["neogeo"]="Neo Geo|zip,7z|${RA} ${CORES}/fbalpha2012_neogeo_libretro.so \"{file.path}\""
SYSTEMS["neogeocd"]="Neo Geo CD|iso,chd,cue|${RA} ${CORES}/neocd_libretro.so \"{file.path}\""
SYSTEMS["neogeocdjp"]="Neo Geo CD JP|iso,chd,cue|${RA} ${CORES}/neocd_libretro.so \"{file.path}\""
SYSTEMS["atomiswave"]="Atomiswave|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["naomi"]="Sega NAOMI|zip,7z,chd|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["naomi2"]="Sega NAOMI 2|zip,7z,chd|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["naomigd"]="Sega NAOMI GD-ROM|zip,7z,chd|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["stv"]="Sega ST-V|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["hikaru"]="Sega Hikaru|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""

# ── Sega (RetroArch) ──────────────────────────────────────────────────────────
SYSTEMS["megadrive"]="Mega Drive|md,bin,smd,gen,zip,7z|${RA} ${CORES}/picodrive_libretro.so \"{file.path}\""
SYSTEMS["genesis"]="Genesis|md,bin,smd,gen,zip,7z|${RA} ${CORES}/picodrive_libretro.so \"{file.path}\""
SYSTEMS["sega32x"]="Sega 32X|32x,bin,md,zip,7z|${RA} ${CORES}/picodrive_libretro.so \"{file.path}\""
SYSTEMS["segacd"]="Sega CD|iso,chd,cue,bin|${RA} ${CORES}/picodrive_libretro.so \"{file.path}\""
SYSTEMS["megacd"]="Mega CD|iso,chd,cue,bin|${RA} ${CORES}/picodrive_libretro.so \"{file.path}\""
SYSTEMS["mastersystem"]="Master System|sms,bin,zip,7z|${RA} ${CORES}/gearsystem_libretro.so \"{file.path}\""
SYSTEMS["mark3"]="Sega Mark III|sms,bin,zip,7z|${RA} ${CORES}/gearsystem_libretro.so \"{file.path}\""
SYSTEMS["sg-1000"]="SG-1000|sg,bin,zip,7z|${RA} ${CORES}/gearsystem_libretro.so \"{file.path}\""
SYSTEMS["sg1000"]="SG-1000|sg,bin,zip,7z|${RA} ${CORES}/gearsystem_libretro.so \"{file.path}\""
SYSTEMS["gamegear"]="Game Gear|gg,bin,zip,7z|${RA} ${CORES}/gearsystem_libretro.so \"{file.path}\""
SYSTEMS["saturn"]="Saturn|iso,chd,cue,bin,mdf|${RA} ${CORES}/yabasanshiro_libretro.so \"{file.path}\""
SYSTEMS["saturnjp"]="Saturn JP|iso,chd,cue,bin,mdf|${RA} ${CORES}/yabasanshiro_libretro.so \"{file.path}\""
SYSTEMS["dreamcast"]="Dreamcast|chd,cdi,gdi,iso|${RA} ${CORES}/mame_libretro.so \"{file.path}\""

# ── Nintendo (RetroArch) ──────────────────────────────────────────────────────
SYSTEMS["snes"]="Super Nintendo|sfc,smc,fig,bs,zip,7z|${RA} ${CORES}/snes9x2010_libretro.so \"{file.path}\""
SYSTEMS["sfc"]="Super Famicom|sfc,smc,fig,zip,7z|${RA} ${CORES}/snes9x2010_libretro.so \"{file.path}\""
SYSTEMS["supergrafx"]="SuperGrafx|pce,sgx,bin,zip,7z|${RA} ${CORES}/mednafen_supergrafx_libretro.so \"{file.path}\""
SYSTEMS["gamecube"]="GameCube|iso,rvz,chd,gcm|${RA} ${CORES}/dolphin_libretro.so \"{file.path}\""
SYSTEMS["gc"]="GameCube|iso,rvz,chd,gcm|${RA} ${CORES}/dolphin_libretro.so \"{file.path}\""
SYSTEMS["wii"]="Wii|iso,wbfs,rvz,chd|${RA} ${CORES}/dolphin_libretro.so \"{file.path}\""
SYSTEMS["3ds"]="Nintendo 3DS|3ds,3dsx,cci,cxi,zip|${RA} ${CORES}/citra2018_libretro.so \"{file.path}\""
SYSTEMS["n3ds"]="Nintendo 3DS|3ds,3dsx,cci,cxi,zip|${RA} ${CORES}/citra2018_libretro.so \"{file.path}\""
SYSTEMS["jaguar"]="Atari Jaguar|j64,jag,rom,zip,7z|${RA} ${CORES}/virtualjaguar_libretro.so \"{file.path}\""
SYSTEMS["atarijaguar"]="Atari Jaguar|j64,jag,rom,zip,7z|${RA} ${CORES}/virtualjaguar_libretro.so \"{file.path}\""

# ── NEC (RetroArch) ───────────────────────────────────────────────────────────
SYSTEMS["pcengine"]="PC Engine|pce,bin,ccd,img,zip,7z|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["tg16"]="TurboGrafx-16|pce,bin,ccd,img,zip,7z|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["pcenginecd"]="PC Engine CD|iso,chd,cue,bin|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["tg-cd"]="TurboGrafx CD|iso,chd,cue,bin|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["pcfx"]="PC-FX|iso,chd,cue,bin,pce|${RA} ${CORES}/mednafen_pcfx_libretro.so \"{file.path}\""

# ── SNK (RetroArch) ──────────────────────────────────────────────────────────
SYSTEMS["ngp"]="Neo Geo Pocket|ngp,ngc,zip,7z|${RA} ${CORES}/mednafen_ngp_libretro.so \"{file.path}\""
SYSTEMS["ngpc"]="Neo Geo Pocket Color|ngp,ngc,zip,7z|${RA} ${CORES}/mednafen_ngp_libretro.so \"{file.path}\""

# ── Atari (RetroArch) ─────────────────────────────────────────────────────────
SYSTEMS["atarilynx"]="Atari Lynx|lnx,zip,7z|${RA} ${CORES}/mednafen_lynx_libretro.so \"{file.path}\""
SYSTEMS["lynx"]="Atari Lynx|lnx,zip,7z|${RA} ${CORES}/mednafen_lynx_libretro.so \"{file.path}\""

# ── Sony (RetroArch) ─────────────────────────────────────────────────────────
SYSTEMS["ps2"]="PlayStation 2|iso,chd,bin,mdf|${RA} ${CORES}/pcsx2_libretro.so \"{file.path}\""

# ── 3DO (RetroArch) ──────────────────────────────────────────────────────────
SYSTEMS["3do"]="3DO|iso,chd,cue,bin|${RA} ${CORES}/opera_libretro.so \"{file.path}\""

# ── ScummVM (RetroArch) ───────────────────────────────────────────────────────
SYSTEMS["scummvm"]="ScummVM|scummvm,zip|${RA} ${CORES}/scummvm_libretro.so \"{file.path}\""

# ── Génération des metadata.pegasus.txt ───────────────────────────────────────

GAME_DIRS_FILE="${PEGASUS_CFG}/game_dirs.txt"
> "${GAME_DIRS_FILE}"   # reset

generated=0
skipped=0

for system_dir in "${ROMS_DIR}"/*/; do
    system=$(basename "${system_dir}")
    meta_file="${system_dir}metadata.pegasus.txt"

    if [[ -z "${SYSTEMS[$system]+x}" ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    IFS='|' read -r display_name extensions launch_cmd <<< "${SYSTEMS[$system]}"

    # Vérifier qu'au moins un fichier avec ces extensions existe
    has_game=false
    IFS=',' read -ra ext_list <<< "$extensions"
    for ext in "${ext_list[@]}"; do
        if compgen -G "${system_dir}*.${ext}" > /dev/null 2>&1; then
            has_game=true
            break
        fi
    done
    # Accepter aussi si le dossier est vide (préparation anticipée)
    # has_game=true  # décommenter pour générer même sans ROMs

    if [[ "$has_game" == "false" ]]; then
        skipped=$((skipped + 1))
        continue
    fi

    cat > "${meta_file}" <<EOF
collection: ${display_name}
shortname: ${system}
extensions: ${extensions}
launch: ${launch_cmd}
EOF

    echo "${system_dir}" >> "${GAME_DIRS_FILE}"
    echo "[pegasus] ${system} → ${meta_file}"
    generated=$((generated + 1))
done

echo "[pegasus] ${generated} systèmes configurés, ${skipped} ignorés (pas de mapping ou pas de ROMs)"
echo "[pegasus] game_dirs.txt : ${GAME_DIRS_FILE}"

# ── Fichier .desktop pour le launcher Selkies / menu labwc ───────────────────
cat > /usr/share/applications/pegasus-fe.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Pegasus Frontend
Comment=Game launcher frontend
Exec=env XDG_RUNTIME_DIR=/config/.XDG WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland pegasus-fe
Icon=pegasus-fe
Categories=Game;
Terminal=false
EOF
echo "[pegasus] pegasus-fe.desktop créé"

# ── Permissions ───────────────────────────────────────────────────────────────
chown -R abc:users "${PEGASUS_CFG}" 2>/dev/null || true
