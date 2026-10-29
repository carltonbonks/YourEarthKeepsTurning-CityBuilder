"""Brewhouse (data/buildings.json "brewhouse"): a thatched hall with a big steaming vat outside, sacks
of grain and barrels stacked by the wall."""


def build(kit):
    t = kit.town_mats()
    kit.hall(t["daub"], t["thatch"], 2.2, 1.3, 0.85, 1.0, at=(-0.4, 0.55), door=t["dark_wood"], beams=t["dark_wood"])
    kit.cylinder(t["wood"], (0.8, -0.3, 0.35), 0.45, 0.7, sides=10)
    for z in (0.15, 0.55):
        kit.cylinder(t["iron"], (0.8, -0.3, z), 0.47, 0.05, sides=10)
    kit.cylinder(kit.mat("ale", (0.45, 0.30, 0.10), rough=0.2, noise=0.1), (0.8, -0.3, 0.69), 0.42, 0.02, sides=10)
    kit.ball(kit.mat("steam", (0.7, 0.7, 0.7), noise=0.1), (0.8, -0.3, 0.95), 0.2)
    for x in (-1.1, -0.75, -0.4):
        kit.barrel(t["wood"], (x, -0.4), r=0.16, h=0.4, band=t["iron"])
    kit.ball(t["straw"], (0.0, -0.75, 0.15), 0.18, scale=(1, 0.8, 1.1))
