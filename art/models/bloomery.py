"""Bloomery (data/buildings.json "bloomery"): a tall clay stack furnace with a glowing tap hole,
leather bellows, a heap of rust-red bog ore and baskets of charcoal."""


def build(kit):
    t = kit.town_mats()
    clay = kit.mat("clay", (0.50, 0.32, 0.22), noise=0.4)
    ore = kit.mat("bog_ore", (0.45, 0.25, 0.14), noise=0.5)
    coal = kit.mat("charcoal", (0.10, 0.09, 0.09), noise=0.3)
    kit.cone(clay, (0.2, 0.0, 0.85), 0.55, 0.28, 1.7, sides=10)
    kit.ball(kit.glow("forge", (1.0, 0.5, 0.15), 7.0), (0.55, -0.32, 0.18), 0.12)
    kit.ball(kit.glow("forge", (1.0, 0.5, 0.15), 4.0), (0.2, 0.0, 1.7), 0.12, scale=(1, 1, 0.4))
    kit.ball(t["hide"], (-0.4, -0.5, 0.18), 0.22, scale=(1.2, 0.8, 0.7))
    kit.limb(t["wood"], (-0.2, -0.4, 0.2), (0.15, -0.2, 0.25), 0.04)
    kit.pile(ore, (-0.8, 0.5), n=8, size=0.11, spread=0.3, seed=17)
    for k in range(2):
        kit.cylinder(kit.mat("wicker", (0.62, 0.48, 0.26), noise=0.5, scale=40.0), (0.9 + k * 0.3, 0.6, 0.15), 0.14, 0.3, sides=8)
        kit.cylinder(coal, (0.9 + k * 0.3, 0.6, 0.31), 0.12, 0.04, sides=8)
