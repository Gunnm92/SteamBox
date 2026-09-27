#!/usr/bin/env python3
"""Raccourci manette « quitter le jeu » (service s6 svc-pad-hotkeys depuis le
27/09), équivalent du Hotkey + Start d'evmapy sous Batocera, pour les jeux
lancés par game-launch.sh hors RetroArch (qui gère ses propres raccourcis) :
émulateurs autonomes et jeux Wine (wsquashfs-launcher).

Service permanent plutôt qu'un surveillant par partie : supervisé par s6,
SDL initialisé une seule fois, et base d'un futur équivalent d'evmapy
(fichiers .keys Batocera). game-launch.sh décrit le jeu en cours dans
$XDG_RUNTIME_DIR/steambox-game (pid=, prefix=, rom=) ; sans jeu en cours,
les manettes ne sont pas lues (coût nul entre deux parties).

Lit les manettes via SDL — seule voie qui voit la DualSense virtuelle de
Sunshine ici (pas de hid-playstation dans le noyau Unraid, evdev muet) — et
sur Hotkey (PS / Xbox / Guide) + Start tenus ensemble :
  - jeu Wine (prefix=) : wineserver -k sur le prefix du jeu, puis SIGKILL
    des processus restants de ce prefix ; wsquashfs-launcher démonte
    ensuite normalement ;
  - sinon : SIGTERM au processus du jeu, SIGKILL 5 s plus tard s'il reste.
"""
import ctypes
import os
import signal
import subprocess
import time

STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "steambox-game")
GUIDE, START = 5, 6          # SDL_CONTROLLER_BUTTON_GUIDE / _START
IDLE_POLL = 1.0              # sans jeu : vérifie seulement le fichier d'état
GAME_POLL = 0.05             # en jeu : manettes lues à 20 Hz (un appui naturel
                             # des deux boutons dure ~0,2 s, vu en direct)


def log(msg):
    print(time.strftime("%H:%M:%S ") + "[pad-hotkeys] " + msg, flush=True)


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def read_state():
    """Jeu en cours décrit par game-launch.sh, ou None (fichier absent ou
    jeu terminé — le fichier périmé est alors supprimé)."""
    try:
        with open(STATE) as f:
            state = dict(line.rstrip("\n").split("=", 1) for line in f if "=" in line)
        pid = int(state.get("pid", "0"))
    except (OSError, ValueError):
        return None
    if pid <= 0 or not alive(pid):
        try:
            os.remove(STATE)
        except OSError:
            pass
        return None
    return pid, state.get("prefix", ""), state.get("rom", "")


def wine_prefix_pids(prefix):
    """Processus dont l'environnement porte ce WINEPREFIX (comme le repli de
    stopWineServer() dans batocera-wine)."""
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
    sdl = ctypes.CDLL("libSDL2-2.0.so.0")
    sdl.SDL_SetHint(b"SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", b"1")
    if sdl.SDL_Init(0x200 | 0x2000) != 0:          # JOYSTICK | GAMECONTROLLER
        sdl.SDL_GetError.restype = ctypes.c_char_p
        log(f"SDL_Init a échoué : {sdl.SDL_GetError().decode(errors='replace')}")
        return 1
    sdl.SDL_GameControllerOpen.restype = ctypes.c_void_p
    sdl.SDL_GameControllerGetButton.argtypes = [ctypes.c_void_p, ctypes.c_int]
    sdl.SDL_GameControllerGetAttached.argtypes = [ctypes.c_void_p]
    sdl.SDL_GameControllerClose.argtypes = [ctypes.c_void_p]
    sdl.SDL_GameControllerNameForIndex.restype = ctypes.c_char_p
    log(f"démarré (état : {STATE})")

    pads = {}                 # index SDL → handle, ouverts seulement en jeu
    current = None
    while True:
        game = read_state()
        if game is None:
            if current is not None:
                log("fin du jeu")
                for gc in pads.values():
                    sdl.SDL_GameControllerClose(gc)
                pads.clear()
                current = None
            time.sleep(IDLE_POLL)
            continue
        if game != current:
            current = game
            log(f"jeu en cours : pid={game[0]} {os.path.basename(game[2]) or '?'}")

        sdl.SDL_PumpEvents()
        for i in range(sdl.SDL_NumJoysticks()):   # manettes branchées en cours de partie
            if i not in pads and sdl.SDL_IsGameController(i):
                gc = sdl.SDL_GameControllerOpen(i)
                if gc:
                    pads[i] = gc
                    log(f"manette {i} ouverte ({sdl.SDL_GameControllerNameForIndex(i).decode(errors='replace')})")
        for i in [i for i, gc in pads.items() if not sdl.SDL_GameControllerGetAttached(gc)]:
            sdl.SDL_GameControllerClose(pads.pop(i))
        if any(sdl.SDL_GameControllerGetButton(gc, GUIDE) and
               sdl.SDL_GameControllerGetButton(gc, START) for gc in pads.values()):
            log("Hotkey + Start : fermeture du jeu")
            quit_game(game[0], game[1])
            # Pas de double déclenchement pendant la fermeture.
            for _ in range(100):
                if read_state() is None:
                    break
                time.sleep(0.1)
            continue
        time.sleep(GAME_POLL)


if __name__ == "__main__":
    raise SystemExit(main())
