"""Blacksmith (data/buildings.json "blacksmith"): a stone-walled smithy with a tall chimney, its
forge glowing through the open front, an iron anvil on a stump and a quench tub."""


def build(kit):
    t = kit.town_mats()
    shingle = kit.mat("shingle", (0.30, 0.24, 0.20), noise=0.5, scale=30.0)
    kit.box(t["stone"], (-0.3, 0.65, 0.7), (2.2, 0.3, 1.4))
    kit.box(t["stone"], (-1.3, 0.1, 0.7), (0.3, 1.4, 1.4))
    for x in (0.7, -0.3):
        kit.post(t["dark_wood"], x, -0.6, 1.35, 0.06)
    kit.slope(shingle, (-0.3, 0.05, 0), 2.4, 1.6, 1.3, 1.75)
    kit.box(t["stone"], (-0.8, 0.3, 0.4), (0.7, 0.55, 0.8))
    kit.box(kit.glow("forge", (1.0, 0.5, 0.15), 7.0), (-0.8, 0.12, 0.6), (0.45, 0.2, 0.2))
    kit.box(t["stone"], (-0.85, 0.5, 1.9), (0.4, 0.4, 2.2))
    kit.cylinder(t["dark_wood"], (0.5, -0.9, 0.25), 0.2, 0.5, sides=8)
    kit.box(t["iron"], (0.5, -0.9, 0.56), (0.42, 0.16, 0.14))
    kit.cone(t["iron"], (0.78, -0.9, 0.59), 0.07, 0.0, 0.2, sides=4, rot=(0, 1.57, 0))
    kit.barrel(t["wood"], (1.1, -0.3), r=0.22, h=0.38, band=t["iron"])
