"""Pedlar's camp (data/pedlars.json): a covered cart and a striped trader's tent with goods laid
out."""
import math


def build(kit):
    t = kit.town_mats()
    stripe = kit.mat("stripe", (0.78, 0.60, 0.29), noise=0.3)
    stripe2 = kit.mat("stripe_red", (0.54, 0.23, 0.16), noise=0.3)
    canvas = kit.mat("canvas", (0.70, 0.64, 0.50), noise=0.3)
    for k in range(6):
        a0 = k / 6 * 2 * math.pi
        kit.cone(stripe if k % 2 else stripe2, (-0.5, 0.4, 0.75), 0.75, 0.05, 1.5, sides=6, rot=(0, 0, a0 + 0.52))
    kit.box(t["wood"], (0.7, -0.2, 0.55), (1.3, 0.8, 0.3))
    for s in (-1, 1):
        for x in (0.3, 1.1):
            kit.cylinder(t["dark_wood"], (x, -0.2 + s * 0.45, 0.3), 0.28, 0.07, sides=10, rot=(1.5708, 0, 0))
    kit.cylinder(canvas, (0.7, -0.2, 0.75), 0.42, 1.3, sides=10, rot=(0, 1.5708, 0), scale=(1, 1.0, 1))
    kit.limb(t["wood"], (1.35, -0.2, 0.45), (2.0, -0.2, 0.2), 0.03)
    kit.box(t["cloth_blue"], (-0.2, -0.6, 0.03), (0.8, 0.5, 0.02))
    kit.pile(t["bronze"], (-0.2, -0.6), n=4, size=0.05, spread=0.2, seed=47)
