"""Forester's hut (data/buildings.json "forester"): a mossy hut among saplings staked to grow, with
a basket of seedlings."""


def build(kit):
    t = kit.town_mats()
    moss = kit.mat("moss", (0.30, 0.40, 0.20), noise=0.6, scale=30.0)
    leaf = kit.mat("leaf", (0.24, 0.44, 0.20), noise=0.5, scale=24.0)
    kit.round_hut(t["daub"], moss, r=0.85, wall_h=0.8, roof_h=1.1, at=(-0.4, 0.35), door=t["dark_wood"], sides=9)
    for k, (x, y) in enumerate(((0.7, -0.6), (1.1, 0.2), (0.2, -1.0), (1.1, -0.9))):
        kit.post(t["wood"], x, y, 0.7, 0.025)
        kit.limb(t["dark_wood"], (x + 0.08, y, 0), (x + 0.08, y, 0.9 + 0.1 * k), 0.03)
        kit.cone(leaf, (x + 0.08, y, 1.0 + 0.1 * k), 0.22, 0.0, 0.6, sides=6)
    kit.cylinder(kit.mat("wicker", (0.62, 0.48, 0.26), noise=0.5, scale=40.0), (0.4, -0.3, 0.12), 0.15, 0.24, sides=8)
    kit.ball(leaf, (0.4, -0.3, 0.28), 0.12)
