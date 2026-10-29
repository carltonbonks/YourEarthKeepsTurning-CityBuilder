"""Duelling ring (data/buildings.json "duel_ring"): a ring of stakes round trodden sand, two crossed
blades on a post and a bench for watchers."""
import math


def build(kit):
    t = kit.town_mats()
    sand = kit.mat("sand", (0.58, 0.48, 0.34), noise=0.4)
    kit.cylinder(sand, (0, 0, 0.02), 1.3, 0.04, sides=16)
    pts = [(1.3 * math.cos(a / 14 * 2 * math.pi), 1.3 * math.sin(a / 14 * 2 * math.pi)) for a in range(14)]
    kit.fence(t["wood"], pts, h=0.7, gap=0.5, closed=True, rail=True)
    kit.post(t["dark_wood"], 0, 1.0, 1.6, 0.05)
    for s in (-1, 1):
        kit.limb(t["iron"], (-0.3 * s, 0.95, 1.15), (0.3 * s, 0.95, 1.65), 0.02, sides=4)
    kit.box(t["wood"], (0.9, -1.45, 0.25), (1.0, 0.25, 0.08))
