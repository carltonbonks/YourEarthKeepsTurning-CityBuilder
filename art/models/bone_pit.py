"""Bone pit (data/buildings.json "bone_pit"): a dark pit ringed with stones and skulls, bones heaped
inside and a sickly green glow rising from it."""
import math


def build(kit):
    t = kit.town_mats()
    kit.cylinder(kit.mat("pit", (0.06, 0.06, 0.05), noise=0.1), (0, 0, 0.01), 0.95, 0.02, sides=12)
    kit.stones(t["dark_stone"], (0, 0), 1.05, n=14, size=0.13)
    for i in range(6):
        a = i / 6 * 2 * math.pi + 0.3
        kit.ball(t["bone"], (1.1 * math.cos(a), 1.1 * math.sin(a), 0.25), 0.09, scale=(1, 0.9, 1.1))
    kit.pile(t["bone"], (0, 0), n=9, size=0.08, spread=0.45, seed=29)
    kit.ball(kit.glow("grave_glow", (0.5, 1.0, 0.5), 2.5), (0, 0, 0.1), 0.35, scale=(1, 1, 0.25))
    for s in (-1, 1):
        kit.post(t["dark_wood"], s * 0.9, 0.9, 1.5, 0.04, lean=(-s * 0.2, -0.2))
