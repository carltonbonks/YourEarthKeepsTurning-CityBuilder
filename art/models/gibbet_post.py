"""Gibbet post (data/buildings.json "gibbet_post"): a tall post and arm with an iron cage swinging
from a chain, crows' bones below. A warning to raiders."""
import math


def build(kit):
    t = kit.town_mats()
    kit.box(t["stone"], (0, 0, 0.12), (0.7, 0.7, 0.24))
    kit.post(t["dark_wood"], 0, 0, 2.8, 0.09)
    kit.limb(t["dark_wood"], (0, 0, 2.7), (0.95, -0.4, 2.7), 0.06)
    kit.limb(t["dark_wood"], (0, 0, 2.2), (0.5, -0.2, 2.68), 0.04)
    kit.limb(t["iron"], (0.9, -0.38, 2.7), (0.9, -0.38, 2.2), 0.012, sides=4)
    for k in range(6):
        a = k / 6 * 2 * math.pi
        kit.limb(t["iron"], (0.9 + 0.18 * math.cos(a), -0.38 + 0.18 * math.sin(a), 1.4), (0.9 + 0.14 * math.cos(a), -0.38 + 0.14 * math.sin(a), 2.2), 0.015, sides=4)
    kit.ball(t["bone"], (0.9, -0.38, 1.6), 0.1)
    kit.pile(t["bone"], (0.5, -0.6), n=4, size=0.06, spread=0.2, seed=19)
