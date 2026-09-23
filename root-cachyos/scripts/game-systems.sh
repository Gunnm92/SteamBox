#!/bin/bash
# Table des systèmes de SteamBox (22/09), à sourcer — partagée par
# es-systems-gen.sh (génère es_systems.cfg d'EmulationStation au démarrage)
# et game-launch.sh (lanceur générique qui démarre le bon émulateur
# d'après le dossier de plateforme du jeu). Une seule source de vérité :
# changer un émulateur ici suffit, aucun fichier de la ludothèque à retoucher.
# shellcheck disable=SC2034  # variables lues par les scripts qui sourcent

SCRIPTS="/usr/local/bin/scripts"
# Dossier de cœurs UTILISATEUR (22/09), pas /usr/lib/libretro : il contient
# des liens vers tous les cœurs pacman (repeuplé par init_retroarch.sh, lancé
# AVANT ce script depuis init-system/run) ET les cœurs téléchargés depuis le
# Core Downloader de RetroArch (opera, pcsx_rearmed, mednafen_ngp/pcfx...),
# absents du dossier système — confirmé en direct le 22/09.
CORES="/config/.config/retroarch/cores"
# -f : plein écran (lancé depuis EmulationStation/Moonlight, jamais en fenêtre).
RA="retroarch -f -L"
# Les .wsquashfs viennent de Batocera, qui tourne intégralement en root (pas
# d'utilisateur non-root chez eux) : les fichiers à l'intérieur sont packagés
# root:root avec des permissions parfois restrictives (ex: rw-r-----). Notre
# session bureau/wine tourne en tant qu'"arcade" (non-root) — squashfuse monte le
# paquet en préservant ces UID/permissions d'origine, donc "arcade" se voit
# refuser la lecture (confirmé en direct : erreurs "Permission denied" sur
# autorun.cmd, jeu qui ne démarre pas). Confirmé aussi que les fichiers ne
# sont PAS corrompus : le même paquet non modifié se lance sans erreur une
# fois élevé en root. sudo -E (accès NOPASSWD déjà configuré pour arcade)
# élève le montage/lancement en root tout en gardant DISPLAY/XDG_RUNTIME_DIR
# d'arcade, donc la session graphique et l'audio (PipeWire) restent accessibles.
WSQUASHFS="sudo -E /usr/local/bin/wsquashfs-launcher"

# ── Mapping systèmes ──────────────────────────────────────────────────────────
# Format : "Nom affiché|extensions (sans point)|commande de lancement"
declare -A SYSTEMS

# ── Windows / Arcade PC (wsquashfs-launcher) ──────────────────────────────────
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

# ── Arcade (MAME / FBNeo) ─────────────────────────────────────────────────────
# Verifie en direct contre /usr/lib/libretro (ls) - la version precedente de
# ce mapping (portee telle quelle de l'ancienne image webstation) referencait
# des noms de core qui n'ont jamais ete installes ici (fbalpha2012_*, neocd,
# gearsystem, yabasanshiro, snes9x2010, citra2018, virtualjaguar, mednafen_ngp/
# lynx/pcfx, pcsx2, opera) et pointait CORES vers un dossier vide
# (~/.config/retroarch/cores au lieu de /usr/lib/libretro, ou pacman installe
# reellement les cores) - aucun de ces systemes n'a donc jamais fonctionne.
# Cores installes en plus pour combler les ecarts : fbneo, picodrive,
# beetle-pce(-fast), beetle-supergrafx, snes9x, melonds, scummvm. Systemes
# sans core disponible dans les depots retires (neogeocd, jaguar, pcfx, ngp,
# lynx, ps2, 3do) plutot que de laisser une reference morte.
SYSTEMS["arcade"]="Arcade|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["mame"]="MAME|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["fbneo"]="FBNeo|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["fba"]="FBA|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
# FBNeo est un core unifie moderne qui couvre CPS-1/2/3 et Neo Geo - remplace
# les anciens cores fbalpha2012_* separes, plus maintenus/disponibles.
SYSTEMS["cps1"]="CPS-1|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["cps2"]="CPS-2|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["cps3"]="CPS-3|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["neogeo"]="Neo Geo|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["atomiswave"]="Atomiswave|zip,7z|${RA} ${CORES}/flycast_libretro.so \"{file.path}\""
SYSTEMS["naomi"]="Sega NAOMI|zip,7z,chd|${RA} ${CORES}/flycast_libretro.so \"{file.path}\""
SYSTEMS["naomi2"]="Sega NAOMI 2|zip,7z,chd|${RA} ${CORES}/flycast_libretro.so \"{file.path}\""
SYSTEMS["naomigd"]="Sega NAOMI GD-ROM|zip,7z,chd|${RA} ${CORES}/flycast_libretro.so \"{file.path}\""
SYSTEMS["stv"]="Sega ST-V|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
SYSTEMS["hikaru"]="Sega Hikaru|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""

# ── Sega (RetroArch) ──────────────────────────────────────────────────────────
SYSTEMS["megadrive"]="Mega Drive|md,bin,smd,gen,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["genesis"]="Genesis|md,bin,smd,gen,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["sega32x"]="Sega 32X|32x,bin,md,zip,7z|${RA} ${CORES}/picodrive_libretro.so \"{file.path}\""
SYSTEMS["segacd"]="Sega CD|iso,chd,cue,bin|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["megacd"]="Mega CD|iso,chd,cue,bin|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
# Genesis Plus GX est multi-systeme (couvre aussi Master System/Game Gear/
# SG-1000) - gearsystem_libretro.so n'a jamais ete disponible dans les depots.
SYSTEMS["mastersystem"]="Master System|sms,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["mark3"]="Sega Mark III|sms,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["sg-1000"]="SG-1000|sg,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["sg1000"]="SG-1000|sg,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["gamegear"]="Game Gear|gg,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["saturn"]="Saturn|iso,chd,cue,bin,mdf|${RA} ${CORES}/yabause_libretro.so \"{file.path}\""
SYSTEMS["saturnjp"]="Saturn JP|iso,chd,cue,bin,mdf|${RA} ${CORES}/yabause_libretro.so \"{file.path}\""
SYSTEMS["dreamcast"]="Dreamcast|chd,cdi,gdi,iso|${RA} ${CORES}/flycast_libretro.so \"{file.path}\""

# ── Nintendo (RetroArch) ──────────────────────────────────────────────────────
SYSTEMS["snes"]="Super Nintendo|sfc,smc,fig,bs,zip,7z|${RA} ${CORES}/snes9x_libretro.so \"{file.path}\""
SYSTEMS["sfc"]="Super Famicom|sfc,smc,fig,zip,7z|${RA} ${CORES}/snes9x_libretro.so \"{file.path}\""
SYSTEMS["supergrafx"]="SuperGrafx|pce,sgx,bin,zip,7z|${RA} ${CORES}/mednafen_supergrafx_libretro.so \"{file.path}\""
SYSTEMS["gamecube"]="GameCube|iso,rvz,chd,gcm|${RA} ${CORES}/dolphin_libretro.so \"{file.path}\""
SYSTEMS["gc"]="GameCube|iso,rvz,chd,gcm|${RA} ${CORES}/dolphin_libretro.so \"{file.path}\""
SYSTEMS["wii"]="Wii|iso,wbfs,rvz,chd|${RA} ${CORES}/dolphin_libretro.so \"{file.path}\""
# 3DS retire (22/09) : pas de core libretro 3DS disponible, et Azahar (le
# standalone vers lequel ces entrees pointaient) a ete retire de l image le
# 18/09 - les jeux 3DS apparaissaient dans le frontend avec une commande de
# lancement vers un binaire inexistant.

# ── NEC (RetroArch) ───────────────────────────────────────────────────────────
SYSTEMS["pcengine"]="PC Engine|pce,bin,ccd,img,zip,7z|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["tg16"]="TurboGrafx-16|pce,bin,ccd,img,zip,7z|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["pcenginecd"]="PC Engine CD|iso,chd,cue,bin|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["tg-cd"]="TurboGrafx CD|iso,chd,cue,bin|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""

# ── ScummVM (RetroArch) ───────────────────────────────────────────────────────
SYSTEMS["scummvm"]="ScummVM|scummvm,zip|${RA} ${CORES}/scummvm_libretro.so \"{file.path}\""

# ── Nomenclature Batocera (22/09) ─────────────────────────────────────────────
# Les dossiers de la ludothèque suivent les noms courts Batocera (dc, ngc, sms,
# tg16, sega32, sfam, neogeoaes, win...) — les clés historiques ci-dessus
# (dreamcast, gamecube, mastersystem, windows...) n'en matchaient presque
# aucune, confirmé en direct sur les 205 dossiers. Émulateurs standalone
# installés dans l'image branchés ici ; options de ligne de commande vérifiées
# dans les sources amont le 22/09 (PCSX2/DuckStation QtHost : -batch -nogui
# -fullscreen -- ; Dolphin CommandLineParse : -b -e -C ; melonDS CLI : -f ;
# Cemu : -f -g ; Eden main_window : -f -g ; PPSSPP --help : --fullscreen).
# Arcade
SYSTEMS["fbneo"]="FinalBurn Neo|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["neogeoaes"]="Neo Geo|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["igspgm"]="IGS PGM|zip,7z|${RA} ${CORES}/fbneo_libretro.so \"{file.path}\""
SYSTEMS["naomi"]="Sega NAOMI|zip,7z,chd,dat|/usr/local/bin/flycast \"{file.path}\""
SYSTEMS["naomi2"]="Sega NAOMI 2|zip,7z,chd,dat|/usr/local/bin/flycast \"{file.path}\""
SYSTEMS["model3"]="Sega Model 3|zip|${SCRIPTS}/game-launch-supermodel.sh \"{file.path}\""
SYSTEMS["segaalls"]="Sega ALLS|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["segaer"]="Sega Europa-R|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["seganu"]="Sega Nu|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["segare"]="Sega RingEdge|wsquashfs|${WSQUASHFS} \"{file.path}\""
SYSTEMS["segarw"]="Sega RingWide|wsquashfs|${WSQUASHFS} \"{file.path}\""
# Windows : seuls les .wsquashfs de ce dossier sont lançables (les dossiers
# .pc ne sont pas pris en charge par wsquashfs-launcher, et ces jeux passent
# par Heroic de toute façon).
SYSTEMS["win"]="Windows|wsquashfs|${WSQUASHFS} \"{file.path}\""
# konamilcd : jeux LCD Konami = romsets MAME (.zip), pas des wsquashfs comme
# le supposait l'ancien mapping (vérifié le 22/09 : 19 .zip sur 20).
SYSTEMS["konamilcd"]="Konami LCD|zip,7z|${RA} ${CORES}/mame_libretro.so \"{file.path}\""
# Systèmes arcade/console lancés comme Batocera (22/09, code de lancement
# batocera-linux relu : emulators/pcsx2x6.py, rpcs3/emulator.py, xemu.py,
# dolphin/emulator.py). BIOS attendus dans bios/ (namco2x6/, cerbios.bin,
# mcpx_1.0.bin, PS3UPDAT.PUP) — voir chaque lanceur.
SYSTEMS["namco2x6"]="Namco System 246/256|squashfs|${SCRIPTS}/game-launch-namco2x6.sh \"{file.path}\""
SYSTEMS["chihiro"]="Sega Chihiro|iso|${SCRIPTS}/game-launch-chihiro.sh \"{file.path}\""
# Triforce : Dolphin officiel, comme la GameCube (Batocera n'utilise plus de
# build Triforce séparé) — remplace l'ancien mapping wsquashfs, faux.
SYSTEMS["triforce"]="Triforce|rvz,iso,gcz|dolphin-emu -b -C Dolphin.Display.Fullscreen=True -e \"{file.path}\""
SYSTEMS["ps3"]="PlayStation 3|squashfs,psn|${SCRIPTS}/game-launch-ps3.sh \"{file.path}\""
# ScummVM : jeux en DOSSIERS (« / » = dossier accepté), lancés par le
# ScummVM standalone du paquet pacman avec détection automatique du jeu.
SYSTEMS["scummvm"]="ScummVM|/|scummvm -f -p \"{file.path}\" --auto-detect"
# Sony
SYSTEMS["psx"]="PlayStation|chd,cue,pbp,7z,bin,m3u|/usr/local/bin/duckstation-qt -batch -nogui -fullscreen -- \"{file.path}\""
SYSTEMS["ps2"]="PlayStation 2|iso,chd,gz,cso|/usr/local/bin/pcsx2 -batch -nogui -fullscreen -- \"{file.path}\""
SYSTEMS["psp"]="PSP|iso,cso,chd,pbp|/usr/local/bin/ppsspp --fullscreen \"{file.path}\""
SYSTEMS["psvita"]="PS Vita|psvita|${SCRIPTS}/game-launch-psvita.sh \"{file.path}\""
# Nintendo
SYSTEMS["nes"]="NES|nes,zip,7z|${RA} ${CORES}/nestopia_libretro.so \"{file.path}\""
SYSTEMS["famicom"]="Famicom|nes,zip,7z|${RA} ${CORES}/nestopia_libretro.so \"{file.path}\""
SYSTEMS["fds"]="Famicom Disk System|fds,zip,7z|${RA} ${CORES}/nestopia_libretro.so \"{file.path}\""
SYSTEMS["sfam"]="Super Famicom|sfc,smc,zip,7z|${RA} ${CORES}/snes9x_libretro.so \"{file.path}\""
SYSTEMS["satellaview"]="Satellaview|bs,sfc,zip,7z|${RA} ${CORES}/snes9x_libretro.so \"{file.path}\""
SYSTEMS["sufami"]="SuFami Turbo|st,sfc,smc,zip,7z|${RA} ${CORES}/snes9x_libretro.so \"{file.path}\""
SYSTEMS["n64"]="Nintendo 64|z64,n64,v64,zip,7z|${RA} ${CORES}/mupen64plus_next_libretro.so \"{file.path}\""
SYSTEMS["gb"]="Game Boy|gb,zip,7z|${RA} ${CORES}/gambatte_libretro.so \"{file.path}\""
SYSTEMS["gbc"]="Game Boy Color|gbc,zip,7z|${RA} ${CORES}/gambatte_libretro.so \"{file.path}\""
SYSTEMS["sgb"]="Super Game Boy|gb,gbc,zip,7z|${RA} ${CORES}/mesen-s_libretro.so \"{file.path}\""
SYSTEMS["gba"]="Game Boy Advance|gba,zip,7z|${RA} ${CORES}/mgba_libretro.so \"{file.path}\""
SYSTEMS["nds"]="Nintendo DS|nds,zip,7z|/usr/local/bin/melonDS -f \"{file.path}\""
SYSTEMS["ngc"]="GameCube|iso,rvz,gcz,ciso|dolphin-emu -b -C Dolphin.Display.Fullscreen=True -e \"{file.path}\""
SYSTEMS["wii"]="Wii|iso,rvz,wbfs,gcz|dolphin-emu -b -C Dolphin.Display.Fullscreen=True -e \"{file.path}\""
SYSTEMS["wiiu"]="Wii U|wux,wud,rpx,wua|/usr/local/bin/cemu -f -g \"{file.path}\""
SYSTEMS["switch"]="Nintendo Switch|nsp,xci|/usr/bin/eden -f -g \"{file.path}\""
# Sega
SYSTEMS["sms"]="Master System|sms,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["gamegear"]="Game Gear|gg,sms,bin,zip,7z|${RA} ${CORES}/genesis_plus_gx_libretro.so \"{file.path}\""
SYSTEMS["sega32"]="Sega 32X|32x,zip,7z|${RA} ${CORES}/picodrive_libretro.so \"{file.path}\""
SYSTEMS["pico"]="Sega Pico|md,bin,zip,7z|${RA} ${CORES}/picodrive_libretro.so \"{file.path}\""
SYSTEMS["dc"]="Dreamcast|chd,cdi,gdi|/usr/local/bin/flycast \"{file.path}\""
SYSTEMS["saturn"]="Saturn|chd,cue,iso|${RA} ${CORES}/kronos_libretro.so \"{file.path}\""
# NEC / SNK / autres
SYSTEMS["turbografx-cd"]="TurboGrafx CD|chd,cue|${RA} ${CORES}/mednafen_pce_libretro.so \"{file.path}\""
SYSTEMS["pc-fx"]="PC-FX|chd,cue,m3u|${RA} ${CORES}/mednafen_pcfx_libretro.so \"{file.path}\""
SYSTEMS["neo-geo-pocket"]="Neo Geo Pocket|ngp,zip,7z|${RA} ${CORES}/mednafen_ngp_libretro.so \"{file.path}\""
SYSTEMS["neo-geo-pocket-color"]="Neo Geo Pocket Color|ngc,zip,7z|${RA} ${CORES}/mednafen_ngp_libretro.so \"{file.path}\""
SYSTEMS["3do"]="3DO|chd,iso,cue|${RA} ${CORES}/opera_libretro.so \"{file.path}\""

# ── Cœurs optionnels (Core Downloader de RetroArch, 22/09) ─────────────────────
# Systèmes de la ludothèque sans cœur installé dans l'image (micro-ordinateurs
# et consoles rétro, ~27 000 jeux) : la commande est prête, et s'active toute
# seule au démarrage qui suit le téléchargement du cœur depuis RetroArch
# (Menu principal > Charger un cœur > Télécharger un cœur) — le contrôle
# d'existence d'inject_launch_commands la laisse inactive d'ici là. Noms de
# cœurs vérifiés sur buildbot.libretro.com le 22/09, extensions relevées sur
# la ludothèque réelle.
SYSTEMS["zxs"]="ZX Spectrum|tzx,tap,z80,sna,zip|${RA} ${CORES}/fuse_libretro.so \"{file.path}\""
SYSTEMS["zx81"]="ZX81|p,tzx,zip|${RA} ${CORES}/81_libretro.so \"{file.path}\""
SYSTEMS["acpc"]="Amstrad CPC|dsk,cdt,m3u,zip|${RA} ${CORES}/cap32_libretro.so \"{file.path}\""
SYSTEMS["x68000"]="Sharp X68000|dim,img,m3u,hdf,zip|${RA} ${CORES}/px68k_libretro.so \"{file.path}\""
SYSTEMS["amiga"]="Amiga|lha,hdf,adf,ipf,m3u,zip|${RA} ${CORES}/puae_libretro.so \"{file.path}\""
SYSTEMS["atari-st"]="Atari ST|st,msa,stx,zip|${RA} ${CORES}/hatari_libretro.so \"{file.path}\""
SYSTEMS["c64"]="Commodore 64|d64,t64,prg,crt,tap,zip|${RA} ${CORES}/vice_x64sc_libretro.so \"{file.path}\""
SYSTEMS["c128"]="Commodore 128|d64,g64,d71,d81,prg,zip|${RA} ${CORES}/vice_x128_libretro.so \"{file.path}\""
SYSTEMS["vic-20"]="Commodore VIC-20|prg,tap,crt,d64,zip|${RA} ${CORES}/vice_xvic_libretro.so \"{file.path}\""
SYSTEMS["cplus4"]="Commodore Plus/4|prg,d64,tap,zip|${RA} ${CORES}/vice_xplus4_libretro.so \"{file.path}\""
SYSTEMS["bbcmicro"]="BBC Micro|ssd,dsd,uef,zip|${RA} ${CORES}/b2_libretro.so \"{file.path}\""
SYSTEMS["msx1"]="MSX|rom,dsk,cas,mx1,zip|${RA} ${CORES}/bluemsx_libretro.so \"{file.path}\""
SYSTEMS["msx2"]="MSX2|rom,dsk,mx2,zip|${RA} ${CORES}/bluemsx_libretro.so \"{file.path}\""
SYSTEMS["msx2+"]="MSX2+|rom,dsk,mx2,zip|${RA} ${CORES}/bluemsx_libretro.so \"{file.path}\""
SYSTEMS["msxturbor"]="MSX turboR|rom,dsk,zip|${RA} ${CORES}/bluemsx_libretro.so \"{file.path}\""
SYSTEMS["x1"]="Sharp X1|d88,2d,dx1,zip|${RA} ${CORES}/x1_libretro.so \"{file.path}\""
SYSTEMS["pc88"]="PC-88|d88,m3u,zip|${RA} ${CORES}/quasi88_libretro.so \"{file.path}\""
SYSTEMS["pc98"]="PC-98|fdi,d88,hdi,m3u,zip|${RA} ${CORES}/np2kai_libretro.so \"{file.path}\""
SYSTEMS["thomson"]="Thomson|k7,fd,sap,m7,zip|${RA} ${CORES}/theodore_libretro.so \"{file.path}\""
SYSTEMS["atari2600"]="Atari 2600|a26,bin,zip|${RA} ${CORES}/stella_libretro.so \"{file.path}\""
SYSTEMS["atari800"]="Atari 800|atr,xex,bin,cas,zip|${RA} ${CORES}/atari800_libretro.so \"{file.path}\""
SYSTEMS["atari5200"]="Atari 5200|a52,bin,zip|${RA} ${CORES}/atari800_libretro.so \"{file.path}\""
SYSTEMS["lynx"]="Atari Lynx|lnx,zip|${RA} ${CORES}/handy_libretro.so \"{file.path}\""
SYSTEMS["jaguar"]="Atari Jaguar|j64,jag,zip|${RA} ${CORES}/virtualjaguar_libretro.so \"{file.path}\""
SYSTEMS["colecovision"]="ColecoVision|col,rom,zip|${RA} ${CORES}/gearcoleco_libretro.so \"{file.path}\""
SYSTEMS["intellivision"]="Intellivision|int,bin,rom,zip|${RA} ${CORES}/freeintv_libretro.so \"{file.path}\""
SYSTEMS["o2em"]="Odyssey 2|bin,zip|${RA} ${CORES}/o2em_libretro.so \"{file.path}\""
SYSTEMS["videopacplus"]="Videopac+|bin,zip|${RA} ${CORES}/o2em_libretro.so \"{file.path}\""
SYSTEMS["vectrex"]="Vectrex|vec,bin,zip|${RA} ${CORES}/vecx_libretro.so \"{file.path}\""
SYSTEMS["virtualboy"]="Virtual Boy|vb,vboy,zip|${RA} ${CORES}/mednafen_vb_libretro.so \"{file.path}\""
SYSTEMS["wonderswan"]="WonderSwan|ws,zip|${RA} ${CORES}/mednafen_wswan_libretro.so \"{file.path}\""
SYSTEMS["wonderswan-color"]="WonderSwan Color|wsc,zip|${RA} ${CORES}/mednafen_wswan_libretro.so \"{file.path}\""
SYSTEMS["pokemini"]="Pokémon Mini|min,zip|${RA} ${CORES}/pokemini_libretro.so \"{file.path}\""
SYSTEMS["supervision"]="Supervision|sv,bin,zip|${RA} ${CORES}/potator_libretro.so \"{file.path}\""
SYSTEMS["channelf"]="Channel F|bin,chf,zip|${RA} ${CORES}/freechaf_libretro.so \"{file.path}\""
SYSTEMS["gameandwatch"]="Game & Watch|mgw,zip|${RA} ${CORES}/gw_libretro.so \"{file.path}\""
SYSTEMS["pico8"]="PICO-8|p8,png|${RA} ${CORES}/retro8_libretro.so \"{file.path}\""
SYSTEMS["tic80"]="TIC-80|tic|${RA} ${CORES}/tic80_libretro.so \"{file.path}\""
SYSTEMS["lowresnx"]="LowRes NX|nx|${RA} ${CORES}/lowresnx_libretro.so \"{file.path}\""
SYSTEMS["wasm4"]="WASM-4|wasm|${RA} ${CORES}/wasm4_libretro.so \"{file.path}\""
