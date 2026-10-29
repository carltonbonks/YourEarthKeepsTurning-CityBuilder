"""Causeway (data/buildings.json "causeway"): logs laid side by side across wet ground, pegged at the
edges, with reeds round it."""


def build(kit):
    t = kit.town_mats()
    reed = kit.mat("reeds", (0.48, 0.52, 0.28), noise=0.5)
    kit.box(kit.mat("wet_ground", (0.20, 0.20, 0.14), rough=0.3, noise=0.4), (0, 0, 0.01), (3.0, 2.4, 0.02))
    for k in range(13):
        y = -1.05 + k * 0.175
        kit.limb(t["wood"], (-1.3, y, 0.07), (1.3, y + 0.03 * (k % 2), 0.07), 0.08)
    for x in (-1.35, 1.35):
        for k in range(4):
            kit.post(t["dark_wood"], x, -0.9 + k * 0.6, 0.3, 0.035)
    for k, (x, y) in enumerate(((-1.4, 1.2), (1.45, -1.2), (1.4, 1.1), (-1.45, -1.15))):
        for j in range(4):
            kit.limb(reed, (x + 0.05 * j, y, 0), (x + 0.08 * j - 0.05, y + 0.03 * j, 0.6 + 0.1 * j), 0.012, sides=4)
