"""Copper seam (data/world.json nodes "copper_seam"): a rock face streaked green and copper."""


def build(kit):
    t = kit.town_mats()
    copper = kit.mat("copper", (0.70, 0.42, 0.22), rough=0.4, noise=0.3)
    verdigris = kit.mat("verdigris", (0.30, 0.55, 0.45), noise=0.4)
    kit.ball(t["dark_stone"], (0, 0.2, 0.35), 0.75, scale=(1.3, 0.9, 0.9))
    for k in range(5):
        kit.ball(copper if k % 2 else verdigris, (0.2 + 0.25 * (k - 2), -0.45, 0.3 + 0.12 * (k % 3)), 0.12, scale=(1.3, 0.6, 0.8))
    kit.pile(copper, (0.7, -0.6), n=4, size=0.08, spread=0.2, seed=61)
