"""Woodcutters' camp (data/buildings.json "woodcutters_camp"): an outpost tent by a felled trunk
with an axe in a stump and a stack of split logs."""


def build(kit):
    t = kit.town_mats()
    kit.tent(t["hide"], t["dark_wood"], at=(-0.6, 0.5), r=0.7, h=1.3)
    kit.cylinder(t["wood"], (0.6, -0.3, 0.2), 0.25, 0.4, sides=8)
    kit.cylinder(kit.mat("cut_wood", (0.70, 0.56, 0.36), noise=0.3), (0.6, -0.3, 0.41), 0.24, 0.02, sides=8)
    kit.limb(t["wood"], (0.6, -0.3, 0.4), (0.75, -0.3, 0.85), 0.025)
    kit.box(t["iron"], (0.62, -0.3, 0.45), (0.16, 0.03, 0.12), rot=(0, -0.3, 0))
    kit.logs(t["wood"], (0.3, 0.6), n=6, length=1.0, r=0.08)
    kit.limb(t["dark_wood"], (-1.2, -0.9, 0.15), (0.6, -1.1, 0.2), 0.15)
