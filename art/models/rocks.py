"""Rocks (data/world.json nodes "rocks"): a scatter of grey boulders, stone for the town."""


def build(kit):
    t = kit.town_mats()
    for k, (x, y, r) in enumerate(((0, 0, 0.55), (0.7, -0.3, 0.38), (-0.6, 0.35, 0.42), (0.3, 0.65, 0.3), (-0.4, -0.6, 0.25))):
        kit.ball(t["stone"] if k % 2 == 0 else t["dark_stone"], (x, y, r * 0.5), r, scale=(1.2, 1.0, 0.8), rot=(0.2, 0.1, k))
