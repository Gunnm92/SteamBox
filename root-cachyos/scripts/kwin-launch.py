#!/usr/bin/python3 -I
"""Lance kwin_wayland avec un nom de socket Wayland fixe ET Xwayland.

kwin_wayland_wrapper crée les sockets X que KWin 6 attend (--xwayland-fd),
mais choisit lui-même le premier wayland-N libre (--socket ignoré). Ce
lanceur fait la partie X du wrapper (deux affichages : un pour les clients,
un pour l'initialisation) et laisse --socket à KWin.

Usage : kwin-launch.py <arguments de kwin_wayland...>
"""
import os
import socket
import sys

X11_DIR = "/tmp/.X11-unix"


def try_display(n):
    lock = f"/tmp/.X{n}-lock"
    try:
        fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    except FileExistsError:
        try:
            pid = int(open(lock).read().strip())
            os.kill(pid, 0)
            return None
        except (ValueError, ProcessLookupError, OSError):
            # Verrou périmé ; s'il appartient à un autre compte (/tmp est
            # sticky), on ne peut pas l'effacer : affichage suivant.
            try:
                os.unlink(lock)
            except OSError:
                return None
            return try_display(n)
    # L'exec garde le PID : le verrou désigne bien KWin.
    os.write(fd, f"{os.getpid():>10}\n".encode())
    os.close(fd)
    path = f"{X11_DIR}/X{n}"
    socks = []
    try:
        if os.path.exists(path):
            os.unlink(path)
        for addr in (path, "\0" + path):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.bind(addr)
            s.listen(128)
            os.set_inheritable(s.fileno(), True)
            socks.append(s)
    except OSError:
        for s in socks:
            s.close()
        os.unlink(lock)
        return None
    return socks


def main():
    st = os.stat(X11_DIR)
    if not st.st_mode & 0o1000:
        sys.exit(f"{X11_DIR} sans sticky bit : KWin refuserait Xwayland")
    found = []
    n = 0
    while len(found) < 2 and n < 64:
        socks = try_display(n)
        if socks:
            found.append((n, socks))
        n += 1
    if len(found) < 2:
        sys.exit("aucun affichage X libre")
    (disp, main_socks), (init_disp, init_socks) = found
    # Descripteurs déplacés au-delà des premiers numéros, que KWin (Qt)
    # réutilise au démarrage : passés en 3-5, Xwayland n'acceptait aucun
    # client (connexions bloquées). Le wrapper de KWin les passe vers 8-11.
    fds = []
    for target, s in zip((20, 21, 22), main_socks + init_socks[:1]):
        os.dup2(s.fileno(), target, inheritable=True)
        fds.append(target)
    for s in main_socks + init_socks:
        s.close()
    args = ["kwin_wayland",
            "--xwayland-fd", str(fds[0]), "--xwayland-fd", str(fds[1]),
            "--xwayland-display", f":{disp}",
            "--xwayland-initfd", str(fds[2]),
            "--xwayland-init-display", f":{init_disp}"]
    os.environ["KWIN_WAYLAND_NO_XAUTHORITY"] = "1"
    os.execvp("kwin_wayland", args + sys.argv[1:])


main()
