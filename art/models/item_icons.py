"""Item icons for cards (art/card_art.json items, one per column): each item base in data/items.json, made in
art/lib/trinkets.py."""
import json
import os

import trinkets

_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ITEMS = json.load(open(os.path.join(_ROOT, "art", "card_art.json")))["items"]


def build(kit, variant=0):
    trinkets.item(kit, ITEMS[variant])
