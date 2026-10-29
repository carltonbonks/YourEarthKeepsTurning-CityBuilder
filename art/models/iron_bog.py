"""Bog-iron pool (data/world.json nodes "iron_bog"): a rusty orange pool in dark peat, reeds round
it, lumps of bog ore at the edge."""


def build(kit):
    peat = kit.mat("peat", (0.16, 0.12, 0.08), noise=0.5)
    rust = kit.mat("rust_water", (0.55, 0.30, 0.12), rough=0.2, noise=0.3)
    reed = kit.mat("reeds", (0.48, 0.52, 0.28), noise=0.5)
    kit.cylinder(peat, (0, 0, 0.02), 1.0, 0.04, sides=12, scale=(1.1, 0.9, 1))
    kit.cylinder(rust, (0, 0, 0.045), 0.7, 0.02, sides=12, scale=(1.1, 0.85, 1))
    kit.pile(kit.mat("bog_ore", (0.45, 0.25, 0.14), noise=0.5), (0.8, -0.4), n=5, size=0.09, spread=0.2, seed=67)
    for x, y in ((-0.9, 0.4), (0.5, 0.75), (-0.5, -0.7)):
        for j in range(4):
            kit.limb(reed, (x + 0.05 * j, y, 0), (x + 0.08 * j - 0.05, y - 0.03 * j, 0.6 + 0.1 * j), 0.012, sides=4)
