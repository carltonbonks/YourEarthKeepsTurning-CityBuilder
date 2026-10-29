"""Barrow warden's hut (data/buildings.json "warden_hut"): a low drystone hut with a turf roof, a
cold blue lantern on a staff and a grave marker by the door."""


def build(kit):
    t = kit.town_mats()
    turf = kit.mat("turf", (0.26, 0.30, 0.18), noise=0.6, scale=24.0)
    kit.cylinder(t["dark_stone"], (-0.2, 0.25, 0.45), 0.95, 0.9, sides=10)
    kit.cone(turf, (-0.2, 0.25, 1.2), 1.15, 0.3, 0.7, sides=10)
    kit.box(t["dark_wood"], (0.72, 0.25, 0.35), (0.1, 0.45, 0.7))
    kit.post(t["dark_wood"], 0.9, -0.6, 1.7, 0.04)
    kit.limb(t["dark_wood"], (0.9, -0.6, 1.65), (1.15, -0.6, 1.6), 0.025)
    kit.ball(kit.glow("ghost_light", (0.55, 0.7, 1.0), 5.0), (1.15, -0.6, 1.45), 0.1)
    kit.box(t["stone"], (0.2, -0.9, 0.3), (0.3, 0.12, 0.6), rot=(0.1, 0, 0))
