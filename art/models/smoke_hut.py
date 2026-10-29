"""Smoke hut (data/buildings.json "smoke_hut"): a low daub hut with a smoking roof hole, firewood by
the wall and clay pots for poultices."""


def build(kit):
    t = kit.town_mats()
    clay = kit.mat("clay", (0.58, 0.36, 0.22), noise=0.3)
    smoke = kit.mat("smoke", (0.55, 0.55, 0.55), noise=0.2)
    kit.round_hut(t["daub"], t["thatch"], r=0.95, wall_h=0.7, roof_h=1.1, door=t["dark_wood"], sides=9)
    for k in range(3):
        kit.ball(smoke, (0.05 * k, -0.05 * k, 2.0 + 0.3 * k), 0.14 + 0.06 * k)
    kit.logs(t["wood"], (-0.2, -1.2), n=5, length=1.0, r=0.07)
    for k in range(3):
        kit.cylinder(clay, (1.15, 0.5 + k * 0.25, 0.12), 0.1, 0.24, sides=7)
