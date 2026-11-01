#!/usr/bin/python3
"""websockify avec « Cache-Control: no-cache » sur toutes ses réponses (02/11).

Le serveur web de websockify n'envoie que Last-Modified : les navigateurs
gardent alors noVNC en cache sans le revérifier (fraîcheur heuristique) et
continuaient d'exécuter l'ancien app/ui.js après un rebuild — onglet resté
« WayVNC - noVNC » puis « SteamBox - noVNC » malgré l'habillage SteamBox.
Avec no-cache, chaque chargement revalide (304 si inchangé, sans renvoi).

Le garde __main__ est indispensable : sous Python 3.14, multiprocessing
démarre en « forkserver » et chaque connexion réimporte ce script ; sans lui,
le processus fils relancerait un serveur (port déjà pris, connexion coupée).
Le patch, lui, doit rester au niveau du module pour s'appliquer aux fils.
"""
import sys

from websockify.websocketproxy import websockify_init
from websockify.websockifyserver import WebSockifyRequestHandler

_end_headers = WebSockifyRequestHandler.end_headers


def end_headers(self):
    self.send_header("Cache-Control", "no-cache")
    _end_headers(self)


WebSockifyRequestHandler.end_headers = end_headers

if __name__ == "__main__":
    sys.argv[0] = "websockify"
    sys.exit(websockify_init())
