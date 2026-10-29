"""Tin diggings (data/buildings.json "tin_diggings"): an outpost shaft with a timber windlass over
it, a spoil heap of dark ore and a tent."""


def build(kit):
    t = kit.town_mats()
    ore = kit.mat("cassiterite", (0.22, 0.18, 0.18), noise=0.4)
    kit.cylinder(kit.mat("pit", (0.05, 0.05, 0.04), noise=0.1), (0.3, -0.2, 0.01), 0.45, 0.02, sides=10)
    kit.stones(t["stone"], (0.3, -0.2), 0.5, n=10, size=0.08)
    for s in (-1, 1):
        kit.post(t["wood"], 0.3, -0.2 + s * 0.5, 1.0, 0.04)
    kit.limb(t["dark_wood"], (0.3, -0.75, 0.9), (0.3, 0.35, 0.9), 0.06)
    kit.limb(t["rope"], (0.3, -0.2, 0.88), (0.3, -0.2, 0.2), 0.012)
    kit.pile(ore, (-0.6, -0.5), n=9, size=0.12, spread=0.3, seed=41)
    kit.tent(t["hide"], t["dark_wood"], at=(-0.6, 0.7), r=0.55, h=1.1)
