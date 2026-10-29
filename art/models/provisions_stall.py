"""Provisions stall (data/buildings.json "provisions_stall"): smoked meat hung under a rust awning,
pots of poultice and baskets on the counter."""


def build(kit):
    t = kit.town_mats()
    awning = kit.mat("awning", (0.62, 0.32, 0.24), noise=0.35)
    meat = kit.mat("meat", (0.42, 0.18, 0.12), noise=0.4)
    clay = kit.mat("clay", (0.58, 0.36, 0.22), noise=0.3)
    x, y, z = kit.stall(awning, t["wood"], t["dark_wood"])
    for k in range(4):
        kit.cylinder(clay, (x - 0.75 + k * 0.5, y, z + 0.1), 0.09, 0.2, sides=7)
    for k in range(6):
        px = -0.9 + k * 0.36
        kit.box(meat, (px, -0.6, 1.15), (0.08, 0.04, 0.32))
