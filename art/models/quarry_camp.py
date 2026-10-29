"""Quarry camp (data/buildings.json "quarry_camp"): an outpost tent beside rough-split stone blocks,
wedges and a hauling sledge."""


def build(kit):
    t = kit.town_mats()
    kit.tent(t["hide"], t["dark_wood"], at=(-0.7, 0.5), r=0.65, h=1.2)
    for k, (x, y) in enumerate(((0.4, 0.3), (0.9, 0.0), (0.6, -0.5))):
        kit.box(t["stone"], (x, y, 0.2), (0.45, 0.4, 0.4 - 0.05 * k), rot=(0, 0, 0.3 * k))
    kit.pile(t["dark_stone"], (-0.2, -0.6), n=6, size=0.1, spread=0.25, seed=37)
    kit.box(t["wood"], (-0.6, -0.9, 0.06), (0.9, 0.35, 0.06))
