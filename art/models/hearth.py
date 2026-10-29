"""The hearth (sim/world.gd HEARTH_RADIUS): the town's great fire in a ring of stones, log seats round
it and old standing stones at the edge. Variant 0 burns; variant 1 is the cold hearth (grey ash)."""
import math


def build(kit, variant=0):
    t = kit.town_mats()
    kit.cylinder(kit.mat("ash", (0.22, 0.20, 0.18), noise=0.5), (0, 0, 0.02), 1.3, 0.04, sides=14)
    kit.stones(t["stone"], (0, 0), 1.35, n=18, size=0.2, z=0.1)
    for i in range(6):
        a = i / 6 * 2 * math.pi + 0.3
        x, y = 2.3 * math.cos(a), 2.3 * math.sin(a)
        kit.limb(t["wood"], (x - 0.4 * math.sin(a), y + 0.4 * math.cos(a), 0.14), (x + 0.4 * math.sin(a), y - 0.4 * math.cos(a), 0.14), 0.13)
    for i in range(5):
        a = i / 5 * 2 * math.pi + 0.9
        h = 1.2 + 0.3 * (i % 2)
        kit.box(t["dark_stone"], (3.4 * math.cos(a), 3.4 * math.sin(a), h / 2), (0.35, 0.28, h), rot=(0.04, 0, a))
    for a in (0.2, 1.3, 2.4):
        kit.limb(t["dark_wood"], (0.7 * math.cos(a), 0.7 * math.sin(a), 0.1), (-0.7 * math.cos(a), -0.7 * math.sin(a), 0.1), 0.12)
    if variant == 0:
        kit.ball(kit.glow("ember", (1.0, 0.45, 0.12), 5.0), (0, 0, 0.15), 0.6, scale=(1, 1, 0.35))
        kit.cone(kit.glow("flame", (1.0, 0.65, 0.22), 9.0), (0, 0, 0.75), 0.5, 0.0, 1.4, sides=6)
        kit.cone(kit.glow("flame_core", (1.0, 0.88, 0.5), 10.0), (0.1, -0.1, 0.6), 0.28, 0.0, 1.0, sides=5)
    else:
        kit.ball(kit.mat("cold_ash", (0.45, 0.44, 0.42), noise=0.4), (0, 0, 0.1), 0.6, scale=(1, 1, 0.3))
