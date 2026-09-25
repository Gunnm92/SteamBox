#!/usr/bin/env python3
"""Raccourci manette « quitter le jeu » (25/09), équivalent du Hotkey + Start
d'evmapy sous Batocera, pour les jeux lancés par game-launch.sh hors
RetroArch (qui gère ses propres raccourcis) : émulateurs autonomes et jeux
Wine (wsquashfs-launcher).

Lit les manettes via SDL — seule voie qui voit la DualSense virtuelle de
Sunshine ici (pas de hid-playstation dans le noyau Unraid, evdev muet) — et
sur Hotkey (PS / Xbox / Guide) + Start tenus ensemble :
  - jeu Wine (--wine-prefix) : wineserver -k sur le prefix du jeu, puis
    SIGKILL des processus restants de ce prefix ; wsquashfs-launcher
    démonte ensuite normalement ;
  - sinon : SIGTERM au processus du jeu, SIGKILL 5 s plus tard s'il reste.
S'arrête seul à la fin du jeu.

Usage : pad-exit-watcher.py <pid> [--wine-prefix <chemin>]
"""
import ctypes
import os
import signal
import subprocess
import sys
import time

LOG = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "pad-exit-watcher.log")
GUIDE, START = 5, 6          # SDL_CONTROLLER_BUTTON_GUIDE / _START
HOLD = 0.0                   # réaction immédiate, comme evmapy (un appui naturel
                             # des deux boutons ne dure que ~0,2 s, vu en direct)


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(time.strftime("%H:%M:%S ") + msg + "\n")
    except OSError:
        pass


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True           # processus d'un autre utilisateur (sudo) : vivant


def wine_prefix_pids(prefix):
    """Processus de l'utilisateur courant dont l'environnement porte ce
    WINEPREFIX (comme le repli de stopWineServer() dans batocera-wine)."""
    needle = ("WINEPREFIX=" + prefix).encode()
    pids = []
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open(f"/proc/{d}/environ", "rb") as f:
                if needle in f.read().split(b"\0"):
                    pids.append(int(d))
        except OSError:
            continue
    return pids


def quit_game(pid, prefix):
    if prefix:
        env = dict(os.environ, WINEPREFIX=prefix)
        subprocess.run(["wineserver", "-k"], env=env,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(3)
        for p in wine_prefix_pids(prefix):
            try:
                os.kill(p, signal.SIGKILL)
            except OSError:
                pass
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    for _ in range(50):
        if not alive(pid):
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    pid = int(sys.argv[1])
    prefix = ""
    if len(sys.argv) >= 4 and sys.argv[2] == "--wine-prefix":
        prefix = sys.argv[3]

    log(f"démarrage pid={pid} prefix={prefix or '-'} uid={os.getuid()}")
    sdl = ctypes.CDLL("libSDL2-2.0.so.0")
    sdl.SDL_SetHint(b"SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", b"1")
    if sdl.SDL_Init(0x200 | 0x2000) != 0:          # JOYSTICK | GAMECONTROLLER
        sdl.SDL_GetError.restype = ctypes.c_char_p
        log(f"SDL_Init a échoué : {sdl.SDL_GetError().decode(errors='replace')}")
        return 1
    sdl.SDL_GameControllerOpen.restype = ctypes.c_void_p
    sdl.SDL_GameControllerGetButton.argtypes = [ctypes.c_void_p, ctypes.c_int]
    sdl.SDL_GameControllerGetAttached.argtypes = [ctypes.c_void_p]
    sdl.SDL_GameControllerNameForIndex.restype = ctypes.c_char_p

    pads = {}                 # index SDL → handle
    since = None
    while alive(pid):
        sdl.SDL_PumpEvents()
        n = sdl.SDL_NumJoysticks()
        for i in range(n):    # manettes branchées en cours de partie
            if i not in pads and sdl.SDL_IsGameController(i):
                gc = sdl.SDL_GameControllerOpen(i)
                if gc:
                    pads[i] = gc
                    log(f"manette {i} ouverte ({sdl.SDL_GameControllerNameForIndex(i).decode(errors='replace')})")
        for i in [i for i, gc in pads.items() if not sdl.SDL_GameControllerGetAttached(gc)]:
            del pads[i]
        combo = any(sdl.SDL_GameControllerGetButton(gc, GUIDE) and
                    sdl.SDL_GameControllerGetButton(gc, START) for gc in pads.values())
        if combo:
            since = since or time.time()
            if time.time() - since >= HOLD:
                log("Hotkey + Start : fermeture du jeu")
                quit_game(pid, prefix)
                return 0
        else:
            since = None
        time.sleep(0.05)
    log("fin du jeu, arrêt du surveillant")
    return 0


if __name__ == "__main__":
    sys.exit(main())
