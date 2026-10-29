"""Relic icons for cards (art/card_art.json relic_looks, one per column): the thing each relic is, made in
art/lib/trinkets.py."""
import json
import os

import trinkets

_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LOOKS = json.load(open(os.path.join(_ROOT, "art", "card_art.json")))["relic_looks"]


def build(kit, variant=0):
    trinkets.look(kit, LOOKS[variant])
