"""Knapper (data/buildings.json "knapper"): an open lean-to over a sitting stone, with heaps of
flint cores and flakes and a rack of finished blades."""


def build(kit):
    t = kit.town_mats()
    flint = kit.mat("flint", (0.35, 0.37, 0.42), rough=0.5, noise=0.3)
    for x in (-1.1, 1.1):
        kit.post(t["wood"], x, 0.6, 1.5, 0.05)
        kit.post(t["wood"], x, -0.4, 1.1, 0.05)
    kit.slope(t["hide"], (0, 0.1, 0), 2.5, 1.3, 1.05, 1.5)
    kit.box(t["stone"], (0.0, -0.1, 0.18), (0.5, 0.45, 0.36))
    kit.pile(flint, (-0.7, -0.5), n=7, size=0.11, spread=0.25, seed=3)
    kit.pile(flint, (0.7, 0.2), n=5, size=0.09, spread=0.2, seed=5)
    for k in range(6):
        kit.box(flint, (0.4 + k * 0.13, -0.75, 0.04), (0.1, 0.22, 0.02), rot=(0, 0, 0.5))
    kit.fence(t["dark_wood"], [(1.3, -0.9), (1.3, 0.5)], h=0.6, gap=0.35, r=0.03)
