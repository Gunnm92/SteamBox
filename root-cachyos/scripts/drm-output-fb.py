#!/usr/bin/env python3
"""Image affichée sur une sortie DRM (23/11).

Usage : drm-output-fb.py /dev/dri/cardN /sys/class/drm/cardM-HDMI-A-1

Affiche l'identifiant du framebuffer que la sortie affiche (0 si elle est
éteinte). Sert à steam-gamescope-session.sh start : la capture KMS de
Sunshine ne trouve la sortie (« Couldn't find monitor [0] » sinon) qu'une
fois qu'un plan y affiche une image, c'est-à-dire une fois gamescope prêt.

Lecture seule, sans être maître DRM : drmModeGetConnectorCurrent ne relance
pas la détection des modes. Le dossier /sys donne connector_id (les cartes
/sys de l'hôte n'ont pas la même numérotation que /dev/dri du conteneur,
voir stream_drm_card dans steambox-env.sh).
"""
import ctypes
import os
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    card, conn_sys = sys.argv[1], sys.argv[2]
    with open(os.path.join(conn_sys, "connector_id")) as f:
        connector_id = int(f.read())

    drm = ctypes.CDLL("libdrm.so.2")
    u32p = ctypes.POINTER(ctypes.c_uint32)
    for name in ("drmModeGetConnectorCurrent", "drmModeGetEncoder", "drmModeGetCrtc"):
        getattr(drm, name).restype = ctypes.c_void_p
        getattr(drm, name).argtypes = [ctypes.c_int, ctypes.c_uint32]
    for name in ("drmModeFreeConnector", "drmModeFreeEncoder", "drmModeFreeCrtc"):
        getattr(drm, name).argtypes = [ctypes.c_void_p]

    fd = os.open(card, os.O_RDWR | os.O_CLOEXEC)
    try:
        # Seuls les premiers champs (uint32) servent :
        # drmModeConnector { connector_id, encoder_id, … }
        # drmModeEncoder   { encoder_id, encoder_type, crtc_id, … }
        # drmModeCrtc      { crtc_id, buffer_id, … }
        conn = drm.drmModeGetConnectorCurrent(fd, connector_id)
        if not conn:
            print(0)
            return 0
        encoder_id = ctypes.cast(conn, u32p)[1]
        drm.drmModeFreeConnector(conn)
        if not encoder_id:
            print(0)
            return 0
        enc = drm.drmModeGetEncoder(fd, encoder_id)
        crtc_id = ctypes.cast(enc, u32p)[2] if enc else 0
        if enc:
            drm.drmModeFreeEncoder(enc)
        if not crtc_id:
            print(0)
            return 0
        crtc = drm.drmModeGetCrtc(fd, crtc_id)
        buffer_id = ctypes.cast(crtc, u32p)[1] if crtc else 0
        if crtc:
            drm.drmModeFreeCrtc(crtc)
        print(buffer_id)
        return 0
    finally:
        os.close(fd)


if __name__ == "__main__":
    sys.exit(main())
