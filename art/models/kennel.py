"""Kennel (data/buildings.json "kennel"): a low shed and a staked pen, a bowl and a gnawed bone."""


def build(kit):
    t = kit.town_mats()
    kit.box(t["wood"], (-0.6, 0.5, 0.4), (1.4, 1.0, 0.8))
    kit.slope(t["thatch"], (-0.6, 0.5, 0), 1.6, 1.2, 0.8, 1.1)
    kit.box(kit.mat("dark_gap", (0.06, 0.05, 0.04), noise=0.0), (-0.4, -0.01, 0.25), (0.4, 0.02, 0.45))
    kit.fence(t["dark_wood"], [(-1.3, -0.1), (-1.3, -1.1), (1.2, -1.1), (1.2, 0.9), (0.15, 0.9)], h=0.65, gap=0.3)
    kit.cylinder(t["wood"], (0.5, -0.5, 0.05), 0.14, 0.1, sides=8)
    kit.limb(t["bone"], (0.0, -0.7, 0.04), (0.25, -0.6, 0.04), 0.03)
