"""Stone-layers' yard (data/buildings.json "stone_yard"): cut blocks stacked by a stone bench, a
timber hoist and a sledge for hauling."""


def build(kit):
    t = kit.town_mats()
    for k in range(3):
        for j in range(3 - k):
            kit.box(t["stone"], (-0.8 + j * 0.42 + k * 0.21, 0.4, 0.15 + k * 0.3), (0.4, 0.4, 0.28), rot=(0, 0, 0.05 * j))
    kit.box(t["stone"], (0.6, -0.4, 0.2), (0.9, 0.45, 0.4))
    kit.pile(t["dark_stone"], (0.3, 0.6), n=6, size=0.1, spread=0.3, seed=13)
    for s in (-1, 1):
        kit.limb(t["wood"], (1.1, s * 0.45, 0), (1.1, 0, 2.0), 0.05)
    kit.limb(t["rope"], (1.1, 0, 2.0), (1.1, 0, 0.8), 0.015)
    kit.box(t["stone"], (1.1, 0, 0.65), (0.28, 0.28, 0.24))
    kit.box(t["wood"], (-0.4, -0.85, 0.07), (1.0, 0.4, 0.06))
    kit.box(t["stone"], (-0.4, -0.85, 0.23), (0.35, 0.3, 0.26))
