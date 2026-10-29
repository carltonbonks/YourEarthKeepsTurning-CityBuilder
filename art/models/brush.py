"""Dry brush (data/world.json nodes "brush"): clumps of dry scrub and dead twigs, burnable fuel."""


def build(kit):
    t = kit.town_mats()
    dry = kit.mat("dry_brush", (0.60, 0.54, 0.30), noise=0.6, scale=30.0)
    for k, (x, y, r) in enumerate(((0, 0, 0.45), (0.6, -0.3, 0.32), (-0.5, 0.4, 0.35), (-0.4, -0.5, 0.25), (0.4, 0.5, 0.28))):
        kit.ball(dry, (x, y, r * 0.6), r, scale=(1.2, 1.0, 0.8), rot=(0, 0, k))
        for j in range(3):
            kit.limb(t["wood"], (x, y, r * 0.5), (x + 0.2 * (j - 1), y - 0.1, r * 1.6), 0.015, sides=4)
