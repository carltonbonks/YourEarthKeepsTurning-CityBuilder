"""Smelter (data/buildings.json "smelter"): a clay shaft furnace glowing at its mouth under a
thatched shelter, with bellows and a heap of green ore."""


def build(kit):
    t = kit.town_mats()
    clay = kit.mat("clay", (0.55, 0.34, 0.22), noise=0.4)
    ore = kit.mat("ore", (0.30, 0.42, 0.34), noise=0.5)
    kit.cone(clay, (0.3, -0.2, 0.6), 0.45, 0.25, 1.2, sides=9)
    kit.box(kit.glow("forge", (1.0, 0.5, 0.15), 6.0), (0.62, -0.42, 0.22), (0.12, 0.2, 0.22), rot=(0, 0, -0.6))
    kit.ball(kit.glow("forge", (1.0, 0.5, 0.15), 6.0), (0.3, -0.2, 1.2), 0.14, scale=(1, 1, 0.4))
    for x in (-1.1, 0.2):
        kit.post(t["wood"], x, 0.75, 1.9, 0.05)
    kit.slope(t["thatch"], (-0.45, 0.6, 0), 1.6, 0.8, 1.6, 1.9)
    kit.box(t["hide"], (-0.4, -0.3, 0.2), (0.45, 0.35, 0.22))
    kit.pile(ore, (-0.8, -0.6), n=7, size=0.1, spread=0.22, seed=11)
