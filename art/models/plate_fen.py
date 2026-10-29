"""Fen plate props (data/plates.json near_kinds "fen"): what grows and lies on the wet ground. One
variant per frame: 0 reed clump, 1 pool, 2 rotten stump, 3 bulrushes."""


def build(kit, variant=0):
    t = kit.town_mats()
    reed = kit.mat("reeds", (0.46, 0.50, 0.28), noise=0.5)
    water = kit.mat("fen_water", (0.16, 0.22, 0.20), rough=0.1, noise=0.2)
    if variant == 0:
        for j in range(9):
            kit.limb(reed, (0.04 * (j - 4), 0.03 * (j % 3), 0), (0.1 * (j - 4), 0.05 * (j % 3), 0.7 + 0.08 * (j % 4)), 0.015, sides=4)
    elif variant == 1:
        kit.cylinder(water, (0, 0, 0.01), 0.7, 0.02, sides=12, scale=(1.2, 0.8, 1))
        for x in (-0.7, 0.75):
            for j in range(4):
                kit.limb(reed, (x + 0.04 * j, 0.1, 0), (x + 0.06 * j, 0.12, 0.5 + 0.08 * j), 0.012, sides=4)
    elif variant == 2:
        kit.cylinder(t["dark_wood"], (0, 0, 0.2), 0.22, 0.4, sides=7)
        kit.limb(t["dark_wood"], (0.1, 0, 0.3), (0.5, -0.15, 0.6), 0.05)
        kit.ball(kit.mat("moss", (0.30, 0.40, 0.20), noise=0.6), (0, 0, 0.42), 0.18, scale=(1.3, 1.3, 0.4))
    else:
        brown = kit.mat("bulrush", (0.35, 0.22, 0.12), noise=0.3)
        for j in range(6):
            x, y = 0.12 * (j - 3), 0.05 * (j % 2)
            kit.limb(reed, (x, y, 0), (x * 1.3, y, 0.9), 0.012, sides=4)
            kit.cylinder(brown, (x * 1.3, y, 0.8), 0.03, 0.16, sides=6)
